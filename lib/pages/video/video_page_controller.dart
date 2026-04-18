import 'package:flutter/material.dart';
import '../../models/video_detail.dart';
import '../../models/comment.dart';
import '../../models/danmaku.dart';
import '../../services/video_service.dart';
import '../../services/history_service.dart';
import '../../services/cache_service.dart';
import '../../services/logger_service.dart';
import '../../services/online_websocket_service.dart';
import '../../controllers/video_player_controller.dart';
import '../../controllers/danmaku_controller.dart';
import '../../utils/auth_state_manager.dart';
import 'progress_tracker.dart';
import 'widgets/auto_play_source.dart';

/// 视频播放页面业务逻辑控制器
///
/// 从 VideoPlayPage 中提取，负责：
/// - 视频数据加载（首次 + 无缝切换）
/// - 分P切换 / 视频切换
/// - 进度恢复逻辑
/// - 次要数据加载（统计、评论、操作状态）
/// - 播放器事件处理（进度上报、弹幕同步、自动连播）
/// - 生命周期管理（登录状态、应用前后台）
class VideoPageController extends ChangeNotifier {
  final VideoService _videoService = VideoService();
  final HistoryService _historyService = HistoryService();
  final ProgressTracker progressTracker = ProgressTracker();
  final AuthStateManager _authStateManager = AuthStateManager();
  final DanmakuController danmakuController = DanmakuController();
  final OnlineWebSocketService onlineWebSocketService =
      OnlineWebSocketService();
  final ValueNotifier<int> danmakuCountNotifier = ValueNotifier<int>(0);

  // ============ 状态 ============
  VideoDetail? videoDetail;
  VideoStat? videoStat;
  UserActionStatus? actionStatus;
  bool isLoading = true;
  String? errorMessage;

/// 当前视频 id
  String? currentVid;
  /// 当前资源标识（rid）
  String? _currentRid;
  String? _bootstrapVideoRef;
  late int currentPart;
  /// 当前资源标识（优先 shortId，回退 int ID）
  Object? currentResourceId;
  double? currentInitialPosition;

  int totalComments = 0;
  Comment? latestComment;

  // ============ 播放器引用 ============
  VideoPlayerController? playerController;

  // ============ 自动连播 GlobalKey ============
  GlobalKey<dynamic>? _collectionListKey;
  GlobalKey<dynamic>? _recommendListKey;

  /// 设置自动连播所需的 GlobalKey（由 View 层调用）
  void setAutoPlayKeys({
    required GlobalKey<dynamic> collectionListKey,
    required GlobalKey<dynamic> recommendListKey,
  }) {
    _collectionListKey = collectionListKey;
    _recommendListKey = recommendListKey;
  }

  // ============ 请求防串台 ============
  int _pageRequestToken = 0;
  int _changePartToken = 0;
  bool _isSwitchingVideo = false;
  bool _disposed = false;

  int _nextPageRequestToken() => ++_pageRequestToken;

bool _isActiveRequest(int token, {String? expectedVid}) {
    if (_disposed || token != _pageRequestToken) return false;
    if (expectedVid != null && currentVid != expectedVid) return false;
    return true;
  }

  // ============ 初始化 / 销毁 ============

void init(String videoRef, {int? initialPart}) {
    final t = videoRef.trim();
    _bootstrapVideoRef = t.isEmpty ? null : t;
    currentVid = null;
    currentPart = initialPart ?? 1;
    danmakuController.addListener(_onDanmakuChanged);
    _authStateManager.addListener(_onAuthStateChanged);
    
    LoggerService.instance.reportEvent(
      'VideoPageController初始化',
      {'videoRef': videoRef, 'initialPart': initialPart},
    );
    loadVideoData();
  }

@override
  void dispose() {
    _disposed = true;
    _authStateManager.removeListener(_onAuthStateChanged);
    final vid = currentVid;
    if (vid != null) {
      progressTracker.saveOnDispose(vid, _currentRid, currentPart, playerController);
    }
    danmakuController.removeListener(_onDanmakuChanged);
    danmakuController.dispose();
    danmakuCountNotifier.dispose();
    onlineWebSocketService.removeDanmakuListener(_onDanmakuReceived);
    onlineWebSocketService.dispose();
    CacheService().cleanupAllTempCache();
    super.dispose();
  }

  // ============ 监听回调 ============

  void _onAuthStateChanged() {
    refreshUserActionStatus();
    playerController?.fetchAndRestoreProgress();
  }

  void _onDanmakuChanged() {
    danmakuCountNotifier.value = danmakuController.rawTotalCount;
  }

  void onAppResumed() => _refreshAuthorInfo();

  // ============ 数据加载 ============

