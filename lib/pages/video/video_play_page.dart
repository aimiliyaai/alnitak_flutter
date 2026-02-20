import 'package:flutter/material.dart';
import '../../models/video_detail.dart';
import '../../models/comment.dart';
import '../../services/video_service.dart';
import '../../services/history_service.dart';
import '../../services/hls_service.dart';
import '../../services/online_websocket_service.dart';
import '../../controllers/video_player_controller.dart';
import '../../controllers/danmaku_controller.dart';
import '../../utils/auth_state_manager.dart';
import '../../theme/theme_extensions.dart';
import '../user/user_space_page.dart';
import 'widgets/media_player_widget.dart';
import 'widgets/author_card.dart';
import 'widgets/video_info_card.dart';
import 'widgets/video_action_buttons.dart';
import 'widgets/part_list.dart';
import 'widgets/collection_list.dart';
import 'widgets/recommend_list.dart';
import 'widgets/comment_preview_card.dart';
import '../../widgets/danmaku_overlay.dart';

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
  final HistoryService _historyService = HistoryService();
  final AuthStateManager _authStateManager = AuthStateManager();
  final ScrollController _scrollController = ScrollController();

  // 使用 GlobalKey 保持播放器状态（使用固定的key，不随分P变化而重建）
  late final GlobalKey _playerKey;

  // 弹幕控制器
  late final DanmakuController _danmakuController;

  // 在线人数 WebSocket 服务
  late final OnlineWebSocketService _onlineWebSocketService;

  // 弹幕数量 ValueNotifier（用于实时更新显示）
  final ValueNotifier<int> _danmakuCountNotifier = ValueNotifier<int>(0);

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

  // 【关键】进度上报用的 vid/part，在播放开始时锁定，防止切换视频/分P时的竞态
  // _onProgressUpdate 使用这两个值而非 _currentVid/_currentPart
  int? _progressReportVid;
  int? _progressReportPart;

  // 播放器控制器引用（通过 onControllerReady 回调获取）
  VideoPlayerController? _playerController;

  // 当前播放的视频ID（用于切换推荐视频时更新）
  late int _currentVid;

  // 当前资源ID和初始位置（驱动 MediaPlayerWidget）
  int? _currentResourceId;
  double? _currentInitialPosition;

  // 评论相关
  int _totalComments = 0;
  Comment? _latestComment;

  // 分集列表和推荐列表的 GlobalKey，用于自动连播
  final GlobalKey<PartListState> _partListKey = GlobalKey<PartListState>();
  final GlobalKey<CollectionListState> _collectionListKey = GlobalKey<CollectionListState>();
  final GlobalKey<RecommendListState> _recommendListKey = GlobalKey<RecommendListState>();

  @override
  void initState() {
    super.initState();
    _currentVid = widget.vid;
    _currentPart = widget.initialPart ?? 1;
    _playerKey = GlobalKey(debugLabel: 'player_stable');

    // 创建弹幕控制器
    _danmakuController = DanmakuController();
    _danmakuController.addListener(_onDanmakuChanged);

    // 创建在线人数服务
    _onlineWebSocketService = OnlineWebSocketService();

    _loadVideoData();
    WidgetsBinding.instance.addObserver(this);
    _authStateManager.addListener(_onAuthStateChanged);
  }

  /// 登录状态变化回调
  void _onAuthStateChanged() {
    _refreshUserActionStatus();
    _playerController?.fetchAndRestoreProgress();
  }

  /// 弹幕控制器变化回调（更新弹幕数量显示）
  void _onDanmakuChanged() {
    _danmakuCountNotifier.value = _danmakuController.rawTotalCount;
  }

  /// 构建非全屏弹幕发送栏
  Widget _buildDanmakuInputBar() {
    final colors = context.colors;
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              color: colors.card,
              child: SafeArea(
                top: false,
                child: DanmakuSendBar(
                  controller: _danmakuController,
                  onSendEnd: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border(
            bottom: BorderSide(color: colors.divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.inputBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '发一条弹幕...',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 刷新用户操作状态
  Future<void> _refreshUserActionStatus() async {
    if (_videoDetail == null) return;

    try {
      final actionStatus = await _videoService.getUserActionStatus(
        _currentVid,
        _videoDetail!.author.uid,
      );
      if (actionStatus != null && mounted) {
        setState(() {
          _actionStatus = actionStatus;
        });
      }
    } catch (_) {
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _refreshAuthorInfo();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authStateManager.removeListener(_onAuthStateChanged);

    // 页面关闭前保存播放进度
    _saveProgressOnDispose();

    _scrollController.dispose();

    // 销毁弹幕控制器
    _danmakuController.removeListener(_onDanmakuChanged);
    _danmakuController.dispose();

    // 释放弹幕数量 ValueNotifier
    _danmakuCountNotifier.dispose();

    // 断开在线人数连接
    _onlineWebSocketService.dispose();

    // 清理 HLS 缓存
    HlsService().cleanupAllTempCache();

    super.dispose();
  }

  /// 页面关闭时保存进度
  void _saveProgressOnDispose() {
    // 当 listeners 异常死亡导致 _currentDuration 未更新时，直接从 player 读取
    var duration = _currentDuration;
    if (duration <= 0 && _playerController != null) {
      try {
        duration = _playerController!.player.state.duration.inSeconds.toDouble();
      } catch (_) {}
    }
    if (duration <= 0) {
      return;
    }

    // 优先从 player 读取实时位置（最准确），fallback 到上次回调记录的位置
    double? progressToSave;
    if (_playerController != null) {
      try {
        final currentPosition = _playerController!.player.state.position;
        if (currentPosition.inSeconds > 0) {
          progressToSave = currentPosition.inSeconds.toDouble();
        }
      } catch (_) {}
    }
    progressToSave ??= _lastReportedPosition?.inSeconds.toDouble();

    if (progressToSave == null || progressToSave <= 0) {
      return;
    }

    // 重置去重状态，确保退出时的最终上报不会被跳过
    _historyService.resetProgressState();

    final time = _hasReportedCompleted ? -1.0 : progressToSave;
    _historyService.addHistory(
      vid: _currentVid,
      part: _currentPart,
      time: time,
      duration: duration.toInt(),
    );
  }

  /// 加载视频数据
  Future<void> _loadVideoData({int? part}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final videoDetail = await _videoService.getVideoDetail(_currentVid);

      if (videoDetail == null) {
        setState(() {
          _errorMessage = '视频不存在或已被删除';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _videoDetail = videoDetail;
        _currentPart = part ?? 1;
        _videoStat = VideoStat(like: 0, collect: 0, share: 0);
        _actionStatus = UserActionStatus(hasLiked: false, hasCollected: false, relationStatus: 0);
        _isLoading = false;
      });

      _fetchProgressAndRestore(part: part);
      _loadSecondaryData(videoDetail.author.uid);
      _onlineWebSocketService.connect(_currentVid);

    } catch (e) {
      setState(() {
        _errorMessage = '加载失败，请重试';
        _isLoading = false;
      });
    }
  }

  /// 异步获取进度并恢复播放
  Future<void> _fetchProgressAndRestore({int? part}) async {
    try {
      final progressData = await _historyService.getProgress(
        vid: _currentVid,
        part: part,
      );

      if (progressData == null) {
        _startPlayback(part ?? 1, null);
        return;
      }

      final progress = progressData.progress;

      if (progress == -1) {
        _startPlayback(progressData.part, null);
        return;
      }

      if (progressData.duration > 0) {
        final adjustedProgressForCheck = progress > 2 ? progress - 2 : progress;
        final remainingAfterSeek = progressData.duration - adjustedProgressForCheck;
        if (remainingAfterSeek <= 3) {
          _startPlayback(progressData.part, null);
          return;
        }
      }

      final targetPart = progressData.part;
      final adjustedProgress = progress > 2 ? progress - 2 : progress;

      _startPlayback(targetPart, adjustedProgress);

    } catch (e) {
      _startPlayback(part ?? 1, null);
    }
  }

  /// 开始播放（统一入口）
  ///
  /// 通过更新 _currentResourceId 和 _currentInitialPosition 来驱动
  /// MediaPlayerWidget 的 didUpdateWidget 触发重新加载
  void _startPlayback(int part, double? position) {
    if (!mounted) return;

    final currentResource = _videoDetail!.resources[part - 1];

    // 设置视频上下文（用于进度恢复）
    _playerController?.setVideoContext(vid: _currentVid, part: part);

    // 锁定进度上报的 vid/part，防止切换时竞态
    _progressReportVid = _currentVid;
    _progressReportPart = part;

    setState(() {
      _currentPart = part;
      _currentResourceId = currentResource.id;
      _currentInitialPosition = position;
    });

    // 加载弹幕
    _danmakuController.loadDanmaku(vid: _currentVid, part: part);
  }

  /// 后台加载次要数据（统计、操作状态、评论预览）
  Future<void> _loadSecondaryData(int authorUid) async {
    final futures = await Future.wait([
      _videoService.getVideoStat(_currentVid).catchError((e) {
        return null;
      }),
      _videoService.getComments(vid: _currentVid, page: 1, pageSize: 1).catchError((e) {
        return null;
      }),
      _videoService.getUserActionStatus(_currentVid, authorUid).catchError((e) {
        return null;
      }),
    ]);

    if (!mounted) return;

    final videoStat = futures[0] as VideoStat?;
    final commentResponse = futures[1] as CommentListResponse?;
    final actionStatus = futures[2] as UserActionStatus?;

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

  /// 刷新评论预览（发表评论后调用）
  Future<void> _refreshCommentPreview() async {
    try {
      final commentResponse = await _videoService.getComments(
        vid: _currentVid,
        page: 1,
        pageSize: 1,
      );
      if (commentResponse != null && mounted) {
        setState(() {
          _totalComments = commentResponse.total;
          _latestComment = commentResponse.comments.isNotEmpty
              ? commentResponse.comments.first
              : null;
        });
      }
    } catch (_) {
    }
  }

  /// 刷新作者信息（用于从个人中心返回后更新）
  Future<void> _refreshAuthorInfo() async {
    if (_videoDetail == null) return;

    try {
      final videoDetail = await _videoService.getVideoDetail(_currentVid);
      if (videoDetail != null && mounted) {
        setState(() {
          _videoDetail = videoDetail;
        });
      }
    } catch (_) {
    }
  }

  /// 切换分P
  Future<void> _changePart(int part) async {
    if (_videoDetail == null || part == _currentPart) return;

    if (part < 1 || part > _videoDetail!.resources.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该分集不存在')),
      );
      return;
    }

    // 先快照旧值，用于切换前的进度上报
    final oldPart = _currentPart;
    final oldPosition = _lastReportedPosition;
    final oldDuration = _currentDuration;

    // 【关键】立即清空进度上报锁定，防止旧播放器的位置事件用新 part 上报
    _progressReportVid = null;
    _progressReportPart = null;

    // 在切换前，先上报当前分P的最后播放进度（使用快照的旧值）
    if (oldPosition != null && oldDuration > 0) {
      await _historyService.addHistory(
        vid: _currentVid,
        part: oldPart,
        time: _hasReportedCompleted ? -1 : oldPosition.inSeconds.toDouble(),
        duration: oldDuration.toInt(),
      );
    }

    // 获取新分P的播放进度
    final progressData = await _historyService.getProgress(
      vid: _currentVid,
      part: part,
    );
    var progress = progressData?.progress;

    if (progress != null && progress == -1) {
      progress = null;
    }

    if (progress != null && progress > 2) {
      progress = progress - 2;
    }

    final newResource = _videoDetail!.resources[part - 1];

    // 设置视频上下文（分P切换）
    _playerController?.setVideoContext(vid: _currentVid, part: part);

    // 锁定新的进度上报 vid/part
    _progressReportVid = _currentVid;
    _progressReportPart = part;

    // 通过更新 _currentResourceId 触发 didUpdateWidget -> initialize
    setState(() {
      _currentPart = part;
      _currentResourceId = newResource.id;
      _currentInitialPosition = progress;
      _lastReportedPosition = null;
      _hasReportedCompleted = false;
      _lastSavedSeconds = null;
      _currentDuration = 0;
    });

    // 切换分P时重新加载弹幕
    _danmakuController.loadDanmaku(vid: _currentVid, part: part);

    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // 防止并发切换视频
  bool _isSwitchingVideo = false;

  /// 切换到其他视频（原地刷新，不重新导航）
  /// [part] 指定目标分P（从1开始），为null时通过历史进度决定
  Future<void> _switchToVideo(int vid, {int? part}) async {
    if (vid == _currentVid) return;

    if (_isSwitchingVideo) {
      return;
    }
    _isSwitchingVideo = true;

    final oldVid = _currentVid;
    final oldPart = _currentPart;
    final oldDuration = _currentDuration;
    final oldPosition = _lastReportedPosition;

    // 【关键】立即清空进度上报锁定，防止旧播放器的位置事件用新 vid 上报
    _progressReportVid = null;
    _progressReportPart = null;
    _currentVid = vid;

    try {
      // 1. 上报当前视频的播放进度（使用保存的旧值，不受 _currentVid 变化影响）
      if (oldPosition != null && oldDuration > 0) {
        await _historyService.addHistory(
          vid: oldVid,
          part: oldPart,
          time: _hasReportedCompleted ? -1 : oldPosition.inSeconds.toDouble(),
          duration: oldDuration.toInt(),
        );
      }

      // 2. 重置播放状态
      _currentPart = 1;
      _lastReportedPosition = null;
      _hasReportedCompleted = false;
      _lastSavedSeconds = null;
      _currentDuration = 0;

      _historyService.resetProgressState();

      // 3. 加载新视频数据
      await _loadVideoDataSeamless(targetPart: part);

      // 4. 清理旧视频缓存
      Future.delayed(const Duration(seconds: 2), () {
        HlsService().cleanupExpiredCache();
      });

      // 5. 滚动到顶部
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } finally {
      _isSwitchingVideo = false;
    }
  }

  /// 无缝加载视频数据（不显示 loading，用于切换推荐视频）
  /// [targetPart] 指定目标分P，为null时通过历史进度决定
  Future<void> _loadVideoDataSeamless({int? targetPart}) async {
    final targetVid = _currentVid;

    try {
      final videoDetail = await _videoService.getVideoDetail(targetVid);

      if (_currentVid != targetVid) {
        return;
      }

      if (videoDetail == null) {
        setState(() {
          _errorMessage = '视频不存在或已被删除';
        });
        return;
      }

      setState(() {
        _videoDetail = videoDetail;
        _currentPart = 1;
        _videoStat = VideoStat(like: 0, collect: 0, share: 0);
        _actionStatus = UserActionStatus(hasLiked: false, hasCollected: false, relationStatus: 0);
        _totalComments = 0;
        _latestComment = null;
        _errorMessage = null;
      });

      _onlineWebSocketService.connect(targetVid);

      _loadSecondaryData(videoDetail.author.uid);

      _fetchProgressAndRestoreSeamless(targetVid: targetVid, videoDetail: videoDetail, targetPart: targetPart);

    } catch (_) {
    }
  }

  /// 无缝加载时异步获取进度
  /// [targetPart] 指定目标分P，为null时通过历史进度决定
  Future<void> _fetchProgressAndRestoreSeamless({required int targetVid, required VideoDetail videoDetail, int? targetPart}) async {
    try {
      if (targetPart != null) {
        // 明确指定了分P（如从合集列表点击特定分P），直接播放该分P
        if (_currentVid != targetVid) return;
        _startPlaybackSeamless(videoDetail, targetPart, null);
        return;
      }

      final progressData = await _historyService.getProgress(vid: targetVid, part: null);

      if (_currentVid != targetVid) return;

      if (progressData == null) {
        _startPlaybackSeamless(videoDetail, 1, null);
        return;
      }

      final progress = progressData.progress;

      if (progress == -1) {
        _startPlaybackSeamless(videoDetail, progressData.part, null);
        return;
      }

      if (progressData.duration > 0) {
        final adjustedProgressForCheck = progress > 2 ? progress - 2 : progress;
        final remainingAfterSeek = progressData.duration - adjustedProgressForCheck;
        if (remainingAfterSeek <= 3) {
          _startPlaybackSeamless(videoDetail, progressData.part, null);
          return;
        }
      }

      final historyPart = progressData.part;
      final adjustedProgress = progress > 2 ? progress - 2 : progress;

      _startPlaybackSeamless(videoDetail, historyPart, adjustedProgress);

    } catch (e) {
      _startPlaybackSeamless(videoDetail, targetPart ?? 1, null);
    }
  }

  /// 无缝模式开始播放
  void _startPlaybackSeamless(VideoDetail videoDetail, int part, double? position) {
    if (!mounted || _currentVid != videoDetail.vid) return;

    final currentResource = videoDetail.resources[part - 1];

    // 设置视频上下文
    _playerController?.setVideoContext(vid: videoDetail.vid, part: part);

    // 锁定进度上报的 vid/part，防止切换时竞态
    _progressReportVid = videoDetail.vid;
    _progressReportPart = part;

    // 通过更新 _currentResourceId 触发 didUpdateWidget -> initialize
    setState(() {
      _currentPart = part;
      _currentResourceId = currentResource.id;
      _currentInitialPosition = position;
    });

    // 加载弹幕
    _danmakuController.loadDanmaku(vid: videoDetail.vid, part: part);
  }

  /// 播放状态变化回调（控制弹幕播放/暂停）
  void _onPlayingStateChanged(bool playing) {
    if (playing) {
      _danmakuController.play();
    } else {
      _danmakuController.pause();
    }
  }

  /// 播放进度更新回调（每秒触发一次）
  void _onProgressUpdate(Duration position, Duration totalDuration) {
    // 同步弹幕进度（弹幕不依赖 vid/part，始终同步）
    _danmakuController.updateTime(position.inSeconds.toDouble());

    // 【关键】进度锁定无效时，说明正在切换视频/分P，
    // 此时 position/duration 可能属于旧视频，不能写入任何状态
    final reportVid = _progressReportVid;
    final reportPart = _progressReportPart;
    if (reportVid == null || reportPart == null) return;

    // 只在 duration > 0 时更新，避免 open() 重置期间覆盖为 0
    if (totalDuration.inSeconds > 0) {
      _currentDuration = totalDuration.inSeconds.toDouble();
    }
    _lastReportedPosition = position;

    if (_hasReportedCompleted) return;

    final currentSeconds = position.inSeconds;

    // 【防御】duration 为 0 时不上报（可能是 open() 重置期间）
    if (_currentDuration <= 0) return;

    // 【防御】进度不应超过总时长（允许 2 秒误差）
    if (currentSeconds > _currentDuration + 2) return;

    if (_lastSavedSeconds == null ||
        (currentSeconds - _lastSavedSeconds!) >= 5) {
      _historyService.addHistory(
        vid: reportVid,
        part: reportPart,
        time: currentSeconds.toDouble(),
        duration: _currentDuration.toInt(),
      );
      _lastSavedSeconds = currentSeconds;
    }
  }

  /// 播放结束回调
  void _onVideoEnded() {
    if (_hasReportedCompleted) {
      return;
    }

    // 使用锁定的 vid/part，防止切换过程中的竞态
    final reportVid = _progressReportVid ?? _currentVid;
    final reportPart = _progressReportPart ?? _currentPart;

    _historyService.addHistory(
      vid: reportVid,
      part: reportPart,
      time: -1,
      duration: _currentDuration > 0 ? _currentDuration.toInt() : 0,
    );
    _hasReportedCompleted = true;

    // 自动连播逻辑
    final nextPart = _partListKey.currentState?.getNextPart();
    if (nextPart != null) {
      _changePart(nextPart);
      return;
    }

    final nextCollectionVideo = _collectionListKey.currentState?.getNextVideo();
    if (nextCollectionVideo != null) {
      _switchToVideo(nextCollectionVideo);
      return;
    }

    final nextVideo = _recommendListKey.currentState?.getNextVideo();
    if (nextVideo != null) {
      _switchToVideo(nextVideo);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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

    final currentResource = _videoDetail!.resources[_currentPart - 1];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 900;

        if (isWideScreen) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: _buildMainContent(currentResource),
              ),
              SizedBox(
                width: 350,
                child: _buildSidebar(),
              ),
            ],
          );
        } else {
          return _buildMainContent(currentResource);
        }
      },
    );
  }

  /// 构建主内容区
  Widget _buildMainContent(VideoResource currentResource) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final playerHeight = constraints.maxWidth * 9 / 16;

        return Column(
      children: [
        // 固定播放器区域
        SizedBox(
          width: double.infinity,
          height: playerHeight,
          child: MediaPlayerWidget(
            key: _playerKey,
            resourceId: _currentResourceId,
            initialPosition: _currentInitialPosition,
            onVideoEnd: _onVideoEnded,
            onProgressUpdate: _onProgressUpdate,
            onControllerReady: (controller) {
              _playerController = controller;
              // 设置视频上下文
              controller.setVideoContext(vid: _currentVid, part: _currentPart);
            },
            title: _videoDetail!.resources.length > 1
                ? currentResource.title
                : _videoDetail!.title,
            author: _videoDetail!.author.name,
            coverUrl: _videoDetail!.cover,
            totalParts: _videoDetail!.resources.length,
            currentPart: _currentPart,
            onPartChange: _changePart,
            danmakuController: _danmakuController,
            onPlayingStateChanged: _onPlayingStateChanged,
            onlineCount: _onlineWebSocketService.onlineCount,
          ),
        ),

        // 可滚动内容区域
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              _buildDanmakuInputBar(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: VideoInfoCard(
                  videoDetail: _videoDetail!,
                  videoStat: _videoStat!,
                  currentPart: _currentPart,
                  onlineCount: _onlineWebSocketService.onlineCount,
                  danmakuCount: _danmakuCountNotifier,
                ),
              ),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VideoActionButtons(
                  vid: _currentVid,
                  initialStat: _videoStat!,
                  initialHasLiked: _actionStatus!.hasLiked,
                  initialHasCollected: _actionStatus!.hasCollected,
                ),
              ),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AuthorCard(
                  author: _videoDetail!.author,
                  initialRelationStatus: _actionStatus!.relationStatus,
                  onAvatarTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserSpacePage(userId: _videoDetail!.author.uid),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              if (MediaQuery.of(context).size.width <= 900)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CollectionList(
                    key: _collectionListKey,
                    vid: _currentVid,
                    currentPart: _currentPart,
                    onVideoTap: _switchToVideo,
                    onPartTap: _changePart,
                  ),
                ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CommentPreviewCard(
                  vid: _currentVid,
                  totalComments: _totalComments,
                  latestComment: _latestComment,
                  onSeek: (seconds) {
                    _playerController?.seek(Duration(seconds: seconds));
                  },
                  onCommentPosted: _refreshCommentPreview,
                ),
              ),
              const SizedBox(height: 16),

              if (MediaQuery.of(context).size.width <= 900)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: RecommendList(
                    key: _recommendListKey,
                    vid: _currentVid,
                    onVideoTap: _switchToVideo,
                  ),
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
            AuthorCard(
              author: _videoDetail!.author,
              initialRelationStatus: _actionStatus!.relationStatus,
              onAvatarTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserSpacePage(userId: _videoDetail!.author.uid),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            CollectionList(
              key: _collectionListKey,
              vid: _currentVid,
              currentPart: _currentPart,
              onVideoTap: _switchToVideo,
              onPartTap: _changePart,
            ),

            const SizedBox(height: 16),

            RecommendList(
              key: _recommendListKey,
              vid: _currentVid,
              onVideoTap: _switchToVideo,
            ),
          ],
        ),
      ),
    );
  }
}
