import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:audio_session/audio_session.dart';
import '../services/video_stream_service.dart';
import '../services/cache_service.dart';
import '../services/history_service.dart';
import '../services/logger_service.dart';
import '../models/data_source.dart';
import '../models/dash_models.dart';
import '../models/loop_mode.dart';
import '../utils/wakelock_manager.dart';
import '../utils/error_handler.dart';
import '../utils/quality_utils.dart';
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
  VoidCallback? onVideoEnd;
  Function(Duration position, Duration totalDuration)? onProgressUpdate;
  Function(String quality)? onQualityChanged;
  Function(bool playing)? onPlayingStateChanged;

  // ============ 内部状态 ============
  int? _currentResourceId;
  bool _isDisposed = false;
  bool _isDisposing = false; // 正在 dispose 中，防止回调在清理时触发
  bool _hasTriggeredCompletion = false;
  bool _hasJustCompleted = false; // 刚播放完毕，用于区分循环重播
  bool _isInitializing = false;
  bool _hasPlaybackStarted = false;
  bool _supportsDash = true; // 新资源=true(JSON直链), 旧资源=false(m3u8 URL)
  DashManifest? _dashManifest; // 缓存完整 DASH 数据（仿 pili_plus）
  bool _isSeeking = false;
  bool _isHandlingStall = false;

  Duration _userIntendedPosition = Duration.zero;
  Duration _lastReportedPosition = Duration.zero;
  int? _lastProgressFetchTime;

  // pilipala 风格：用 List 管理所有 stream subscription，方便批量取消/重建
  List<StreamSubscription> _subscriptions = [];
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Timer? _stalledTimer;
  Timer? _seekTimer;
  /// 缓冲持续超过此时间才对外置 isBuffering=true（避免短暂抖动闪加载，参考 YouTube/哔哩哔哩）
  Timer? _bufferingShowTimer;
  static const int _bufferingSustainMs = 1500;

  /// 方案 B 加强：open(play: false) 后等缓冲量达标且 buffering 结束再 play
  bool _pendingStablePlay = false;
  Timer? _stablePlayFallbackTimer;
  /// 本次 setDataSource 是否为清晰度切换（用更长延迟避免高码率切换时音频卡两次）
  bool _isQualitySwitchStablePlay = false;
  static const int _stablePlayDelayMs = 60;
  static const int _stablePlayDelayQualitySwitchMs = 60;
  static const int _minBufferSeconds = 1;
  static const int _stablePlayFallbackSeconds = 3;

  int? _currentVid;
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
  static const String _decodeModeKey = 'video_decode_mode';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  bool _settingsLoaded = false;

  VideoPlayerController();

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
        if (videoBuffer > 0) {
          _updateNotifierValue(bufferedSeconds, videoBuffer);
          return;
        }
        _updateNotifierValue(bufferedSeconds, buffer);
      });
    } else {
      _updateNotifierValue(bufferedSeconds, buffer);
    }
  }

  Future<int> _tryGetVideoBuffer() async {
    try {
      final nativePlayer = _player!.platform as NativePlayer;
      final cacheState = await nativePlayer.getProperty('demuxer-cache-state');
      if (cacheState.toString().isEmpty) return 0;
      
      final cacheStr = cacheState.toString();
      final videoRangeMatch = RegExp(r'video\[(\d+)\]:(\d+)-(\d+)').firstMatch(cacheStr);
      if (videoRangeMatch != null) {
        final end = int.tryParse(videoRangeMatch.group(3) ?? '') ?? 0;
        final pos = _player?.state.position.inSeconds ?? 0;
        final videoBuffer = end - pos;
        if (videoBuffer > 0) return videoBuffer;
      }
    } catch (_) {}
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

    if (onProgressUpdate != null && position.inSeconds > 0) {
      final diff = (position.inMilliseconds - _lastReportedPosition.inMilliseconds).abs();
      if (diff >= 500) {
        _lastReportedPosition = position;
        onProgressUpdate!(position, _player!.state.duration);
      }
    }
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
    required int resourceId,
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

      if (!_settingsLoaded) await _loadSettings();

      // 仿 pili_plus：一次性获取所有清晰度的 DASH 数据
      final manifest = await _streamService.getDashManifest(resourceId);
      _dashManifest = manifest;
      _supportsDash = manifest.supportsDash;
      availableQualities.value = manifest.qualities;
      if (manifest.qualities.isEmpty) throw Exception('没有可用的清晰度');

      currentQuality.value = await _getPreferredQuality(availableQualities.value);

      if (_isDisposed || _currentResourceId != resourceId) return;

      // 获取 DataSource：DASH 从缓存取，旧资源回退 m3u8
      final DataSource dataSource;
      if (_supportsDash) {
        final cached = manifest.getDataSource(currentQuality.value!);
        if (cached == null) throw Exception('DASH 数据获取失败');
        dataSource = cached;
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

  // ============ 核心方法：setDataSource（照搬 pilipala）============

  /// 设置播放数据源（pilipala 风格）
  ///
  /// 流程：
  /// 1. removeListeners()，清空缓冲状态
  /// 2. 创建 Player（??= 复用），配置 audio-files 挂载独立音频
  /// 3. startListeners() 先注册监听
  /// 4. player.open(Media(..., start: seekTo), play: false) — 方案 B：等缓冲稳定再 play
  /// 5. 若 autoPlay：设 _pendingStablePlay，buffering 变 false 后延迟 80ms 再 play() 并激活 AudioSession
  Future<void> setDataSource(
    DataSource dataSource, {
    Duration seekTo = Duration.zero,
    bool autoPlay = true,
    bool fromQualitySwitch = false,
  }) async {
    if (_isDisposed) return;

    _isQualitySwitchStablePlay = fromQualitySwitch;

    try {
      isLoading.value = true;

      if (_player != null && _player!.state.playing) {
        await pause();
      }

      removeListeners();
      _pendingStablePlay = false;
      _stablePlayFallbackTimer?.cancel();
      _stablePlayFallbackTimer = null;
      _bufferingShowTimer?.cancel();
      _bufferingShowTimer = null;
      isBuffering.value = false;
      hasEverPlayed.value = false;
      _hasPlaybackStarted = false;
      _hasTriggeredCompletion = false;
      _hasJustCompleted = false;
      _isSeeking = false;

      // pili_plus 风格：removeListeners 后立即预设 sliderPosition = seekTo
      // 防止 UI 在 open() → startListeners() 之间看到 position=0 的闪跳
      _position = _sliderPosition = seekTo;
      _updateSliderPositionSecond();
      _updateBufferedSecond();

      final isNewPlayer = _player == null;
      if (isNewPlayer) {
        final decodeMode = await getDecodeMode();
        _player = Player(
          configuration: PlayerConfiguration(
            title: '',
            bufferSize: 32 * 1024 * 1024,
            logLevel: MPVLogLevel.v,
          ),
        );
        audioHandler.attachPlayer(_player!);
        await _initAudioSession();
        await _configurePlayerOnce(decodeMode);

        _videoController = VideoController(
          _player!,
          configuration: VideoControllerConfiguration(
            enableHardwareAcceleration: decodeMode != 'no',
            androidAttachSurfaceAfterVideoParameters: false,
            hwdec: decodeMode != 'no' ? decodeMode : null,
          ),
        );
      }

      final nativePlayer = _player!.platform as NativePlayer;

      // pilipala 风格：视频和音频是独立 URL，通过 audio-files 挂载外部音频
      if (dataSource.audioSource != null && dataSource.audioSource!.isNotEmpty) {
        final escapedAudio = Platform.isWindows
            ? dataSource.audioSource!.replaceAll(';', '\\;')
            : dataSource.audioSource!.replaceAll(':', '\\:');
        _logger.logDebug('设置 audio-files: ${dataSource.audioSource}');
        await nativePlayer.setProperty('audio-files', escapedAudio);
      } else {
        await nativePlayer.setProperty('audio-files', '');
      }

      // 方案 B：先注册监听器，再 open(play: false)，等缓冲稳定后再 play，避免首帧音频播两次
      startListeners();

      final shouldPlayAfterStable = autoPlay;
      _logger.logDebug('setDataSource: open (seekTo=${seekTo.inSeconds}s, play: $shouldPlayAfterStable)');
      await _player!.open(
        Media(
          dataSource.videoSource,
          start: seekTo,
          httpHeaders: dataSource.httpHeaders,
        ),
        play: false,
      );

      isLoading.value = false;
      isPlayerInitialized.value = true;

      if (shouldPlayAfterStable && !_isDisposed) {
        _pendingStablePlay = true;
        _trySchedulePlayWhenStable();
        _stablePlayFallbackTimer = Timer(const Duration(seconds: _stablePlayFallbackSeconds), () {
          if (_pendingStablePlay) _schedulePlayWhenStable();
          _stablePlayFallbackTimer = null;
        });
      }

    } catch (e) {
      _isSeeking = false;
      // 失败后恢复 listeners，防止播放器变成"聋子"（进度不再上报）
      if (_player != null) startListeners();
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
      _logger.logError(message: 'setDataSource 失败', error: e, stackTrace: StackTrace.current);
    }
  }

  // ============ seek（统一封装）============

  Future<void> seek(Duration position) async {
    if (_isDisposed || _player == null) return;
    if (position < Duration.zero) position = Duration.zero;

    _userIntendedPosition = position;
    _isSeeking = true;

    try {
      await _seekInternal(position);
    } catch (e) {
      _logger.logDebug('seek 错误: $e');
    } finally {
      _isSeeking = false;
    }
  }

  Future<void> _seekInternal(Duration position) async {
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
          try {
            await _player!.seek(position);
          } catch (_) {}
          _isSeeking = false;
        }
      });
    }
  }

  // ============ changeQuality（照搬 pili_plus 的 updatePlayer）============

  Future<void> changeQuality(String quality) async {
    if (_isDisposed || _player == null) return;
    if (currentQuality.value == quality || _currentResourceId == null) return;

    final playerPos = _player!.state.position;
    final position = playerPos.inMilliseconds > 0 ? playerPos : _userIntendedPosition;
    _logger.logDebug('changeQuality: $quality, 保存位置 ${position.inSeconds}s');

    isSwitchingQuality.value = true;

    try {
      await _reloadWithDataSource(quality, position, fromQualitySwitch: true);
      currentQuality.value = quality;
      await _savePreferredQuality(quality);
      _userIntendedPosition = position;
      onQualityChanged?.call(quality);
    } catch (e) {
      _logger.logError(message: '切换清晰度失败', error: e);
      errorMessage.value = '切换清晰度失败';
    } finally {
      isSwitchingQuality.value = false;
    }
  }

  /// 重新加载数据源（用于清晰度切换、卡顿恢复等场景）
  Future<void> _reloadWithDataSource(String? quality, Duration position, {bool setQuality = true, bool fromQualitySwitch = false}) async {
    final targetQuality = quality ?? currentQuality.value;
    if (targetQuality == null || _currentResourceId == null) return;

    final dataSource = await _getDataSourceForQuality(targetQuality);
    if (_isDisposed) return;

    await setDataSource(
      dataSource,
      seekTo: position.inSeconds > 0 ? position : Duration.zero,
      autoPlay: true,
      fromQualitySwitch: fromQualitySwitch,
    );
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

  // ============ 事件监听（照搬 pilipala 的 startListeners/removeListeners）============

  /// 注册播放事件监听（照搬 pilipala 的 startListeners）
  ///
  /// 每次 setDataSource 时先 removeListeners，加载后重新 startListeners
  void startListeners() {
    if (_player == null) return;

    _subscriptions.addAll([
      _player!.stream.playing.listen((playing) {
        if (playing && _hasTriggeredCompletion) {
          _hasTriggeredCompletion = false;
        }

        onPlayingStateChanged?.call(playing);

        // 参考 pili_plus: WakelockPlus.toggle(enable: event)
        WakelockManager.toggle(enable: playing);
      }),

      _player!.stream.completed.listen((completed) {
        if (_isDisposed || _isDisposing) return;
        
        if (completed && !_hasTriggeredCompletion && !_isSeeking && !isSwitchingQuality.value) {
          // 断网假完成检测：HLS 加载不到后续 ts 分片时 mpv 会发出 completed=true，
          // 但实际并没有播放到结尾。用播放进度比例判断：超过 90% 视为真正结束。
          // dur=0（未获取到时长）时不阻塞连播，默认为真完成。
          final pos = _player!.state.position;
          final dur = _player!.state.duration;
          final progress = dur.inSeconds > 0
              ? pos.inMilliseconds / dur.inMilliseconds
              : 1.0; // dur=0 时默认为播完
          final isRealEnd = progress >= 0.9;

          if (!isRealEnd && pos.inSeconds > 0) {
            // 假完成（断网导致流中断）：不触发结束逻辑，改为重试
            _logger.logDebug('断网假完成检测: pos=${pos.inSeconds}s, dur=${dur.inSeconds}s, progress=${(progress * 100).toInt()}%, 尝试重试');
            _handleStalled();
            return;
          }

          _hasTriggeredCompletion = true;
          _hasJustCompleted = true;

          // 触发播放结束回调
          onVideoEnd?.call();

          if (loopMode.value == LoopMode.on) {
            // 循环模式（参考 pili_plus）：play(repeat:true) 原子 seek+play
            _hasTriggeredCompletion = false;
            _hasJustCompleted = false;
            _logger.logDebug('循环模式: play(repeat:true)');
            play(repeat: true);
          }
        }
        if (!completed) {
          _hasTriggeredCompletion = false;
        }
      }),

      _player!.stream.position.listen((position) {
        if (_isDisposed || _isDisposing) return;
        if (_isSeeking) return;
        // 切换清晰度期间忽略 position=0 的跳变（open 重置导致）
        if (isSwitchingQuality.value && position.inSeconds <= 1) return;

        if (!_hasPlaybackStarted) {
          if (position.inSeconds == 0) return;
          _hasPlaybackStarted = true;
        }

        if (position.inSeconds <= 1 && _hasJustCompleted) {
          _hasJustCompleted = false;
        }

        // 调试：打印音视频 PTS 状态（每10秒一次）
        if (position.inSeconds % 10 == 0 && position.inSeconds > 0) {
          _logPtsState();
        }

        _updatePositionState(position);
        if (position > Duration.zero && !hasEverPlayed.value) {
          hasEverPlayed.value = true;
        }
      }),

      _player!.stream.duration.listen((duration) {
        if (duration > Duration.zero) {
          _updateDurationSecond();
        }
      }),

      _player!.stream.buffer.listen((buffer) {
        _updateBufferedSecond();
        if (_pendingStablePlay && !_player!.state.buffering && buffer.inSeconds >= _minBufferSeconds) {
          _schedulePlayWhenStable();
        }
      }),

      _player!.stream.buffering.listen((buffering) {
        if (buffering) {
          _bufferingShowTimer?.cancel();
          _bufferingShowTimer = Timer(const Duration(milliseconds: _bufferingSustainMs), () {
            _bufferingShowTimer = null;
            if (_player != null && _player!.state.buffering) {
              isBuffering.value = true;
            }
          });
          _stalledTimer?.cancel();
          _stalledTimer = Timer(const Duration(seconds: 15), () {
            if (_player != null && _player!.state.buffering) {
              _handleStalled();
            }
          });
        } else {
          _bufferingShowTimer?.cancel();
          _bufferingShowTimer = null;
          isBuffering.value = false;
          _stalledTimer?.cancel();
          if (_pendingStablePlay) {
            _trySchedulePlayWhenStable();
          }
        }
      }),

      // 网络错误监听（PiliPlus 方式）：通过 error stream 检测断网/加载失败，
      // 双重确认（isBuffering + buffer==0）后重试，避免误判。
      _player!.stream.error.listen((error) {
        if (error.isEmpty) return;
        _logger.logDebug('播放错误: $error');

        // 网络相关错误：tcp 超时、URL 打开失败、外部音频文件打开失败（DASH）
        if (error.startsWith('tcp: ') ||
            error.startsWith('Failed to open ') ||
            error.startsWith('Can not open external file ')) {
          // 延迟 3 秒后双重确认：仍在 buffering 且缓冲为空才重试
          Future.delayed(const Duration(seconds: 3), () {
            if (_isDisposed || _player == null) return;
            if (_player!.state.buffering && _player!.state.buffer == Duration.zero) {
              _logger.logDebug('网络错误确认: buffering 且缓冲为空, 重试');
              _handleStalled();
            }
          });
        }
      }),

      // mpv 日志抓取：捕获 AV sync、音频、时间戳相关日志
      _player!.stream.log.listen((log) {
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

  /// 仅在 buffering 结束且缓冲量 >= _minBufferSeconds 时才调度 play
  void _trySchedulePlayWhenStable() {
    if (!_pendingStablePlay || _isDisposed || _player == null) return;
    if (_player!.state.buffering) return;
    if (_player!.state.buffer.inSeconds < _minBufferSeconds) return;
    _schedulePlayWhenStable();
  }

  /// 方案 B：真正执行「延迟后 play」，只执行一次，并取消兜底定时器
  /// 清晰度切换时用更长延迟，避免高码率流起播时音频卡两次
  void _schedulePlayWhenStable() {
    if (!_pendingStablePlay || _isDisposed || _player == null) return;
    _pendingStablePlay = false;
    _stablePlayFallbackTimer?.cancel();
    _stablePlayFallbackTimer = null;
    final delayMs = _isQualitySwitchStablePlay ? _stablePlayDelayQualitySwitchMs : _stablePlayDelayMs;
    _isQualitySwitchStablePlay = false;
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (_isDisposed || _player == null) return;
      play();
      _audioSession?.setActive(true);
    });
  }

  /// 移除事件监听（照搬 pilipala 的 removeListeners）
  void removeListeners() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions = [];
    _stalledTimer?.cancel();
    _stalledTimer = null;
    _seekTimer?.cancel();
    _seekTimer = null;
    _bufferingShowTimer?.cancel();
    _bufferingShowTimer = null;
    _stablePlayFallbackTimer?.cancel();
    _stablePlayFallbackTimer = null;
  }

  /// 处理卡顿恢复（参考 pili_plus 的 refreshPlayer，复用 setDataSource）
  Future<void> _handleStalled() async {
    if (_isHandlingStall) return;
    if (_isInitializing || isLoading.value) return;
    if (isSwitchingQuality.value) return;
    if (_currentResourceId == null || currentQuality.value == null) return;
    if (_player == null) return;

    _isHandlingStall = true;
    try {
      final currentPos = _player!.state.position;
      if (currentPos <= Duration.zero) return;

      _logger.logDebug('_handleStalled: refreshPlayer from ${currentPos.inSeconds}s');
      await _reloadWithDataSource(currentQuality.value!, currentPos, setQuality: false);
      _userIntendedPosition = currentPos;
    } catch (e) {
      _logger.logDebug('_handleStalled 失败: $e');
    } finally {
      _isHandlingStall = false;
    }
  }

  // ============ 辅助方法 ============

  /// 获取指定清晰度的 DataSource（统一入口）
  ///
  /// 优先从缓存的 manifest 获取；manifest 过期或缺失则重新请求；
  /// 旧资源直接回退到 m3u8。
  Future<DataSource> _getDataSourceForQuality(String quality) async {
    // DASH 缓存命中且未过期
    if (_dashManifest != null && _supportsDash && !_dashManifest!.isExpired) {
      final cached = _dashManifest!.getDataSource(quality);
      if (cached != null) return cached;
    }
    // DASH 缓存过期或缺失，重新获取
    if (_supportsDash) {
      _dashManifest = await _streamService.getDashManifest(_currentResourceId!);
      availableQualities.value = _dashManifest!.qualities;
      final cached = _dashManifest!.getDataSource(quality);
      if (cached != null) return cached;
    }
    // 最终回退：旧资源 m3u8 或 DASH 缓存里没有该清晰度
    return _streamService.getM3u8DataSource(_currentResourceId!, quality);
  }

  /// 首次创建 Player 时配置不变的 mpv 属性
  /// 这些属性在整个 Player 生命周期内只需设置一次
  Future<void> _configurePlayerOnce(String decodeMode) async {
    if (_player == null) return;
    final nativePlayer = _player!.platform as NativePlayer;

    // 开启音视频同步日志
    await nativePlayer.setProperty('msg-level', 'cplayer=v,avsync=v');

    // seek 精度：双独立流(video+audio-files)必须用精确 seek，
    // 否则两个流的关键帧位置不同导致 AV 错位
    await nativePlayer.setProperty('hr-seek', 'yes');

    // 不覆盖 video-sync，使用 mpv 默认值（audio）
    await nativePlayer.setProperty('interpolation', 'no');

    // fMP4 容错：discardcorrupt 丢弃损坏帧
    // 注意：不用 genpts / linearize-timestamps（都会破坏 fMP4 的 PTS）
    await nativePlayer.setProperty('demuxer-lavf-o', 'fflags=+discardcorrupt');

    // 禁止 demuxer 回退读取，防止 fMP4 fragment 边界 PTS 回退
    await nativePlayer.setProperty('demuxer-max-back-bytes', '0');

    // 网络超时配置
    await nativePlayer.setProperty('network-timeout', '10');

    // 解码模式配置
    await nativePlayer.setProperty('hwdec', decodeMode);

    // Android 特有配置（参考 pili_plus：仅设 volume-max，ao/audio-buffer 用 mpv 默认）
    if (Platform.isAndroid) {
      await nativePlayer.setProperty('volume-max', '100');
    }

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
    } catch (_) {}
  }

  Future<String> _getPreferredQuality(List<String> qualities) async {
    try {
      final prefs = await _preferences;
      final preferredName = prefs.getString(_preferredQualityKey);
      return findBestQualityMatch(qualities, preferredName);
    } catch (_) {}
    return getDefaultQuality(qualities);
  }

  Future<void> _savePreferredQuality(String quality) async {
    try {
      final prefs = await _preferences;
      final displayName = formatQualityDisplayName(quality);
      await prefs.setString(_preferredQualityKey, displayName);
    } catch (_) {}
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

  void setVideoContext({required int vid, int part = 1}) {
    _currentVid = vid;
    _currentPart = part;
  }

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
  /// 始终设为 no：不依赖 mpv 的 loop-file=inf，因为对于 HLS/DASH 流媒体，
  /// mpv 自动循环会重新请求所有分片（重新 open URL），浪费流量。
  /// 循环逻辑改为在 completed 事件中手动 seek(0) + play()，复用已缓存的资源。
  Future<void> _syncLoopProperty() async {
    if (_player == null) return;
    try {
      final nativePlayer = _player!.platform as NativePlayer;
      await nativePlayer.setProperty('loop-file', 'no');
    } catch (_) {}
  }

  void handleAppLifecycleState(bool isPaused) {
    if (_player == null || _isDisposed) return;

    if (isPaused) {
      // 进入后台
      if (!backgroundPlayEnabled.value) {
        pause();
      }
      // 进入后台时快照一次当前位置（确保即使后台被杀也有可恢复的位置）
      final pos = _player!.state.position;
      if (pos.inSeconds > 0) {
        _userIntendedPosition = pos;
      }
    } else {
      // 回到前台，刷新通知栏信息
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

  /// 播放（参考 pili_plus）
  ///
  /// [repeat] 循环模式时传 true，会先 seek 到开头
  Future<void> play({bool repeat = false}) async {
    if (_isDisposed || _player == null) return;
    if (repeat) {
      await _player!.seek(Duration.zero);
    }
    await _player!.play();
    _audioSession?.setActive(true);
  }

  /// 暂停（参考 pili_plus）
  ///
  /// [isInterrupt] 系统中断（电话等）时传 true，不释放音频焦点
  Future<void> pause({bool isInterrupt = false}) async {
    if (_isDisposed || _player == null) return;
    await _player!.pause();
    if (!isInterrupt) {
      _audioSession?.setActive(false);
    }
  }

  // ============ dispose（照搬 pilipala）============

  /// 初始化音频会话（处理电话等音频中断）
  Future<void> _initAudioSession() async {
    try {
      _audioSession = await AudioSession.instance;
      await _audioSession!.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.movie,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

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
        case AudioInterruptionType.unknown:
          if (_wasPlayingBeforeInterruption) {
            _wasPlayingBeforeInterruption = false;
            play();
            _logger.logDebug('[AudioSession] 中断结束，恢复播放');
          }
          break;
      }
    }
  }

  /// 调试：打印音视频 PTS 状态
  Future<void> _logPtsState() async {
    if (_player == null) return;
    try {
      final nativePlayer = _player!.platform as NativePlayer;
      final videoPtsStr = await nativePlayer.getProperty('video-pts') as String? ?? '0';
      final audioPtsStr = await nativePlayer.getProperty('audio-pts') as String? ?? '0';
      final avsyncStr = await nativePlayer.getProperty('avsync') as String? ?? '0';
      final videoPts = double.tryParse(videoPtsStr) ?? 0;
      final audioPts = double.tryParse(audioPtsStr) ?? 0;
      final avsync = double.tryParse(avsyncStr) ?? 0;
      _logger.logDebug('[PTS] video=${videoPts.toStringAsFixed(3)}s, audio=${audioPts.toStringAsFixed(3)}s, avsync=${avsync.toStringAsFixed(3)}s');
    } catch (_) {}
  }

  /// 处理音频设备变化（耳机拔出等，参考 pili_plus becomingNoisy）
  void _handleBecomingNoisy() {
    if (_player == null || _isDisposed) return;
    if (_player!.state.playing) {
      pause();
      _logger.logDebug('[AudioSession] 耳机拔出，已暂停');
    }
  }

  /// 清理音频会话
  Future<void> _disposeAudioSession() async {
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
    _dashManifest = null;

    WakelockManager.disable();
    await _disposeAudioSession();

    _seekTimer?.cancel();
    _stalledTimer?.cancel();
    _bufferingShowTimer?.cancel();
    _stablePlayFallbackTimer?.cancel();
    _stablePlayFallbackTimer = null;

    // pilipala: removeListeners + 清空 audio-files
    removeListeners();
    await _connectivitySubscription?.cancel();

    // 停止 AudioService 通知栏（先 stop 再 detach，确保状态转换正确）
    await audioHandler.stop();
    audioHandler.detachPlayer();

    // 清理视频缓存
    _cacheService.cleanupAllTempCache();

    if (_player != null) {
      try {
        final nativePlayer = _player!.platform as NativePlayer;
        await nativePlayer.setProperty('audio-files', '');
      } catch (_) {}
      await _player!.dispose();
      _player = null;
    }

    _positionStreamController.close();

    sliderPositionSeconds.dispose();
    durationSeconds.dispose();
    bufferedSeconds.dispose();
    isSliderMoving.dispose();

    super.dispose();
  }
}
