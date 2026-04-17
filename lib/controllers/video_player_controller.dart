import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:audio_session/audio_session.dart';
import '../config/api_config.dart';
import '../services/video_stream_service.dart';
import '../services/cache_service.dart';
import '../services/history_service.dart';
import '../services/logger_service.dart';
import '../models/data_source.dart';
import 'player_event_listener.dart';
import '../models/dash_models.dart';
import '../models/loop_mode.dart';
import '../utils/wakelock_manager.dart';
import '../utils/error_handler.dart';
import '../utils/quality_utils.dart';
import '../services/player_settings_service.dart';
import '../main.dart' show audioHandler;

class VideoPlayerController extends ChangeNotifier {
  final VideoStreamService _streamService = VideoStreamService();
  final CacheService _cacheService = CacheService();
  final LoggerService _logger = LoggerService.instance;
  Player? _player;
  VideoController? _videoController;

  /// 对外暴露 player（延迟创建，首次访问时初始化）
  Player get player => _player!;
  VideoController get videoController => _videoController!;

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
  /// 是否已经有过播放进度（position > 0），用于区分首帧前加载 vs 播放中缓冲（行业惯例）
  final ValueNotifier<bool> hasEverPlayed = ValueNotifier(false);

  // ============ pili_plus 风格进度条状态（秒级粒度，防跳变） ============
  /// 进度条显示位置（秒），拖拽时冻结不接收 mpv 更新
  final ValueNotifier<int> sliderPositionSeconds = ValueNotifier(0);
  /// 总时长（秒）
  final ValueNotifier<int> durationSeconds = ValueNotifier(0);
  /// 缓冲位置（秒）
  final ValueNotifier<int> bufferedSeconds = ValueNotifier(0);
  /// 用户是否正在拖拽进度条
  final ValueNotifier<bool> isSliderMoving = ValueNotifier(false);

  /// 原始位置（每次 mpv 事件都更新，内部使用）
  Duration _position = Duration.zero;
  /// 滑块位置（拖拽时独立于 _position）
  Duration _sliderPosition = Duration.zero;

  final StreamController<Duration> _positionStreamController = StreamController.broadcast();
  Stream<Duration> get positionStream => _positionStreamController.stream;

  // ============ 回调 ============
  PlayerEventListener? eventListener;
  /// 用户从「播放结束」状态点重播时回调（由页面设置，UI 调用）
  VoidCallback? onReplayAfterCompletion;

  // ============ 内部状态 ============
  Object? _currentResourceId;
  Future<void>? _playerCreationFuture;
  bool _isDisposed = false;
  bool _isDisposing = false; // 正在 dispose 中，防止回调在清理时触发
  bool _hasTriggeredCompletion = false;
  bool _hasJustCompleted = false; // 刚播放完毕，用于区分循环重播
  bool _isInitializing = false;
  bool _hasPlaybackStarted = false;
  bool _supportsDash = true; // 新资源=true(直链), 旧资源=false(m3u8 URL)
  DashManifest? _manifest; // 缓存 DASH manifest（含所有清晰度的视频/音频直链）
  bool _isSeeking = false;
  bool _isHandlingStall = false;

  Duration _userIntendedPosition = Duration.zero;
  Duration _lastReportedPosition = Duration.zero;
  int _lastPtsLoggedSecond = -1;
  int? _lastProgressFetchTime;
  // pilipala 风格：用 List 管理所有 stream subscription，方便批量取消/重建
  List<StreamSubscription> _subscriptions = [];
  bool _listenersStarted = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Timer? _stalledTimer;
  Timer? _seekTimer;
  /// 缓冲持续超过此时间才对外置 isBuffering=true（避免短暂抖动闪加载，参考 YouTube/哔哩哔哩）
  Timer? _bufferingShowTimer;
  static const int _bufferingSustainMs = 1500;
  static const int _videoEndDebounceMs = 800;
  static const int _startupReadyTimeoutMs = 1000;

  int _playbackSessionId = 0;
  DateTime? _lastVideoEndAt;
  Duration? _pendingSeekAfterSwitch;
  Future<void> _operationQueue = Future.value();
  final int _audioOwnerId = identityHashCode(Object());
  bool _seekInFlight = false;
  Duration? _latestSeekRequest;
  DateTime? _lastSeekAt;


String? _currentVid;
  // ignore: unused_field - 保留以备将来使用（如进度上报）
  String? _currentRid;  
  int _currentPart = 1;

  // 视频元数据（通知栏显示）
  String? _videoTitle;
  String? _videoAuthor;
  Uri? _videoCoverUri;

  // 音频中断处理
  AudioSession? _audioSession;
  bool _wasPlayingBeforeInterruption = false;
  StreamSubscription? _interruptionSubscription;
  StreamSubscription? _becomingNoisySubscription;

  static const String _preferredQualityKey = 'preferred_video_quality_display_name';
  static const String _loopModeKey = 'video_loop_mode';
  static const String _backgroundPlayKey = 'background_play_enabled';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  bool _settingsLoaded = false;

  VideoPlayerController();

  int _nextPlaybackSessionId() => ++_playbackSessionId;

  bool _isSessionActive(int sessionId) {
    return !_isDisposed && _player != null && _playbackSessionId == sessionId;
  }

  Future<void> _enqueueOperation(Future<void> Function() operation) {
    _operationQueue = _operationQueue.then((_) => operation()).catchError((e, st) {
      _logger.logError(
        message: '播放操作队列执行失败',
        error: e,
        stackTrace: st is StackTrace ? st : StackTrace.current,
      );
    });
    return _operationQueue;
  }

