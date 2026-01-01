import 'package:flutter/material.dart';
import '../../models/video_detail.dart';
import '../../models/comment.dart';
import '../../models/history_models.dart';
import '../../services/video_service.dart';
import '../../services/hls_service.dart';
import '../../services/history_service.dart';
import '../../managers/video_player_manager.dart';
import '../../utils/auth_state_manager.dart';
import '../../theme/theme_extensions.dart';
import 'widgets/media_player_widget.dart';
import 'widgets/author_card.dart';
import 'widgets/video_info_card.dart';
import 'widgets/video_action_buttons.dart';
import 'widgets/part_list.dart';
import 'widgets/recommend_list.dart';
import 'widgets/comment_preview_card.dart';

/// 视频播放页面
class VideoPlayPage extends StatefulWidget {
  final int vid;
  final int? initialPart;

  const VideoPlayPage({
    super.key,
    required this.vid,
    this.initialPart,
  });

  @override
  State<VideoPlayPage> createState() => _VideoPlayPageState();
}

class _VideoPlayPageState extends State<VideoPlayPage> with WidgetsBindingObserver {
  final VideoService _videoService = VideoService();
  final HlsService _hlsService = HlsService();
  final HistoryService _historyService = HistoryService();
  final AuthStateManager _authStateManager = AuthStateManager();
  final ScrollController _scrollController = ScrollController();

  // 使用 GlobalKey 保持播放器状态（使用固定的key，不随分P变化而重建）
  late final GlobalKey _playerKey;

  // 【新增】播放管理器 - 统一管理 HLS预加载 和 播放器实例化
  late final VideoPlayerManager _playerManager;

  VideoDetail? _videoDetail;
  VideoStat? _videoStat;
  UserActionStatus? _actionStatus;
  bool _isLoading = true;
  String? _errorMessage;

  late int _currentPart;
  Duration? _lastReportedPosition; // 最后上报的播放位置（用于切换分P前上报）
  bool _hasReportedCompleted = false; // 是否已上报播放完成(-1)
  int? _lastSavedSeconds; // 最后一次保存到服务器的播放秒数（用于节流）
  double _currentDuration = 0;

  // 【关键】播放器控制器引用，用于离开页面时获取实时进度
  dynamic _playerController;

  // 评论相关
  int _totalComments = 0;
  Comment? _latestComment;

  @override
  void initState() {
    super.initState();
    _currentPart = widget.initialPart ?? 1;
    // 为播放器创建稳定的 GlobalKey，使用 vid 作为标识（不包含分P，保持全屏状态）
    _playerKey = GlobalKey(debugLabel: 'player_${widget.vid}');

    // 【新增】创建播放管理器
    _playerManager = VideoPlayerManager();

    _loadVideoData();
    // 添加生命周期监听
    WidgetsBinding.instance.addObserver(this);
    // 监听登录状态变化
    _authStateManager.addListener(_onAuthStateChanged);
  }

  /// 登录状态变化回调
  void _onAuthStateChanged() {
    // 当登录状态变化时，刷新用户操作状态（点赞、收藏、关注）
    _refreshUserActionStatus();
  }

