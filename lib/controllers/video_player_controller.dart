import 'dart:async';
import 'dart:convert';
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
import '../services/logger_service.dart';
import '../services/audio_service_handler.dart';
import '../models/loop_mode.dart';
import '../utils/wakelock_manager.dart';
import '../utils/error_handler.dart';

/// 视频播放器控制器 (V2 - 简化版)
///
/// 行业级标准设计：
/// 1. 用户意图优先：用户期望的进度就是"真实进度"
/// 2. 简单状态机：加载中 -> 播放中 -> 已完成
/// 3. 最小化状态变量：不追踪复杂的中间状态
class VideoPlayerController extends ChangeNotifier {
  final HlsService _hlsService = HlsService();
  final LoggerService _logger = LoggerService.instance;
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

  /// 【核心】用户期望的进度位置
  /// - seek 时更新为目标位置
  /// - 播放时跟随实际位置
  /// - 上报进度时使用此值
  Duration _userIntendedPosition = Duration.zero;

  /// 是否正在执行 seek（用于防止 seek 过程中的进度上报）
  bool _isSeeking = false;

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

  // ============ 回调 ============
  VoidCallback? onVideoEnd;
  Function(Duration position, Duration totalDuration)? onProgressUpdate;
  Function(String quality)? onQualityChanged;

  // ============ 视频元数据（后台播放通知用）============
  String? _videoTitle;
  String? _videoAuthor;
  Uri? _videoCoverUri;

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
    try {
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;
      _userIntendedPosition = Duration(seconds: initialPosition?.toInt() ?? 0);

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
      if (backgroundPlayEnabled.value) {
        _ensureAudioServiceReady().catchError((_) {});
      }

      // 加载视频
      await _loadVideo(currentQuality.value!, initialPosition: initialPosition);

      isLoading.value = false;
      isPlayerInitialized.value = true;
    } catch (e) {
      _logger.logError(message: '初始化失败', error: e, stackTrace: StackTrace.current);
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
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
    try {
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;
      _userIntendedPosition = Duration(seconds: initialPosition?.toInt() ?? 0);

      debugPrint('📹 [Controller] 使用预加载数据初始化: resourceId=$resourceId, quality=$selectedQuality');

      // 并发：配置播放器 + 加载设置
      await Future.wait([
        _configurePlayer(),
        _loadSettings(),
      ]);

      // 使用预加载的清晰度列表
      availableQualities.value = _sortQualities(qualities);
      currentQuality.value = selectedQuality;

      // 后台启动 AudioService
      if (backgroundPlayEnabled.value) {
        _ensureAudioServiceReady().catchError((_) {});
      }

      // 直接使用预加载的媒体源加载视频
      await _loadVideoWithMediaSource(
        mediaSource: mediaSource,
        quality: selectedQuality,
        initialPosition: initialPosition,
      );

      isLoading.value = false;
      isPlayerInitialized.value = true;

      debugPrint('✅ [Controller] 预加载初始化完成');
    } catch (e) {
      _logger.logError(message: '预加载初始化失败', error: e, stackTrace: StackTrace.current);
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
    }
  }

  // ============================================================
  // 核心：加载视频
  // ============================================================

