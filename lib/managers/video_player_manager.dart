import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/hls_service.dart';
import '../controllers/video_player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/quality_utils.dart';

/// 播放状态枚举
enum PlaybackState {
  idle,       // 初始状态
  loading,    // 正在加载资源
  ready,      // 资源就绪，等待播放
  playing,    // 播放中
  paused,     // 暂停
  buffering,  // 缓冲中
  completed,  // 播放完成
  error,      // 错误
}

/// 预加载的资源数据
class PreloadedResource {
  final int resourceId;
  final int epoch; // 资源版本号，用于防止过期资源被使用
  final List<String> qualities;
  final String selectedQuality;
  final MediaSource mediaSource;
  final double? initialPosition;

  const PreloadedResource({
    required this.resourceId,
    required this.epoch,
    required this.qualities,
    required this.selectedQuality,
    required this.mediaSource,
    this.initialPosition,
  });
}

/// 视频播放业务管理器
///
/// 职责：
/// 1. 协调 HLS资源预加载 和 播放器实例化
/// 2. 管理播放状态机
/// 3. 提供统一的播放控制接口
///
/// 设计目标：
/// - UI 渲染不等待资源加载
/// - 资源加载和播放器创建并行进行
/// - 消除两次加载动作
/// - 使用 epoch 机制防止竞态条件
class VideoPlayerManager extends ChangeNotifier {
  final HlsService _hlsService = HlsService();

  // ============ 状态 ============
  final ValueNotifier<PlaybackState> playbackState = ValueNotifier(PlaybackState.idle);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<bool> isResourceReady = ValueNotifier(false);

  // ============ 预加载的资源 ============
  PreloadedResource? _preloadedResource;
  Completer<PreloadedResource>? _preloadCompleter;

  // ============ 播放器控制器 ============
  VideoPlayerController? _controller;
  VideoPlayerController? get controller => _controller;

  // ============ 回调 ============
  VoidCallback? onVideoEnd;
  Function(Duration position, Duration totalDuration)? onProgressUpdate;
  Function(String quality)? onQualityChanged;

  // ============ 元数据 ============
  String? _title;
  String? _author;
  String? _coverUrl;

  // ============ 视频上下文（用于进度恢复）============
  int? _currentVid;
  int _currentPart = 1;

  // ============ 竞态条件防护 ============
  bool _isDisposed = false;
  int _currentEpoch = 0; // 资源版本号，每次加载新资源时递增
  bool _isPreloading = false; // 是否正在预加载
  bool _isStartingPlayback = false; // 是否正在启动播放

  VideoPlayerManager();