  /// 刷新用户操作状态
  Future<void> _refreshUserActionStatus() async {
    if (_videoDetail == null) return;

    try {
      final actionStatus = await _videoService.getUserActionStatus(
        widget.vid,
        _videoDetail!.author.uid,
      );
      if (actionStatus != null && mounted) {
        setState(() {
          _actionStatus = actionStatus;
        });
        print('✅ 用户操作状态已刷新: hasLiked=${actionStatus.hasLiked}, hasCollected=${actionStatus.hasCollected}');
      }
    } catch (e) {
      print('刷新用户操作状态失败: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 当应用从后台返回前台时，刷新作者信息
    if (state == AppLifecycleState.resumed) {
      _refreshAuthorInfo();
    }
  }

  @override
  void dispose() {
    // 移除生命周期监听
    WidgetsBinding.instance.removeObserver(this);
    // 移除登录状态监听
    _authStateManager.removeListener(_onAuthStateChanged);

    // 【关键修复】页面关闭前保存播放进度
    // 核心原则：只有当视频真正播放过（有 duration）时才保存进度，避免覆盖服务器正确记录
    _saveProgressOnDispose();

    _scrollController.dispose();

    // 【新增】销毁播放管理器
    _playerManager.dispose();

    // 【修复】退出播放页时立即清理HLS流缓存（使用 clearAllCache 确保完整清理）
    _hlsService.clearAllCache();
    super.dispose();
  }

  /// 页面关闭时保存进度
  void _saveProgressOnDispose() {
    // 【关键】如果视频从未真正加载完成（duration == 0），不保存进度
    // 避免用户快速进入又退出时，用错误的进度覆盖服务器的正确记录
    if (_currentDuration <= 0) {
      print('📊 页面关闭: 视频未加载完成(duration=0)，不保存进度以保留服务器记录');
      return;
    }

    // 【优先级】使用回调记录的位置（已经验证过的稳定位置）
    // 而不是播放器的实时位置（可能在 seek/切换过程中不稳定）
    double? progressToSave = _lastReportedPosition?.inSeconds.toDouble();

    // 如果回调没有记录过，再尝试从播放器获取
    if (progressToSave == null && _playerController != null) {
      try {
        final currentPosition = _playerController.player.state.position;
        final playerDuration = _playerController.player.state.duration;
        // 只有当播放器的 duration 也有效时，才信任其 position
        if (playerDuration.inSeconds > 0 && currentPosition.inSeconds > 0) {
          progressToSave = currentPosition.inSeconds.toDouble();
          print('📊 从播放器获取进度: ${currentPosition.inSeconds}秒');
        }
      } catch (e) {
        print('⚠️ 获取播放器进度失败: $e');
      }
    }

    if (progressToSave == null || progressToSave <= 0) {
      print('📊 页面关闭: 无有效进度需要保存');
      return;
    }

    // 如果已经完播，退出时应该上报-1而不是总时长
    if (_hasReportedCompleted) {
      print('📊 页面关闭前上报进度: -1 (已完播)');
      _historyService.addHistory(
        vid: widget.vid,
        part: _currentPart,
        time: -1,
        duration: _currentDuration.toInt(),
      );
    } else {
      print('📊 页面关闭前上报进度: ${progressToSave.toStringAsFixed(1)}秒, duration=${_currentDuration.toInt()}秒');
      _historyService.addHistory(
        vid: widget.vid,
        part: _currentPart,
        time: progressToSave,
        duration: _currentDuration.toInt(),
      );
    }
  }

  /// 加载视频数据
  Future<void> _loadVideoData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 【性能优化】并发请求视频详情和历史记录
      final initialResults = await Future.wait([
        _videoService.getVideoDetail(widget.vid),
        _historyService.getProgress(
          vid: widget.vid,
          part: widget.initialPart, // 如果指定了分P则获取该分P进度，否则获取最后观看的
        ),
      ]);

      final videoDetail = initialResults[0] as VideoDetail?;
      final progressData = initialResults[1] as PlayProgressData?;

      if (videoDetail == null) {
        setState(() {
          _errorMessage = '视频不存在或已被删除';
          _isLoading = false;
        });
        return;
      }

      // 解析历史记录
      int targetPart = widget.initialPart ?? 1;
      double? progress;

      if (progressData != null) {
        targetPart = progressData.part;
        progress = progressData.progress;
        print('📺 从历史记录恢复: 分P=$targetPart, 进度=${progress.toStringAsFixed(1)}秒');
      }

      // 如果进度为-1，表示已看完，应该从头开始播放
      if (progress != null && progress == -1) {
        print('📺 检测到视频已看完(progress=-1)，将从头开始播放');
        progress = null;
        _hasReportedCompleted = false;
      }

      // 获取当前分P的资源ID
      final currentResource = videoDetail.resources[targetPart - 1];

      // 【关键优化】立即开始预加载 HLS 资源（不阻塞UI渲染）
      _playerManager.preloadResource(
        resourceId: currentResource.id,
        initialPosition: progress,
      );

      // 设置视频元数据（用于后台播放通知）
      _playerManager.setMetadata(
        title: currentResource.title,
        author: videoDetail.author.name,
        coverUrl: videoDetail.cover,
      );

      // 【关键优化】先设置基础数据，让UI立即渲染（播放器可以开始加载）
      setState(() {
        _videoDetail = videoDetail;
        _currentPart = targetPart;
        _videoStat = VideoStat(like: 0, collect: 0, share: 0); // 临时默认值
        _actionStatus = UserActionStatus(
          hasLiked: false,
          hasCollected: false,
          relationStatus: 0,
        );
        _isLoading = false; // 立即结束加载状态
      });

      // 【后台加载】并发请求次要数据（不阻塞主UI）
      _loadSecondaryData(videoDetail.author.uid);
    } catch (e) {
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 后台加载次要数据（统计、操作状态、评论预览）
  Future<void> _loadSecondaryData(int authorUid) async {
    // 【优化】并发请求所有次要数据，每个请求独立处理错误
    final futures = await Future.wait([
      // 1. 视频统计（不需要登录）
      _videoService.getVideoStat(widget.vid).catchError((e) {
        print('❌ 获取视频统计失败: $e');
        return null;
      }),
      // 2. 评论预览（不需要登录）
      _videoService.getComments(vid: widget.vid, page: 1, pageSize: 1).catchError((e) {
        print('❌ 获取评论预览失败: $e');
        return null;
      }),
      // 3. 用户操作状态（需要登录）
      _videoService.getUserActionStatus(widget.vid, authorUid).catchError((e) {
        print('❌ 获取用户操作状态失败: $e');
        return null;
      }),
    ]);

    if (!mounted) return;

    final videoStat = futures[0] as VideoStat?;
    final commentResponse = futures[1] as CommentListResponse?;
    final actionStatus = futures[2] as UserActionStatus?;

    print('📺 次要数据加载完成: stat=${videoStat != null}, comments=${commentResponse != null}, action=${actionStatus != null}');
    print('📺 用户操作状态: hasLiked=${actionStatus?.hasLiked}, hasCollected=${actionStatus?.hasCollected}');

    setState(() {
      if (videoStat != null) {
        _videoStat = videoStat;
      }
      if (commentResponse != null) {
        _totalComments = commentResponse.total;
        _latestComment = commentResponse.comments.isNotEmpty
            ? commentResponse.comments.first
            : null;
      }
      if (actionStatus != null) {
        _actionStatus = actionStatus;
      }
    });
  }

  /// 刷新作者信息（用于从个人中心返回后更新）
  Future<void> _refreshAuthorInfo() async {
    if (_videoDetail == null) return;

    try {
      // 重新获取视频详情以刷新作者信息
      final videoDetail = await _videoService.getVideoDetail(widget.vid);
      if (videoDetail != null && mounted) {
        setState(() {
          _videoDetail = videoDetail;
        });
        print('✅ 作者信息已刷新');
      }
    } catch (e) {
      print('刷新作者信息失败: $e');
    }
  }

  /// 切换分P
  Future<void> _changePart(int part) async {
    if (_videoDetail == null || part == _currentPart) return;

    // 检查分P是否存在
    if (part < 1 || part > _videoDetail!.resources.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该分集不存在')),
      );
      return;
    }

    // 在切换前，先上报当前分P的最后播放进度（参考PC端逻辑）
    if (_lastReportedPosition != null) {
      print('📊 切换分集前上报进度: ${_lastReportedPosition!.inSeconds}秒');
      await _historyService.addHistory(
        vid: widget.vid,
        part: _currentPart,
        time: _lastReportedPosition!.inSeconds.toDouble(),
        duration: _currentDuration.toInt(),
      );
    }

    // 获取新分P的播放进度
    final progressData = await _historyService.getProgress(
      vid: widget.vid,
      part: part,
    );
    var progress = progressData?.progress;

    // 如果进度为-1，表示已看完，应该从头开始播放
    if (progress != null && progress == -1) {
      progress = null;
    }

    // 获取新分P的资源
    final newResource = _videoDetail!.resources[part - 1];

    // 【关键】使用 Manager 切换资源（预加载新资源）
    _playerManager.setMetadata(
      title: newResource.title,
      author: _videoDetail!.author.name,
      coverUrl: _videoDetail!.cover,
    );
    _playerManager.switchResource(
      resourceId: newResource.id,
      initialPosition: progress,
    );

    setState(() {
      _currentPart = part;
      // 切换分P时清空上次播放位置，准备记录新分P的播放位置
      _lastReportedPosition = null;
      // 切换分P时重置已看完标记
      _hasReportedCompleted = false;
      // 切换分P时重置上次保存的秒数，允许新分P立即上报首次进度
      _lastSavedSeconds = null;
      // 不再重新创建 GlobalKey，保持播放器实例以维持全屏状态
    });

    // 滚动到顶部
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// 跳转到其他视频
  void _navigateToVideo(int vid) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayPage(vid: vid),
      ),
    );
  }

  /// 播放进度更新回调（每秒触发一次）
  void _onProgressUpdate(Duration position, Duration totalDuration) {
    _currentDuration = totalDuration.inSeconds.toDouble();
    // 记录最后播放位置（用于切换分P前上报）
    _lastReportedPosition = position;

    // 使用节流机制：只有当播放进度与上次保存相差5秒以上时才上报
    final currentSeconds = position.inSeconds;

    if (_hasReportedCompleted) {
      return; // 已上报完成标记，不再上报进度
    }

    // 首次上报 或 距离上次上报已经过了5秒
    if (_lastSavedSeconds == null ||
        (currentSeconds - _lastSavedSeconds!) >= 5) {
      print(
        '📊 上报播放进度: $currentSeconds秒 (距上次上报: ${_lastSavedSeconds == null ? "首次" : "${currentSeconds - _lastSavedSeconds!}秒"})',
      );
      _historyService.addHistory(
        vid: widget.vid,
        part: _currentPart,
        time: currentSeconds.toDouble(),
        // 【修改点】传入真实总时长
        duration: _currentDuration.toInt(),
      );
      _lastSavedSeconds = currentSeconds;
    }
  }

  /// 播放结束回调（仅用于上报播放完成，不处理自动播放逻辑）
  void _onVideoEnded() {
    // 避免重复上报
    if (_hasReportedCompleted) {
      print('📺 视频播放结束 (已上报过-1，跳过)');
      return;
    }

    print('📺 视频播放结束，上报已看完标记');

    // 播放完成后上报进度为 -1，表示已看完
    _historyService.addHistory(
      vid: widget.vid,
      part: _currentPart,
      time: -1,
      duration: _currentDuration.toInt(),
    );
    _hasReportedCompleted = true; // 标记为已上报

    // 注意：自动播放逻辑现在由播放器的循环模式控制
    // 当循环模式为"列表循环"时，播放器会通过 onPartChange 回调来切换分P
    print('✅ 播放完成上报结束');
  }

