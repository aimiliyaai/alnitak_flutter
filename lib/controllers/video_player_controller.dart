import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/hls_service.dart';
import '../services/history_service.dart';
import '../services/logger_service.dart';
import '../models/data_source.dart';
import '../models/loop_mode.dart';
import '../utils/wakelock_manager.dart';
import '../utils/error_handler.dart';
import '../utils/quality_utils.dart';

class VideoPlayerController extends ChangeNotifier {
  final HlsService _hlsService = HlsService();
  final LoggerService _logger = LoggerService.instance;
  late final Player player;
  late final VideoController videoController;

  // ============ 公开状态（custom_player_ui.dart 使用） ============
  final ValueNotifier<List<String>> availableQualities = ValueNotifier([]);
  final ValueNotifier<String?> currentQuality = ValueNotifier(null);
  final ValueNotifier<bool> isLoading = ValueNotifier(true);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<bool> isPlayerInitialized = ValueNotifier(false);
  final ValueNotifier<bool> isSwitchingQuality = ValueNotifier(false);
  final ValueNotifier<LoopMode> loopMode = ValueNotifier(LoopMode.off);
  final ValueNotifier<bool> backgroundPlayEnabled = ValueNotifier(false);
  final ValueNotifier<bool> isBuffering = ValueNotifier(false);

  final StreamController<Duration> _positionStreamController = StreamController.broadcast();
  Stream<Duration> get positionStream => _positionStreamController.stream;

  // ============ 回调 ============
  VoidCallback? onVideoEnd;
  Function(Duration position, Duration totalDuration)? onProgressUpdate;
  Function(String quality)? onQualityChanged;
  Function(bool playing)? onPlayingStateChanged;

  // ============ 内部状态 ============
  int? _currentResourceId;
  bool _isDisposed = false;
  bool _hasTriggeredCompletion = false;
  bool _isInitializing = false;
  bool _hasPlaybackStarted = false;
  bool _useDash = false;
  bool _isSeeking = false;

  Duration _userIntendedPosition = Duration.zero;
  Duration _lastReportedPosition = Duration.zero;
  int? _lastProgressFetchTime;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Timer? _stalledTimer;
  Timer? _seekTimer;

  int? _currentVid;
  int _currentPart = 1;

  static const String _preferredQualityKey = 'preferred_video_quality_display_name';
  static const String _loopModeKey = 'video_loop_mode';
  static const String _backgroundPlayKey = 'background_play_enabled';

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

  // ============ 核心方法：initialize ============

  /// 初始化播放器并加载视频
  ///
  /// 统一入口，替代之前的 initialize() 和 initializeWithPreloadedData()
  Future<void> initialize({
    required int resourceId,
    double? initialPosition,
  }) async {
    // 如果正在初始化同一个资源，忽略；否则允许切换到新资源
    if (_isInitializing && _currentResourceId == resourceId) return;
    _isInitializing = true;

    try {
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;
      isPlayerInitialized.value = false;
      _userIntendedPosition = Duration(seconds: initialPosition?.toInt() ?? 0);
      _hasPlaybackStarted = false;
      _hasTriggeredCompletion = false;

      await _loadSettings();

      // 获取清晰度列表
      final qualityInfo = await _hlsService.getQualityInfo(resourceId);
      if (qualityInfo.qualities.isEmpty) throw Exception('没有可用的清晰度');

      _useDash = HlsService.shouldUseDash() && qualityInfo.supportsDash;

      await _configurePlayer();

      availableQualities.value = HlsService.sortQualities(qualityInfo.qualities);
      currentQuality.value = await _getPreferredQuality(availableQualities.value);

      // 获取 DataSource
      final dataSource = await _hlsService.getDataSource(
        resourceId,
        currentQuality.value!,
        useDash: _useDash,
      );

      if (_isDisposed || _currentResourceId != resourceId) return;

      // 设置数据源并开始播放
      await setDataSource(
        dataSource,
        seekTo: initialPosition != null && initialPosition > 0
            ? Duration(seconds: initialPosition.toInt())
            : null,
        autoPlay: true,
      );

      // 后台预加载相邻清晰度
      _preloadAdjacentQualities();
    } catch (e) {
      _logger.logError(message: '初始化失败', error: e, stackTrace: StackTrace.current);
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
    } finally {
      _isInitializing = false;
    }
  }

  // ============ 核心方法：setDataSource（pilipala 风格）============