  void _notifyVideoEndOnce() {
    final now = DateTime.now();
    if (_lastVideoEndAt != null &&
        now.difference(_lastVideoEndAt!).inMilliseconds < _videoEndDebounceMs) {
      return;
    }
    _lastVideoEndAt = now;
    eventListener?.onVideoEnd();
  }

  // ============ pili_plus 风格：秒级更新方法（统一封装）============

  void _updateSliderPositionSecond() {
    _updateNotifierValue(sliderPositionSeconds, _sliderPosition.inSeconds);
  }

  void _updatePositionSecond() {
    if (!isSliderMoving.value) {
      _sliderPosition = _position;
      _updateSliderPositionSecond();
    }
  }

  void _updateDurationSecond() {
    _updateNotifierValue(durationSeconds, _player?.state.duration.inSeconds ?? 0);
  }

  void _updateBufferedSecond() {
    final buffer = _player?.state.buffer.inSeconds ?? 0;

    if (_supportsDash && _player != null) {
      _tryGetVideoBuffer().then((videoBuffer) {
        if (_isDisposed) return;
        _updateNotifierValue(bufferedSeconds, videoBuffer > 0 ? videoBuffer : buffer);
      });
    } else {
      _updateNotifierValue(bufferedSeconds, buffer);
    }
  }

  Future<int> _tryGetVideoBuffer() async {
    try {
      final cacheStr = await _player!.getProperty('demuxer-cache-state');
      if (cacheStr.isEmpty) return 0;
      final videoRangeMatch = RegExp(r'video\[(\d+)\]:(\d+)-(\d+)').firstMatch(cacheStr);
      if (videoRangeMatch != null) {
        final end = int.tryParse(videoRangeMatch.group(3) ?? '') ?? 0;
        final pos = _player?.state.position.inSeconds ?? 0;
        final videoBuffer = end - pos;
        if (videoBuffer > 0) return videoBuffer;
      }
    } catch (e) {
      _logger.logDebug('获取视频缓冲状态失败: $e');
    }
    return 0;
  }

  void _updateNotifierValue(ValueNotifier<int> notifier, int newValue) {
    if (notifier.value != newValue) {
      notifier.value = newValue;
    }
  }

  void _updatePositionState(Duration position) {
    _position = position;
    _updatePositionSecond();
    _positionStreamController.add(position);
    _userIntendedPosition = position;

    if (eventListener != null && position.inSeconds > 0) {
      final diff = (position.inMilliseconds - _lastReportedPosition.inMilliseconds).abs();
      if (diff >= 500) {
        _lastReportedPosition = position;
        eventListener!.onProgressUpdate(position, _player!.state.duration);
      }
    }
  }

  /// 预设总时长（用于播放器初始化早期，避免进度条在 duration 未就绪时瞬间满格）
  void setInitialDurationHint(double? duration) {
    if (duration == null || duration <= 0) return;
    durationSeconds.value = duration.toInt();
  }

  /// 用户开始拖拽进度条
  void onSliderDragStart() {
    isSliderMoving.value = true;
  }

  /// 用户拖拽中更新（乐观 UI）
  void onSliderDragUpdate(Duration position) {
    _sliderPosition = position;
    _updateSliderPositionSecond();
  }

  /// 用户拖拽结束，执行 seek
  void onSliderDragEnd(Duration position) {
    isSliderMoving.value = false;
    _sliderPosition = position;
    _updateSliderPositionSecond();
    seek(position);
  }

  // ============ 核心方法：initialize ============

  /// 初始化播放器并加载视频
  ///
  /// 统一入口，替代之前的 initialize() 和 initializeWithPreloadedData()
  Future<void> initialize({
    required Object resourceId,
    double? initialPosition,
    double? duration,
  }) async {
    // 如果正在初始化同一个资源，忽略；否则允许切换到新资源
    if (_isInitializing && _currentResourceId == resourceId) return;
    _isInitializing = true;

    try {
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;
      isPlayerInitialized.value = false;
      hasEverPlayed.value = false;
      _userIntendedPosition = Duration(seconds: initialPosition?.toInt() ?? 0);
      _hasPlaybackStarted = false;
      _hasTriggeredCompletion = false;

      // 预设总时长，防止 mpv duration 就绪前进度条因 duration=0 显示满格
      if (duration != null && duration > 0) {
        durationSeconds.value = duration.toInt();
      }

      // ── 并行 I/O：Settings + Manifest + Player 创建同时执行 ──
      // 网络请求（100-500ms）与本地初始化（mpv 50-100ms + SharedPreferences）重叠，
      // 首次加载可节省 50-150ms，后续加载 manifest 与 player 已就绪则几乎零开销。
      late final DashManifest manifest;
      await Future.wait<void>([
        if (!_settingsLoaded) _loadSettings(),
        _streamService.getDashManifest(resourceId).then((m) => manifest = m),
        _ensurePlayerReady(),
      ]);

      if (_isDisposed || _currentResourceId != resourceId) return;

      _manifest = manifest;
      _supportsDash = manifest.supportsDash;
      availableQualities.value = manifest.qualities;
      if (manifest.qualities.isEmpty) throw Exception('没有可用的清晰度');

      currentQuality.value = await _getPreferredQuality(availableQualities.value);

      if (_isDisposed || _currentResourceId != resourceId) return;

      // 获取 DataSource：DASH 直连视频+音频URL，旧资源回退 m3u8
      final DataSource dataSource;
      if (_supportsDash) {
        final ds = manifest.getDataSource(currentQuality.value!);
        if (ds == null) throw Exception('清晰度数据不可用');
        dataSource = ds;
      } else {
        dataSource = await _streamService.getM3u8DataSource(
          resourceId,
          currentQuality.value!,
        );
      }

      if (_isDisposed || _currentResourceId != resourceId) return;

      // 设置数据源并开始播放
      await setDataSource(
        dataSource,
        seekTo: initialPosition != null && initialPosition > 0
            ? Duration(seconds: initialPosition.toInt())
            : Duration.zero,
        autoPlay: true,
      );
    } catch (e) {
      _logger.logError(message: '初始化失败', error: e, stackTrace: StackTrace.current);
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
    } finally {
      _isInitializing = false;
    }
  }