///头部
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // 只在顶部添加安全区域，适配刘海、挖孔、水滴屏
        top: true,
        bottom: false,
        left: false,
        right: false,
        child: _buildBody(),
      ),
    );
  }

  /// 构建页面主体
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      final colors = context.colors;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadVideoData,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_videoDetail == null) {
      final colors = context.colors;
      return Center(
        child: Text('视频加载失败', style: TextStyle(color: colors.textSecondary)),
      );
    }

    // 获取当前分P的视频URL
    final currentResource = _videoDetail!.resources[_currentPart - 1];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 900;

        if (isWideScreen) {
          // 宽屏布局：左右两栏
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧主内容区
              Expanded(
                flex: 7,
                child: _buildMainContent(currentResource),
              ),

              // 右侧边栏
              SizedBox(
                width: 350,
                child: _buildSidebar(),
              ),
            ],
          );
        } else {
          // 窄屏布局：单栏
          return _buildMainContent(currentResource);
        }
      },
    );
  }

  /// 构建主内容区
  Widget _buildMainContent(VideoResource currentResource) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用实际可用宽度计算播放器高度（16:9 比例）
        final playerHeight = constraints.maxWidth * 9 / 16;

        return Column(
      children: [
        // 固定播放器区域（不参与滚动）
        SizedBox(
          width: double.infinity,
          height: playerHeight,
          child: MediaPlayerWidget(
            key: _playerKey,
            // 【优化】使用 Manager 模式，避免两次加载
            manager: _playerManager,
            onVideoEnd: _onVideoEnded,
            onProgressUpdate: _onProgressUpdate,
            onControllerReady: (controller) => _playerController = controller,
            title: currentResource.title, // 传递分P标题
            author: _videoDetail!.author.name, // 传递作者名（后台播放通知用）
            coverUrl: _videoDetail!.cover, // 传递封面（后台播放通知用）
            totalParts: _videoDetail!.resources.length,
            currentPart: _currentPart,
            onPartChange: _changePart,
          ),
        ),

        // 可滚动内容区域
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // 视频标题和信息
              VideoInfoCard(
                videoDetail: _videoDetail!,
                videoStat: _videoStat!,
                currentPart: _currentPart,
              ),
              const SizedBox(height: 16),

              // 操作按钮
              VideoActionButtons(
                vid: widget.vid,
                initialStat: _videoStat!,
                initialHasLiked: _actionStatus!.hasLiked,
                initialHasCollected: _actionStatus!.hasCollected,
              ),
              const SizedBox(height: 16),

              // 作者信息
              AuthorCard(
                author: _videoDetail!.author,
                initialRelationStatus: _actionStatus!.relationStatus,
                onAvatarTap: () {
                  // TODO: 跳转到用户主页
                },
              ),
              const SizedBox(height: 16),

              // 分P列表（手机端）
              if (MediaQuery.of(context).size.width <= 900)
                PartList(
                  resources: _videoDetail!.resources,
                  currentPart: _currentPart,
                  onPartChange: _changePart,
                ),

              const SizedBox(height: 16),

              // 评论预览卡片（YouTube 风格）
              CommentPreviewCard(
                vid: widget.vid,
                totalComments: _totalComments,
                latestComment: _latestComment,
              ),
              const SizedBox(height: 16),

              // 推荐视频（手机端）
              if (MediaQuery.of(context).size.width <= 900)
                RecommendList(
                  vid: widget.vid,
                  onVideoTap: _navigateToVideo,
                ),
            ],
          ),
        ),
      ],
    );
      },
    );
  }

  /// 构建侧边栏（宽屏）
  Widget _buildSidebar() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 作者信息
            AuthorCard(
              author: _videoDetail!.author,
              initialRelationStatus: _actionStatus!.relationStatus,
              onAvatarTap: () {
                // TODO: 跳转到用户主页
              },
            ),
            const SizedBox(height: 16),

            // 分P列表
            if (_videoDetail!.resources.length > 1)
              PartList(
                resources: _videoDetail!.resources,
                currentPart: _currentPart,
                onPartChange: _changePart,
              ),

            const SizedBox(height: 16),

            // 推荐视频
            RecommendList(
              vid: widget.vid,
              onVideoTap: _navigateToVideo,
            ),
          ],
        ),
      ),
    );
  }
}