  /// 设置播放数据源
  ///
  /// 参考 pilipala 的 setDataSource 模式：
  /// 1. player.open(videoSource, play: false)
  /// 2. 挂载音频：NativePlayer.setProperty('audio-files', audioSource)
  /// 3. 等待 duration
  /// 4. seek（如果需要）
  /// 5. 自动播放
  Future<void> setDataSource(
    DataSource dataSource, {
    Duration? seekTo,
    bool autoPlay = true,
  }) async {
    if (_isDisposed) return;

    try {
      _isSeeking = true;

      // 1. 设置音频轨道（pilipala 风格：先设置属性，再 open）
      final nativePlayer = player.platform as NativePlayer;
      await player.setAudioTrack(AudioTrack.auto());

      // DASH MPD 已包含音频 AdaptationSet，不需要额外挂载 audio-files
      // 只有 HLS 模式需要外挂音频（m3u8 只包含视频分片）
      if (!_useDash && dataSource.audioSource != null && dataSource.audioSource!.isNotEmpty) {
        // 转义列表分隔符（Windows 用分号，其他用冒号）
        final escapedAudio = Platform.isWindows
            ? dataSource.audioSource!.replaceAll(';', '\\;')
            : dataSource.audioSource!.replaceAll(':', '\\:');
        _logger.logDebug('🔊 设置 audio-files: ${dataSource.audioSource}');
        await nativePlayer.setProperty('audio-files', escapedAudio);
      } else if (!_useDash) {
        await nativePlayer.setProperty('audio-files', '');
      }

      // 2. 打开视频源（不自动播放）
      await player.open(
        Media(dataSource.videoSource, start: _useDash ? seekTo : null),
        play: false,
      );

      // 3. 等待 duration 就绪
      await _waitForDuration();

      if (_isDisposed) return;

      // 4. 非 DASH 模式需要手动 seek（DASH 通过 Media start 参数已定位）
      if (!_useDash && seekTo != null && seekTo.inSeconds > 0) {
        await _doSeek(seekTo);
      }

      // 5. 自动播放
      if (autoPlay) {
        await player.play();
      }

      // 6. 标记初始化完成
      isLoading.value = false;
      isPlayerInitialized.value = true;
      _isSeeking = false;

    } catch (e) {
      _isSeeking = false;
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
      _logger.logError(message: 'setDataSource 失败', error: e, stackTrace: StackTrace.current);
    }
  }

  // ============ seek（简化为一个方法）============

  /// 跳转到指定位置（pilipala 风格）
  Future<void> seek(Duration position) async {
    if (position < Duration.zero) position = Duration.zero;

    _userIntendedPosition = position;
    _isSeeking = true;

    try {
      if (player.state.duration.inSeconds != 0) {
        await player.stream.buffer.first;
        await player.seek(position);
      } else {
        // duration 未就绪，使用定时重试
        _seekTimer?.cancel();
        _seekTimer = Timer.periodic(const Duration(milliseconds: 200), (Timer t) async {
          if (player.state.duration.inSeconds != 0) {
            await player.stream.buffer.first;
            await player.seek(position);
            t.cancel();
            _seekTimer = null;
          }
        });
      }
    } finally {
      _isSeeking = false;
    }
  }