  // ============ Player 预创建（与网络请求并行） ============

  /// 幂等预创建 Player（已创建则立即返回，并发调用共享同一 Future）
  Future<void> _ensurePlayerReady() async {
    if (_player != null || _isDisposed) return;
    if (_playerCreationFuture != null) {
      await _playerCreationFuture;
      return;
    }
    _playerCreationFuture = _createPlayerInternal();
    try {
      await _playerCreationFuture;
    } finally {
      _playerCreationFuture = null;
    }
  }

  /// 创建 mpv Player + AudioSession + VideoController
  ///
  /// 并行读取 3 个 SharedPreferences 设置项，再一次性创建。
  Future<void> _createPlayerInternal() async {
    if (_player != null || _isDisposed) return;

    // 并行读取所有播放器设置（每个都是独立的 SharedPreferences 查询）
    final results = await Future.wait([
      PlayerSettingsService.getDecodeMode(),
      PlayerSettingsService.getExpandBuffer(),
      PlayerSettingsService.getAudioOutput(),
    ]);
    final decodeMode = results[0] as String;
    final expandBuffer = results[1] as bool;
    final audioOutput = results[2] as String;

    if (_player != null || _isDisposed) return; // await 后二次检查

    final opt = <String, String>{
      'video-sync': 'display-resample',
    };
    if (Platform.isAndroid) {
      opt['volume-max'] = '100';
      opt['ao'] = audioOutput;
      opt['autosync'] = '30';
    }
    final bufferSizeBytes = expandBuffer ? 32 * 1024 * 1024 : 16 * 1024 * 1024;
    _player = await Player.create(
      configuration: PlayerConfiguration(
        bufferSize: bufferSizeBytes,
        logLevel: kDebugMode ? MPVLogLevel.warn : MPVLogLevel.error,
        options: opt,
      ),
    );
    audioHandler.attachPlayer(
      _player!,
      ownerId: _audioOwnerId,
      onPlay: () => play(),
      onPause: () => pause(),
      onSeek: (pos) => seek(pos),
    );
    await _initAudioSession();
    await _configurePlayerOnce(decodeMode);

    _player!.setMediaHeader(
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.0.0 Safari/537.36',
      referer: ApiConfig.baseUrl,
    );

    _videoController = VideoController(
      _player!,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: decodeMode != 'no',
        androidAttachSurfaceAfterVideoParameters: false,
        hwdec: decodeMode != 'no' ? decodeMode : null,
      ),
    );
  }

  // ============ 核心方法：setDataSource ============

  /// 设置播放数据源
  ///
  /// 流程：
  /// 1. removeListeners()，清空缓冲状态
  /// 2. _ensurePlayerReady()（幂等，通常已在 initialize 中并行完成）
  /// 3. startListeners() 先注册监听
  /// 4. player.open(Media(..., start: seekTo), play: false)
  /// 5. 若 autoPlay：事件驱动等待视频就绪后再 play
  Future<void> setDataSource(
    DataSource dataSource, {
    Duration seekTo = Duration.zero,
    bool autoPlay = true,
  }) async {
    if (_isDisposed) return;
    final sessionId = _nextPlaybackSessionId();

    try {
      isLoading.value = true;

      if (_player != null && _player!.state.playing) {
        await pause();
      }

      removeListeners();
      _bufferingShowTimer?.cancel();
      _bufferingShowTimer = null;
      isBuffering.value = false;
      hasEverPlayed.value = false;
      _hasPlaybackStarted = false;
      _hasTriggeredCompletion = false;
      _hasJustCompleted = false;
      _isSeeking = false;
      _pendingSeekAfterSwitch = null;

      // pili_plus 风格：removeListeners 后立即预设 sliderPosition = seekTo
      // 防止 UI 在 open() → startListeners() 之间看到 position=0 的闪跳
      _position = _sliderPosition = seekTo;
      _updateSliderPositionSecond();
      _updateBufferedSecond();

      // Player 创建（幂等，通常已在 initialize 中并行完成）
      await _ensurePlayerReady();

      // 先注册监听器，再 open(play: false)
      startListeners();

      final shouldPlayAfterStable = autoPlay;
      _logger.logDebug('setDataSource: open (seekTo=${seekTo.inSeconds}s, play: $shouldPlayAfterStable)');

      // 方案 A：视频直链 + audio-files 外挂音频（绕过 DASH MPD，mpv 原生 fMP4 demuxer）
      Map<String, String>? extras;
      if (dataSource.audioSource != null && dataSource.audioSource!.isNotEmpty) {
        // 对齐 pili_plus：按平台转义 audio-files 参数中的分隔符
        final escapedAudio = Platform.isWindows
            ? dataSource.audioSource!.replaceAll(';', r'\;')
            : dataSource.audioSource!.replaceAll(':', r'\:');
        extras = {'audio-files': '"$escapedAudio"'};
      }

      await _player!.open(
        Media(
          dataSource.videoSource,
          start: seekTo,
          extras: extras,
        ),
        play: false,
      );

      if (!_isSessionActive(sessionId)) return;

      isLoading.value = false;
      isPlayerInitialized.value = true;

      if (shouldPlayAfterStable && !_isDisposed) {
        // 等待视频流具备起播条件，降低“音频先播放、视频晚起”概率
        await _waitForVideoReadyBeforePlay(sessionId);
        if (!_isSessionActive(sessionId)) return;
        await play();
      }

    } catch (e) {
      if (!_isSessionActive(sessionId)) return;
      _isSeeking = false;
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
      _logger.logError(message: 'setDataSource 失败', error: e, stackTrace: StackTrace.current);
    }
  }

  /// 事件驱动等待视频起播就绪（替代轮询，响应更快）
  ///
  /// 监听 player streams 检测视频参数 + 缓冲就绪，超时兜底。
  /// 比 80ms 轮询平均快 40ms（事件即时触发 vs 半个轮询周期延迟）。
  Future<void> _waitForVideoReadyBeforePlay(int sessionId) async {
    if (_player == null) return;

    final completer = Completer<void>();
    final subs = <StreamSubscription>[];

    void tryComplete() {
      if (completer.isCompleted || !_isSessionActive(sessionId)) return;
      final w = _player?.state.width ?? 0;
      final h = _player?.state.height ?? 0;
      final bufMs = _player?.state.buffer.inMilliseconds ?? 0;
      if ((w > 0 && h > 0 && bufMs >= 800) || bufMs >= 2000) {
        if (!completer.isCompleted) completer.complete();
      }
    }

    subs.add(_player!.stream.width.listen((_) => tryComplete()));
    subs.add(_player!.stream.height.listen((_) => tryComplete()));
    subs.add(_player!.stream.buffer.listen((_) => tryComplete()));

    final timeout = Timer(
      Duration(milliseconds: _startupReadyTimeoutMs),
      () {
        if (!completer.isCompleted) {
          _logger.logDebug('起播门控超时，兜底继续播放');
          completer.complete();
        }
      },
    );

    // 立即检查（open 后可能已就绪）
    tryComplete();

    await completer.future;
    timeout.cancel();
    for (final sub in subs) {
      sub.cancel();
    }
  }

  @visibleForTesting
  static bool hasValidVideoSize(String raw) {
    if (raw.isEmpty) return false;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        final w = (parsed['w'] as num?)?.toInt() ?? 0;
        final h = (parsed['h'] as num?)?.toInt() ?? 0;
        return w > 0 && h > 0;
      }
    } catch (_) {
      // JSON 解析失败表示 raw 不是有效 JSON，正常返回 false
    }
    return false;
  }

  /// 判断播放完成事件是否为真正的播放结束（非断网假完成）
  /// [posMs] 当前播放位置（毫秒），[durMs] 视频总时长（毫秒）
  /// 返回 true 表示真正播完，false 表示假完成（断网导致流中断）
  @visibleForTesting
  static bool isRealCompletion(int posMs, int durMs) {
    if (durMs <= 0) return true; // 未获取到时长时默认为真完成
    final progress = posMs / durMs;
    return progress >= 0.9;
  }

  // ============ seek（统一封装）============

  Future<void> seek(Duration position) async {
    if (_isDisposed || _player == null) return;
    if (position < Duration.zero) position = Duration.zero;

    _userIntendedPosition = position;
    _lastSeekAt = DateTime.now();
    if (isSwitchingQuality.value) {
      _pendingSeekAfterSwitch = position;
      return;
    }

    _latestSeekRequest = position;
    if (_seekInFlight) return;

    _seekInFlight = true;
    try {
      while (!_isDisposed && _player != null && _latestSeekRequest != null) {
        final target = _latestSeekRequest!;
        _latestSeekRequest = null;

        _isSeeking = true;
        try {
          await _seekInternal(target);
        } catch (e) {
          _logger.logWarning('seek 错误: $e');
        } finally {
          _isSeeking = false;
        }
      }
    } finally {
      _seekInFlight = false;
    }
  }

  static const int _seekBufferWaitTimeoutMs = 300;

  Future<void> _seekBufferWaitIfNeeded() async {
    if (_player == null || _player!.state.buffer != Duration.zero) return;
    try {
      await _player!.stream.buffer.first
          .timeout(const Duration(milliseconds: _seekBufferWaitTimeoutMs));
    } catch (_) {
      // 超时是正常情况，不需要日志
    }
  }

  Future<void> _seekInternal(Duration position) async {
    await _seekBufferWaitIfNeeded();

    if (_player!.state.duration.inSeconds != 0) {
      await _player!.seek(position);
    } else {
      _seekTimer?.cancel();
      _seekTimer = Timer.periodic(const Duration(milliseconds: 200), (Timer t) async {
        if (_isDisposed || _player == null) {
          t.cancel();
          _seekTimer = null;
          _isSeeking = false;
          return;
        }
        if (_player!.state.duration.inSeconds != 0) {
          t.cancel();
          _seekTimer = null;
          await _seekBufferWaitIfNeeded();
          if (_isDisposed || _player == null) return;
          try {
            await _player!.seek(position);
          } catch (e) {
            _logger.logWarning('seek 执行失败: $e');
          }
          _isSeeking = false;
        }
      });
    }
  }

  // ============ changeQuality（照搬 pili_plus 的 updatePlayer）============

  Future<void> changeQuality(String quality) async {
    if (_isDisposed || _player == null) return;
    if (currentQuality.value == quality || _currentResourceId == null || isSwitchingQuality.value) {
      return;
    }

    await _enqueueOperation(() async {
      if (_isDisposed || _player == null) return;
      if (currentQuality.value == quality || _currentResourceId == null) return;

      final playerPos = _player!.state.position;
      final position = playerPos.inMilliseconds > 0 ? playerPos : _userIntendedPosition;
      _logger.logDebug('changeQuality: $quality, 保存位置 ${position.inSeconds}s');

      isSwitchingQuality.value = true;

      try {
        await _reloadWithDataSource(quality, position);
        currentQuality.value = quality;
        await _savePreferredQuality(quality);
        _userIntendedPosition = position;
        eventListener?.onQualityChanged(quality);
      } catch (e) {
        _logger.logError(message: '切换清晰度失败', error: e);
        errorMessage.value = ErrorHandler.getErrorMessage(e);
      } finally {
        isSwitchingQuality.value = false;
      }

      final pendingSeek = _pendingSeekAfterSwitch;
      _pendingSeekAfterSwitch = null;
      if (pendingSeek != null && !_isDisposed && _player != null) {
        _isSeeking = true;
        try {
          await _seekInternal(pendingSeek);
        } finally {
          _isSeeking = false;
        }
      }
    });
  }

  /// 重新加载数据源（用于清晰度切换、卡顿恢复等场景）
  Future<void> _reloadWithDataSource(String? quality, Duration position) async {
    final targetQuality = quality ?? currentQuality.value;
    if (targetQuality == null || _currentResourceId == null) return;

    final dataSource = await _getDataSourceForQuality(targetQuality);
    if (_isDisposed) return;

    await setDataSource(
      dataSource,
      seekTo: position.inSeconds > 0 ? position : Duration.zero,
      autoPlay: true,
    );
  }

  // ============ 进度恢复 ============

  Future<void> fetchAndRestoreProgress() async {
    if (_isDisposed) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastProgressFetchTime != null && now - _lastProgressFetchTime! < 500) return;
    _lastProgressFetchTime = now;

    if (_currentVid == null) return;
    final sessionId = _playbackSessionId;

    if (!isPlayerInitialized.value) {
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (_isSessionActive(sessionId) && _currentVid != null) {
          await _doFetchAndRestoreProgress();
        }
      });
      return;
    }

    await _doFetchAndRestoreProgress();
  }

  Future<void> _doFetchAndRestoreProgress() async {
    if (_currentVid == null) return;

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
    } catch (e) {
      _logger.logWarning('恢复播放进度失败: $e');
    }
  }

  // ============ 事件监听（照搬 pilipala 的 startListeners/removeListeners）============

  /// 注册播放事件监听（照搬 pilipala 的 startListeners）
  ///
  /// 每次 setDataSource 时先 removeListeners，加载后重新 startListeners
  void startListeners() {
    if (_player == null || _listenersStarted) return;
    _listenersStarted = true;
    final sessionId = _playbackSessionId;

    _subscriptions.addAll([
      _player!.stream.playing.listen((playing) {
        if (!_isSessionActive(sessionId)) return;
        if (playing && _hasTriggeredCompletion) {
          _hasTriggeredCompletion = false;
        }

        eventListener?.onPlayingStateChanged(playing);

        // 参考 pili_plus: WakelockPlus.toggle(enable: event)
        WakelockManager.toggle(enable: playing);
      }),

      _player!.stream.completed.listen((completed) {
        if (!_isSessionActive(sessionId)) return;
        if (_isDisposed || _isDisposing) return;
        
        if (completed && !_hasTriggeredCompletion && !_isSeeking && !isSwitchingQuality.value) {
          // 断网假完成检测：HLS 加载不到后续 ts 分片时 mpv 会发出 completed=true，
          // 但实际并没有播放到结尾。用播放进度比例判断：超过 90% 视为真正结束。
          final pos = _player!.state.position;
          final dur = _player!.state.duration;
          final isRealEnd = isRealCompletion(pos.inMilliseconds, dur.inMilliseconds);

          if (!isRealEnd && pos.inSeconds > 0) {
            // 假完成（断网导致流中断）：不触发结束逻辑，改为重试
            final progress = dur.inSeconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 1.0;
            _logger.logDebug('断网假完成检测: pos=${pos.inSeconds}s, dur=${dur.inSeconds}s, progress=${(progress * 100).toInt()}%, 尝试重试');
            _handleStalled();
            return;
          }

          _hasTriggeredCompletion = true;
          _hasJustCompleted = true;

          // 触发播放结束回调（loop-file=inf 时 mpv 不触发 completed，此处仅非循环模式走到）
          _notifyVideoEndOnce();
        }
        if (!completed) {
          _hasTriggeredCompletion = false;
        }
      }),

      _player!.stream.position.listen((position) {
        if (!_isSessionActive(sessionId)) return;
        if (_isDisposed || _isDisposing) return;
        if (_isSeeking) return;
        // 切换清晰度期间忽略 position=0 的跳变（open 重置导致）
        if (isSwitchingQuality.value && position.inSeconds <= 1) return;

        if (!_hasPlaybackStarted) {
          if (position.inSeconds == 0) return;
          _hasPlaybackStarted = true;
          // 排查「起始位置非 0」：首帧 position/duration 若非预期，多为播放器或流对齐问题（见 docs/PLAYBACK_START_END_ANALYSIS.md）
          final dur = _player?.state.duration ?? Duration.zero;
          _logger.logDebug('首帧 position=${position.inSeconds}s (${position.inMilliseconds}ms), duration=${dur.inSeconds}s');
        }

        if (position.inSeconds <= 1 && _hasJustCompleted) {
          _hasJustCompleted = false;
        }

        // loop-file=inf 循环检测：position 从接近结尾跳回开头，触发 onVideoEnd
        if (loopMode.value == LoopMode.on &&
            !isSwitchingQuality.value &&
            !_isSeeking &&
            position.inSeconds <= 1 &&
            _lastReportedPosition.inSeconds > 5) {
          final dur = _player?.state.duration ?? Duration.zero;
          if (isRealCompletion(_lastReportedPosition.inMilliseconds, dur.inMilliseconds) && dur.inSeconds > 0) {
            _logger.logDebug('loop-file 循环重播检测: 触发 onVideoEnd');
            _notifyVideoEndOnce();
          }
        }

        // 调试：打印音视频 PTS 状态（每10秒一次）
        if (position.inSeconds % 10 == 0 &&
            position.inSeconds > 0 &&
            _lastPtsLoggedSecond != position.inSeconds) {
          _lastPtsLoggedSecond = position.inSeconds;
          _logPtsState();
        }

        _updatePositionState(position);
        if (position > Duration.zero && !hasEverPlayed.value) {
          hasEverPlayed.value = true;
        }
      }),

      _player!.stream.duration.listen((duration) {
        if (!_isSessionActive(sessionId)) return;
        if (duration > Duration.zero) {
          _updateDurationSecond();
        }
      }),

      _player!.stream.buffer.listen((buffer) {
        if (!_isSessionActive(sessionId)) return;
        _updateBufferedSecond();
      }),

      _player!.stream.buffering.listen((buffering) {
        if (!_isSessionActive(sessionId)) return;
        if (buffering) {
          _bufferingShowTimer?.cancel();
          _bufferingShowTimer = Timer(const Duration(milliseconds: _bufferingSustainMs), () {
            _bufferingShowTimer = null;
            if (_isSessionActive(sessionId) && _player!.state.buffering) {
              isBuffering.value = true;
            }
          });
          _stalledTimer?.cancel();
          _stalledTimer = Timer(const Duration(seconds: 15), () {
            if (_isSessionActive(sessionId) && _player!.state.buffering) {
              _handleStalled();
            }
          });
        } else {
          _bufferingShowTimer?.cancel();
          _bufferingShowTimer = null;
          isBuffering.value = false;
          _stalledTimer?.cancel();
        }
      }),

      // 网络错误监听（PiliPlus 方式）：通过 error stream 检测断网/加载失败，
      // 双重确认（isBuffering + buffer==0）后重试，避免误判。
      _player!.stream.error.listen((error) {
        if (!_isSessionActive(sessionId)) return;
        if (error.isEmpty) return;
        _logger.logDebug('播放错误: $error');

        // 网络相关错误：tcp 超时、URL 打开失败、外部音频文件打开失败（DASH）
        if (error.startsWith('tcp: ') ||
            error.startsWith('Failed to open ') ||
            error.startsWith('Can not open external file ')) {
          // 延迟 3 秒后双重确认：仍在 buffering 且缓冲为空才重试
          Future.delayed(const Duration(seconds: 3), () {
            if (!_isSessionActive(sessionId)) return;
            if (_player!.state.buffering && _player!.state.buffer == Duration.zero) {
              _logger.logDebug('网络错误确认: buffering 且缓冲为空, 重试');
              _handleStalled();
            }
          });
        }
      }),

      // mpv 日志抓取：捕获 AV sync、音频、时间戳相关日志
      _player!.stream.log.listen((log) {
        if (!_isSessionActive(sessionId)) return;
        if (log.prefix == 'av_sync' ||
            log.prefix == 'audio' ||
            log.prefix == 'cplayer' ||
            log.text.contains('patients') ||
            log.text.contains('A-V:') ||
            log.text.contains('sync') ||
            log.text.contains('drop') ||
            log.text.contains('delay') ||
            log.text.contains('underrun') ||
            log.text.contains('reset') ||
            log.text.contains('timestamp') ||
            log.text.contains('desync')) {
          _logger.logDebug('[mpv:${log.prefix}] ${log.text}');
        }
      }),
    ]);

    // 网络连接监听（全局只注册一次）
    _connectivitySubscription ??= Connectivity().onConnectivityChanged.listen((results) {
      final isConnected = results.any((r) => r != ConnectivityResult.none);
      if (isConnected && errorMessage.value != null) {
        errorMessage.value = null;
        _handleStalled();
      }
    });

  }

  /// 移除事件监听（照搬 pilipala 的 removeListeners）
  void removeListeners() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions = [];
    _listenersStarted = false;
    _stalledTimer?.cancel();
    _stalledTimer = null;
    _seekTimer?.cancel();
    _seekTimer = null;
    _bufferingShowTimer?.cancel();
    _bufferingShowTimer = null;
  }

  /// 处理卡顿恢复（参考 pili_plus 的 refreshPlayer，复用 setDataSource）
  Future<void> _handleStalled() async {
    await _enqueueOperation(() async {
      if (_isHandlingStall) return;
      if (_isInitializing || isLoading.value) return;
      if (isSwitchingQuality.value) return;
      if (_isSeeking || _seekInFlight) return;
      final lastSeekAt = _lastSeekAt;
      if (lastSeekAt != null &&
          DateTime.now().difference(lastSeekAt).inSeconds < 4) {
        return;
      }
      if (_currentResourceId == null || currentQuality.value == null) return;
      if (_player == null) return;

      _isHandlingStall = true;
      try {
        final currentPos = _player!.state.position;
        if (currentPos <= Duration.zero) return;

        _logger.logDebug('_handleStalled: refreshPlayer from ${currentPos.inSeconds}s');
        await _reloadWithDataSource(currentQuality.value!, currentPos);
        _userIntendedPosition = currentPos;
      } catch (e) {
        _logger.logWarning('_handleStalled 失败: $e');
      } finally {
        _isHandlingStall = false;
      }
    });
  }

  // ============ 辅助方法 ============

  /// 获取指定清晰度的 DataSource（统一入口）
  ///
  /// DASH 直连视频+音频 URL（从缓存的 manifest 取）；旧资源回退 m3u8。
  Future<DataSource> _getDataSourceForQuality(String quality) async {
    if (_supportsDash && _manifest != null) {
      // manifest 过期时重新获取（签名 URL 有时效）
      if (_manifest!.isExpired && _currentResourceId != null) {
        _manifest = await _streamService.getDashManifest(_currentResourceId!);
      }
      final ds = _manifest!.getDataSource(quality);
      if (ds != null) return ds;
    }
    // 旧资源回退 m3u8
    return _streamService.getM3u8DataSource(_currentResourceId!, quality);
  }

  /// 首次创建 Player 时配置运行时可变的 mpv 属性
  /// 注意：ao / video-sync / autosync / volume-max 已通过 PlayerConfiguration.options 在初始化前设置
  /// fork 版 setProperty 是同步 void，不需要 await
  Future<void> _configurePlayerOnce(String decodeMode) async {
    if (_player == null) return;

    // 双独立流（video+audio 分离）需精确 seek 保证音画同步，hr-seek=yes
    _player!.setProperty('hr-seek', 'yes');

    // 禁用帧插值
    _player!.setProperty('interpolation', 'no');

// fMP4 容错：discardcorrupt 丢弃损坏帧
    _player!.setProperty('demuxer-lavf-o', 'fflags=+discardcorrupt');

    // 允许小范围回退但限制大规模回退（解决 fMP4 边界问题 + 切换质量回退）
    //_player!.setProperty('demuxer-max-back-bytes', '0');

    // 网络超时配置
    _player!.setProperty('network-timeout', '10');

    // 解码模式配置
    _player!.setProperty('hwdec', decodeMode);

    // 循环模式
    await _syncLoopProperty();
    await _player!.setAudioTrack(AudioTrack.auto());
  }

  // ============ 设置持久化 ============

  Future<void> _loadSettings() async {
    try {
      final prefs = await _preferences;
      backgroundPlayEnabled.value = prefs.getBool(_backgroundPlayKey) ?? false;
      final loopModeValue = prefs.getInt(_loopModeKey) ?? 0;
      loopMode.value = LoopMode.values[loopModeValue];
      _settingsLoaded = true;
    } catch (e) {
      _logger.logWarning('加载播放器设置失败: $e');
    }
  }

  Future<String> _getPreferredQuality(List<String> qualities) async {
    try {
      final prefs = await _preferences;
      final preferredName = prefs.getString(_preferredQualityKey);
      return findBestQualityMatch(qualities, preferredName);
    } catch (e) {
      _logger.logWarning('获取首选清晰度失败: $e');
    }
    return getDefaultQuality(qualities);
  }

  Future<void> _savePreferredQuality(String quality) async {
    try {
      final prefs = await _preferences;
      final displayName = formatQualityDisplayName(quality);
      await prefs.setString(_preferredQualityKey, displayName);
    } catch (e) {
      _logger.logWarning('保存首选清晰度失败: $e');
    }
  }

  // ============ 公开方法（custom_player_ui.dart 使用）============

  void setVideoMetadata({required String title, String? author, Uri? coverUri}) {
    _videoTitle = title;
    _videoAuthor = author;
    _videoCoverUri = coverUri;
    // 同步到 AudioService 通知栏
    audioHandler.setMediaItem(
      id: _currentResourceId?.toString() ?? '',
      title: title,
      artist: author,
      artUri: coverUri,
    );
  }