  /// 开始预加载资源（在页面 initState 时调用）
  ///
  /// 此方法会：
  /// 1. 立即返回，不阻塞UI渲染
  /// 2. 在后台获取清晰度列表和媒体源
  /// 3. 缓存结果供播放器使用
  Future<void> preloadResource({
    required int resourceId,
    double? initialPosition,
  }) async {
    if (_isDisposed) return;

    // 递增 epoch，使之前的加载任务失效
    final myEpoch = ++_currentEpoch;

    // 如果正在预加载，取消之前的
    if (_isPreloading) {
      debugPrint('⚠️ [Manager] 取消之前的预加载任务');
    }
    _isPreloading = true;

    // 重置状态
    _preloadedResource = null;
    _isStartingPlayback = false;
    isResourceReady.value = false;
    playbackState.value = PlaybackState.loading;
    errorMessage.value = null;

    // 创建新的 Completer
    _preloadCompleter = Completer<PreloadedResource>();

    debugPrint('🚀 [Manager] 开始预加载资源: resourceId=$resourceId, epoch=$myEpoch');

    try {
      // 1. 获取清晰度列表
      final qualities = await _hlsService.getAvailableQualities(resourceId);

      // 检查是否已过期
      if (_isDisposed || myEpoch != _currentEpoch) {
        debugPrint('⚠️ [Manager] 预加载已过期(epoch不匹配)，跳过');
        return;
      }

      if (qualities.isEmpty) {
        throw Exception('没有可用的清晰度');
      }

      // 2. 确定首选清晰度
      final selectedQuality = await _getPreferredQuality(qualities);

      // 再次检查是否过期
      if (_isDisposed || myEpoch != _currentEpoch) {
        debugPrint('⚠️ [Manager] 预加载已过期(epoch不匹配)，跳过');
        return;
      }

      // 3. 获取媒体源
      final mediaSource = await _hlsService.getMediaSource(resourceId, selectedQuality);

      // 最终检查
      if (_isDisposed || myEpoch != _currentEpoch) {
        debugPrint('⚠️ [Manager] 预加载已过期(epoch不匹配)，跳过');
        return;
      }

      debugPrint('✅ [Manager] 资源预加载完成: quality=$selectedQuality, epoch=$myEpoch');

      // 4. 缓存预加载结果（带有 epoch）
      _preloadedResource = PreloadedResource(
        resourceId: resourceId,
        epoch: myEpoch,
        qualities: qualities,
        selectedQuality: selectedQuality,
        mediaSource: mediaSource,
        initialPosition: initialPosition,
      );

      isResourceReady.value = true;
      _isPreloading = false;

      if (_preloadCompleter != null && !_preloadCompleter!.isCompleted) {
        _preloadCompleter!.complete(_preloadedResource!);
      }

      // 5. 如果播放器已创建且未开始播放，立即开始播放
      if (_controller != null && !_isStartingPlayback) {
        await _startPlaybackWithPreloadedResource(myEpoch);
      }

    } catch (e) {
      // 检查是否过期
      if (_isDisposed || myEpoch != _currentEpoch) {
        debugPrint('⚠️ [Manager] 预加载失败但已过期，忽略错误');
        return;
      }

      debugPrint('❌ [Manager] 预加载失败: $e');
      _isPreloading = false;
      playbackState.value = PlaybackState.error;
      errorMessage.value = '加载视频失败: $e';

      if (_preloadCompleter != null && !_preloadCompleter!.isCompleted) {
        _preloadCompleter!.completeError(e);
      }
    }
  }

  /// 创建播放器控制器（在 MediaPlayerWidget initState 时调用）
  ///
  /// 此方法会：
  /// 1. 立即创建 Player 和 VideoController 实例
  /// 2. 如果资源已预加载完成，立即开始播放
  /// 3. 如果资源未就绪，等待预加载完成
  Future<VideoPlayerController> createController() async {
    if (_controller != null) {
      debugPrint('⚠️ [Manager] Controller 已存在，直接返回');
      return _controller!;
    }

    debugPrint('🎬 [Manager] 创建播放器控制器');

    // 创建控制器（内部会创建 Player 实例）
    _controller = VideoPlayerController();

    // 绑定回调
    _controller!.onVideoEnd = onVideoEnd;
    _controller!.onProgressUpdate = onProgressUpdate;
    _controller!.onQualityChanged = onQualityChanged;

    // 设置元数据
    if (_title != null) {
      _controller!.setVideoMetadata(
        title: _title!,
        author: _author,
        coverUri: _coverUrl != null ? Uri.tryParse(_coverUrl!) : null,
      );
    }

    // 设置视频上下文（用于进度恢复）
    if (_currentVid != null) {
      _controller!.setVideoContext(vid: _currentVid!, part: _currentPart);
    }

    // 如果资源已就绪且未开始播放，立即开始播放
    if (_preloadedResource != null && !_isStartingPlayback) {
      await _startPlaybackWithPreloadedResource(_preloadedResource!.epoch);
    }

    return _controller!;
  }