  Future<void> loadVideoData({int? part}) async {
    final requestToken = _nextPageRequestToken();
    final vidQuery =
        (_bootstrapVideoRef != null && _bootstrapVideoRef!.isNotEmpty)
            ? _bootstrapVideoRef!
            : currentVid.toString();
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final detail = await _videoService.getVideoDetail(vidQuery);
      // 首次加载时 currentVid=0，不能用 expectedVid 校验（会误判为过期请求）
      if (!_isActiveRequest(requestToken)) return;

      if (detail == null) {
        errorMessage = '视频不存在或已被删除';
        isLoading = false;
        notifyListeners();
        return;
      }

      _bootstrapVideoRef = null;
      videoDetail = detail;
      currentVid = detail.vid;
      currentPart = part ?? 1;
      videoStat = VideoStat(like: 0, collect: 0, share: 0);
      actionStatus = UserActionStatus(
          hasLiked: false, hasCollected: false, relationStatus: 0);
      isLoading = false;
      notifyListeners();

      LoggerService.instance.reportEvent(
        '视频数据加载成功',
        {'vid': detail.vid, 'title': detail.title, 'part': currentPart, 'author': detail.author.name},
      );

      _fetchProgressAndRestore(
          part: part,
          requestToken: requestToken,
          requestVid: detail.vid,
          expectedVid: detail.vid);
_loadSecondaryData(detail.author.uid,
          requestToken: requestToken,
          requestVid: detail.vid,
          expectedVid: detail.vid);
      _setupDanmakuListener();
    } catch (e) {
      if (!_isActiveRequest(requestToken)) return;
      errorMessage = '加载失败，请重试';
      isLoading = false;
      notifyListeners();
    }
  }

  // ============ 进度恢复（通用逻辑） ============

  /// 根据历史进度数据计算调整后的播放位置
  /// 返回 (targetPart, adjustedPosition)
  @visibleForTesting
  static (int, double?) resolveProgress(
      dynamic progressData, int fallbackPart) {
    if (progressData == null) return (fallbackPart, null);

    final progress = progressData.progress as double;
    final part = progressData.part as int;

    if (progress == -1) return (part, null);

    if (progressData.duration > 0) {
      final adjusted = progress > 2 ? progress - 2 : progress;
      final remaining = progressData.duration - adjusted;
      if (remaining <= 3) return (part, null);
    }

    final adjustedProgress = progress > 2 ? progress - 2 : progress;
    return (part, adjustedProgress);
  }

Future<void> _fetchProgressAndRestore(
      {int? part,
      required int requestToken,
      required String requestVid,
      required String expectedVid}) async {
    try {
      final progressData =
          await _historyService.getProgress(vid: requestVid, part: part);
      if (!_isActiveRequest(requestToken, expectedVid: expectedVid)) return;

      final (targetPart, position) = resolveProgress(progressData, part ?? 1);
      _startPlayback(targetPart, position);
    } catch (e) {
      if (!_isActiveRequest(requestToken, expectedVid: expectedVid)) return;
      _startPlayback(part ?? 1, null);
    }
  }

  // ============ 开始播放 ============

void _startPlayback(int part, double? position) {
    if (_disposed) return;

    final currentResource = videoDetail!.resources[part - 1];
    _currentRid = currentResource.shortId ?? currentResource.id;
    playerController?.setVideoContext(vid: currentVid!, part: part);
    progressTracker.lock(currentVid!, _currentRid, part);
    progressTracker.reset();

    currentPart = part;
    currentResourceId = currentResource.shortId ?? currentResource.id;
    currentInitialPosition = position;
    notifyListeners();

danmakuController.loadDanmaku(vid: currentVid!, rid: _currentRid, part: part);
    onlineWebSocketService.connect(currentVid!, rid: _currentRid);

    LoggerService.instance.reportEvent(
      '开始播放',
      {'vid': currentVid, 'part': part, 'position': position, 'resourceId': currentResource.id},
    );
  }

  // ============ 弹幕 WebSocket 监听 ============

  void _setupDanmakuListener() {
    // 防止重复注册：每次 loadVideoData 都会调到这里
    onlineWebSocketService.removeDanmakuListener(_onDanmakuReceived);
    onlineWebSocketService.addDanmakuListener(_onDanmakuReceived);
  }

  void _onDanmakuReceived(Map<String, dynamic> danmakuData) {
    // 将 WebSocket 消息转换为 Danmaku 对象
    final danmaku = Danmaku.fromJson(danmakuData);
    // 添加到弹幕控制器（会按时间排序并在正确时间显示）
    danmakuController.addExternalDanmaku(danmaku);
  }

  // ============ 次要数据 ============

