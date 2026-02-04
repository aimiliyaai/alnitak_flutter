import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:call_state_handler/call_state_handler.dart';
import 'package:call_state_handler/models/call_state.dart';
import '../services/hls_service.dart';
import '../services/history_service.dart';
import '../services/logger_service.dart';
import '../services/audio_service_handler.dart';
import '../services/video_heart_beat_service.dart';
import '../models/loop_mode.dart';
import '../utils/wakelock_manager.dart';
import '../utils/error_handler.dart';
import '../utils/quality_utils.dart';

/// 视频播放器控制器 (V2 - 简化版)
///
/// 行业级标准设计：
/// 1. 用户意图优先：用户期望的进度就是"真实进度"
/// 2. 简单状态机：加载中 -> 播放中 -> 已完成
/// 3. 最小化状态变量：不追踪复杂的中间状态
class VideoPlayerController extends ChangeNotifier {
  final HlsService _hlsService = HlsService();
  final LoggerService _logger = LoggerService.instance;
  final VideoHeartBeatService _heartBeatService = VideoHeartBeatService();
  late final Player player;
  late final VideoController videoController;

  // ============ AudioService (后台播放) ============
  static VideoAudioHandler? _audioHandler;
  static bool _audioServiceInitialized = false;

  // ============ 状态 Notifiers ============
  final ValueNotifier<List<String>> availableQualities = ValueNotifier([]);
  final ValueNotifier<String?> currentQuality = ValueNotifier(null);
  final ValueNotifier<bool> isLoading = ValueNotifier(true);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<bool> isPlayerInitialized = ValueNotifier(false);
  final ValueNotifier<bool> isSwitchingQuality = ValueNotifier(false);
  final ValueNotifier<LoopMode> loopMode = ValueNotifier(LoopMode.off);
  final ValueNotifier<bool> backgroundPlayEnabled = ValueNotifier(false);
  final ValueNotifier<bool> isBuffering = ValueNotifier(false);

  // ============ 进度流 ============
  final StreamController<Duration> _positionStreamController = StreamController.broadcast();
  Stream<Duration> get positionStream => _positionStreamController.stream;

  // ============ 核心状态（极简）============
  int? _currentResourceId;
  bool _isDisposed = false;
   bool _hasTriggeredCompletion = false;
  bool _isInitializing = false; // 防止并发初始化
  bool _hasPlaybackStarted = false; // 防止重复播放（首帧声音问题）

  /// 【核心】用户期望的进度位置
  /// - seek 时更新为目标位置
  /// - 播放时跟随实际位置
  /// - 上报进度时使用此值
  Duration _userIntendedPosition = Duration.zero;

  /// 【新增】待执行的 seek 位置（用于兜底 seek）
  double? _pendingSeekPosition;

  /// 【新增】进度校验的目标位置
  double? _validationTargetPosition;

  /// 【新增】是否已校验过（防止重复校验）
  bool _progressValidated = false;

  /// 是否正在执行 seek（用于防止 seek 过程中的进度上报）
  bool _isSeeking = false;

  /// Player 完全释放的 completer
  Completer<void>? _playerDisposeCompleter;

  /// 当前加载的唯一标识符
  String _currentLoadId = '';

  /// 上次获取进度的时间戳（用于防抖）
  int? _lastProgressFetchTime;

  // ============ 切换清晰度 ============
  Timer? _qualityDebounceTimer;
  int _qualityEpoch = 0;

  // ============ 订阅管理 ============
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSubscription;
  CallStateHandler? _callStateHandler;
  StreamSubscription<CallState>? _callStateSubscription;

  // ============ 辅助状态 ============
  bool _wasPlayingBeforeBackground = false;
  bool _wasPlayingBeforeInterruption = false;
  Timer? _stalledTimer;
  final Map<String, MediaSource> _qualityCache = {};
  Timer? _preloadTimer;
  Duration _lastReportedPosition = Duration.zero;
  String _currentDecodeMode = 'no';

  // ============ 设置键 ============
  static const String _preferredQualityKey = 'preferred_video_quality_display_name';
  static const String _loopModeKey = 'video_loop_mode';
  static const String _backgroundPlayKey = 'background_play_enabled';
  static const String _decodeModeKey = 'video_decode_mode';
  static const String _volumeKey = 'player_volume';

  // ============ 回调 ============
  VoidCallback? onVideoEnd;
  Function(Duration position, Duration totalDuration)? onProgressUpdate;
  Function(String quality)? onQualityChanged;
  /// 播放状态变化回调（true=播放中, false=暂停）
  Function(bool playing)? onPlayingStateChanged;

  // ============ 视频元数据（后台播放通知用）============
  String? _videoTitle;
  String? _videoAuthor;
  Uri? _videoCoverUri;

  // ============ 视频上下文（进度恢复用）============
  int? _currentVid;
  int _currentPart = 1;

