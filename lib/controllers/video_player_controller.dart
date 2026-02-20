import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:audio_session/audio_session.dart';
import '../services/hls_service.dart';
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
  final HlsService _hlsService = HlsService();
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
  Timer? _positionPollingTimer;
  Timer? _waitAndSeekTimer;

  // Surface 重置检测
  Duration _lastValidPosition = Duration.zero;
  bool _isRecoveringFromSurfaceReset = false;

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

  // 缓存设置，避免每次 initialize 都读磁盘
  bool _settingsLoaded = false;

  VideoPlayerController();

  // ============ pili_plus 风格：秒级更新方法（只在秒数变化时通知 UI）============

  void _updateSliderPositionSecond() {
    final newSecond = _sliderPosition.inSeconds;
    if (sliderPositionSeconds.value != newSecond) {
      sliderPositionSeconds.value = newSecond;
    }
  }

  void _updatePositionSecond() {
    // sliderPosition 在非拖拽时跟随 position
    if (!isSliderMoving.value) {
      _sliderPosition = _position;
      _updateSliderPositionSecond();
    }
  }

  void _updateDurationSecond() {
    final newSecond = _player?.state.duration.inSeconds ?? 0;
    if (durationSeconds.value != newSecond) {
      durationSeconds.value = newSecond;
    }
  }

  void _updateBufferedSecond() {
    final newSecond = _player?.state.buffer.inSeconds ?? 0;
    if (bufferedSeconds.value != newSecond) {
      bufferedSeconds.value = newSecond;
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

      if (!_settingsLoaded) await _loadSettings();

      // 仿 pili_plus：一次性获取所有清晰度的 DASH 数据
      final manifest = await _hlsService.getDashManifest(resourceId);
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
        dataSource = await _hlsService.getDataSource(
          resourceId,
          currentQuality.value!,
          supportsDash: false,
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
  /// 3. player.open(Media(videoUrl, start: seekTo), play: false) — mpv 原子 seek 所有流
  /// 4. startListeners()
  /// 5. play()
  Future<void> setDataSource(
    DataSource dataSource, {
    Duration seekTo = Duration.zero,
    bool autoPlay = true,
  }) async {
    if (_isDisposed) return;

    try {
      isLoading.value = true;

      if (_player != null && _player!.state.playing) {
        await _player!.pause();
      }

      removeListeners();
      isBuffering.value = false;
      _hasPlaybackStarted = false;
      _hasTriggeredCompletion = false;
      _hasJustCompleted = false;
      _isRecoveringFromSurfaceReset = false;
      _lastValidPosition = Duration.zero;
      _isSeeking = false;

      // pili_plus 风格：removeListeners 后立即预设 sliderPosition = seekTo
      // 防止 UI 在 open() → startListeners() 之间看到 position=0 的闪跳
      _position = _sliderPosition = seekTo;
      _updateSliderPositionSecond();
      _updateBufferedSecond();

      final isNewPlayer = _player == null;
      _player ??= Player(
        configuration: const PlayerConfiguration(
          title: '',
          bufferSize: 32 * 1024 * 1024,
          logLevel: MPVLogLevel.error,
        ),
      );
      if (isNewPlayer) {
        audioHandler.attachPlayer(_player!);
        await _initAudioSession();
        // 只在首次创建 Player 时设置不变的 mpv 属性
        await _configurePlayerOnce();
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

      _videoController ??= VideoController(
        _player!,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters: false,
        ),
      );

      // 不使用 Media(start:) — 因为 Player 复用(??=)时 on_unload(旧media)会在
      // on_load(新media)之后触发，将 mpv 的 start 属性重置为 'none'，导致进度丢失。
      // 改用 play:false → _waitAndSeek → play() 保证音画同步。
      _logger.logDebug('setDataSource: open (seekTo=${seekTo.inSeconds}s)');
      await _player!.open(
        Media(dataSource.videoSource),
        play: false, // 不自动播放，等 seek 到位后再 play()
      );

      startListeners();

      if (seekTo > Duration.zero) {
        // 等 duration 就绪后 seek，seek 完成后再 play（防音画不同步）
        await _waitAndSeek(seekTo, autoPlay: autoPlay);
      } else if (autoPlay) {
        await _player!.play();
      }

      isLoading.value = false;
      isPlayerInitialized.value = true;

    } catch (e) {
      _isSeeking = false;
      // 失败后恢复 listeners，防止播放器变成"聋子"（进度不再上报）
      if (_player != null) startListeners();
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
      _logger.logError(message: 'setDataSource 失败', error: e, stackTrace: StackTrace.current);
    }
  }


  // ============ seek ============

  /// 跳转到指定位置（仿 pili_plus 的 seekTo）
  ///
  /// pili_plus 做法：立即写入 position → player.seek()
  /// duration 未就绪时用 Timer.periodic 轮询
  /// 没有 _waitForSeekBuffering、没有确认到位重试
  Future<void> seek(Duration position) async {
    if (_isDisposed || _player == null) return;
    if (position < Duration.zero) position = Duration.zero;

    _userIntendedPosition = position;
    _isSeeking = true;

    try {
      if (_player!.state.duration.inSeconds != 0) {
        await _player!.seek(position);
        _isSeeking = false;
      } else {
        // pili_plus: duration 未就绪，Timer.periodic 轮询
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
    } catch (e) {
      _logger.logDebug('seek 错误: $e');
      _isSeeking = false;
    }
  }

  // ============ changeQuality（照搬 pilipala 的 updatePlayer）============

  /// 切换清晰度
  ///
  /// 照搬 pilipala 的 updatePlayer() 流程：
  /// 1. 保存当前位置 defaultST = position.value
  /// 2. removeListeners，清空缓冲状态
  /// 3. 获取新清晰度的 DataSource
  /// 4. 调用 setDataSource(seekTo: defaultST)
  ///
  /// surface 短暂重置是 media_kit 的正常行为，pilipala 也一样。
  Future<void> changeQuality(String quality) async {
    if (_isDisposed) return;
    if (currentQuality.value == quality || _currentResourceId == null) return;

    // 保存当前播放位置，优先级：
    // 1. player.state.position（真实播放位置）
    // 2. _userIntendedPosition（用户拖拽/seek 的目标位置，或上次位置监听器推送的位置）
    // 3. _lastValidPosition（surface 重置前的最后有效位置）
    // 关键：必须在 removeListeners / setDataSource 之前读取，否则 open() 会重置为 0
    final playerPos = _player?.state.position ?? Duration.zero;
    final defaultST = playerPos.inMilliseconds > 0
        ? playerPos
        : (_userIntendedPosition.inMilliseconds > 0
            ? _userIntendedPosition
            : _lastValidPosition);
    _logger.logDebug('changeQuality: 保存位置 defaultST=${defaultST.inSeconds}s '
        '(playerPos=${playerPos.inSeconds}s, userIntended=${_userIntendedPosition.inSeconds}s, '
        'lastValid=${_lastValidPosition.inSeconds}s)');

    // pilipala: removeListeners + 清空状态
    removeListeners();
    isBuffering.value = false;
    _stalledTimer?.cancel(); // 防止质量切换期间 _handleStalled 触发

    isSwitchingQuality.value = true;

    try {
      final dataSource = await _getDataSourceForQuality(quality);
      if (_isDisposed) return;

      await setDataSource(
        dataSource,
        seekTo: defaultST,
        autoPlay: true,
      );

      currentQuality.value = quality;
      await _savePreferredQuality(quality);
      _userIntendedPosition = defaultST;

      onQualityChanged?.call(quality);
    } catch (e) {
      // 失败后恢复 listeners，防止播放器变成"聋子"（进度不再上报）
      if (_player != null) startListeners();
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

        if (playing) {
          WakelockManager.enable();
        } else {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (_player != null && !_player!.state.playing) {
              WakelockManager.disable();
            }
          });
        }
      }),

      _player!.stream.completed.listen((completed) {
        if (completed && !_hasTriggeredCompletion && !_isSeeking) {
          _hasTriggeredCompletion = true;
          _hasJustCompleted = true;

          if (loopMode.value == LoopMode.on) {
            // 循环模式：seek 回开头重新播放，复用已缓存的资源，不重新请求网络
            _hasTriggeredCompletion = false;
            _logger.logDebug('循环模式: seek 到开头复用缓存');
            _player!.seek(Duration.zero).then((_) {
              _player?.play();
              _hasJustCompleted = false;
            });
          } else {
            // 非循环模式：触发播放结束回调（自动连播等）
            onVideoEnd?.call();
          }
        }
        if (!completed) {
          _hasTriggeredCompletion = false;
        }
      }),

      _player!.stream.position.listen((position) {
        // _isSeeking 期间完全不推送，进度条冻结
        if (_isSeeking) return;

        if (!_hasPlaybackStarted) {
          if (position.inSeconds == 0) return;
          _hasPlaybackStarted = true;
        }

        // 判断是否为合法的"回到开头"场景：
        // 1. 循环模式：completed 后手动 seek(0)，position 从接近 duration 跳回 0
        // 2. 刚播放完毕后重新开始（onVideoEnd 触发后用户点重播等）
        final isLooping = loopMode.value == LoopMode.on;
        final isNearEnd = _lastValidPosition.inSeconds > 0 &&
            _player!.state.duration.inSeconds > 0 &&
            (_player!.state.duration.inSeconds - _lastValidPosition.inSeconds).abs() <= 3;
        final isLegitRestart = isLooping || _hasJustCompleted || isNearEnd;

        // Surface 重置检测：从 >3秒 跳回 <=1秒（正常播放中的意外 surface 重建）
        // 排除合法回到开头的场景
        if (!_isRecoveringFromSurfaceReset &&
            !isLegitRestart &&
            _lastValidPosition.inSeconds > 3 &&
            position.inSeconds <= 1) {

          _logger.logDebug('Surface 重置检测: ${_lastValidPosition.inSeconds}s -> ${position.inSeconds}s, 准备恢复');
          _isRecoveringFromSurfaceReset = true;

          final recoveryPosition = _lastValidPosition;

          Future.delayed(const Duration(milliseconds: 200), () {
            if (_player != null && !_isDisposed) {
              _logger.logDebug('Surface 重置恢复: seek to ${recoveryPosition.inSeconds}s');
              _player!.seek(recoveryPosition).then((_) {
                _isRecoveringFromSurfaceReset = false;
              });
            }
          });

          return;
        }

        // 回到开头时重置标记
        if (position.inSeconds <= 1 && isLegitRestart) {
          _hasJustCompleted = false;
          _lastValidPosition = position;
        }

        // 更新最后有效位置
        if (!_isRecoveringFromSurfaceReset) {
          _lastValidPosition = position;
        }

        // pili_plus 风格：更新内部 position，秒级粒度通知 UI
        _position = position;
        _updatePositionSecond();
        _positionStreamController.add(position);
        _userIntendedPosition = position;

        if (onProgressUpdate != null) {
          if (position.inSeconds == 0) return;

          final diff = (position.inMilliseconds - _lastReportedPosition.inMilliseconds).abs();
          if (diff >= 500) {
            _lastReportedPosition = position;
            onProgressUpdate!(position, _player!.state.duration);
          }
        }
      }),

      _player!.stream.duration.listen((duration) {
        if (duration > Duration.zero) {
          _updateDurationSecond();
        }
      }),

      _player!.stream.buffer.listen((buffer) {
        _updateBufferedSecond();
      }),

      _player!.stream.buffering.listen((buffering) {
        isBuffering.value = buffering;

        if (buffering) {
          _stalledTimer?.cancel();
          _stalledTimer = Timer(const Duration(seconds: 15), () {
            if (_player != null && _player!.state.buffering) {
              _handleStalled();
            }
          });
        } else {
          _stalledTimer?.cancel();
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

    // 兜底：position stream 可能在某些设备/场景下停止发射事件
    // 每秒从 player.state.position 轮询，确保进度条始终能更新
    _positionPollingTimer?.cancel();
    _positionPollingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed || _player == null) return;
      if (_isSeeking) return;
      if (!_player!.state.playing) return;

      final position = _player!.state.position;
      if (position.inSeconds <= 0) return;

      if (!_hasPlaybackStarted) {
        _hasPlaybackStarted = true;
      }

      // 只有当 stream 长时间没推送时才由 polling 补发
      final diff = (position.inMilliseconds - _userIntendedPosition.inMilliseconds).abs();
      if (diff >= 800) {
        _lastValidPosition = position;
        _position = position;
        _updatePositionSecond();
        _positionStreamController.add(position);
        _userIntendedPosition = position;

        if (onProgressUpdate != null && position.inSeconds > 0) {
          final reportDiff = (position.inMilliseconds - _lastReportedPosition.inMilliseconds).abs();
          if (reportDiff >= 500) {
            _lastReportedPosition = position;
            onProgressUpdate!(position, _player!.state.duration);
          }
        }
      }
    });
  }

  /// 移除事件监听（照搬 pilipala 的 removeListeners）
  void removeListeners() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions = [];
    _positionPollingTimer?.cancel();
    _positionPollingTimer = null;
    _stalledTimer?.cancel();
    _stalledTimer = null;
    _seekTimer?.cancel();
    _seekTimer = null;
    _waitAndSeekTimer?.cancel();
    _waitAndSeekTimer = null;
  }

  /// 等待 duration 就绪后 seek，seek 完成后再 play()
  ///
  /// 解决音画不同步：open(play:false) 后音频和视频都未播放，
  /// 等 mpv 获取到 duration 后一次性 seek 所有流到目标位置，
  /// 再统一 play()，确保音视频从同一位置同时开始解码。
  Future<void> _waitAndSeek(Duration target, {bool autoPlay = true}) async {
    _waitAndSeekTimer?.cancel();

    // duration 已就绪，直接 seek
    if (_player != null && _player!.state.duration.inSeconds > 0) {
      _logger.logDebug('_waitAndSeek: duration ready, seeking to ${target.inSeconds}s');
      await _player!.seek(target);
      if (autoPlay && !_isDisposed && _player != null) {
        await _player!.play();
      }
      return;
    }

    // duration 未就绪，轮询等待
    _logger.logDebug('_waitAndSeek: waiting for duration...');
    _waitAndSeekTimer = Timer.periodic(const Duration(milliseconds: 200), (Timer t) async {
      if (_isDisposed || _player == null) {
        t.cancel();
        _waitAndSeekTimer = null;
        return;
      }
      if (_player!.state.duration.inSeconds > 0) {
        t.cancel();
        _waitAndSeekTimer = null;
        _logger.logDebug('_waitAndSeek: duration ready, seeking to ${target.inSeconds}s');
        try {
          await _player!.seek(target);
          if (autoPlay && !_isDisposed && _player != null) {
            await _player!.play();
          }
        } catch (e) {
          _logger.logDebug('_waitAndSeek seek error: $e');
          // seek 失败也要播放，否则卡住
          if (autoPlay && !_isDisposed && _player != null) {
            await _player!.play();
          }
        }
      }
    });
  }

  /// 处理卡顿恢复
  Future<void> _handleStalled() async {
    if (_isHandlingStall) return;
    if (_isInitializing || isLoading.value) return;
    if (isSwitchingQuality.value) return; // 质量切换期间不处理卡顿
    if (_currentResourceId == null || currentQuality.value == null) return;

    _isHandlingStall = true;
    try {
      final position = _userIntendedPosition;

      final dataSource = await _getDataSourceForQuality(currentQuality.value!);
      if (_isDisposed) return;

      await setDataSource(
        dataSource,
        seekTo: position.inSeconds > 0 ? position : Duration.zero,
        autoPlay: true,
      );
    } catch (_) {} finally {
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
      _dashManifest = await _hlsService.getDashManifest(_currentResourceId!);
      availableQualities.value = _dashManifest!.qualities;
      final cached = _dashManifest!.getDataSource(quality);
      if (cached != null) return cached;
    }
    // 最终回退：旧资源 m3u8 或 DASH 缓存里没有该清晰度
    return _hlsService.getDataSource(
      _currentResourceId!, quality, supportsDash: _supportsDash);
  }

  /// 首次创建 Player 时配置不变的 mpv 属性
  /// 这些属性在整个 Player 生命周期内只需设置一次
  Future<void> _configurePlayerOnce() async {
    if (_player == null) return;
    final nativePlayer = _player!.platform as NativePlayer;

    // 缓存配置
    await nativePlayer.setProperty('demuxer-seekable-cache', 'yes');
    await nativePlayer.setProperty('cache-secs', '300');
    await nativePlayer.setProperty('cache-backbuffer', '300');
    await nativePlayer.setProperty('cache-pause-initial', 'no');
    await nativePlayer.setProperty('cache-pause-wait', '0');
    await nativePlayer.setProperty('prefetch-playlist', 'no');
    await nativePlayer.setProperty('demuxer-max-bytes', '150MiB');

    // 音画同步配置（仿 pili_plus）
    // display-resample: mpv 重采样音频以匹配显示帧率，保证 AV 同步
    await nativePlayer.setProperty('video-sync', 'display-resample');

    // Android 特有配置
    if (Platform.isAndroid) {
      await nativePlayer.setProperty('volume-max', '100');
      // autosync=30: 每 30 帧重新同步音视频（仿 pili_plus Android 配置）
      await nativePlayer.setProperty('autosync', '30');
      final decodeMode = await getDecodeMode();
      await nativePlayer.setProperty('hwdec', decodeMode);
    }

    // 循环模式
    await _syncLoopProperty();
    await _player!.setAudioTrack(AudioTrack.auto());
  }

  // ============ 设置持久化 ============

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      backgroundPlayEnabled.value = prefs.getBool(_backgroundPlayKey) ?? false;
      final loopModeValue = prefs.getInt(_loopModeKey) ?? 0;
      loopMode.value = LoopMode.values[loopModeValue];
      _settingsLoaded = true;
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
      // 保存显示名（如 '1080p'），findBestQualityMatch 基于显示名匹配
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
    final prefs = await SharedPreferences.getInstance();
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
        _player!.pause();
      }
      // 进入后台时快照一次当前位置（确保即使后台被杀也有可恢复的位置）
      final pos = _player!.state.position;
      if (pos.inSeconds > 0) {
        _lastValidPosition = pos;
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

  Future<void> play() async {
    await _player?.play();
  }

  Future<void> pause() async {
    await _player?.pause();
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

  /// 处理音频中断（电话、语音助手等）
  void _handleAudioInterruption(AudioInterruptionEvent event) {
    if (_player == null || _isDisposed) return;

    if (event.begin) {
      // 中断开始
      switch (event.type) {
        case AudioInterruptionType.duck:
          // 短暂中断（如导航语音）：降低音量即可
          _wasPlayingBeforeInterruption = false;
          _player!.setVolume(30);
          _logger.logDebug('[AudioSession] duck 中断，已降低音量');
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          // 需要暂停的中断（如电话）
          _wasPlayingBeforeInterruption = _player!.state.playing;
          if (_wasPlayingBeforeInterruption) {
            _player!.pause();
            _logger.logDebug('[AudioSession] 中断开始(${event.type})，已暂停播放');
          }
          break;
      }
    } else {
      // 中断结束
      switch (event.type) {
        case AudioInterruptionType.duck:
          // duck 结束：恢复音量
          _player!.setVolume(100);
          _logger.logDebug('[AudioSession] duck 中断结束，已恢复音量');
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          // 暂停中断结束：恢复播放（如果之前在播放）
          if (_wasPlayingBeforeInterruption) {
            _wasPlayingBeforeInterruption = false;
            _player!.play();
            _logger.logDebug('[AudioSession] 中断结束(${event.type})，已恢复播放');
          }
          break;
      }
    }
  }

  /// 处理音频设备变化（耳机拔出等）
  void _handleBecomingNoisy() {
    if (_player == null || _isDisposed) return;
    if (_player!.state.playing) {
      _player!.pause();
      _logger.logDebug('[AudioSession] 音频设备变化，已暂停播放');
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
    _isDisposed = true;
    _dashManifest = null;

    WakelockManager.disable();
    await _disposeAudioSession();

    _seekTimer?.cancel();
    _stalledTimer?.cancel();
    _positionPollingTimer?.cancel();
    _waitAndSeekTimer?.cancel();

    // pilipala: removeListeners + 清空 audio-files
    removeListeners();
    await _connectivitySubscription?.cancel();

    // 停止 AudioService 通知栏
    audioHandler.detachPlayer();
    await audioHandler.stop();

    // 清理视频缓存
    _hlsService.cleanupAllTempCache();

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
