import 'package:flutter/material.dart';
import '../../models/video_detail.dart';
import '../../models/comment.dart';
import '../../services/video_service.dart';
import '../../services/hls_service.dart';
import '../../services/history_service.dart';
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

class _VideoPlayPageState extends State<VideoPlayPage> {
  final VideoService _videoService = VideoService();
  final HlsService _hlsService = HlsService();
  final HistoryService _historyService = HistoryService();
  final ScrollController _scrollController = ScrollController();

  // 使用 GlobalKey 保持播放器状态（需要可变以支持切换分P）
  late GlobalKey _playerKey;

  VideoDetail? _videoDetail;
  VideoStat? _videoStat;
  UserActionStatus? _actionStatus;
  bool _isLoading = true;
  String? _errorMessage;

  late int _currentPart;
  double? _initialProgress; // 改为 double 类型（秒）
  Duration? _lastReportedPosition; // 最后上报的播放位置（用于切换分P前上报）
  bool _hasReportedCompleted = false; // 是否已上报播放完成(-1)
  int? _lastSavedSeconds; // 最后一次保存到服务器的播放秒数（用于节流）

  // 评论相关
  int _totalComments = 0;
  Comment? _latestComment;

  @override
  void initState() {
    super.initState();
    _currentPart = widget.initialPart ?? 1;
    // 为播放器创建稳定的 GlobalKey，使用 vid 和 part 作为标识
    _playerKey = GlobalKey(debugLabel: 'player_${widget.vid}_$_currentPart');
    _loadVideoData();
  }

  @override
  void dispose() {
    // 页面关闭前上报最后播放进度（参考PC端逻辑）
    if (_lastReportedPosition != null) {
      // 如果已经完播，退出时应该上报-1而不是总时长
      if (_hasReportedCompleted) {
        print('📊 页面关闭前上报进度: -1 (已完播)');
        _historyService.addHistory(
          vid: widget.vid,
          part: _currentPart,
          time: -1,
        );
      } else {
        print('📊 页面关闭前上报进度: ${_lastReportedPosition!.inSeconds}秒');
        _historyService.addHistory(
          vid: widget.vid,
          part: _currentPart,
          time: _lastReportedPosition!.inSeconds.toDouble(),
        );
      }
    }

    _scrollController.dispose();
    // 清理临时 m3u8 文件
    _hlsService.cleanupTempFiles();
    super.dispose();
  }

  /// 加载视频数据
  Future<void> _loadVideoData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 并发请求多个接口
      final results = await Future.wait([
        _videoService.getVideoDetail(widget.vid),
        _videoService.getVideoStat(widget.vid),
        _historyService.getProgress(vid: widget.vid, part: _currentPart),
      ]);

      final videoDetail = results[0] as VideoDetail?;
      final videoStat = results[1] as VideoStat?;
      var progress = results[2] as double?; // 进度单位为秒

      if (videoDetail == null) {
        setState(() {
          _errorMessage = '视频不存在或已被删除';
          _isLoading = false;
        });
        return;
      }

      // 如果进度为-1，表示已看完，应该从头开始播放
      if (progress != null && progress == -1) {
        print('📺 检测到视频已看完(progress=-1)，将从头开始播放');
        progress = null; // 设为null表示从头播放
        _hasReportedCompleted = false; // 重置已看完标记，允许重新上报完成状态
      }

      // 获取用户操作状态
      final actionStatus = await _videoService.getUserActionStatus(
        widget.vid,
        videoDetail.author.uid,
      );

      // 获取评论信息（仅获取第一页的第一条评论作为预览）
      await _loadCommentPreview();

      setState(() {
        _videoDetail = videoDetail;
        _videoStat = videoStat ?? VideoStat(like: 0, collect: 0, share: 0);
        _actionStatus = actionStatus ?? UserActionStatus(
          hasLiked: false,
          hasCollected: false,
          relationStatus: 0,
        );
        _initialProgress = progress;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
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
      );
    }

    // 获取新分P的播放进度
    var progress = await _historyService.getProgress(vid: widget.vid, part: part);

    // 如果进度为-1，表示已看完，应该从头开始播放
    if (progress != null && progress == -1) {
      progress = null;
    }

    setState(() {
      _currentPart = part;
      _initialProgress = progress;
      // 切换分P时清空上次播放位置，准备记录新分P的播放位置
      _lastReportedPosition = null;
      // 切换分P时重置已看完标记
      _hasReportedCompleted = false;
      // 切换分P时重置上次保存的秒数，允许新分P立即上报首次进度
      _lastSavedSeconds = null;
      // 切换分P时更新播放器 key
      _playerKey = GlobalKey(debugLabel: 'player_${widget.vid}_$part');
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
  void _onProgressUpdate(Duration position) {
    // 记录最后播放位置（用于切换分P前上报）
    _lastReportedPosition = position;

    // 使用节流机制：只有当播放进度与上次保存相差5秒以上时才上报
    final currentSeconds = position.inSeconds;

    if (_hasReportedCompleted) {
      return; // 已上报完成标记，不再上报进度
    }

    // 首次上报 或 距离上次上报已经过了5秒
    if (_lastSavedSeconds == null || (currentSeconds - _lastSavedSeconds!) >= 5) {
      print('📊 上报播放进度: $currentSeconds秒 (距上次上报: ${_lastSavedSeconds == null ? "首次" : "${currentSeconds - _lastSavedSeconds!}秒"})');
      _historyService.addHistory(
        vid: widget.vid,
        part: _currentPart,
        time: currentSeconds.toDouble(),
      );
      _lastSavedSeconds = currentSeconds;
    }
  }

  /// 加载评论预览（仅加载第一条评论和总数）
  Future<void> _loadCommentPreview() async {
    try {
      final response = await _videoService.getComments(
        vid: widget.vid,
        page: 1,
        pageSize: 1, // 只获取第一条评论
      );

      if (response != null) {
        setState(() {
          _totalComments = response.total;
          _latestComment = response.comments.isNotEmpty ? response.comments.first : null;
        });
      }
    } catch (e) {
      print('加载评论预览失败: $e');
      // 失败时不影响主流程
    }
  }

  /// 播放结束回调
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
    );
    _hasReportedCompleted = true; // 标记为已上报

    // 检查是否有下一P，并自动播放（需要参考PC端逻辑，从PartList组件获取自动连播状态）
    // 这里暂时保持简单实现，后续可以通过PartList的回调来控制
    if (_videoDetail != null && _currentPart < _videoDetail!.resources.length) {
      print('🎬 存在下一集，准备自动播放: P${_currentPart + 1}');
      // 延迟1秒后自动播放下一P（参考PC端的1秒延迟）
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _changePart(_currentPart + 1);
        }
      });
    } else {
      print('✅ 已是最后一集');
    }
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadVideoData,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_videoDetail == null) {
      return const Center(
        child: Text('视频加载失败', style: TextStyle(color: Colors.grey)),
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
    // 计算播放器高度（16:9 比例）
    final screenWidth = MediaQuery.of(context).size.width;
    final playerHeight = screenWidth * 9 / 16;

    return Column(
      children: [
        // 固定播放器区域（不参与滚动）
        SizedBox(
          width: double.infinity,
          height: playerHeight,
          child: MediaPlayerWidget(
            key: _playerKey,
            resourceId: currentResource.id,
            initialPosition: _initialProgress,
            onVideoEnd: _onVideoEnded,
            onProgressUpdate: _onProgressUpdate,
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