Future<void> _loadSecondaryData(int authorUid,
      {required int requestToken,
      required String requestVid,
      String? expectedVid}) async {
    final futures = await Future.wait([
      _videoService.getVideoStat(requestVid).catchError((e) => null),
      _videoService
          .getComments(vid: requestVid, page: 1, pageSize: 1)
          .catchError((e) => null),
      _videoService
          .getUserActionStatus(requestVid, authorUid)
          .catchError((e) => null),
    ]);

    if (!_isActiveRequest(requestToken, expectedVid: expectedVid)) return;

    final stat = futures[0] as VideoStat?;
    final commentResponse = futures[1] as CommentListResponse?;
    final action = futures[2] as UserActionStatus?;

    if (stat != null) videoStat = stat;
    if (commentResponse != null) {
      totalComments = commentResponse.total;
      latestComment = commentResponse.comments.isNotEmpty
          ? commentResponse.comments.first
          : null;
    }
    if (action != null) actionStatus = action;
    notifyListeners();
  }

Future<void> refreshCommentPreview() async {
    if (currentVid == null) return;
    final requestVid = currentVid!;
    try {
      final commentResponse = await _videoService.getComments(
          vid: requestVid, page: 1, pageSize: 1);
      if (_disposed || currentVid != requestVid) return;
      if (commentResponse != null) {
        totalComments = commentResponse.total;
        latestComment = commentResponse.comments.isNotEmpty
            ? commentResponse.comments.first
            : null;
        notifyListeners();
      }
    } catch (e) {
      LoggerService.instance.logWarning('获取最新评论失败: $e', tag: 'VideoPageCtrl');
    }
  }

  Future<void> _refreshAuthorInfo() async {
    if (videoDetail == null) return;
    final requestVid = currentVid;
    if (requestVid == null) return;
    try {
      final detail = await _videoService.getVideoDetail(requestVid);
      if (_disposed || currentVid != requestVid) return;
      if (detail != null) {
        videoDetail = detail;
        notifyListeners();
      }
    } catch (e) {
      LoggerService.instance.logWarning('刷新作者信息失败: $e', tag: 'VideoPageCtrl');
    }
  }

  Future<void> refreshUserActionStatus() async {
    if (videoDetail == null || currentVid == null) return;
    try {
      final status = await _videoService.getUserActionStatus(
          currentVid!, videoDetail!.author.uid);
      if (status != null && !_disposed) {
        actionStatus = status;
        notifyListeners();
      }
    } catch (e) {
      LoggerService.instance
          .logWarning('刷新用户操作状态失败: $e', tag: 'VideoPageController');
    }
  }

  // ============ 分P切换 ============

  Future<void> changePart(int part,
      {VoidCallback? onInvalidPart, VoidCallback? onComplete}) async {
    if (videoDetail == null || part == currentPart) return;
    if (part < 1 || part > videoDetail!.resources.length) {
      onInvalidPart?.call();
      return;
    }

final requestToken = ++_changePartToken;
    final oldPart = currentPart;

    progressTracker.unlock();
    await progressTracker.saveBeforeSwitch(currentVid!, _currentRid, oldPart);

    final progressData =
        await _historyService.getProgress(vid: currentVid!, part: part);
    if (_disposed || requestToken != _changePartToken) return;

    var progress = progressData?.progress;
    if (progress != null && progress == -1) progress = null;
    if (progress != null && progress > 2) progress = progress - 2;

    final newResource = videoDetail!.resources[part - 1];
    _currentRid = newResource.shortId ?? newResource.id as String?;
    playerController?.setVideoContext(vid: currentVid!, part: part);

    progressTracker.lock(currentVid!, _currentRid, part);
    progressTracker.reset();

    currentPart = part;
    currentResourceId = newResource.shortId ?? newResource.id;
    currentInitialPosition = progress;
    notifyListeners();

    danmakuController.loadDanmaku(vid: currentVid!, rid: _currentRid, part: part);
    onlineWebSocketService.connect(currentVid!, rid: _currentRid);
    onComplete?.call();
  }

// ============ 视频切换（无缝） ============

  Future<void> switchToVideo(String vid,
      {int? part, VoidCallback? onComplete}) async {
    if (vid == currentVid || _isSwitchingVideo) return;
    _isSwitchingVideo = true;

    final oldVid = currentVid;
    final oldRid = _currentRid;
    final oldPart = currentPart;

    progressTracker.unlock();
    currentVid = vid;
    _currentRid = null;

    try {
      await progressTracker.saveBeforeSwitch(oldVid!, oldRid, oldPart);

      progressTracker.reset();
      currentPart = 1;
      videoStat = VideoStat(like: 0, collect: 0, share: 0);
      actionStatus = UserActionStatus(
          hasLiked: false, hasCollected: false, relationStatus: 0);
      totalComments = 0;
      latestComment = null;
      notifyListeners();

      _historyService.resetProgressState();
      await _loadVideoDataSeamless(targetPart: part);
      onComplete?.call();
    } finally {
      _isSwitchingVideo = false;
    }
  }