  Future<void> _loadVideo(String quality, {double? initialPosition}) async {
    if (_isDisposed) return;

    try {
      _hasTriggeredCompletion = false;
      final needSeek = initialPosition != null && initialPosition > 0;
      final targetPosition = Duration(seconds: initialPosition?.toInt() ?? 0);

      debugPrint('📹 [Load] 加载视频: quality=$quality, seekTo=${targetPosition.inSeconds}s');

      // 1. 获取资源
      final mediaSource = await _hlsService.getMediaSource(_currentResourceId!, quality);
      if (!mediaSource.isDirectUrl) {
        _qualityCache[quality] = mediaSource;
      }
      final media = await _createMedia(mediaSource);

      // 2. 打开视频
      _isSeeking = true;
      await player.open(media, play: false);
      await _waitForDuration();

      // 3. 恢复历史进度
      if (needSeek) {
        debugPrint('🔄 [Load] 恢复历史进度: ${targetPosition.inSeconds}s');

        // 先播放一下让播放器真正就绪，然后立即暂停
        await player.play();
        await Future.delayed(const Duration(milliseconds: 100));
        await player.pause();

        // 现在 seek
        await player.seek(targetPosition);
        await Future.delayed(const Duration(milliseconds: 200));

        // 验证位置
        final actualPos = player.state.position;
        debugPrint('📍 [Load] seek 后位置: ${actualPos.inSeconds}s');

        _userIntendedPosition = targetPosition;
      }

      _isSeeking = false;

      // 4. 开始播放
      if (!isSwitchingQuality.value) {
        await player.play();
        debugPrint('▶️ [Load] 开始播放');
      }

      // 5. 预加载相邻清晰度
      _preloadAdjacentQualities();

    } catch (e) {
      _isSeeking = false;
      debugPrint('❌ [Load] 失败: $e');
      rethrow;
    }
  }

  /// 使用已加载的媒体源加载视频（避免重复网络请求）
  Future<void> _loadVideoWithMediaSource({
    required MediaSource mediaSource,
    required String quality,
    double? initialPosition,
  }) async {
    if (_isDisposed) return;

    try {
      _hasTriggeredCompletion = false;
      final needSeek = initialPosition != null && initialPosition > 0;
      final targetPosition = Duration(seconds: initialPosition?.toInt() ?? 0);

      debugPrint('📹 [Load] 使用预加载媒体源: quality=$quality, seekTo=${targetPosition.inSeconds}s');

      // 缓存媒体源
      if (!mediaSource.isDirectUrl) {
        _qualityCache[quality] = mediaSource;
      }
      final media = await _createMedia(mediaSource);

      // 打开视频
      _isSeeking = true;
      await player.open(media, play: false);
      await _waitForDuration();

      // 恢复历史进度
      if (needSeek) {
        debugPrint('🔄 [Load] 恢复历史进度: ${targetPosition.inSeconds}s');

        // 先播放一下让播放器真正就绪，然后立即暂停
        await player.play();
        await Future.delayed(const Duration(milliseconds: 100));
        await player.pause();

        // 现在 seek
        await player.seek(targetPosition);
        await Future.delayed(const Duration(milliseconds: 200));

        // 验证位置
        final actualPos = player.state.position;
        debugPrint('📍 [Load] seek 后位置: ${actualPos.inSeconds}s');

        _userIntendedPosition = targetPosition;
      }

      _isSeeking = false;

      // 开始播放
      if (!isSwitchingQuality.value) {
        await player.play();
        debugPrint('▶️ [Load] 开始播放');
      }

      // 预加载相邻清晰度
      _preloadAdjacentQualities();

    } catch (e) {
      _isSeeking = false;
      debugPrint('❌ [Load] 失败: $e');
      rethrow;
    }
  }

  // ============================================================
  // 核心：Seek
  // ============================================================

  Future<void> seek(Duration position) async {
    debugPrint('⏩ [Seek] 目标: ${position.inSeconds}s');

    // 【关键】立即更新用户期望位置
    _userIntendedPosition = position;
    _isSeeking = true;

    try {
      await player.seek(position);
      // 短暂等待让播放器响应
      await Future.delayed(const Duration(milliseconds: 100));
    } finally {
      _isSeeking = false;
    }
  }

  // ============================================================
  // 核心：切换清晰度
  // ============================================================