  /// 使用预加载的资源开始播放
  Future<void> _startPlaybackWithPreloadedResource(int expectedEpoch) async {
    // 【关键】多重防护
    if (_isStartingPlayback) {
      debugPrint('⚠️ [Manager] 正在启动播放中，跳过重复调用');
      return;
    }
    if (_controller == null || _preloadedResource == null || _isDisposed) {
      debugPrint('⚠️ [Manager] 条件不满足，跳过播放');
      return;
    }
    // 检查 epoch 是否匹配
    if (_preloadedResource!.epoch != expectedEpoch || expectedEpoch != _currentEpoch) {
      debugPrint('⚠️ [Manager] epoch 不匹配 (resource=${_preloadedResource!.epoch}, expected=$expectedEpoch, current=$_currentEpoch)，跳过播放');
      return;
    }

    _isStartingPlayback = true;
    final resource = _preloadedResource!;
    debugPrint('▶️ [Manager] 使用预加载资源开始播放, epoch=$expectedEpoch');

    try {
      // 使用预加载的数据初始化播放器
      await _controller!.initializeWithPreloadedData(
        resourceId: resource.resourceId,
        qualities: resource.qualities,
        selectedQuality: resource.selectedQuality,
        mediaSource: resource.mediaSource,
        initialPosition: resource.initialPosition,
      );

      // 再次检查 epoch，确保播放完成时资源未被切换
      if (expectedEpoch == _currentEpoch && !_isDisposed) {
        playbackState.value = PlaybackState.playing;
        debugPrint('✅ [Manager] 播放已启动');
      } else {
        // 【修复】epoch 不匹配时也重置标志，为新资源让路
        _isStartingPlayback = false;
      }

    } catch (e) {
      debugPrint('❌ [Manager] 播放失败: $e');
      if (expectedEpoch == _currentEpoch && !_isDisposed) {
        playbackState.value = PlaybackState.error;
        errorMessage.value = '播放视频失败: $e';
      }
      _isStartingPlayback = false; // 【修复】始终重置，允许重试
    }
  }

  /// 切换到新的资源（分P切换时调用）
  Future<void> switchResource({
    required int resourceId,
    double? initialPosition,
  }) async {
    if (_isDisposed) return;

    debugPrint('🔄 [Manager] 切换资源: resourceId=$resourceId');

    // preloadResource 内部会递增 epoch 并重置状态
    await preloadResource(
      resourceId: resourceId,
      initialPosition: initialPosition,
    );
  }

  /// 设置视频元数据
  void setMetadata({
    required String title,
    String? author,
    String? coverUrl,
  }) {
    _title = title;
    _author = author;
    _coverUrl = coverUrl;

    // 如果控制器已创建，同步更新
    _controller?.setVideoMetadata(
      title: title,
      author: author,
      coverUri: coverUrl != null ? Uri.tryParse(coverUrl) : null,
    );
  }

  /// 设置视频上下文（用于进度恢复）
  ///
  /// 在加载/切换视频时调用，让 Manager 和 Controller 都知道当前视频
  void setVideoContext({required int vid, int part = 1}) {
    _currentVid = vid;
    _currentPart = part;

    // 如果控制器已创建，同步更新
    _controller?.setVideoContext(vid: vid, part: part);
    debugPrint('📹 [Manager] 设置视频上下文: vid=$vid, part=$part');
  }

  /// 获取首选清晰度
  Future<String> _getPreferredQuality(List<String> qualities) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferredName = prefs.getString('preferred_video_quality_display_name');
      return findBestQualityMatch(qualities, preferredName);
    } catch (_) {}
    return HlsService.getDefaultQuality(qualities);
  }

  /// 等待资源就绪
  Future<PreloadedResource> waitForResource() async {
    if (_preloadedResource != null) {
      return _preloadedResource!;
    }

    if (_preloadCompleter != null) {
      return _preloadCompleter!.future;
    }

    throw Exception('资源未开始加载');
  }

  /// 播放控制
  Future<void> play() async => _controller?.play();
  Future<void> pause() async => _controller?.pause();
  Future<void> seek(Duration position) async => _controller?.seek(position);

  /// 获取 VideoController（用于 Video widget）
  VideoController? get videoController => _controller?.videoController;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    debugPrint('🗑️ [Manager] 销毁');

    // 递增 epoch 使所有正在进行的异步操作失效
    _currentEpoch++;

    playbackState.dispose();
    errorMessage.dispose();
    isResourceReady.dispose();

    _controller?.dispose();
    _controller = null;

    _preloadedResource = null;
    _preloadCompleter = null;

    super.dispose();
  }
}
