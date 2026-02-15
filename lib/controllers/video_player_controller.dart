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
  bool _isSeeking = false;

  Duration _userIntendedPosition = Duration.zero;
  Duration _lastReportedPosition = Duration.zero;
  Duration? _seekAfterOpen; // open() 后等 duration 就绪再显式 seek，期间冻结 UI
  int _seekAfterOpenRetries = 0; // _waitAndSeek 的重试计数
  static const int _maxSeekAfterOpenRetries = 20; // 最多重试 20 次（每次 300ms = 6s）
  int? _lastProgressFetchTime;

  // pilipala 风格：用 List 管理所有 stream subscription，方便批量取消/重建
  List<StreamSubscription> _subscriptions = [];
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Timer? _stalledTimer;
  Timer? _seekTimer;
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

  VideoPlayerController();

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

      _supportsDash = qualityInfo.supportsDash;
      availableQualities.value = HlsService.sortQualities(qualityInfo.qualities);
      currentQuality.value = await _getPreferredQuality(availableQualities.value);

      // 获取 DataSource
      final dataSource = await _hlsService.getDataSource(
        resourceId,
        currentQuality.value!,
        supportsDash: _supportsDash,
      );

      if (_isDisposed || _currentResourceId != resourceId) return;

      // 设置数据源并开始播放
      await setDataSource(
        dataSource,
        seekTo: initialPosition != null && initialPosition > 0
            ? Duration(seconds: initialPosition.toInt())
            : Duration.zero,
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

  // ============ 核心方法：setDataSource（照搬 pilipala）============

  /// 设置播放数据源（pilipala 风格）
  ///
  /// 流程：
  /// 1. removeListeners()，清空缓冲状态
  /// 2. 创建 Player（??= 复用），配置 audio-files 挂载独立音频
  /// 3. player.open(Media(videoUrl, start: seekTo)) 加载视频直链
  /// 4. startListeners()
  /// 5. _seekAfterOpen 机制处理 surface 重建后的进度恢复
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
      }

      final nativePlayer = _player!.platform as NativePlayer;

      // 启用 HTTP 请求调试日志
      await nativePlayer.setProperty('msg-level', 'http/curl:6');
      await nativePlayer.setProperty('msg-level', 'httpv=6');
      await nativePlayer.setProperty('log-level', 'debug');

      // 优化 DASH/HLS 分段请求 - 按需加载，减少预缓存
      await nativePlayer.setProperty('demuxer-seekable-cache', 'no');  // 不缓存不可查找区域
      await nativePlayer.setProperty('cache-seek-min', '50');  // 至少 50MB 空闲内存才缓存 seek
      await nativePlayer.setProperty('cache-backbuffer', '0');  // 不缓存回放位置之前的内容
      await nativePlayer.setProperty('cache-pause-initial', 'no');  // 暂停时不预加载
      await nativePlayer.setProperty('cache-pause-wait', '0');  // 暂停时不等待缓存

      // 禁用预加载，减少网络占用
      await nativePlayer.setProperty('prefetch-playlist', 'no');  // 不预加载播放列表
      await nativePlayer.setProperty('demuxer-max-bytes', '15MiB');  // 限制解复用器缓存为 15MB

      if (Platform.isAndroid) {
        await nativePlayer.setProperty("volume-max", "100");
        final decodeMode = await getDecodeMode();
        await nativePlayer.setProperty("hwdec", decodeMode);
      }

      await _syncLoopProperty();
      await _player!.setAudioTrack(AudioTrack.auto());

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

      // 不使用 Media(start:) —— media_kit 的 on_load/on_unload 钩子存在竞态：
      // on_unload（卸载旧媒体）可能在 on_load（加载新媒体）之后触发，
      // 导致 start 属性被重置为 'none'，进度丢失。
      // 改用：open() 后监听 duration > 0，然后显式 seek()。
      if (seekTo > Duration.zero) {
        _seekAfterOpen = seekTo;
        _seekAfterOpenRetries = 0;
        _logger.logDebug('setDataSource: 设置 _seekAfterOpen=${seekTo.inSeconds}s');
        // 安全超时：10秒后强制解冻 UI，防止网络慢时永久冻结
        Future.delayed(const Duration(seconds: 10), () {
          if (_seekAfterOpen != null && !_isDisposed) {
            _logger.logDebug('_seekAfterOpen 超时 10s，强制清除');
            _seekAfterOpen = null;
            _seekAfterOpenRetries = 0;
          }
        });
      } else {
        _seekAfterOpen = null;
        _seekAfterOpenRetries = 0;
      }

      _logger.logDebug('setDataSource: open (不带 start，后续显式 seek)');
      await _player!.open(
        Media(dataSource.videoSource),
        play: autoPlay,
      );

      removeListeners();
      startListeners();

      // open() 完成后，等待 duration 就绪再显式 seek
      if (_seekAfterOpen != null) {
        _waitAndSeek(_seekAfterOpen!);
      }

      isLoading.value = false;
      isPlayerInitialized.value = true;

    } catch (e) {
      _isSeeking = false;
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
      _logger.logError(message: 'setDataSource 失败', error: e, stackTrace: StackTrace.current);
    }
  }


  /// open() 后等待 duration 就绪，然后显式 seek 到目标位置
  ///
  /// 为什么不用 Media(start:)：media_kit 通过 on_load/on_unload 钩子设置 mpv 的
  /// start 属性，但 on_unload（卸载旧媒体）可能在 on_load（加载新媒体）之后触发，
  /// 导致 start 被重置为 'none'。这在复用 Player 切换清晰度时尤其容易发生。
  ///
  /// 此方法使用 Timer.periodic 轮询 duration，一旦 > 0 就执行 seek。
  /// 整个过程中 _seekAfterOpen 保持非 null，位置监听器会冻结 UI。
  void _waitAndSeek(Duration target) {
    _seekAfterOpenRetries = 0;
    _waitAndSeekTimer?.cancel();
    _waitAndSeekTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (_isDisposed || _player == null || _seekAfterOpen == null) {
        timer.cancel();
        _waitAndSeekTimer = null;
        return;
      }

      _seekAfterOpenRetries++;

      // 超过最大重试次数，放弃
      if (_seekAfterOpenRetries > _maxSeekAfterOpenRetries) {
        _logger.logDebug('_waitAndSeek: 超过最大重试 $_maxSeekAfterOpenRetries 次，放弃');
        timer.cancel();
        _waitAndSeekTimer = null;
        _seekAfterOpen = null;
        _seekAfterOpenRetries = 0;
        return;
      }

      final duration = _player!.state.duration;
      if (duration.inSeconds > 0) {
        timer.cancel();
        _waitAndSeekTimer = null;
        _logger.logDebug('_waitAndSeek: duration 就绪 (${duration.inSeconds}s)，seek to ${target.inSeconds}s');
        try {
          await _player!.seek(target);
          // 短暂延迟确认 seek 生效
          await Future.delayed(const Duration(milliseconds: 500));
          if (_isDisposed) return;
          final pos = _player!.state.position;
          _logger.logDebug('_waitAndSeek: seek 后 position=${pos.inSeconds}s');
          // 如果位置偏差过大，再试一次
          if ((pos.inMilliseconds - target.inMilliseconds).abs() > 3000 &&
              _player != null && !_isDisposed) {
            _logger.logDebug('_waitAndSeek: 偏差过大，重试 seek');
            await _player!.seek(target);
            await Future.delayed(const Duration(milliseconds: 300));
          }
        } catch (e) {
          _logger.logDebug('_waitAndSeek: seek 失败: $e');
        } finally {
          _seekAfterOpen = null;
          _seekAfterOpenRetries = 0;
          _logger.logDebug('_waitAndSeek: 解冻 UI');
        }
      }
    });
  }

  /// 等待 seek 引发的缓冲完成
  ///
  /// DASH 下 seek 会触发 buffering=true（加载目标位置的分片），
  /// 等到 buffering=false 时 mpv 才真正准备好从目标位置播放。
  ///
  /// 注意：不能用 position stream 判断 seek 是否完成 —— mpv 在 seek 命令后
  /// 会立刻把 state.position 设为目标值（内部标记），但数据还没加载到，
  /// 随后 position 可能跳回 0。
  Future<void> _waitForSeekBuffering() async {
    if (_player == null) return;

    final c = Completer<void>();
    bool sawBufferingTrue = false;

    final sub = _player!.stream.buffering.listen((buffering) {
      if (buffering) {
        sawBufferingTrue = true;
      } else if (sawBufferingTrue && !c.isCompleted) {
        c.complete();
      }
    });

    try {
      // 如果 seek 没触发 buffering（例如目标位置已在缓冲区内），
      // 短暂等待后检查状态
      await c.future.timeout(const Duration(seconds: 8), onTimeout: () {
        if (!sawBufferingTrue) {
          _logger.logDebug('_waitForSeekBuffering: seek 未触发缓冲, 直接继续');
        } else {
          _logger.logDebug('_waitForSeekBuffering: 超时 8s');
        }
      });
    } finally {
      await sub.cancel();
    }
  }

  // ============ seek ============

  /// 跳转到指定位置
  ///
  /// 直接调用 player.seek()，mpv 会自动丢弃旧缓冲、从目标位置的分片开始加载
  /// duration 未就绪时用 Timer.periodic 重试
  Future<void> seek(Duration position) async {
    if (_isDisposed || _player == null) return;
    if (position < Duration.zero) position = Duration.zero;

    _userIntendedPosition = position;
    _isSeeking = true;

    try {
      if (_player!.state.duration.inSeconds != 0) {
        await _player!.seek(position);
        // 等待 seek 引发的缓冲完成
        await _waitForSeekBuffering();
        if (_isDisposed) return;
        
        // 确认位置是否到位
        final currentPos = _player!.state.position;
        if ((currentPos.inMilliseconds - position.inMilliseconds).abs() > 3000) {
          await _player!.seek(position);
          await _waitForSeekBuffering();
        }
      } else {
        // duration 未就绪，定时重试
        _seekTimer?.cancel();
        _seekTimer = Timer.periodic(const Duration(milliseconds: 200), (Timer t) async {
          if (_isDisposed || _player == null) {
            t.cancel();
            _seekTimer = null;
            return;
          }
          if (_player!.state.duration.inSeconds != 0) {
            t.cancel();
            _seekTimer = null;
            await _player!.seek(position);
            await _waitForSeekBuffering();
          }
        });
      }
    } catch (e) {
      _logger.logDebug('seek 错误: $e');
    } finally {
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

    isSwitchingQuality.value = true;

    try {
      final dataSource = await _hlsService.getDataSource(
        _currentResourceId!,
        quality,
        supportsDash: _supportsDash,
      );

      if (_isDisposed) return;

      // pilipala: playerInit() → setDataSource(seekTo: defaultST)
      await setDataSource(
        dataSource,
        seekTo: defaultST,
        autoPlay: true,
      );

      currentQuality.value = quality;
      await _savePreferredQuality(quality);
      _userIntendedPosition = defaultST;

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
          _hasJustCompleted = true; // 刚播放完毕
          onVideoEnd?.call();
        }
        // 循环播放时重置标记
        if (!completed) {
          _hasTriggeredCompletion = false;
        }
      }),

      _player!.stream.position.listen((position) {
        // _isSeeking 期间完全不推送，进度条冻结
        if (_isSeeking) return;

        // _seekAfterOpen 期间冻结 UI：_waitAndSeek 正在等 duration 就绪后 seek
        // 整个过程不推送任何位置给 UI，避免进度条跳动
        if (_seekAfterOpen != null) return;

        if (!_hasPlaybackStarted) {
          if (position.inSeconds == 0) return;
          _hasPlaybackStarted = true;
        }

        // 判断是否为合法的"回到开头"场景：
        // 1. 循环模式 (loop-file=inf)：mpv 自动循环，position 从接近 duration 跳回 0
        // 2. 刚播放完毕后重新开始（onVideoEnd 触发后用户点重播等）
        final isLooping = loopMode.value == LoopMode.on;
        final isNearEnd = _lastValidPosition.inSeconds > 0 &&
            _player!.state.duration.inSeconds > 0 &&
            (_player!.state.duration.inSeconds - _lastValidPosition.inSeconds).abs() <= 3;
        final isLegitRestart = isLooping || _hasJustCompleted || isNearEnd;

        // Surface 重置检测：从 >3秒 跳回 <=1秒（正常播放中的意外 surface 重建）
        // 排除合法回到开头的场景和 _seekAfterOpen 场景（已在上面处理）
        if (!_isRecoveringFromSurfaceReset &&
            _seekAfterOpen == null &&
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
        // pilipala: 只在 duration > 0 时更新
        if (duration > Duration.zero) {
          // duration 更新通知（用于 UI）
        }
      }),

      _player!.stream.buffer.listen((buffer) {
        // 缓冲位置更新
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
  }

  /// 移除事件监听（照搬 pilipala 的 removeListeners）
  void removeListeners() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions = [];
  }

  /// 处理卡顿恢复
  Future<void> _handleStalled() async {
    if (_isInitializing || isLoading.value) return;
    if (_currentResourceId == null || currentQuality.value == null) return;

    try {
      final position = _userIntendedPosition;

      final dataSource = await _hlsService.getDataSource(
        _currentResourceId!,
        currentQuality.value!,
        supportsDash: _supportsDash,
      );

      if (_isDisposed) return;

      await setDataSource(
        dataSource,
        seekTo: position.inSeconds > 0 ? position : Duration.zero,
        autoPlay: true,
      );
    } catch (_) {}
  }

  // ============ 辅助方法 ============

  void _preloadAdjacentQualities() {
    final current = currentQuality.value;
    if (current == null || _currentResourceId == null) return;

    final qualities = availableQualities.value;
    final index = qualities.indexOf(current);
    if (index == -1) return;

    if (index > 0) {
      unawaited(_hlsService.getDataSource(_currentResourceId!, qualities[index - 1], supportsDash: _supportsDash));
    }
    if (index < qualities.length - 1) {
      unawaited(_hlsService.getDataSource(_currentResourceId!, qualities[index + 1], supportsDash: _supportsDash));
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
  Future<void> _syncLoopProperty() async {
    if (_player == null) return;
    try {
      final nativePlayer = _player!.platform as NativePlayer;
      // loop-file=inf: mpv 自动循环当前文件，不触发 completed
      // loop-file=no: 播放完成后触发 completed
      await nativePlayer.setProperty(
        'loop-file',
        loopMode.value == LoopMode.on ? 'inf' : 'no',
      );
    } catch (_) {}
  }

  void handleAppLifecycleState(bool isPaused) {
    if (_player == null) return;

    if (isPaused) {
      // 进入后台
      if (!backgroundPlayEnabled.value) {
        // 未开启后台播放，暂停
        _player!.pause();
      }
      // 开启了后台播放，AudioService 的通知栏控件自动接管
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

    WakelockManager.disable();
    await _disposeAudioSession();

    _seekTimer?.cancel();
    _waitAndSeekTimer?.cancel();
    _stalledTimer?.cancel();

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

    super.dispose();
  }
}