Future<void> _loadVideoDataSeamless({int? targetPart}) async {
    final targetVid = currentVid;
    if (targetVid == null) return;
    final requestToken = _nextPageRequestToken();

    try {
      final detail = await _videoService.getVideoDetail(targetVid);
      if (!_isActiveRequest(requestToken, expectedVid: targetVid)) return;

      if (detail == null) {
        errorMessage = '视频不存在或已被删除';
        notifyListeners();
        return;
      }

      final newResource = detail.resources.isNotEmpty ? detail.resources[0] : null;
      _currentRid = newResource?.shortId ?? newResource?.id;
      videoDetail = detail;
      currentVid = detail.vid;
      currentPart = 1;
      videoStat = VideoStat(like: 0, collect: 0, share: 0);
      actionStatus = UserActionStatus(
          hasLiked: false, hasCollected: false, relationStatus: 0);
      totalComments = 0;
      latestComment = null;
      errorMessage = null;
      notifyListeners();

      _loadSecondaryData(detail.author.uid,
          requestToken: requestToken,
          requestVid: detail.vid,
          expectedVid: detail.vid);
      _fetchProgressAndRestoreSeamless(
        targetVid: detail.vid,
        videoDetail: detail,
        targetPart: targetPart,
        requestToken: requestToken,
      );
    } catch (e) {
      LoggerService.instance.logWarning('自动播放下一个失败: $e', tag: 'VideoPageCtrl');
    }
  }

Future<void> _fetchProgressAndRestoreSeamless({
    required String targetVid,
    required VideoDetail videoDetail,
    int? targetPart,
    required int requestToken,
  }) async {
    try {
      if (targetPart != null) {
        if (!_isActiveRequest(requestToken, expectedVid: targetVid)) return;
        _startPlaybackSeamless(videoDetail, targetPart, null);
        return;
      }

      final progressData =
          await _historyService.getProgress(vid: targetVid, part: null);
      if (!_isActiveRequest(requestToken, expectedVid: targetVid)) return;

      final (part, position) = resolveProgress(progressData, 1);
      _startPlaybackSeamless(videoDetail, part, position);
    } catch (e) {
      if (!_isActiveRequest(requestToken, expectedVid: targetVid)) return;
      _startPlaybackSeamless(videoDetail, targetPart ?? 1, null);
    }
  }

  void _startPlaybackSeamless(VideoDetail detail, int part, double? position) {
    if (_disposed || currentVid != detail.vid) return;

final currentResource = detail.resources[part - 1];
    _currentRid = currentResource.shortId ?? currentResource.id as String?;
    playerController?.setVideoContext(vid: currentVid!, part: part);

    progressTracker.lock(currentVid!, _currentRid, part);
    progressTracker.reset();

    currentPart = part;
    currentResourceId = currentResource.shortId ?? currentResource.id;
    currentInitialPosition = position;
    notifyListeners();

    danmakuController.loadDanmaku(vid: detail.vid, rid: _currentRid, part: part);
    onlineWebSocketService.connect(detail.vid, rid: _currentRid);
  }

  // ============ 播放器事件处理 ============

  void onPlayingStateChanged(bool playing) {
    if (playing) {
      danmakuController.play();
    } else {
      danmakuController.pause();
    }
  }

  void onProgressUpdate(Duration position, Duration totalDuration) {
    // 用毫秒精度喂给弹幕控制器：_processNewDanmakus 的时间窗只有 0.6s，秒级截断会大量漏弹幕
    danmakuController.updateTime(position.inMilliseconds / 1000.0);
    progressTracker.onProgressUpdate(position, totalDuration);
  }

void onVideoEnded() {
    final shouldAutoPlay =
        progressTracker.onVideoEnded(currentVid!, _currentRid, currentPart, playerController);
    if (!shouldAutoPlay) return;

    // 自动连播：分P → 合集 → 推荐
    final collectionSource =
        _collectionListKey?.currentState as AutoPlaySource?;
    final recommendSource =
        _recommendListKey?.currentState as AutoPlaySource?;

    // 1. 分P连播（CollectionList 在分P模式下提供 getNextPart）
    final nextPart = collectionSource?.getNextPart();
    if (nextPart != null) {
      changePart(nextPart);
      return;
    }

    // 2. 合集连播
    final nextCollectionVideo = collectionSource?.getNextVideo();
    if (nextCollectionVideo != null) {
      switchToVideo(nextCollectionVideo);
      return;
    }

    // 3. 推荐连播
    final nextVideo = recommendSource?.getNextVideo();
    if (nextVideo != null) {
      switchToVideo(nextVideo);
      return;
    }
  }

  void onReplayFromEnd() {
    progressTracker.resetCompletionState();
  }
}