  VideoPlayerController() {
    player = Player(
      configuration: const PlayerConfiguration(
        title: '',
        bufferSize: 32 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );

    videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    _setupListeners();
  }

  // ============================================================
  // 初始化
  // ============================================================

  Future<void> initialize({
    required int resourceId,
    double? initialPosition,
  }) async {
    // 防止并发初始化
    if (_isInitializing) {
      _logger.logWarning('[Controller] 已在初始化中，跳过重复调用', tag: 'PlayerController');
      return;
    }
    _isInitializing = true;

    try {
      _qualityCache.clear();
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;
      _userIntendedPosition = Duration(seconds: initialPosition?.toInt() ?? 0);
      _hasPlaybackStarted = false; // 重置播放状态

      // 并发：配置播放器 + 获取清晰度 + 加载设置
      await Future.wait([
        _configurePlayer(),
        _loadSettings(),
      ]);

      final qualities = await _hlsService.getAvailableQualities(resourceId);
      if (qualities.isEmpty) throw Exception('没有可用的清晰度');

      availableQualities.value = _sortQualities(qualities);
      currentQuality.value = await _getPreferredQuality(availableQualities.value);

      // 后台启动 AudioService
      _logger.logDebug('[Controller] backgroundPlayEnabled=${backgroundPlayEnabled.value}，决定是否启动 AudioService', tag: 'PlayerController');
      if (backgroundPlayEnabled.value) {
        _ensureAudioServiceReady().catchError((_) {});
      }

      // 加载视频
      await _loadVideo(currentQuality.value!, initialPosition: initialPosition);

      // 注意：isLoading=false 和 isPlayerInitialized=true 会在 _loadMediaInternal() 中设置
      // 这里不需要重复设置，避免 ValueListenableBuilder 多次触发
    } catch (e) {
      _logger.logError(message: '初始化失败', error: e, stackTrace: StackTrace.current);
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
    } finally {
      _isInitializing = false;
    }
  }

  /// 使用预加载的数据初始化播放器（避免重复请求HLS资源）
  ///
  /// 由 VideoPlayerManager 调用，资源已经预先加载好
  Future<void> initializeWithPreloadedData({
    required int resourceId,
    required List<String> qualities,
    required String selectedQuality,
    required MediaSource mediaSource,
    double? initialPosition,
  }) async {
    final loadId = '${DateTime.now().millisecondsSinceEpoch}_${resourceId}_${initialPosition?.toInt() ?? 0}';
    _currentLoadId = loadId;

    _logger.logDebug('[Controller][$loadId] 开始初始化: resourceId=$resourceId, initialPos=$initialPosition', tag: 'PlayerController');

    // 如果已经初始化过同一个资源且播放器正常，检查 initialPosition 是否变化
    if (isPlayerInitialized.value && _currentResourceId == resourceId && errorMessage.value == null) {
      // 如果 initialPosition 没变或没有，跳过
      final currentPosition = _userIntendedPosition.inSeconds;
      final newPosition = initialPosition?.toInt() ?? 0;
      if (currentPosition == newPosition || newPosition == 0) {
        _logger.logWarning('[Controller][$loadId] 资源已初始化且正常，位置未变化，跳过', tag: 'PlayerController');
        _currentLoadId = '';
        return;
      }
      // 位置变了，需要重新加载
      _logger.logDebug('[Controller][$loadId] 资源已初始化，但位置变化: $currentPosition -> $newPosition，重新加载', tag: 'PlayerController');
      isPlayerInitialized.value = false;
    }

    // 【关键】立即设置 isPlayerInitialized=false，避免中间状态
    _logger.logDebug('[Controller][$loadId] isPlayerInitialized=false', tag: 'PlayerController');
    isPlayerInitialized.value = false;

    try {
      _qualityCache.clear();
      _currentResourceId = resourceId;
      _logger.logDebug('[Controller] isLoading=true (Manager模式)', tag: 'PlayerController');
      isLoading.value = true;
      _logger.logDebug('[Controller] errorMessage=null', tag: 'PlayerController');
      errorMessage.value = null;
      _userIntendedPosition = Duration(seconds: initialPosition?.toInt() ?? 0);
      _hasPlaybackStarted = false; // 重置播放状态

      _logger.logDebug('[Controller] 使用预加载数据初始化: resourceId=$resourceId, quality=$selectedQuality', tag: 'PlayerController');

      // 并发：配置播放器 + 加载设置
      await Future.wait([
        _configurePlayer(),
        _loadSettings(),
      ]);

      // 使用预加载的清晰度列表
      availableQualities.value = _sortQualities(qualities);
      currentQuality.value = selectedQuality;

      // 后台启动 AudioService
      _logger.logDebug('[Controller] backgroundPlayEnabled=${backgroundPlayEnabled.value}，决定是否启动 AudioService', tag: 'PlayerController');
      if (backgroundPlayEnabled.value) {
        _ensureAudioServiceReady().catchError((_) {});
      }

      // 直接使用预加载的媒体源加载视频
      await _loadVideoWithMediaSource(
        mediaSource: mediaSource,
        quality: selectedQuality,
        initialPosition: initialPosition,
      );

      // 注意：isLoading=false 和 isPlayerInitialized=true 会在 _loadMediaInternal() 中设置
      // 这里不需要重复设置，避免 ValueListenableBuilder 多次触发
      _logger.logSuccess('[Controller] 预加载初始化完成', tag: 'PlayerController');
    } catch (e) {
      _logger.logError(message: '预加载初始化失败', error: e, stackTrace: StackTrace.current);
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
    } finally {
      _isInitializing = false;
    }
  }

  // ============================================================
  // 核心：加载视频
  // ============================================================

  /// 传统模式：自己获取资源并加载
  Future<void> _loadVideo(String quality, {double? initialPosition}) async {
    if (_isDisposed) return;

    final loadingResourceId = _currentResourceId;

    try {
      _logger.logDebug('[Load] 加载视频: quality=$quality, seekTo=${initialPosition ?? 0}s', tag: 'PlayerController');

      // 1. 获取资源
      final mediaSource = await _hlsService.getMediaSource(loadingResourceId!, quality);

      // 检查一致性：如果ID变了，说明已经切换了视频，终止当前加载
      if (_currentResourceId != loadingResourceId) return;
      //_logger.logDebug('[Load] 等待播放器就绪...');
      //await Future.delayed(const Duration(milliseconds: 70));

      // 2. 使用统一的内部加载方法
      await _loadMediaInternal(
        mediaSource: mediaSource,
        quality: quality,
        initialPosition: initialPosition,
        autoPlay: false,  // 传统模式不自动播放
        resourceIdCheck: () => _currentResourceId == loadingResourceId,
      );

    } catch (e) {
      // 只有当前资源匹配时才抛出异常给上层UI处理
      if (_currentResourceId == loadingResourceId) {
        _logger.logWarning('[Load] 失败: $e', tag: 'PlayerController');
        rethrow;
      }
    }
  }

  /// Manager模式：使用预加载的媒体源
  Future<void> _loadVideoWithMediaSource({
    required MediaSource mediaSource,
    required String quality,
    double? initialPosition,
  }) async {
    if (_isDisposed) return;

    _logger.logDebug('[Load] 使用预加载媒体源: quality=$quality, seekTo=${initialPosition ?? 0}s', tag: 'PlayerController');

    await _loadMediaInternal(
      mediaSource: mediaSource,
      quality: quality,
      initialPosition: initialPosition,
      autoPlay: true,  // Manager模式自动播放
      resourceIdCheck: null,  // Manager 已处理竞态
    );
  }

    /// 【统一】内部加载逻辑，避免代码重复
   Future<void> _loadMediaInternal({
     required MediaSource mediaSource,
     required String quality,
     double? initialPosition,
     required bool autoPlay,
     bool Function()? resourceIdCheck,
   }) async {
     final loadId = _currentLoadId;
     if (loadId.isEmpty) return;

     try {
       _hasTriggeredCompletion = false;
       final needSeek = initialPosition != null && initialPosition > 0;
       final targetPosition = Duration(seconds: initialPosition?.toInt() ?? 0);

       _logger.logDebug('[LoadInternal][$loadId] 开始: quality=$quality, needSeek=$needSeek, autoPlay=$autoPlay, target=${targetPosition.inSeconds}s', tag: 'PlayerController');

       if (!mediaSource.isDirectUrl) {
         _qualityCache[quality] = mediaSource;
       }

       final media = await _createMedia(mediaSource);

       _isSeeking = true;
       _logger.logDebug('[LoadInternal][$loadId] 调用 player.open', tag: 'PlayerController');
       await player.open(media, play: false);
       _logger.logDebug('[LoadInternal][$loadId] player.open 完成', tag: 'PlayerController');

       await _waitForVideoTrack();

       _logger.logDebug('[LoadInternal][$loadId] 等待缓冲...', tag: 'PlayerController');
       int waitCount = 0;
       while (player.state.buffering && waitCount < 10) {
         await Future.delayed(const Duration(milliseconds: 50));
         waitCount++;
       }
       _logger.logDebug('[LoadInternal][$loadId] 缓冲完成 (${waitCount * 50}ms)', tag: 'PlayerController');

       if (player.state.playing) {
         _logger.logDebug('[LoadInternal][$loadId] 暂停播放器', tag: 'PlayerController');
         await player.pause();
         await Future.delayed(const Duration(milliseconds: 30));
       }

       if (needSeek) {
         _logger.logDebug('[LoadInternal][$loadId] seek 到 ${targetPosition.inSeconds}s', tag: 'PlayerController');
         _userIntendedPosition = targetPosition;
         
         _logger.logDebug('[LoadInternal][$loadId] 播放让数据流动...', tag: 'PlayerController');
         await player.play();
         await Future.delayed(const Duration(milliseconds: 80));
         await player.pause();
         
         await player.seek(targetPosition);
         await Future.delayed(const Duration(milliseconds: 100));
         
         final actualPos = player.state.position.inSeconds;
         _logger.logDebug('[LoadInternal][$loadId] seek 验证: 目标=${targetPosition.inSeconds}s, 实际=$actualPos', tag: 'PlayerController');
         
         if ((actualPos - targetPosition.inSeconds).abs() > 1) {
           _logger.logWarning('[LoadInternal][$loadId] seek 未生效，再次尝试', tag: 'PlayerController');
           await player.seek(targetPosition);
           await Future.delayed(const Duration(milliseconds: 100));
           final retryPos = player.state.position.inSeconds;
           _logger.logDebug('[LoadInternal][$loadId] 重试后位置: $retryPos', tag: 'PlayerController');
         }
       }

       if (resourceIdCheck != null && !resourceIdCheck()) {
         _logger.logWarning('[LoadInternal][$loadId] 竞态检查失败，跳过', tag: 'PlayerController');
         _isSeeking = false;
         return;
       }

       _logger.logDebug('[LoadInternal][$loadId] autoPlay=$autoPlay, playing=${player.state.playing}', tag: 'PlayerController');
       if (autoPlay && !player.state.playing) {
         _logger.logDebug('[LoadInternal][$loadId] 调用 player.play()', tag: 'PlayerController');
         try {
           await player.play();

           int waitPlaying = 0;
           while (!player.state.playing && waitPlaying < 20) {
             await Future.delayed(const Duration(milliseconds: 50));
             waitPlaying++;
           }

           _logger.logDebug('[LoadInternal][$loadId] player.play() 完成, playing=${player.state.playing} (${waitPlaying * 50}ms)', tag: 'PlayerController');
         } catch (e) {
           _logger.logWarning('[LoadInternal][$loadId] player.play() 异常: $e', tag: 'PlayerController');
         }
       }

        await Future.delayed(const Duration(milliseconds: 100));

        if (player.state.playing) {
          _logger.logDebug('[LoadInternal][$loadId] 视频开始播放，设置 isLoading=false', tag: 'PlayerController');
          isLoading.value = false;
          isPlayerInitialized.value = true;
          _logger.logSuccess('[Controller][$loadId] 预加载初始化完成', tag: 'PlayerController');
          _currentLoadId = '';

          // 【新增】兜底 seek：确保进度恢复成功
          await _ensureSeekPosition();
        } else {
         _logger.logDebug('[LoadInternal][$loadId] 未开始播放，保持 loading', tag: 'PlayerController');
       }

       if (needSeek) {
         await Future.delayed(const Duration(milliseconds: 200));
         final actualPos = player.state.position.inSeconds;
         final diff = (actualPos - targetPosition.inSeconds).abs();
         if (diff > 2) {
           _logger.logWarning('[LoadInternal][$loadId] 位置偏差($actualPos vs ${targetPosition.inSeconds})，重试', tag: 'PlayerController');
           await player.seek(targetPosition);
         }
         _logger.logDebug('[LoadInternal][$loadId] 进度恢复完成: ${player.state.position.inSeconds}s', tag: 'PlayerController');
       }

       _isSeeking = false;
       _preloadAdjacentQualities();

     } catch (e) {
       _isSeeking = false;
       _logger.logWarning('[LoadInternal][$loadId] 失败: $e', tag: 'PlayerController');
       isLoading.value = false;
       errorMessage.value = e.toString();
       _currentLoadId = '';
     }
   }

  // ============================================================
  // 核心：Seek
  // ============================================================

  Timer? _seekTimer;

  Future<void> seek(Duration position) async {
    if (position < Duration.zero) position = Duration.zero;
    _logger.logDebug('[Seek] 目标: ${position.inSeconds}s', tag: 'PlayerController');

    _userIntendedPosition = position;
    _isSeeking = true;

    try {
      if (player.state.duration.inSeconds != 0) {
        await player.seek(position);
        await Future.delayed(const Duration(milliseconds: 100));
      } else {
        _seekTimer?.cancel();
        _seekTimer = _startSeekTimer(position);
      }
    } finally {
      _isSeeking = false;
    }
  }

  Timer? _startSeekTimer(Duration position) {
    return Timer.periodic(const Duration(milliseconds: 200), (Timer t) async {
      if (player.state.duration.inSeconds != 0) {
        await player.stream.buffer.first;
        await player.seek(position);
        t.cancel();
        _seekTimer = null;
      }
    });
  }

  /// 【新增】兜底 seek：确保进度恢复成功
  ///
  /// 当播放器就绪后，检查是否有待执行的 seek 位置
  /// 如果有，执行 seek 并验证，偏差大于1秒则重试
  Future<void> _ensureSeekPosition() async {
    if (_pendingSeekPosition == null) return;
    if (_isDisposed) return;

    final targetPosition = _pendingSeekPosition!;
    _pendingSeekPosition = null; // 清除待执行标记

    _logger.logDebug('[EnsureSeek] 开始兜底 seek: $targetPosition', tag: 'PlayerController');

    try {
      // 【修复】如果当前正在播放，保持播放状态；否则只 seek 不播放
      final wasPlaying = player.state.playing;

      // 直接 seek，不调用 play/pause 避免影响自动播放
      await player.seek(Duration(seconds: targetPosition.toInt()));
      await Future.delayed(const Duration(milliseconds: 100));

      final actualPos = player.state.position.inSeconds;
      final diff = (actualPos - targetPosition).abs();

      if (diff > 1) {
        _logger.logWarning('[EnsureSeek] 位置偏差($actualPos vs $targetPosition)，重试', tag: 'PlayerController');
        await player.seek(Duration(seconds: targetPosition.toInt()));
        await Future.delayed(const Duration(milliseconds: 100));
        final retryPos = player.state.position.inSeconds;
        _logger.logDebug('[EnsureSeek] 重试后位置: $retryPos', tag: 'PlayerController');
      } else {
        _logger.logDebug('[EnsureSeek] 成功: $actualPos', tag: 'PlayerController');
      }

      // 【修复】如果之前是播放状态，恢复播放
      if (wasPlaying && !player.state.playing) {
        await player.play();
        _logger.logDebug('[EnsureSeek] 恢复播放', tag: 'PlayerController');
      }
    } catch (e) {
      _logger.logWarning('[EnsureSeek] 失败: $e', tag: 'PlayerController');
    }
  }

  /// 【新增】设置待执行的 seek 位置（用于异步进度恢复）
  void setPendingSeekPosition(double? position) {
    if (position != null && position > 0) {
      _pendingSeekPosition = position;
      _validationTargetPosition = position;  // 设置校验目标
      _progressValidated = false;  // 重置校验状态
      _userIntendedPosition = Duration(seconds: position.toInt());
      _logger.logDebug('[PendingSeek] 设置待执行 seek: $position', tag: 'PlayerController');
    }
  }

  /// 【新增】播放时校验进度
  ///
  /// 当真正开始播放时，检查当前位置是否与目标进度一致
  /// 如果偏差大于2秒，执行 seek 校正
  Future<void> _validateProgressOnPlayback() async {
    if (_validationTargetPosition == null || _isDisposed) return;

    final currentPosition = player.state.position.inSeconds;
    final targetPosition = _validationTargetPosition!;
    final diff = (currentPosition - targetPosition).abs();

    _logger.logDebug('[ProgressValidate] 开始校验: 当前=$currentPosition, 目标=$targetPosition, 偏差=${diff.toStringAsFixed(1)}s', tag: 'PlayerController');

    // 偏差大于2秒，需要校正
    if (diff > 2) {
      _logger.logWarning('[ProgressValidate] 进度偏差大($currentPosition vs $targetPosition)，执行 seek', tag: 'PlayerController');
      await player.seek(Duration(seconds: targetPosition.toInt()));
      await Future.delayed(const Duration(milliseconds: 100));

      final newPosition = player.state.position.inSeconds;
      final newDiff = (newPosition - targetPosition).abs();

      if (newDiff <= 2) {
        _logger.logSuccess('[ProgressValidate] 校验成功: $newPosition', tag: 'PlayerController');
        _progressValidated = true;
      } else {
        _logger.logWarning('[ProgressValidate] 校验失败: $newPosition，重试', tag: 'PlayerController');
        // 再试一次
        await player.seek(Duration(seconds: targetPosition.toInt()));
        await Future.delayed(const Duration(milliseconds: 100));
        final retryPosition = player.state.position.inSeconds;
        _logger.logDebug('[ProgressValidate] 重试后: $retryPosition', tag: 'PlayerController');
        _progressValidated = true;
      }
    } else {
      // 偏差在可接受范围内，标记为已校验
      _logger.logSuccess('[ProgressValidate] 校验通过: 当前=$currentPosition (偏差=${diff.toStringAsFixed(1)}s)', tag: 'PlayerController');
      _progressValidated = true;
    }

    // 清除校验目标
    _validationTargetPosition = null;
  }

  /// 从服务端获取并恢复播放进度
  ///
  /// 使用内部的 _currentVid 和 _currentPart，无需外部传参
  /// 典型场景：用户登录后调用此方法同步服务端进度
  /// 【关键】只能在播放器就绪后才能调用，否则 seek 可能被丢弃
  Future<void> fetchAndRestoreProgress() async {
    if (_isDisposed) return;

    // 【防抖】500ms内重复调用直接跳过
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastProgressFetchTime != null && now - _lastProgressFetchTime! < 500) {
      _logger.logDebug('[Progress] 500ms内重复调用，跳过', tag: 'PlayerController');
      return;
    }
    _lastProgressFetchTime = now;

    // 检查视频上下文是否已设置
    if (_currentVid == null) {
      _logger.logWarning('[Progress] 视频上下文未设置，跳过进度恢复', tag: 'PlayerController');
      return;
    }

    // 【关键】检查播放器是否已就绪
    if (!isPlayerInitialized.value) {
      _logger.logDebug('[Progress] 播放器未就绪，设置延迟恢复', tag: 'PlayerController');
      // 延迟等待播放器就绪
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!_isDisposed && _currentVid != null) {
          _logger.logDebug('[Progress] 播放器已就绪，尝试恢复进度', tag: 'PlayerController');
          await _doFetchAndRestoreProgress();
        }
      });
      return;
    }

    await _doFetchAndRestoreProgress();
  }

  /// 实际执行进度恢复的内部方法
  Future<void> _doFetchAndRestoreProgress() async {
    // 检查视频上下文
    if (_currentVid == null) return;

    // 【防抖】再次检查
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastProgressFetchTime != null && now - _lastProgressFetchTime! < 500) {
      _logger.logDebug('[Progress] 500ms内重复调用，跳过', tag: 'PlayerController');
      return;
    }
    _lastProgressFetchTime = now;

    // 【关键】检查视频是否已切换
    final requestVid = _currentVid!;
    final requestPart = _currentPart;

    try {
      _logger.logDebug('[Progress] 开始获取服务端进度: vid=$requestVid, part=$requestPart', tag: 'PlayerController');
      final historyService = HistoryService();
      final progressData = await historyService.getProgress(vid: requestVid, part: requestPart);

      // 【关键】检查视频是否已切换
      if (_isDisposed || _currentVid != requestVid || _currentPart != requestPart) {
        _logger.logWarning('[Progress] 视频已切换 (请求: vid=$requestVid/part=$requestPart, 当前: vid=$_currentVid/part=$_currentPart)，丢弃旧数据', tag: 'PlayerController');
        return;
      }

      if (progressData == null) {
        _logger.logDebug('[Progress] 无历史进度数据', tag: 'PlayerController');
        return;
      }

      final progress = progressData.progress;
      _logger.logDebug('[Progress] 获取到进度: $progress', tag: 'PlayerController');

      final currentPos = player.state.position.inSeconds;
      final targetPos = progress.toInt();

      // 只有当服务端进度明显不同时才 seek（差异超过3秒）
      if ((targetPos - currentPos).abs() > 3) {
        _logger.logDebug('[Progress] 恢复服务端进度: $currentPos -> $targetPos 秒', tag: 'PlayerController');
        
        // 【关键】HLS 流在暂停状态下 seek 不生效，需要先播放一下
        if (!player.state.playing) {
          await player.play();
          await Future.delayed(const Duration(milliseconds: 80));
          await player.pause();
        }
        
        await seek(Duration(seconds: targetPos));
      } else {
        _logger.logDebug('[Progress] 进度差异小于3秒，无需 seek', tag: 'PlayerController');
      }
    } catch (e) {
      _logger.logWarning('[Progress] 恢复历史进度失败: $e', tag: 'PlayerController');
    }
  }

  // ============================================================
  // 核心：切换清晰度
  // ============================================================

  Future<void> changeQuality(String quality) async {
    if (currentQuality.value == quality) return;

    // 记录当前状态（在暂停前获取）
    final wasPlaying = player.state.playing;
    final currentPos = player.state.position;
    // 优先使用当前播放位置，否则使用用户意图位置
    final rawTargetPosition = currentPos.inMilliseconds > 0 ? currentPos : _userIntendedPosition;

    // 【关键】回退2秒避免HLS分片边界问题
    final targetPosition = rawTargetPosition.inSeconds > 2
        ? Duration(seconds: rawTargetPosition.inSeconds - 2)
        : rawTargetPosition;

    _logger.logDebug('[Quality] 切换: $quality, 原位置=${rawTargetPosition.inSeconds}s, 目标位置=${targetPosition.inSeconds}s (回退2秒)', tag: 'PlayerController');

    // 暂停
    await player.pause();

    // 防抖
    _qualityDebounceTimer?.cancel();
    _qualityEpoch++;
    final myEpoch = _qualityEpoch;
    isSwitchingQuality.value = true;

    _qualityDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (myEpoch != _qualityEpoch || _isDisposed) return;

      try {
        // 获取资源
        final mediaSource = await _hlsService.getMediaSource(_currentResourceId!, quality);
        final media = await _createMedia(mediaSource);

        // 打开视频
        await player.open(media, play: false);
        await _waitForDuration();

        // 【关键改进】确保恢复进度，使用多次重试机制
        if (targetPosition.inMilliseconds > 0) {
          await _seekWithRetry(targetPosition, maxRetries: 3);
        }

        // 更新状态
        currentQuality.value = quality;
        await _savePreferredQuality(quality);
        _userIntendedPosition = targetPosition;

        // 恢复播放并再次验证位置
        if (wasPlaying) {
          await player.play();

          // 【关键】播放后再次检查位置，防止 MPV 重置
          await Future.delayed(const Duration(milliseconds: 150));
          final afterPlayPos = player.state.position;
          final diff = (afterPlayPos.inSeconds - targetPosition.inSeconds).abs();

           if (diff > 3 && targetPosition.inSeconds > 3) {
             _logger.logWarning('[Quality] 播放后位置被重置 (${afterPlayPos.inSeconds}s vs ${targetPosition.inSeconds}s)，重新 seek', tag: 'PlayerController');
             await player.seek(targetPosition);
           }
         }

         _logger.logSuccess('[Quality] 切换完成，最终位置=${player.state.position.inSeconds}s', tag: 'PlayerController');
         onQualityChanged?.call(quality);
         _preloadAdjacentQualities();

       } catch (e) {
         _logger.logWarning('[Quality] 切换失败: $e', tag: 'PlayerController');
         errorMessage.value = '切换清晰度失败';
      } finally {
        isSwitchingQuality.value = false;
      }
    });
  }

    /// 【简化】带重试的 seek 方法，确保切换清晰度时进度恢复成功
   Future<void> _seekWithRetry(Duration targetPosition, {int maxRetries = 3}) async {
     final targetSeconds = targetPosition.inSeconds;
     _logger.logDebug('[SeekRetry] 开始 seek 到 ${targetSeconds}s', tag: 'PlayerController');

     for (int attempt = 1; attempt <= maxRetries; attempt++) {
       try {
         await player.play();
         await Future.delayed(const Duration(milliseconds: 80));
         await player.pause();

         await player.seek(targetPosition);
         await Future.delayed(const Duration(milliseconds: 200));

         final actualPos = player.state.position.inSeconds;
         final diff = (actualPos - targetSeconds).abs();

         if (diff <= 3) {
           _logger.logSuccess('[SeekRetry] seek 成功: $actualPos/$targetSeconds', tag: 'PlayerController');
           return;
         }

         _logger.logWarning('[SeekRetry] 偏差: $actualPos/$targetSeconds');
         if (attempt < maxRetries) {
           await Future.delayed(const Duration(milliseconds: 100));
         }
       } catch (e) {
         _logger.logWarning('[SeekRetry] 第 $attempt 次异常: $e', tag: 'PlayerController');
         if (attempt == maxRetries) rethrow;
       }
     }

     _logger.logWarning('[SeekRetry] 重试失败，直接 seek', tag: 'PlayerController');
     await player.seek(targetPosition);
   }

  // ============================================================
  // 监听器
  // ============================================================

  void _setupListeners() {
    // 进度监听
    _positionSubscription = player.stream.position.listen((position) {
      // UI 始终更新
      _positionStreamController.add(position);

      // seek 过程中，不更新期望位置
      if (_isSeeking || isSwitchingQuality.value) return;

      // 【关键修复】如果还没正式开始播放，跳过
      // 但如果位置已经稳定且大于0，则允许（用于重播场景）
      if (!_hasPlaybackStarted) {
        // 首帧或位置为0时不更新不上报
        if (position.inSeconds == 0) return;
        // 位置大于0且不是首帧，标记为稳定并允许
        _hasPlaybackStarted = true;
      }

      // 正常播放时，跟随实际位置
      _userIntendedPosition = position;

      // 节流上报（每 500ms）
      if (onProgressUpdate != null) {
        // 【关键】位置为0时不上报
        if (position.inSeconds == 0) return;
        
        final diff = (position.inMilliseconds - _lastReportedPosition.inMilliseconds).abs();
        if (diff >= 500) {
          _lastReportedPosition = position;
          onProgressUpdate!(position, player.state.duration);
        }
      }
    });

    // 完播监听
    _completedSubscription = player.stream.completed.listen((completed) {
      if (completed && !_hasTriggeredCompletion && !_isSeeking) {
        _hasTriggeredCompletion = true;
        _heartBeatService.onCompleted(duration: player.state.duration.inSeconds);
        _handlePlaybackEnd();
      }
    });

    // 播放状态监听 + Wakelock + 心跳
    _playingSubscription = player.stream.playing.listen((playing) async {
      if (playing && _hasTriggeredCompletion) {
        _hasTriggeredCompletion = false;
      }

      // 通知播放状态变化
      onPlayingStateChanged?.call(playing);

      // 【新增】进度校验：真正播放时检查进度是否正确
      if (playing && _validationTargetPosition != null && !_progressValidated) {
        await _validateProgressOnPlayback();
      }

      if (playing) {
        WakelockManager.enable();
        _heartBeatService.onPlaying(progress: player.state.position.inSeconds);
      } else {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!player.state.playing) {
            WakelockManager.disable();
            _heartBeatService.onPaused(progress: player.state.position.inSeconds);
          }
        });
      }
    });

    // 缓冲监听
    _bufferingSubscription = player.stream.buffering.listen((buffering) {
      isBuffering.value = buffering;

      if (buffering) {
        _stalledTimer?.cancel();
         _stalledTimer = Timer(const Duration(seconds: 15), () {
           if (player.state.buffering) {
             _logger.logWarning('播放卡顿，尝试恢复...', tag: 'PlayerController');
             _handleStalled();
           }
         });
      } else {
        _stalledTimer?.cancel();
      }
    });

    // 网络监听
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final isConnected = results.any((r) => r != ConnectivityResult.none);
      if (isConnected && errorMessage.value != null) {
        errorMessage.value = null;
        _handleStalled();
      }
    });

    // 音频打断监听
    _setupAudioInterruptionListener();
    _setupCallStateListener();
  }

  void _handlePlaybackEnd() {
    if (loopMode.value == LoopMode.on) {
      seek(Duration.zero).then((_) => player.play());
    } else {
      onVideoEnd?.call();
    }
  }

   Future<void> _handleStalled() async {
     // 【修改】新增卫语句：如果正在初始化或处于Loading状态，严禁触发重载
     if (_isInitializing || isLoading.value) {
       _logger.logDebug('[Stalled] 正在初始化或加载中，忽略卡顿检测', tag: 'PlayerController');
       return;
     }
     
     if (_currentResourceId == null || currentQuality.value == null) return;

     try {
       final position = _userIntendedPosition;
       _logger.logDebug('[Stalled] 恢复: position=${position.inSeconds}s', tag: 'PlayerController');

       final mediaSource = await _hlsService.getMediaSource(_currentResourceId!, currentQuality.value!);
       final media = await _createMedia(mediaSource);

       await player.open(media, play: false);
       await _waitForDuration();

       if (position.inSeconds > 0) {
         await player.seek(position);
         await Future.delayed(const Duration(milliseconds: 200));
       }

       await player.play();
     } catch (e) {
       _logger.logWarning('[Stalled] 恢复失败: $e', tag: 'PlayerController');
     }
   }

  // ============================================================
  // 辅助方法
  // ============================================================

  /// 临时文件计数器，用于生成唯一文件名
  int _tempFileCounter = 0;

   /// 临时目录列表，用于退出时清理
  final List<Directory> _tempDirs = [];

  Future<Media> _createMedia(MediaSource source, {Duration? start}) async {
    if (source.isDirectUrl) {
      return Media(source.content);
    } else {
      final tempFile = await _writeTempM3u8File(source.content);
      return Media(tempFile.path, start: start);
    }
  }

   /// 将 m3u8 内容写入临时文件
  Future<File> _writeTempM3u8File(String content) async {
    final tempDir = await Directory.systemTemp.createTemp('hls_');
    _tempDirs.add(tempDir);
    final fileName = 'playlist_${_tempFileCounter++}_${DateTime.now().millisecondsSinceEpoch}.m3u8';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(content);
    return file;
  }

  /// 清理所有临时文件（退出时调用）
  Future<void> _cleanupTempFiles() async {
    for (final dir in _tempDirs) {
      try {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          _logger.logDebug('[Cleanup] 已删除临时目录: ${dir.path}', tag: 'PlayerController');
        }
      } catch (e) {
        _logger.logWarning('[Cleanup] 删除临时目录失败: ${dir.path}, $e', tag: 'PlayerController');
      }
    }
    _tempDirs.clear();
  }

  /// 等待视频轨道就绪
  ///
  /// 确保视频画面已经可以显示后再继续，解决音视频同步问题
  Future<void> _waitForVideoTrack({Duration timeout = const Duration(seconds: 5)}) async {
    _logger.logDebug('[_waitForVideoTrack] 开始检查视频轨道', tag: 'PlayerController');

    final currentTrack = player.state.track;
    final hasVideo = currentTrack.video.id.isNotEmpty;
    if (hasVideo) {
      _logger.logDebug('[_waitForVideoTrack] 视频轨道已存在', tag: 'PlayerController');
      return;
    }

    final completer = Completer<void>();
    StreamSubscription? sub;

    sub = player.stream.track.listen((track) {
      final trackHasVideo = track.video.id.isNotEmpty;
      if (trackHasVideo && !completer.isCompleted) {
        _logger.logDebug('[_waitForVideoTrack] 收到视频轨道', tag: 'PlayerController');
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(timeout, onTimeout: () {
        _logger.logDebug('[_waitForVideoTrack] 超时，视频轨道仍未可用', tag: 'PlayerController');
      });
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _waitForDuration({Duration timeout = const Duration(seconds: 5)}) async {
     _logger.logDebug('[_waitForDuration] 开始检查 duration，当前: ${player.state.duration.inSeconds}s', tag: 'PlayerController');
     if (player.state.duration.inSeconds > 0) {
       _logger.logDebug('[_waitForDuration] duration 已存在，立即返回', tag: 'PlayerController');
       return;
     }

       final completer = Completer<void>();
       StreamSubscription? sub;

        sub = player.stream.duration.listen((duration) {
          _logger.logDebug('[_waitForDuration] 收到 duration 事件: ${duration.inSeconds}s', tag: 'PlayerController');
          if (duration.inSeconds > 0 && !completer.isCompleted) {
            _heartBeatService.updateDuration(duration.inSeconds);
            completer.complete();
          }
        });

       try {
         _logger.logDebug('[_waitForDuration] 等待 duration (超时: ${timeout.inSeconds}s)...', tag: 'PlayerController');
         await completer.future.timeout(timeout, onTimeout: () {
           _logger.logDebug('[_waitForDuration] 超时，duration 仍未可用 (当前: ${player.state.duration.inSeconds}s)', tag: 'PlayerController');
         });
         _logger.logDebug('[_waitForDuration] 完成', tag: 'PlayerController');
       } finally {
         await sub.cancel();
       }
     }

     Future<void> _configurePlayer() async {
      if (kIsWeb) return;

      try {
        final nativePlayer = player.platform as NativePlayer?;
        if (nativePlayer == null) return;

        await nativePlayer.setProperty('cache', 'yes');
        await nativePlayer.setProperty('cache-secs', '60');
        await nativePlayer.setProperty('demuxer-readahead-secs', '30');
        await nativePlayer.setProperty('demuxer-max-bytes', '512M');
        await nativePlayer.setProperty('demuxer-max-back-bytes', '200M');
        await nativePlayer.setProperty('demuxer-seekable-cache', 'yes');

        await nativePlayer.setProperty('video-latency-hack', 'yes');
        await nativePlayer.setProperty('video-queue', 'yes');
        await nativePlayer.setProperty('video-queue-max-bytes', '50M');
        await nativePlayer.setProperty('video-queue-min-bytes', '1M');

        await nativePlayer.setProperty('stream-lavf-o',
            'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
            'reconnect_delay_max=10,'
            'threads=4');
        await nativePlayer.setProperty('network-timeout', '15');

        await nativePlayer.setProperty('hls-bitrate', 'max');
        await nativePlayer.setProperty('initial-byte-range', 'yes');

        await nativePlayer.setProperty('hr-seek', 'absolute');
        await nativePlayer.setProperty('hr-seek-framedrop', 'no');

        await nativePlayer.setProperty('video-buffer-time', '5');
        await nativePlayer.setProperty('audio-buffer-time', '2');

        // 解码模式
        await nativePlayer.setProperty('hwdec', _currentDecodeMode);

        _logger.logSuccess('MPV 激缓存配置完成', tag: 'PlayerController');
      } catch (e) {
        _logger.logWarning('MPV 配置失败: $e', tag: 'PlayerController');
      }
    }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    loopMode.value = LoopModeExtension.fromString(prefs.getString(_loopModeKey));
    backgroundPlayEnabled.value = prefs.getBool(_backgroundPlayKey) ?? false;
    _logger.logDebug('[Settings] backgroundPlayEnabled=${backgroundPlayEnabled.value}', tag: 'PlayerController');
    _currentDecodeMode = prefs.getString(_decodeModeKey) ?? 'no';

     // 在视频播放前预先设置音量，避免初始化时音量过大
     final savedVolume = prefs.getDouble(_volumeKey) ?? 100.0;
     await player.setVolume(savedVolume);
     _logger.logSuccess('预设音量: ${savedVolume.toInt()}%', tag: 'PlayerController');
   }

  void _preloadAdjacentQualities() {
    _preloadTimer?.cancel();
    _preloadTimer = Timer(const Duration(seconds: 5), () async {
      if (currentQuality.value == null || _currentResourceId == null) return;

      final currentIndex = availableQualities.value.indexOf(currentQuality.value!);
      if (currentIndex == -1) return;

      // 预加载下一档
      if (currentIndex < availableQualities.value.length - 1) {
        final nextQuality = availableQualities.value[currentIndex + 1];
        if (!_qualityCache.containsKey(nextQuality)) {
           try {
             final mediaSource = await _hlsService.getMediaSource(_currentResourceId!, nextQuality);
             if (!mediaSource.isDirectUrl) {
               _qualityCache[nextQuality] = mediaSource;
               _logger.logSuccess('预加载: ${HlsService.getQualityLabel(nextQuality)}', tag: 'PlayerController');
             }
           } catch (_) {}
        }
      }
    });
  }

  // ============================================================
  // 播放控制
  // ============================================================

  Future<void> play() async => await player.play();
  Future<void> pause() async => await player.pause();
  Future<void> setRate(double rate) async => await player.setRate(rate);

  void toggleLoopMode() async {
    final newMode = loopMode.value.toggle();
    loopMode.value = newMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loopModeKey, newMode.toSavedString());
  }

  // ============================================================
  // 清晰度相关
  // ============================================================

  Future<String> _getPreferredQuality(List<String> qualities) async {
    final prefs = await SharedPreferences.getInstance();
    final preferredName = prefs.getString(_preferredQualityKey);
    return findBestQualityMatch(qualities, preferredName);
  }

  Future<void> _savePreferredQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredQualityKey, getQualityDisplayName(quality));
  }

  List<String> _sortQualities(List<String> qualities) {
    final sorted = List<String>.from(qualities);
    sorted.sort((a, b) {
      final resA = _parseResolution(a);
      final resB = _parseResolution(b);
      if (resA != resB) return resB.compareTo(resA);
      return _parseFrameRate(b).compareTo(_parseFrameRate(a));
    });
    return sorted;
  }

  int _parseResolution(String quality) {
    try {
      final parts = quality.split('_');
      if (parts.isEmpty) return 0;
      final dims = parts[0].split('x');
      if (dims.length != 2) return 0;
      return (int.tryParse(dims[0]) ?? 0) * (int.tryParse(dims[1]) ?? 0);
    } catch (_) {
      return 0;
    }
  }

  int _parseFrameRate(String quality) {
    try {
      final parts = quality.split('_');
      return parts.length >= 3 ? (int.tryParse(parts[2]) ?? 30) : 30;
    } catch (_) {
      return 30;
    }
  }

  String getQualityDisplayName(String quality) {
    return formatQualityDisplayName(quality);
  }

  // ============================================================
  // 解码模式
  // ============================================================

  static Future<String> getDecodeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_decodeModeKey) ?? 'no';
  }

  static Future<void> setDecodeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_decodeModeKey, mode);
  }

  static String getDecodeModeDisplayName(String mode) {
    return mode == 'no' ? '软解码' : '硬解码';
  }

  // ============================================================
  // 后台播放
  // ============================================================

  Future<void> toggleBackgroundPlay() async {
    backgroundPlayEnabled.value = !backgroundPlayEnabled.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundPlayKey, backgroundPlayEnabled.value);

    if (backgroundPlayEnabled.value) {
      _ensureAudioServiceReady();
    }
  }

    Future<void> _ensureAudioServiceReady() async {
      _logger.logDebug('[AudioService] _ensureAudioServiceReady() 被调用', tag: 'PlayerController');
      try {
        if (_audioServiceInitialized && _audioHandler != null) {
          _logger.logDebug('[AudioService] 已有实例，只更新 player', tag: 'PlayerController');
          _audioHandler!.setPlayer(player);
          _updateAudioServiceMetadata();
          return;
        }

       if (!_audioServiceInitialized) {
         _logger.logDebug('[AudioService] 开始初始化...', tag: 'PlayerController');
         _audioHandler = await AudioService.init(
           builder: () => VideoAudioHandler(player),
           config: const AudioServiceConfig(
             androidNotificationChannelId: 'com.alnitak.video_playback',
             androidNotificationChannelName: '视频播放',
             androidNotificationOngoing: false,
             androidStopForegroundOnPause: false,
             androidNotificationIcon: 'mipmap/ic_launcher',
           ),
         );
         _audioServiceInitialized = true;
         _logger.logDebug('[AudioService] 初始化完成', tag: 'PlayerController');
         // 附加 player 并同步已有的媒体元数据（如果有）
         _audioHandler?.setPlayer(player);
         _updateAudioServiceMetadata();
       }
     } catch (e) {
       _logger.logWarning('AudioService 初始化失败: $e', tag: 'PlayerController');
     }
   }

  void setVideoMetadata({required String title, String? author, Uri? coverUri}) {
    _videoTitle = title;
    _videoAuthor = author;
    _videoCoverUri = coverUri;
    _updateAudioServiceMetadata();
  }

    /// 设置视频上下文（用于进度恢复和心跳上报）
    ///
    /// 在切换视频/分P时调用，让 Controller 知道当前播放的是哪个视频
    void setVideoContext({required int vid, int part = 1}) {
      _currentVid = vid;
      _currentPart = part;
      _logger.logDebug('[Controller] 设置视频上下文: vid=$vid, part=$part', tag: 'PlayerController');
      _heartBeatService.startHeartBeat(
        vid: vid,
        part: part,
        duration: player.state.duration.inSeconds,
        enableHeart: true,
      );
    }

  /// 更新 AudioService 的媒体信息
  void _updateAudioServiceMetadata() {
    if (_audioHandler == null || _currentResourceId == null) return;
    if (_videoTitle == null) return;

    _audioHandler!.setMediaItem(
      id: 'video_$_currentResourceId',
      title: _videoTitle!,
      artist: _videoAuthor,
      duration: player.state.duration,
      artUri: _videoCoverUri,
    );
  }

  Future<void> stopBackgroundPlayback() async {
    await _audioHandler?.stop();
  }

  // ============================================================
  // 生命周期
  // ============================================================

  void handleAppLifecycleState(bool isPaused) {
    if (isPaused) {
      _wasPlayingBeforeBackground = player.state.playing;
      if (backgroundPlayEnabled.value && _wasPlayingBeforeBackground) {
        // 开关打开 → 切后台时继续播放
        WakelockManager.enable();
        _audioHandler?.updatePlaybackState(
          playing: true,
          position: player.state.position,
        );
      } else if (_wasPlayingBeforeBackground) {
        // 开关关闭 → 切后台时暂停
        player.pause();
      }
    } else {
      // 切回前台时：之前在播放就恢复
      if (_wasPlayingBeforeBackground) {
        player.play();
      }
      _wasPlayingBeforeBackground = false;
    }
  }

  void _setupAudioInterruptionListener() {
    AudioSession.instance.then((session) async {
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.moviePlayback,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.movie,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));

      await session.setActive(true);

      _audioInterruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          if (event.type == AudioInterruptionType.pause || event.type == AudioInterruptionType.unknown) {
            _wasPlayingBeforeInterruption = player.state.playing;
            if (_wasPlayingBeforeInterruption) player.pause();
          }
        } else {
          if (event.type == AudioInterruptionType.pause && _wasPlayingBeforeInterruption) {
            player.play();
            _wasPlayingBeforeInterruption = false;
          }
        }
      });
    }).catchError((_) {});
  }

  void _setupCallStateListener() {
    try {
      _callStateHandler = CallStateHandler();
      _callStateHandler!.initialize().then((_) {
        _callStateSubscription = _callStateHandler!.onCallStateChanged.listen((state) {
          if (state.isCallActive) {
            if (!_wasPlayingBeforeInterruption && player.state.playing) {
              _wasPlayingBeforeInterruption = true;
              player.pause();
            }
          } else {
            if (_wasPlayingBeforeInterruption) {
              player.play();
              _wasPlayingBeforeInterruption = false;
            }
          }
        });
      }).catchError((_) {});
    } catch (_) {}
  }

  // ============================================================
  // 清理
  // ============================================================

  Future<void> _disposePlayer() async {
    _logger.logDebug('[_disposePlayer] 开始释放 Player', tag: 'PlayerController');

    _playerDisposeCompleter = Completer<void>();

    _positionSubscription?.cancel();
    _completedSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _audioInterruptionSubscription?.cancel();
    _callStateSubscription?.cancel();
    _callStateHandler?.dispose();

    if (!_positionStreamController.isClosed) {
      _positionStreamController.close();
    }

    _qualityCache.clear();
    WakelockManager.disable();
    _audioHandler?.stop();

    try {
      if (player.state.playing || player.state.buffering || player.state.position.inSeconds > 0) {
        _logger.logDebug('[_disposePlayer] 停止播放器', tag: 'PlayerController');
        player.stop();
      }

      _logger.logDebug('[_disposePlayer] 等待播放器停止...', tag: 'PlayerController');
      int waitCount = 0;
      while (player.state.playing && waitCount < 20) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitCount++;
      }

      _logger.logDebug('[_disposePlayer] 销毁播放器', tag: 'PlayerController');
      player.dispose();
      _logger.logSuccess('[_disposePlayer] Player 已完全释放', tag: 'PlayerController');
    } catch (e) {
      _logger.logWarning('[_disposePlayer] 释放失败: $e', tag: 'PlayerController');
    }

    if (!_playerDisposeCompleter!.isCompleted) {
      _playerDisposeCompleter!.complete();
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _logger.logDebug('[Controller] dispose 开始', tag: 'PlayerController');

    _qualityDebounceTimer?.cancel();
    _stalledTimer?.cancel();
    _preloadTimer?.cancel();
    _seekTimer?.cancel();

    _heartBeatService.stopHeartBeat();

    availableQualities.dispose();
    currentQuality.dispose();
    isLoading.dispose();
    errorMessage.dispose();
    isPlayerInitialized.dispose();
    isSwitchingQuality.dispose();
    loopMode.dispose();
    backgroundPlayEnabled.dispose();
    isBuffering.dispose();

    _disposePlayer();

    _logger.logDebug('[Controller] 开始清理临时文件', tag: 'PlayerController');
    _cleanupTempFiles().then((_) {
      _logger.logSuccess('[Controller] 临时文件清理完成', tag: 'PlayerController');
    }).catchError((e) {
      _logger.logWarning('[Controller] 临时文件清理失败: $e', tag: 'PlayerController');
    });

    super.dispose();
  }
}