void setVideoContext({required String vid, String? rid, int part = 1}) {
    _currentVid = vid;
    _currentRid = rid;
    _currentPart = part;
  }

  String getQualityDisplayName(String quality) {
    return getQualityLabel(quality);
  }

  Future<void> toggleBackgroundPlay() async {
    backgroundPlayEnabled.value = !backgroundPlayEnabled.value;
    final prefs = await _preferences;
    await prefs.setBool(_backgroundPlayKey, backgroundPlayEnabled.value);
  }

  Future<void> toggleLoopMode() async {
    final nextMode = (loopMode.value.index + 1) % LoopMode.values.length;
    loopMode.value = LoopMode.values[nextMode];
    await _syncLoopProperty();
    final prefs = await _preferences;
    await prefs.setInt(_loopModeKey, loopMode.value.index);
  }

  /// 同步 mpv 的 loop-file 属性
  ///
  /// 直链 fMP4 模式下 loop-file=inf 由 mpv 内部处理循环，
  /// demuxer 缓存 100% 复用，循环时零额外网络请求。
  Future<void> _syncLoopProperty() async {
    if (_player == null) return;
    try {
      _player!.setProperty(
        'loop-file',
        loopMode.value == LoopMode.on ? 'inf' : 'no',
      );
    } catch (e) {
      _logger.logWarning('设置循环模式失败: $e');
    }
  }

  void handleAppLifecycleState(bool isPaused) {
    if (_player == null || _isDisposed) return;

    if (isPaused) {
      if (!backgroundPlayEnabled.value) {
        pause();
      }
      // 进入后台时快照一次当前位置（确保即使后台被杀也有可恢复的位置）
      final pos = _player!.state.position;
      if (pos.inSeconds > 0) {
        _userIntendedPosition = pos;
      }
    } else {
      if (_videoTitle != null) {
        audioHandler.setMediaItem(
          id: _currentResourceId?.toString() ?? '',
          title: _videoTitle!,
          artist: _videoAuthor,
          artUri: _videoCoverUri,
        );
      }
    }
  }

  /// 与 pili_plus 一致：先 player.play 再 setActive，避免音频路由切换时卡顿
  Future<void> play() async {
    if (_isDisposed || _player == null) return;
    await _player!.play();
    if (_audioSession != null) {
      await _audioSession!.setActive(true);
    }
  }

  /// [isInterrupt] 系统中断时传 true，不释放音频焦点
  Future<void> pause({bool isInterrupt = false}) async {
    if (_isDisposed || _player == null) return;
    await _player!.pause();
    if (!isInterrupt && _audioSession != null) {
      await _audioSession!.setActive(false);
    }
  }

  // ============ dispose（照搬 pilipala）============

  /// 初始化音频会话（与 pili_plus 一致：使用 .music() 预设，利于 iOS/蓝牙表现）
  Future<void> _initAudioSession() async {
    try {
      _audioSession = await AudioSession.instance;
      await _audioSession!.configure(const AudioSessionConfiguration.music());

      _interruptionSubscription = _audioSession!.interruptionEventStream.listen((event) {
        _handleAudioInterruption(event);
      });

      _becomingNoisySubscription = _audioSession!.becomingNoisyEventStream.listen((_) {
        _handleBecomingNoisy();
      });

      _logger.logDebug('[AudioSession] 初始化成功', tag: 'AudioSession');
    } catch (e) {
      _logger.logError(message: '[AudioSession] 初始化失败: $e');
    }
  }

  /// 处理音频中断（参考 pili_plus AudioSessionHandler）
  void _handleAudioInterruption(AudioInterruptionEvent event) {
    if (_player == null || _isDisposed) return;

    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          // 短暂中断（如导航语音）：降低音量（pili_plus: *0.5）
          _player!.setVolume((_player!.state.volume * 0.5).clamp(0, 100));
          _logger.logDebug('[AudioSession] duck 中断，音量减半');
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          // 需要暂停的中断（电话等）：isInterrupt=true 不释放音频焦点
          _wasPlayingBeforeInterruption = _player!.state.playing;
          if (_wasPlayingBeforeInterruption) {
            pause(isInterrupt: true);
            _logger.logDebug('[AudioSession] 中断(${event.type})，已暂停');
          }
          break;
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          // duck 结束：恢复音量（pili_plus: *2）
          _player!.setVolume((_player!.state.volume * 2).clamp(0, 100));
          _logger.logDebug('[AudioSession] duck 结束，音量恢复');
          break;
        case AudioInterruptionType.pause:
          if (_wasPlayingBeforeInterruption) {
            _wasPlayingBeforeInterruption = false;
            if (_player != null && !_isDisposed && !_player!.state.playing) {
              play();
              _logger.logDebug('[AudioSession] 中断结束，恢复播放', tag: 'AudioSession');
            }
          }
          break;
        case AudioInterruptionType.unknown:
          _wasPlayingBeforeInterruption = false;
          break;
      }
    }
  }

  /// 调试：打印音视频 PTS 状态
  Future<void> _logPtsState() async {
    if (_player == null) return;
    try {
      final videoPtsStr = await _player!.getProperty('video-pts');
      final audioPtsStr = await _player!.getProperty('audio-pts');
      final avsyncStr = await _player!.getProperty('avsync');
      final videoPts = double.tryParse(videoPtsStr) ?? 0;
      final audioPts = double.tryParse(audioPtsStr) ?? 0;
      final avsync = double.tryParse(avsyncStr) ?? 0;
      _logger.logDebug('[PTS] video=${videoPts.toStringAsFixed(3)}s, audio=${audioPts.toStringAsFixed(3)}s, avsync=${avsync.toStringAsFixed(3)}s');
    } catch (_) {
      // PTS 日志是诊断用，获取失败静默忽略
    }
  }

  /// 处理音频设备变化（耳机拔出等，参考 pili_plus becomingNoisy）
  void _handleBecomingNoisy() {
    if (_player == null || _isDisposed) return;
    if (_player!.state.playing) {
      pause();
      _logger.logDebug('[AudioSession] 耳机拔出，已暂停');
    }
  }

  /// 清理音频会话（必须先 setActive(false) 释放焦点，否则电话中断后系统状态异常需重启才能恢复）
  Future<void> _disposeAudioSession() async {
    try {
      await _audioSession?.setActive(false);
    } catch (e) {
      _logger.logDebug('释放音频焦点失败: $e');
    }
    await _interruptionSubscription?.cancel();
    await _becomingNoisySubscription?.cancel();
    _interruptionSubscription = null;
    _becomingNoisySubscription = null;
    _audioSession = null;
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposing = true;
    _isDisposed = true;

    WakelockManager.disable();
    await _disposeAudioSession();

    _seekTimer?.cancel();
    _seekTimer = null;
    _stalledTimer?.cancel();
    _stalledTimer = null;
    _bufferingShowTimer?.cancel();
    _bufferingShowTimer = null;

    // pilipala: removeListeners
    eventListener = null;
    removeListeners();
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;

    // 停止 AudioService 通知栏（先 stop 再 detach，确保状态转换正确）
    await audioHandler.stopIfOwner(_audioOwnerId);
    audioHandler.detachPlayerIfOwner(_audioOwnerId);

    _manifest = null;

    // 清理视频缓存
    _cacheService.cleanupAllTempCache();

    if (_player != null) {
      await _player!.dispose();
      _player = null;
    }

    _positionStreamController.close();

    availableQualities.dispose();
    currentQuality.dispose();
    isLoading.dispose();
    errorMessage.dispose();
    isPlayerInitialized.dispose();
    isSwitchingQuality.dispose();
    loopMode.dispose();
    backgroundPlayEnabled.dispose();
    isBuffering.dispose();
    hasEverPlayed.dispose();
    sliderPositionSeconds.dispose();
    durationSeconds.dispose();
    bufferedSeconds.dispose();
    isSliderMoving.dispose();

    super.dispose();
  }
}