  /// 内部 seek 辅助（用于 setDataSource 中的初始定位）
  Future<void> _doSeek(Duration position) async {
    _userIntendedPosition = position;

    // 先短暂播放再暂停，确保解码器就绪
    await player.play();
    await Future.delayed(const Duration(milliseconds: 80));
    await player.pause();

    await player.seek(position);
    await Future.delayed(const Duration(milliseconds: 150));

    // 验证 seek 结果
    final actualPos = player.state.position.inSeconds;
    if ((actualPos - position.inSeconds).abs() > 2) {
      await player.seek(position);
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // ============ changeQuality（无闪烁切换）============

  /// 切换清晰度
  ///
  /// 使用 mpv 的 `loadfile replace` 命令替代 `player.open()`，
  /// 避免 stop() 将 width/height 置 null 导致的 surface 闪烁。
  Future<void> changeQuality(String quality) async {
    if (currentQuality.value == quality || _currentResourceId == null) return;

    final wasPlaying = player.state.playing;
    final currentPos = player.state.position;
    final targetPosition = currentPos.inMilliseconds > 0 ? currentPos : _userIntendedPosition;

    await player.pause();
    isSwitchingQuality.value = true;

    try {
      final dataSource = await _hlsService.getDataSource(
        _currentResourceId!,
        quality,
        useDash: _useDash,
      );

      if (_isDisposed) return;

      final nativePlayer = player.platform as NativePlayer;

      // HLS 模式需要更新 audio-files 属性
      if (!_useDash) {
        if (dataSource.audioSource != null && dataSource.audioSource!.isNotEmpty) {
          final escapedAudio = Platform.isWindows
              ? dataSource.audioSource!.replaceAll(';', '\\;')
              : dataSource.audioSource!.replaceAll(':', '\\:');
          await nativePlayer.setProperty('audio-files', escapedAudio);
        } else {
          await nativePlayer.setProperty('audio-files', '');
        }
      }

      // 使用 loadfile replace 替代 player.open()
      // 这样不会触发 stop()，width/height 不会被置 null，不会闪烁
      final startSeconds = targetPosition.inSeconds;
      if (startSeconds > 0) {
        await nativePlayer.command([
          'loadfile',
          dataSource.videoSource,
          'replace',
          'start=$startSeconds',
        ]);
      } else {
        await nativePlayer.command([
          'loadfile',
          dataSource.videoSource,
          'replace',
        ]);
      }

      // 等待新源加载
      await _waitForDuration();

      if (_isDisposed) return;

      if (wasPlaying) {
        await player.play();
      }

      currentQuality.value = quality;
      await _savePreferredQuality(quality);
      _userIntendedPosition = targetPosition;

      onQualityChanged?.call(quality);
      _preloadAdjacentQualities();
    } catch (e) {
      errorMessage.value = '切换清晰度失败';
    } finally {
      isSwitchingQuality.value = false;
    }
  }

  // ============ 进度恢复 ============

  Future<void> fetchAndRestoreProgress() async {
    if (_isDisposed) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastProgressFetchTime != null && now - _lastProgressFetchTime! < 500) return;
    _lastProgressFetchTime = now;

    if (_currentVid == null) return;

    if (!isPlayerInitialized.value) {
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!_isDisposed && _currentVid != null) {
          await _doFetchAndRestoreProgress();
        }
      });
      return;
    }

    await _doFetchAndRestoreProgress();
  }

  Future<void> _doFetchAndRestoreProgress() async {
    if (_currentVid == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastProgressFetchTime != null && now - _lastProgressFetchTime! < 500) return;
    _lastProgressFetchTime = now;

    final requestVid = _currentVid!;
    final requestPart = _currentPart;

    try {
      final historyService = HistoryService();
      final progressData = await historyService.getProgress(vid: requestVid, part: requestPart);

      if (_isDisposed || _currentVid != requestVid || _currentPart != requestPart) return;
      if (progressData == null) return;

      final progress = progressData.progress;
      final currentPos = player.state.position.inSeconds;
      final targetPos = progress.toInt();

      if ((targetPos - currentPos).abs() > 3) {
        await seek(Duration(seconds: targetPos));
      }
    } catch (_) {}
  }

  // ============ 事件监听 ============

  void _setupListeners() {
    _positionSubscription = player.stream.position.listen((position) {
      _positionStreamController.add(position);

      if (_isSeeking || isSwitchingQuality.value) return;

      if (!_hasPlaybackStarted) {
        if (position.inSeconds == 0) return;
        _hasPlaybackStarted = true;
      }

      _userIntendedPosition = position;

      if (onProgressUpdate != null) {
        if (position.inSeconds == 0) return;

        final diff = (position.inMilliseconds - _lastReportedPosition.inMilliseconds).abs();
        if (diff >= 500) {
          _lastReportedPosition = position;
          onProgressUpdate!(position, player.state.duration);
        }
      }
    });

    _completedSubscription = player.stream.completed.listen((completed) {
      if (completed && !_hasTriggeredCompletion && !_isSeeking) {
        _hasTriggeredCompletion = true;
        _handlePlaybackEnd();
      }
    });

    _playingSubscription = player.stream.playing.listen((playing) async {
      if (playing && _hasTriggeredCompletion) {
        _hasTriggeredCompletion = false;
      }

      onPlayingStateChanged?.call(playing);

      if (playing) {
        WakelockManager.enable();
      } else {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!player.state.playing) {
            WakelockManager.disable();
          }
        });
      }
    });

    _bufferingSubscription = player.stream.buffering.listen((buffering) {
      isBuffering.value = buffering;

      if (buffering) {
        _stalledTimer?.cancel();
        _stalledTimer = Timer(const Duration(seconds: 15), () {
          if (player.state.buffering) {
            _handleStalled();
          }
        });
      } else {
        _stalledTimer?.cancel();
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final isConnected = results.any((r) => r != ConnectivityResult.none);
      if (isConnected && errorMessage.value != null) {
        errorMessage.value = null;
        _handleStalled();
      }
    });
  }

  void _handlePlaybackEnd() {
    // loop-file=inf 时 mpv 自动循环，不会走到这里
    // 只有 loop-file=no 时 completed 才为 true
    onVideoEnd?.call();
  }

  /// 处理卡顿恢复（使用 loadfile replace 避免闪烁）
  Future<void> _handleStalled() async {
    if (_isInitializing || isLoading.value) return;
    if (_currentResourceId == null || currentQuality.value == null) return;

    try {
      final position = _userIntendedPosition;

      final dataSource = await _hlsService.getDataSource(
        _currentResourceId!,
        currentQuality.value!,
        useDash: _useDash,
      );

      if (_isDisposed) return;

      final nativePlayer = player.platform as NativePlayer;

      // HLS 模式需要更新 audio-files
      if (!_useDash) {
        if (dataSource.audioSource != null && dataSource.audioSource!.isNotEmpty) {
          final escapedAudio = Platform.isWindows
              ? dataSource.audioSource!.replaceAll(';', '\\;')
              : dataSource.audioSource!.replaceAll(':', '\\:');
          await nativePlayer.setProperty('audio-files', escapedAudio);
        } else {
          await nativePlayer.setProperty('audio-files', '');
        }
      }

      final startSeconds = position.inSeconds;
      if (startSeconds > 0) {
        await nativePlayer.command([
          'loadfile',
          dataSource.videoSource,
          'replace',
          'start=$startSeconds',
        ]);
      } else {
        await nativePlayer.command([
          'loadfile',
          dataSource.videoSource,
          'replace',
        ]);
      }

      await _waitForDuration();
      if (_isDisposed) return;
      await player.play();
    } catch (_) {}
  }

  // ============ 辅助方法 ============

  Future<void> _configurePlayer() async {
    try {
      final nativePlayer = player.platform as NativePlayer;

      if (Platform.isAndroid) {
        await nativePlayer.setProperty("volume-max", "100");

        final decodeMode = await getDecodeMode();
        await nativePlayer.setProperty("hwdec", decodeMode);
      }

      // 同步循环模式到 mpv
      await _syncLoopProperty();
    } catch (_) {}
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

  void _preloadAdjacentQualities() {
    final current = currentQuality.value;
    if (current == null || _currentResourceId == null) return;

    final qualities = availableQualities.value;
    final index = qualities.indexOf(current);
    if (index == -1) return;

    if (index > 0) {
      unawaited(_hlsService.getDataSource(_currentResourceId!, qualities[index - 1], useDash: _useDash));
    }
    if (index < qualities.length - 1) {
      unawaited(_hlsService.getDataSource(_currentResourceId!, qualities[index + 1], useDash: _useDash));
    }
  }

  // ============ 设置持久化 ============

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      backgroundPlayEnabled.value = prefs.getBool(_backgroundPlayKey) ?? false;
      final loopModeValue = prefs.getInt(_loopModeKey) ?? 0;
      loopMode.value = LoopMode.values[loopModeValue];
    } catch (_) {}
  }

  Future<String> _getPreferredQuality(List<String> qualities) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferredName = prefs.getString(_preferredQualityKey);
      return findBestQualityMatch(qualities, preferredName);
    } catch (_) {}
    return HlsService.getDefaultQuality(qualities);
  }

  Future<void> _savePreferredQuality(String quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferredQualityKey, quality);
    } catch (_) {}
  }

  // ============ 公开方法（custom_player_ui.dart 使用）============

  void setVideoMetadata({required String title, String? author, Uri? coverUri}) {}

  void setVideoContext({required int vid, int part = 1}) {
    _currentVid = vid;
    _currentPart = part;
  }

  static const String _decodeModeKey = 'video_decode_mode';

  static Future<String> getDecodeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_decodeModeKey) ?? 'no';
  }

  static Future<void> setDecodeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_decodeModeKey, mode);
  }

  static String getDecodeModeDisplayName(String mode) {
    switch (mode) {
      case 'no':
        return '软解码';
      case 'auto-copy':
        return '硬解码';
      default:
        return '软解码';
    }
  }

  String getQualityDisplayName(String quality) {
    return HlsService.getQualityLabel(quality);
  }

  Future<void> toggleBackgroundPlay() async {
    backgroundPlayEnabled.value = !backgroundPlayEnabled.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundPlayKey, backgroundPlayEnabled.value);
  }

  Future<void> toggleLoopMode() async {
    final nextMode = (loopMode.value.index + 1) % LoopMode.values.length;
    loopMode.value = LoopMode.values[nextMode];
    await _syncLoopProperty();
  }

  /// 同步 mpv 的 loop-file 属性
  Future<void> _syncLoopProperty() async {
    try {
      final nativePlayer = player.platform as NativePlayer;
      // loop-file=inf: mpv 自动循环当前文件，不触发 completed
      // loop-file=no: 播放完成后触发 completed
      await nativePlayer.setProperty(
        'loop-file',
        loopMode.value == LoopMode.on ? 'inf' : 'no',
      );
    } catch (_) {}
  }

  void handleAppLifecycleState(bool isPaused) {}

  Future<void> play() async {
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
  }

  // ============ dispose ============

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _seekTimer?.cancel();
    _stalledTimer?.cancel();

    await _positionSubscription?.cancel();
    await _completedSubscription?.cancel();
    await _playingSubscription?.cancel();
    await _bufferingSubscription?.cancel();
    await _connectivitySubscription?.cancel();

    await player.dispose();

    _positionStreamController.close();

    super.dispose();
  }
}