  Future<void> changeQuality(String quality) async {
    if (currentQuality.value == quality) return;

    // 记录当前状态
    final wasPlaying = player.state.playing;
    final currentPos = player.state.position;
    final targetPosition = currentPos.inSeconds > 0 ? currentPos : _userIntendedPosition;

    debugPrint('🔄 [Quality] 切换: $quality, 位置=${targetPosition.inSeconds}s');

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

        // 恢复到之前的位置
        if (targetPosition.inSeconds > 0) {
          debugPrint('🔄 [Quality] seek 到 ${targetPosition.inSeconds}s');

            // 先播放一下让播放器真正就绪，然后立即暂停
            await player.play();
            await Future.delayed(const Duration(milliseconds: 100));
            await player.pause();

            // 现在 seek
            await player.seek(targetPosition);
            await Future.delayed(const Duration(milliseconds: 200));

            // 验证位置
            final actualPos = player.state.position;
            debugPrint('📍 [Quality] seek 后位置: ${actualPos.inSeconds}s');
        }

        // 更新状态
        currentQuality.value = quality;
        await _savePreferredQuality(quality);
        _userIntendedPosition = targetPosition;

        // 恢复播放
        if (wasPlaying) {
          await player.play();
        }

        debugPrint('✅ [Quality] 切换完成');
        onQualityChanged?.call(quality);
        _preloadAdjacentQualities();

      } catch (e) {
        debugPrint('❌ [Quality] 切换失败: $e');
        errorMessage.value = '切换清晰度失败';
      } finally {
        isSwitchingQuality.value = false;
      }
    });
  }

  // ============================================================
  // 监听器
  // ============================================================

  void _setupListeners() {
    // 进度监听
    _positionSubscription = player.stream.position.listen((position) {
      // UI 始终更新
      _positionStreamController.add(position);

      // seek 过程中不更新期望位置、不上报
      if (_isSeeking || isSwitchingQuality.value) return;

      // 正常播放时，跟随实际位置
      if (position.inSeconds > 0) {
        _userIntendedPosition = position;
      }

      // 节流上报（每 500ms）
      if (onProgressUpdate != null) {
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
        _handlePlaybackEnd();
      }
    });

    // 播放状态监听 + Wakelock
    _playingSubscription = player.stream.playing.listen((playing) {
      if (playing && _hasTriggeredCompletion) {
        _hasTriggeredCompletion = false;
      }

      if (playing) {
        WakelockManager.enable();
      } else {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!player.state.playing) {
            WakelockManager.disable();
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
            debugPrint('⚠️ 播放卡顿，尝试恢复...');
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
    if (_currentResourceId == null || currentQuality.value == null) return;

    try {
      final position = _userIntendedPosition;
      debugPrint('🔧 [Stalled] 恢复: position=${position.inSeconds}s');

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
      debugPrint('❌ [Stalled] 恢复失败: $e');
    }
  }

  // ============================================================
  // 辅助方法
  // ============================================================

  Future<Media> _createMedia(MediaSource source) async {
    if (source.isDirectUrl) {
      return Media(source.content);
    } else {
      final bytes = Uint8List.fromList(utf8.encode(source.content));
      return await Media.memory(bytes);
    }
  }

  Future<void> _waitForDuration({Duration timeout = const Duration(seconds: 5)}) async {
    if (player.state.duration.inSeconds > 0) return;

    final completer = Completer<void>();
    StreamSubscription? sub;

    sub = player.stream.duration.listen((duration) {
      if (duration.inSeconds > 0 && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(timeout, onTimeout: () {});
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _configurePlayer() async {
    if (kIsWeb) return;

    try {
      final nativePlayer = player.platform as NativePlayer?;
      if (nativePlayer == null) return;

      // 缓冲配置
      await nativePlayer.setProperty('cache', 'yes');
      await nativePlayer.setProperty('cache-secs', '120');
      await nativePlayer.setProperty('demuxer-readahead-secs', '120');
      await nativePlayer.setProperty('demuxer-max-bytes', '500M');
      await nativePlayer.setProperty('demuxer-max-back-bytes', '50M');
      await nativePlayer.setProperty('demuxer-seekable-cache', 'yes');

      // 精确跳转
      await nativePlayer.setProperty('hr-seek', 'absolute');
      await nativePlayer.setProperty('hr-seek-framedrop', 'no');

      // 解码模式
      await nativePlayer.setProperty('hwdec', _currentDecodeMode);

      debugPrint('✅ MPV 配置完成');
    } catch (e) {
      debugPrint('⚠️ MPV 配置失败: $e');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    loopMode.value = LoopModeExtension.fromString(prefs.getString(_loopModeKey));
    backgroundPlayEnabled.value = prefs.getBool(_backgroundPlayKey) ?? false;
    _currentDecodeMode = prefs.getString(_decodeModeKey) ?? 'no';
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
              debugPrint('✅ 预加载: ${HlsService.getQualityLabel(nextQuality)}');
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

    if (preferredName != null) {
      for (final q in qualities) {
        if (getQualityDisplayName(q) == preferredName) return q;
      }
    }
    return HlsService.getDefaultQuality(qualities);
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
    const map = {
      '640x360_1000k_30': '360p',
      '854x480_1500k_30': '480p',
      '1280x720_3000k_30': '720p',
      '1920x1080_6000k_30': '1080p',
      '1920x1080_8000k_60': '1080p60',
    };

    if (map.containsKey(quality)) return map[quality]!;

    try {
      final parts = quality.split('_');
      final resolution = parts[0];
      final fps = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 30) : 30;

      if (resolution.contains('x')) {
        final height = int.tryParse(resolution.split('x')[1]);
        if (height != null) {
          final suffix = fps > 30 ? '$fps' : '';
          if (height <= 360) return '360p$suffix';
          if (height <= 480) return '480p$suffix';
          if (height <= 720) return '720p$suffix';
          if (height <= 1080) return '1080p$suffix';
          if (height <= 1440) return '2K$suffix';
          return '4K$suffix';
        }
      }
    } catch (_) {}
    return quality;
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
    try {
      if (_audioServiceInitialized && _audioHandler != null) {
        _audioHandler!.setPlayer(player);
        // 同步元数据，确保通知栏信息更新
        _updateAudioServiceMetadata();
        return;
      }

      if (!_audioServiceInitialized) {
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
        // 附加 player 并同步已有的媒体元数据（如果有）
        _audioHandler?.setPlayer(player);
        _updateAudioServiceMetadata();
      }
    } catch (e) {
      debugPrint('❌ AudioService 初始化失败: $e');
    }
  }

  void setVideoMetadata({required String title, String? author, Uri? coverUri}) {
    _videoTitle = title;
    _videoAuthor = author;
    _videoCoverUri = coverUri;
    _updateAudioServiceMetadata();
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
        WakelockManager.enable();
        _audioHandler?.updatePlaybackState(
          playing: true,
          position: player.state.position,
        );
      } else if (_wasPlayingBeforeBackground) {
        player.pause();
      }
    } else {
      if (!backgroundPlayEnabled.value && _wasPlayingBeforeBackground) {
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

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    // 取消定时器
    _qualityDebounceTimer?.cancel();
    _stalledTimer?.cancel();
    _preloadTimer?.cancel();

    // 取消订阅
    _positionSubscription?.cancel();
    _completedSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _audioInterruptionSubscription?.cancel();
    _callStateSubscription?.cancel();
    _callStateHandler?.dispose();

    // 关闭流
    _positionStreamController.close();

    // 清理缓存
    _qualityCache.clear();
    WakelockManager.disable();
    _audioHandler?.stop();
    _hlsService.cleanupAllTempCache();

    // 停止并销毁播放器
    player.stop();
    Future.delayed(const Duration(milliseconds: 200), () {
      player.dispose();
    });

    // 销毁 Notifiers
    availableQualities.dispose();
    currentQuality.dispose();
    isLoading.dispose();
    errorMessage.dispose();
    isPlayerInitialized.dispose();
    isSwitchingQuality.dispose();
    loopMode.dispose();
    backgroundPlayEnabled.dispose();
    isBuffering.dispose();

    super.dispose();
  }
}
