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

/// 视频播放器控制器 (V_Refactored_Unified_Progress)
///
/// 重构版本：
/// 1. 统一进度管理：所有 seek/恢复/切换清晰度使用相同的 5 步原子操作
/// 2. Native 优先：使用 MPV --start 属性实现零秒起播
/// 3. 严格时序：Open(Paused) -> Verify Position -> Play
/// 4. 可靠位置追踪：_lastKnownGoodPosition 在 seek 和播放时实时更新
class VideoPlayerController extends ChangeNotifier {
  final HlsService _hlsService = HlsService();
  final LoggerService _logger = LoggerService.instance;
  late final Player player;
  late final VideoController videoController;

// AudioService Handler (后台播放) - 【关键修复】改为静态实例，全局共享
  static VideoAudioHandler? _audioHandler;

  // 【关键修复】标记 AudioService 是否已初始化（AudioService.init 只能调用一次）
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

  // ============ 自定义进度流 (防跳变) ============
  final StreamController<Duration> _positionStreamController = StreamController.broadcast();
  Stream<Duration> get positionStream => _positionStreamController.stream;

  // ============ 核心并发控制变量 ============
  Timer? _debounceTimer;
  int _switchEpoch = 0;
  Timer? _seekRetryTimer;
  Duration? _anchorPosition;
  bool? _resumeAfterQualitySwitch;
  Duration _lastKnownGoodPosition = Duration.zero;
  bool _isFreezingPosition = false;
  bool _isDisposed = false;

  // ============ 内部状态 ============
  bool _hasTriggeredCompletion = false;
  bool _isRecovering = false;
  bool _wasPlayingBeforeBackground = false;
  Duration? _positionBeforeBackground; // 保存进入后台前的播放位置

  // 【关键修复】保存所有 player.stream 的订阅，以便 dispose 时正确取消
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;

  // 【关键】进度恢复锁：在初始进度恢复成功之前，不触发进度上报
  bool _isSeekingInitialPosition = false;
  // 【关键】成功恢复的位置，用于防止解锁后的异常跳变
  Duration? _confirmedSeekPosition;
  // 【关键】解锁后的保护期结束时间
  DateTime? _seekProtectionEndTime;
  // 【关键】上次进度修复的时间，用于节流
  DateTime? _lastSeekRecoveryTime;

  // 网络状态监听
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasConnected = true;

  // 【通话监听】音频会话打断监听
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSubscription;
  bool _wasPlayingBeforeInterruption = false; // 通话前是否正在播放

  // 【电话检测】使用 call_state_handler 更可靠地检测电话
  CallStateHandler? _callStateHandler;
  StreamSubscription<CallState>? _callStateSubscription;

  // 播放卡顿监听
  Timer? _stalledTimer;
  int _stalledCount = 0;

  // 智能缓冲检测（防止在已缓存范围内快进时显示加载动画）
  bool _isSeekingWithinCache = false;
  Timer? _seekDebounceTimer;

  // 预加载清晰度缓存 - 存储 MediaSource 对象
  final Map<String, MediaSource> _qualityCache = {};
  Timer? _preloadTimer;

  // SharedPreferences Keys
  static const String _preferredQualityKey = 'preferred_video_quality_display_name';
  static const String _loopModeKey = 'video_loop_mode';
  static const String _backgroundPlayKey = 'background_play_enabled';
  static const String _decodeModeKey = 'video_decode_mode';

  // 解码模式：软解码(no)、硬解码(auto-copy)
  // 默认使用软解码，兼容性更好
  String _currentDecodeMode = 'no';

  int? _currentResourceId;

  // 回调
  VoidCallback? onVideoEnd;
  // 【修改后】增加 totalDuration 参数
  Function(Duration position, Duration totalDuration)? onProgressUpdate;

  Function(String quality)? onQualityChanged;

  VideoPlayerController() {
    player = Player(
      configuration: const PlayerConfiguration(
        title: '',
        bufferSize: 32 * 1024 * 1024,
        // 【关键修复】使用最低可用日志级别，减少日志回调
        // 这可以降低 dispose 时 "Callback invoked after deleted" 崩溃的概率
        logLevel: MPVLogLevel.error,
      ),
    );

    // 【性能优化】配置 VideoController，增加帧缓冲区大小
    // 解决 "Unable to acquire a buffer item" 警告
    videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        // 启用硬件加速
        enableHardwareAcceleration: true,
        // Android 纹理输出（性能更好）
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );
    _setupPlayerListeners();
    _setupConnectivityListener();
    _setupAudioInterruptionListener();
    _setupCallStateListener();
  }

  Future<void> initialize({
    required int resourceId,
    double? initialPosition,
  }) async {
    try {
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;

      // 【关键】重置进度恢复状态
      _isSeekingInitialPosition = false;
      _confirmedSeekPosition = null;
      _seekProtectionEndTime = null;

      // 【性能优化】并发执行初始化操作
      // 第一批：配置播放器属性 + 获取清晰度列表 + 加载设置（并发）
      final initResults = await Future.wait([
        _configurePlayerProperties(), // 配置 MPV 属性
        _hlsService.getAvailableQualities(resourceId), // 获取清晰度
        _loadSettingsParallel(), // 并发加载所有设置
      ]);

      final qualities = initResults[1] as List<String>;

      if (qualities.isEmpty) {
        throw Exception('没有可用的清晰度');
      }

      availableQualities.value = _sortQualitiesDescending(qualities);

      // 获取首选清晰度（使用已缓存的 prefs）
      currentQuality.value = await _getPreferredQuality(availableQualities.value);

      // 【性能优化】后台启动 AudioService（不阻塞视频加载）
      if (backgroundPlayEnabled.value) {
        _ensureAudioServiceReady().catchError((e) {
          debugPrint('❌ [AudioService] 准备失败: $e');
        });
      }

      // 加载视频（这里是主要耗时操作）
      await _loadVideo(currentQuality.value!, isInitialLoad: true, initialPosition: initialPosition);

      isLoading.value = false;
      isPlayerInitialized.value = true;
    } catch (e) {
      _logger.logError(
        message: '初始化播放器失败',
        error: e,
        stackTrace: StackTrace.current,
        context: {'resourceId': resourceId},
      );
      isLoading.value = false;
      errorMessage.value = _getErrorMessage(e);
    }
  }

  /// 并发加载所有设置
  Future<void> _loadSettingsParallel() async {
    final prefs = await SharedPreferences.getInstance();
    // 一次性读取所有设置
    loopMode.value = LoopModeExtension.fromString(prefs.getString(_loopModeKey));
    backgroundPlayEnabled.value = prefs.getBool(_backgroundPlayKey) ?? false;
    // 加载解码模式设置，默认软解码
    _currentDecodeMode = prefs.getString(_decodeModeKey) ?? 'no';
  }

  /// 根据错误类型返回友好的错误提示
  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // 视频特定错误
    if (errorStr.contains('没有可用的清晰度')) {
      return '暂无可播放的视频源';
    }

    // 使用统一的错误处理
    final message = ErrorHandler.getErrorMessage(error);

    // 视频相关错误特殊处理
    if (message.contains('资源不存在')) {
      return '视频资源不存在';
    }
    if (message.contains('访问权限')) {
      return '暂无播放权限';
    }

    return message;
  }

 // 【性能优化】上一次更新的进度（用于节流）
  Duration _lastReportedPosition = Duration.zero;
  // 【性能优化】上一次 Wakelock 状态
  bool _lastWakelockState = false;

  void _setupPlayerListeners() {
    // 【关键修复】保存所有订阅引用，以便 dispose 时正确取消
    // 这可以防止 "Callback invoked after it has been deleted" 崩溃

    // 1. 进度监听（节流优化：每500ms最多更新一次回调，UI流仍然实时）
    _positionSubscription = player.stream.position.listen((position) {
      if (_isFreezingPosition && _anchorPosition != null) {
        _positionStreamController.add(_anchorPosition!);
        return;
      }
      // 【新增】时刻记录最后一次非0进度
      if (position.inSeconds > 0) {
        _lastKnownGoodPosition = position;
      }
      // 【关键修复】只有在 非切换状态 且 大于0 时才更新备份
      // 防止切换瞬间的 0 值覆盖了正确的备份
      if (!isSwitchingQuality.value && position.inSeconds > 0) {
        _lastKnownGoodPosition = position;
      }
      // UI 进度条始终实时更新
      _positionStreamController.add(position);

      // 【性能优化】onProgressUpdate 回调节流（每500ms调用一次）
      // 【关键修复】在初始进度恢复期间不触发上报，避免网络不好时上报错误进度
      if (!isSwitchingQuality.value && !_isSeekingInitialPosition && onProgressUpdate != null) {
        // 【关键修复】解锁后的保护期内，检测异常跳变并主动修复
        if (_seekProtectionEndTime != null && _confirmedSeekPosition != null) {
          final now = DateTime.now();
          // 计算与确认位置的绝对偏差（双向检测：向前跳或向后跳都算异常）
          final positionDiff = (position.inSeconds - _confirmedSeekPosition!.inSeconds).abs();

          if (now.isBefore(_seekProtectionEndTime!)) {
            // 在保护期内，如果偏差超过 10 秒，说明发生了异常跳变
            if (positionDiff > 10) {
              // 【关键】不仅忽略上报，还要主动修复进度
              // 使用节流避免频繁 seek
              if (_lastSeekRecoveryTime == null ||
                  now.difference(_lastSeekRecoveryTime!).inMilliseconds > 500) {
                _lastSeekRecoveryTime = now;
                debugPrint('🛡️ [ProgressGuard] 检测到异常跳变: ${position.inSeconds}s (期望=${_confirmedSeekPosition!.inSeconds}s) -> 修复');
                player.seek(_confirmedSeekPosition!);
              }
              return;
            }
          } else {
            // 保护期结束，检查进度是否正确
            if (positionDiff > 10) {
              // 保护期结束但进度仍然错误，延长保护期并修复
              debugPrint('⚠️ [ProgressGuard] 保护期结束但进度仍错误 (当前=${position.inSeconds}s, 期望=${_confirmedSeekPosition!.inSeconds}s)，延长保护期并修复');
              _seekProtectionEndTime = DateTime.now().add(const Duration(seconds: 5));
              player.seek(_confirmedSeekPosition!);
              return;
            }
            // 进度正确，清除保护状态
            _seekProtectionEndTime = null;
            _confirmedSeekPosition = null;
          }
        }

        final diff = (position.inMilliseconds - _lastReportedPosition.inMilliseconds).abs();
        if (diff >= 500) {
          _lastReportedPosition = position;
          onProgressUpdate!(position, player.state.duration);
        }
      }
    });

    // 2. 完播监听
    _completedSubscription = player.stream.completed.listen((completed) {
      // 【关键修复】在初始进度恢复期间或保护期内，忽略完播事件
      // 防止 m4s/mp4 文件 seek 时误触发完播
      if (completed && !_hasTriggeredCompletion && !_isFreezingPosition &&
          !_isSeekingInitialPosition && _seekProtectionEndTime == null) {
        _hasTriggeredCompletion = true;
        _handlePlaybackEnd();
      }
    });

    // 3. 播放状态监听 + Wakelock 控制
    // 【简化逻辑】只要播放器正在播放就保持亮屏，暂停/停止时才关闭
    _playingSubscription = player.stream.playing.listen((playing) {
      if (playing && _hasTriggeredCompletion) {
        _hasTriggeredCompletion = false;
      }

      // 【关键修复】直接绑定播放状态，播放中始终保持亮屏
      if (playing) {
        // 播放中 -> 保持亮屏
        if (!_lastWakelockState) {
          _lastWakelockState = true;
          WakelockManager.enable();
        }
      } else {
        // 暂停/停止时，延迟检查：如果很快又恢复播放（如循环播放），则不关闭亮屏
        Future.delayed(const Duration(milliseconds: 500), () {
          // 500ms 后再次检查播放状态
          if (!player.state.playing && _lastWakelockState) {
            _lastWakelockState = false;
            WakelockManager.disable();
          }
        });
      }
    });

    // 4. 缓冲状态监听 + 超时检测
    _bufferingSubscription = player.stream.buffering.listen((buffering) {
      // 【修复】智能检测逻辑优化
      if (_isSeekingWithinCache && buffering) {
        return;
      }

      isBuffering.value = buffering;

      if (buffering) {
        _stalledTimer?.cancel();
        _stalledTimer = Timer(const Duration(seconds: 15), () {
          if (player.state.buffering) {
            debugPrint('⚠️ 播放卡住超过15秒，尝试智能恢复...');
            _handleStalledPlayback();
          }
        });
      } else {
        _stalledTimer?.cancel();
        _stalledCount = 0;
      }
    });
  }

  void _handlePlaybackEnd() {
    switch (loopMode.value) {
      case LoopMode.on:
        // 【修复】重置缓冲状态，防止上一轮播放结束时的缓冲状态残留
        isBuffering.value = false;

        // 循环播放：直接 seek 到开头并播放
        // Wakelock 由播放状态监听器自动管理（延迟关闭机制会保护循环播放）
        seek(Duration.zero).then((_) {
          player.play();
        });
        break;
      case LoopMode.off:
        onVideoEnd?.call();
        break;
    }
  }
  /// 设置网络状态监听
  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isConnected = results.any((result) => result != ConnectivityResult.none);

      // 从断网恢复到联网
      if (!_wasConnected && isConnected) {
        debugPrint('📡 网络已恢复，尝试重新连接...');
        _onNetworkRestored();
      }

      // 检测到断网
      if (_wasConnected && !isConnected) {
        debugPrint('📡 网络已断开');
      }

      _wasConnected = isConnected;
    });
  }

  /// 网络恢复后的处理
  void _onNetworkRestored() {
    // 重置计数器
    _stalledCount = 0;

    // 如果当前有错误或正在缓冲，尝试恢复
    if (errorMessage.value != null || isBuffering.value) {
      errorMessage.value = null;
      _handleStalledPlayback();
    }
  }

  /// 设置音频打断监听（电话、其他应用播放音频等）
  void _setupAudioInterruptionListener() {
    AudioSession.instance.then((session) async {
      // 【关键修复】配置音频会话 - 不使用 mixWithOthers，这样才能正确响应电话打断
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        // 【关键】不设置 mixWithOthers，让系统能正确发送打断事件
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.moviePlayback,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.movie,
          usage: AndroidAudioUsage.media,
        ),
        // 【关键】使用 gainTransientMayDuck，这样来电时会收到打断事件
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));

      // 【关键修复】激活音频会话，这样才能接收打断事件
      await session.setActive(true);
      debugPrint('📞 [AudioSession] 音频会话已激活');

      // 监听音频打断事件（电话、其他应用等）
      _audioInterruptionSubscription = session.interruptionEventStream.listen((event) {
        debugPrint('📞 [AudioInterruption] begin=${event.begin}, type=${event.type}');

        if (event.begin) {
          // 打断开始（如来电）
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 其他应用需要降低音量（如导航提示音），可以选择降低音量而不是暂停
              debugPrint('📞 [AudioInterruption] 需要降低音量');
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              // 需要暂停播放（如来电）
              _wasPlayingBeforeInterruption = player.state.playing;
              if (_wasPlayingBeforeInterruption) {
                debugPrint('📞 [AudioInterruption] 来电/其他应用打断，暂停播放');
                player.pause();
              }
              break;
          }
        } else {
          // 打断结束（如挂断电话）
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 恢复音量
              debugPrint('📞 [AudioInterruption] 恢复音量');
              break;
            case AudioInterruptionType.pause:
              // 打断结束，恢复播放
              if (_wasPlayingBeforeInterruption) {
                debugPrint('📞 [AudioInterruption] 通话结束，恢复播放');
                player.play();
                _wasPlayingBeforeInterruption = false;
              }
              break;
            case AudioInterruptionType.unknown:
              // 未知类型的打断结束，不自动恢复
              debugPrint('📞 [AudioInterruption] 未知打断结束，不自动恢复');
              _wasPlayingBeforeInterruption = false;
              break;
          }
        }
      });

      // 【新增】监听音频焦点变化（Android 特有，更可靠地检测电话）
      session.becomingNoisyEventStream.listen((_) {
        // 耳机拔出时暂停
        if (player.state.playing) {
          debugPrint('📞 [AudioSession] 耳机拔出，暂停播放');
          player.pause();
        }
      });

      debugPrint('📞 [AudioInterruption] 监听已启动');
    }).catchError((e) {
      debugPrint('❌ [AudioInterruption] 初始化失败: $e');
    });
  }

  /// 【关键】设置电话状态监听（更可靠的方案）
  void _setupCallStateListener() {
    try {
      _callStateHandler = CallStateHandler();
      _callStateHandler!.initialize().then((_) {
        debugPrint('📞 [CallStateHandler] 初始化成功');

        _callStateSubscription = _callStateHandler!.onCallStateChanged.listen((callState) {
          debugPrint('📞 [CallStateHandler] 通话状态变化: isCallActive=${callState.isCallActive}, callType=${callState.callType}');

          if (callState.isCallActive) {
            // 来电或正在通话中
            if (!_wasPlayingBeforeInterruption && player.state.playing) {
              _wasPlayingBeforeInterruption = true;
              debugPrint('📞 [CallStateHandler] 检测到来电，暂停播放');
              player.pause();
            }
          } else {
            // 通话结束
            if (_wasPlayingBeforeInterruption) {
              debugPrint('📞 [CallStateHandler] 通话结束，恢复播放');
              player.play();
              _wasPlayingBeforeInterruption = false;
            }
          }
        });
      }).catchError((e) {
        debugPrint('⚠️ [CallStateHandler] 初始化失败: $e');
      });
    } catch (e) {
      debugPrint('❌ [CallStateHandler] 创建失败: $e');
    }
  }

  /// 智能预加载相邻清晰度（参考 YouTube/B站）
  ///
  /// 在播放稳定后，后台预加载上下相邻的清晰度，实现无缝切换
  void _startPreloadAdjacentQualities() {
    _preloadTimer?.cancel();

    // 延迟 5 秒后开始预加载（避免影响当前播放）
    _preloadTimer = Timer(const Duration(seconds: 5), () async {
      if (currentQuality.value == null || _currentResourceId == null) return;

      final currentIndex = availableQualities.value.indexOf(currentQuality.value!);
      if (currentIndex == -1) return;

      final toPreload = <String>[];

      // 预加载下一档清晰度（降低）- 优先级更高
      if (currentIndex < availableQualities.value.length - 1) {
        toPreload.add(availableQualities.value[currentIndex + 1]);
      }

      // 预加载上一档清晰度（提高）
      if (currentIndex > 0) {
        toPreload.add(availableQualities.value[currentIndex - 1]);
      }

      // 异步预加载
      for (final quality in toPreload) {
        if (_qualityCache.containsKey(quality)) {
          debugPrint('✅ 清晰度已缓存: ${HlsService.getQualityLabel(quality)}');
          continue;
        }

        try {
          final mediaSource = await _hlsService.getMediaSource(
            _currentResourceId!,
            quality,
          );
          // 直接缓存 MediaSource 对象，包含类型和内容
          _qualityCache[quality] = mediaSource;
          if (mediaSource.isDirectUrl) {
            debugPrint('✅ 预加载完成 (直接URL): ${HlsService.getQualityLabel(quality)}');
          } else {
            debugPrint('✅ 预加载完成 (HLS): ${HlsService.getQualityLabel(quality)} (${(mediaSource.content.length / 1024).toStringAsFixed(1)} KB)');
          }
        } catch (e) {
          debugPrint('⚠️ 预加载失败: ${HlsService.getQualityLabel(quality)} - $e');
        }
      }
    });
  }

  /// 处理播放卡顿（智能恢复方案）
  /// [fallbackPosition] 可选的备用位置，当 player.state.position 不可靠时使用
  Future<void> _handleStalledPlayback({Duration? fallbackPosition}) async {
    if (_isRecovering || currentQuality.value == null) return;

    _isRecovering = true;
    _stalledCount++;

    try {
      debugPrint('🔧 卡顿恢复尝试 $_stalledCount/2');

      // 获取可靠的播放位置：优先使用当前位置，如果看起来不可靠则使用备用位置
      final currentPos = player.state.position;
      final reliablePosition = (currentPos.inSeconds > 0 || fallbackPosition == null)
          ? currentPos
          : fallbackPosition;
      debugPrint('📍 恢复位置: ${reliablePosition.inSeconds}s (当前=${currentPos.inSeconds}s, 备用=${fallbackPosition?.inSeconds}s)');

      if (_stalledCount == 1) {
        // 第一次卡顿：尝试轻量级恢复 - 跳过坏的 TS 分片
        debugPrint('💡 方案1: 尝试跳过损坏分片 (+2秒)');
        final newPos = reliablePosition + const Duration(seconds: 2);

        // 直接 seek，依靠 MPV 的底层重连机制
        await player.seek(newPos);

        // 等待 3 秒看是否恢复
        await Future.delayed(const Duration(seconds: 3));

        if (!player.state.buffering) {
          debugPrint('✅ 轻量级恢复成功');
          _isRecovering = false;
          _stalledCount = 0;
          return;
        }
      }

      // 第二次卡顿或第一次失败：重新加载 m3u8
      // 直接使用原始位置，不做回退
      final safePosition = reliablePosition;

      debugPrint('💡 方案2: 重新加载视频，恢复到 ${safePosition.inSeconds}s');
      final wasPlaying = player.state.playing;

      // 获取视频资源
      final mediaSource = await _hlsService.getMediaSource(
        _currentResourceId!,
        currentQuality.value!,
      );
      final media = await _createMediaFromResource(mediaSource, debugTag: 'StalledReload');

      // 重新打开
      await player.open(media, play: false);
      await _waitForDuration(timeout: const Duration(seconds: 5));
      await player.seek(safePosition);

      if (wasPlaying) {
        await player.play();
      }

      debugPrint('✅ m3u8 重载恢复成功');
      _stalledCount = 0;
    } catch (e) {
      debugPrint('❌ 卡顿恢复失败: $e');
      errorMessage.value = '播放出现问题，请稍后重试';
    } finally {
      _isRecovering = false;
    }
  }

  /// 配置播放器属性 (行业级 HLS 优化 + 雪花屏修复)
  Future<void> _configurePlayerProperties() async {
    if (kIsWeb) return;
    try {
      final nativePlayer = player.platform as NativePlayer?;
      if (nativePlayer == null) return;

      // ========== 1. HLS 核心配置（参考 YouTube/B站）==========

      // HTTP 连接保持
      await nativePlayer.setProperty('http-header-fields', 'Connection: keep-alive');

      // TS 分片超时和重试配置 + 多连接加速
      // multiple_requests=1 启用HTTP流水线（多个请求复用连接）
      // reconnect=1 启用重连
      // reconnect_streamed=1 流媒体重连
      // reconnect_delay_max=2 最大重连延迟2秒（更快重连）
      await nativePlayer.setProperty('stream-lavf-o',
        'timeout=10000000,reconnect=1,reconnect_streamed=1,reconnect_delay_max=2,multiple_requests=1'
      );

      // ========== 2. 缓冲策略（激进预载模式）==========

      // 启用缓存
      await nativePlayer.setProperty('cache', 'yes');

      // 【关键】预缓冲时长：120秒
      await nativePlayer.setProperty('cache-secs', '120');

      // 【关键】demuxer前向读取：120秒（强制demuxer预读120秒数据）
      // 这是让MPV积极预载的核心参数
      await nativePlayer.setProperty('demuxer-readahead-secs', '120');

      // 最大缓冲大小：500MB（扩大以支持高码率120秒缓冲）
      // 1080p60 约 8Mbps = 1MB/s，120秒 = 120MB，留余量
      await nativePlayer.setProperty('demuxer-max-bytes', '500M');

      // 【关键】后向缓冲：50MB（允许快退时不重新加载）
      await nativePlayer.setProperty('demuxer-max-back-bytes', '50M');

      // 允许缓存 seek（在已缓冲范围内快进不重新请求）
      await nativePlayer.setProperty('demuxer-seekable-cache', 'yes');

      // ========== 3. 激进预缓冲模式（平衡秒开与预载）==========

      // 【关键】允许暂停等待缓冲（这样MPV才会积极预载）
      await nativePlayer.setProperty('cache-pause', 'yes');

      // 【秒开优化】初始不等待缓冲，立即开始播放
      // 结合 demuxer-readahead-secs=120，播放的同时会积极预载后续内容
      await nativePlayer.setProperty('cache-pause-initial', 'no');

      // 缓冲恢复阈值：当缓冲低于3秒时才暂停等待（减少卡顿）
      await nativePlayer.setProperty('cache-pause-wait', '3');

      // ========== 4. 网络优化 ==========

      // 增加网络缓冲区大小（加快下载速度）
      await nativePlayer.setProperty('network-timeout', '10');

      // ========== 5. 精确跳转（解决 HLS seek 跳到分片边界的问题）==========

      // 强制开启绝对精确跳转（精确到帧）
      await nativePlayer.setProperty('hr-seek', 'absolute');

      // 【关键】禁用快速 seek，确保精确定位到目标时间点
      // 默认 yes 会跳到最近的关键帧，导致进度偏移一个分片
      await nativePlayer.setProperty('hr-seek-framedrop', 'no');

      // 【关键】demuxer 层面的精确 seek
      await nativePlayer.setProperty('demuxer-seek-fast', 'no');

      // ========== 6. 解码模式配置 ==========

      // 根据设置选择解码模式
      // 'no' = 软解码（兼容性好，CPU解码）
      // 'auto-copy' = 硬解码（GPU加速，性能好但可能有兼容性问题）
      await nativePlayer.setProperty('hwdec', _currentDecodeMode);
      debugPrint('🎬 解码模式: ${_currentDecodeMode == "no" ? "软解码" : "硬解码"}');

      // 关闭直接渲染（软解码时可提高稳定性）
      await nativePlayer.setProperty('vd-lavc-dr', 'no');

      // ========== 7. 帧缓冲优化（解决 ImageReader buffer 不足）==========

      // 允许丢帧以保持音视频同步（减少缓冲区压力）
      await nativePlayer.setProperty('framedrop', 'vo');

      // 视频输出队列大小（增加缓冲帧数）
      await nativePlayer.setProperty('vo-queue-max-frames', '5');

      // 减少视频输出延迟
      await nativePlayer.setProperty('video-latency-hacks', 'yes');

      debugPrint('✅ MPV 底层配置完成：激进预载模式 (120秒前向读取), 解码=${_currentDecodeMode == "no" ? "软" : "硬"}');
    } catch (e) {
      debugPrint('⚠️ 配置失败: $e');
    }
  }

  /// 清理 MPV 底层缓存
  ///
  /// 触发条件：
  /// 1. 播放器重新实例化（initialize）
  /// 2. 切换清晰度（changeQuality）
  ///
  /// 不清理条件：
  /// - 正常播放过程中（保持缓存以流畅播放）
  Future<void> _clearPlayerCache() async {
    if (kIsWeb) return;
    try {
      final nativePlayer = player.platform as NativePlayer?;
      if (nativePlayer == null) return;

      // 方式1: 清理 demuxer 缓存
      await nativePlayer.setProperty('demuxer-cache-clear', 'yes');

      debugPrint('🗑️ MPV 底层缓存已清理');
    } catch (e) {
      debugPrint('⚠️ 清理缓存失败: $e');
    }
  }
  // ============ 核心：防抖切换清晰度 ============

  Future<void> changeQuality(String quality) async {
    if (currentQuality.value == quality) return;

    // 1. 记录原始播放状态
    _resumeAfterQualitySwitch ??= player.state.playing;

    // 2. 立即暂停
    await player.pause();

    // 3. 锁定锚点位置
    if (_anchorPosition == null) {
      final currentPos = player.state.position;
      debugPrint('⚓ [Quality] 锁定位置检测: player.position=${currentPos.inSeconds}s, _lastKnownGoodPosition=${_lastKnownGoodPosition.inSeconds}s');

      if (currentPos.inSeconds > 0) {
        _anchorPosition = currentPos;
        debugPrint('⚓ [Quality] 使用播放器当前位置: ${_anchorPosition!.inSeconds}s');
      } else if (_lastKnownGoodPosition.inSeconds > 0) {
        // 使用备份位置（来自用户 seek 或播放进度）
        _anchorPosition = _lastKnownGoodPosition;
        debugPrint('⚓ [Quality] 播放器位置归零，使用备份位置: ${_anchorPosition!.inSeconds}s');
      } else {
        // 【修复】如果真的没有任何位置信息，打印警告
        _anchorPosition = Duration.zero;
        debugPrint('⚠️ [Quality] 警告: 无法获取有效位置，将从头开始播放');
      }
    }

    // 4. 取消上一次未执行的任务
    _debounceTimer?.cancel();

    // 5. 状态标记
    _switchEpoch++;
    final int myEpoch = _switchEpoch;
    isSwitchingQuality.value = true;
    _isFreezingPosition = true;

    // 6. 启动防抖
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      if (myEpoch != _switchEpoch) return;

      // 【核心修复】智能兜底目标位置 (移除 >5s 的限制)
      // 只要有进度，哪怕只有1秒，也要尝试恢复，而不是重置为0
      var targetPos = _anchorPosition;
      if (targetPos == null || targetPos == Duration.zero) {
        if (player.state.position.inSeconds > 0) {
          targetPos = player.state.position;
        } else if (_lastKnownGoodPosition.inSeconds > 0) {
          targetPos = _lastKnownGoodPosition;
        } else {
          targetPos = Duration.zero;
        }
      }

      try {
        await _performSwitch(quality, targetPos);
      } catch (e) {
        _logger.logError(message: '切换失败', error: e, context: {'quality': quality});
        // 恢复状态
        _isFreezingPosition = false;
        isSwitchingQuality.value = false;
        _anchorPosition = null;
        _resumeAfterQualitySwitch = null;
      }
    });
  }

  /// 执行真正的切换逻辑（统一版：使用 5 步原子操作）
  ///
  /// 【5步原子操作】与 _loadVideo 保持一致：
  /// 1. 设置原生 Start 属性
  /// 2. 静态打开 (play: false)
  /// 3. 等待元数据
  /// 4. 阻塞式校验栅栏
  /// 5. 安全播放
  Future<void> _performSwitch(String quality, Duration seekPos) async {
    // 【核心策略】预加载位置回退 10 秒确保分片完整，但最终 seek 到精确位置播放
    final Duration targetPosition = seekPos;  // 用户期望的精确位置
    Duration preloadPosition = seekPos;       // 预加载位置

    // 预加载位置回退 10 秒
    if (seekPos.inSeconds > 10) {
      preloadPosition = Duration(seconds: seekPos.inSeconds - 10);
    } else {
      preloadPosition = Duration.zero;
    }

    final bool shouldResume = _resumeAfterQualitySwitch ?? true;

    debugPrint('🔄 [SwitchQuality] 切换开始: $quality, 预加载=${preloadPosition.inSeconds}s, 目标=${targetPosition.inSeconds}s');

    try {
      await _clearPlayerCache();

      // ========== 步骤 1: 设置原生 Start 属性（使用预加载位置）==========
      NativePlayer? nativePlayer;
      if (!kIsWeb) {
        try {
          nativePlayer = player.platform as NativePlayer?;
          if (nativePlayer != null) {
            // 【关键】使用预加载位置，让 MPV 从更早的分片开始加载
            await nativePlayer.setProperty('start', '${preloadPosition.inSeconds}.0');
            debugPrint('🚀 [SwitchQuality] 设置 MPV start=${preloadPosition.inSeconds}.0 (预加载)');
          }
        } catch (e) {
          debugPrint('⚠️ [SwitchQuality] 设置 start 属性失败: $e');
        }
      }

      // ========== 步骤 2: 静态打开 (强制 play: false) ==========
      final mediaSource = await _hlsService.getMediaSource(_currentResourceId!, quality);
      final media = await _createMediaFromResource(mediaSource, debugTag: 'LoadVideo');

      // 【关键】绝对不能让底层自动起播
      await player.open(media, play: false);
      await player.pause(); // 双重保险

      // ========== 步骤 3: 等待元数据 (duration > 0) ==========
      await _waitForDuration(timeout: const Duration(seconds: 3));
      // 额外缓冲
      await Future.delayed(const Duration(milliseconds: 100));

      // ========== 步骤 4: Seek 到精确目标位置 ==========
      // 【关键】无论预加载位置是否生效，都要 seek 到用户期望的精确位置
      final success = await _blockingVerifyAndSeek(targetPosition);

      // 【关键修复】立即设置保护期，防止播放开始后进度异常跳变
      _confirmedSeekPosition = targetPosition;
      _seekProtectionEndTime = DateTime.now().add(const Duration(seconds: 10));
      debugPrint('🛡️ [SwitchQuality] 已启动进度保护期: 目标=${targetPosition.inSeconds}s');

      if (!success) {
        debugPrint('⚠️ [SwitchQuality] 位置校验最终失败，但保护期已启动');
      }

      // 清除 start 属性
      if (nativePlayer != null) {
        try {
          await nativePlayer.setProperty('start', 'none');
        } catch (_) {}
      }

      // ========== 步骤 5: 更新状态并安全播放 ==========
      currentQuality.value = quality;
      await _savePreferredQuality(quality);

      _isFreezingPosition = false;
      isSwitchingQuality.value = false;
      _anchorPosition = null;
      _resumeAfterQualitySwitch = null;

      // 根据切换前的状态决定是否播放
      if (shouldResume) {
        await player.play();
        debugPrint('▶️ [SwitchQuality] 位置确认，恢复播放');
      } else {
        debugPrint('⏸️ [SwitchQuality] 位置确认，保持暂停');
      }

      _startPreloadAdjacentQualities();
      onQualityChanged?.call(quality);

    } catch (e) {
      debugPrint('❌ [SwitchQuality] 异常: $e');
      _isFreezingPosition = false;
      isSwitchingQuality.value = false;
      _anchorPosition = null;
      _resumeAfterQualitySwitch = null;
      if (!kIsWeb) {
        try {
          (player.platform as NativePlayer?)?.setProperty('start', 'none');
        } catch (_) {}
      }
      rethrow;
    }
  }

  // ============ 核心加载逻辑 (V_Refactored_Unified) ============
  //
  // 【5步原子操作】:
  // 1. 设置原生 Start 属性 (nativePlayer.setProperty('start', 'TARGET.0'))
  // 2. 静态打开 (player.open(media, play: false))
  // 3. 等待元数据 (duration > 0)
  // 4. 阻塞式校验栅栏 (验证 position 是否正确，不正确则 seek + 死等)
  // 5. 安全播放 (确认位置后才 play)

  Future<void> _loadVideo(String quality, {bool isInitialLoad = false, double? initialPosition}) async {
    if (_isDisposed) return;

    try {
      _hasTriggeredCompletion = false;

      // ========== 步骤 0: 计算加载位置和播放位置 ==========
      // 【核心策略】预加载位置回退 10 秒确保分片完整，但最终 seek 到精确位置播放
      Duration preloadPosition = Duration.zero;  // MPV start 属性使用（提前加载）
      Duration targetPosition = Duration.zero;   // 最终 seek 目标（用户期望的精确位置）
      final bool needSeek = initialPosition != null && initialPosition > 0.0;

      if (needSeek) {
        // 用户期望的精确位置
        targetPosition = Duration(seconds: initialPosition.toInt());

        // 预加载位置：回退 10 秒，确保 HLS 分片完整加载
        // 这样 MPV 会从更早的分片开始下载，避免关键帧丢失
        if (initialPosition > 10.0) {
          preloadPosition = Duration(seconds: (initialPosition - 10.0).toInt());
        } else {
          preloadPosition = Duration.zero;
        }

        _isSeekingInitialPosition = true;
        debugPrint('🎯 [LoadVideo] 进场恢复: 预加载=${preloadPosition.inSeconds}s, 目标=${targetPosition.inSeconds}s');
      }

      // ========== 步骤 1: 设置原生 Start 属性（使用预加载位置）==========
      NativePlayer? nativePlayer;
      if (!kIsWeb) {
        try {
          nativePlayer = player.platform as NativePlayer?;
          if (nativePlayer != null) {
            if (needSeek) {
              // 【关键】使用预加载位置，让 MPV 从更早的分片开始加载
              await nativePlayer.setProperty('start', '${preloadPosition.inSeconds}.0');
              debugPrint('🚀 [LoadVideo] 设置 MPV start=${preloadPosition.inSeconds}.0 (预加载)');
            } else {
              await nativePlayer.setProperty('start', 'none');
            }
          }
        } catch (e) {
          debugPrint('⚠️ [LoadVideo] 设置 start 属性失败: $e');
        }
      }

      // ========== 步骤 2: 静态打开 (强制 play: false) ==========
      // 优先使用缓存的资源
      MediaSource mediaSource;
      if (_qualityCache.containsKey(quality)) {
        mediaSource = _qualityCache[quality]!;
        debugPrint('📦 [PerformSwitch] 使用缓存的视频资源');
      } else {
        mediaSource = await _hlsService.getMediaSource(_currentResourceId!, quality);
        // 存入缓存以便下次使用
        _qualityCache[quality] = mediaSource;
      }
      final media = await _createMediaFromResource(mediaSource, debugTag: 'PerformSwitch');

      // 【关键】绝对不能让底层自动起播，防止 0 秒画面闪现
      await player.open(media, play: false);
      await player.pause(); // 双重保险

      if (_isDisposed) return;

      // ========== 步骤 3: 等待元数据 (duration > 0) ==========
      await _waitForDuration(timeout: const Duration(seconds: 4));
      // 额外缓冲，给底层刷新 position 的时间
      await Future.delayed(const Duration(milliseconds: 100));

      if (_isDisposed) return;

      // ========== 步骤 4: Seek 到精确目标位置 ==========
      if (needSeek) {
        // 【关键】无论预加载位置是否生效，都要 seek 到用户期望的精确位置
        final success = await _blockingVerifyAndSeek(targetPosition);

        // 【关键修复】立即设置保护期，防止播放开始后进度异常跳变
        // 不要等到 _verifySeekInBackground 的 800ms 延迟后才设置
        _isSeekingInitialPosition = false;
        _confirmedSeekPosition = targetPosition;
        _seekProtectionEndTime = DateTime.now().add(const Duration(seconds: 10));
        debugPrint('🛡️ [LoadVideo] 已启动进度保护期: 目标=${targetPosition.inSeconds}s');

        if (!success) {
          debugPrint('⚠️ [LoadVideo] 位置校验最终失败，但保护期已启动');
        }

        // 清除 start 属性
        if (nativePlayer != null) {
          try {
            await nativePlayer.setProperty('start', 'none');
          } catch (_) {}
        }

        // 启动后台验证（作为二次保险）
        _verifySeekInBackground(targetPosition);
      }

      // ========== 步骤 5: 安全播放 ==========
      // 只有非切换清晰度模式下才自动播放
      if (!isSwitchingQuality.value) {
        await player.play();
        debugPrint('▶️ [LoadVideo] 位置确认，开始播放');
      }

      if (isInitialLoad) _startPreloadAdjacentQualities();

    } catch (e) {
      debugPrint('❌ [LoadVideo] 加载失败: $e');
      _isSeekingInitialPosition = false;
      rethrow;
    }
  }

  /// 从 MediaSource 创建 Media 对象
  /// 支持直接视频URL和HLS m3u8内容两种格式
  Future<Media> _createMediaFromResource(MediaSource resource, {String? debugTag}) async {
    final tag = debugTag ?? 'CreateMedia';
    if (resource.isDirectUrl) {
      debugPrint('📹 [$tag] 使用直接视频URL');
      return Media(resource.content);
    } else {
      debugPrint('📹 [$tag] 使用HLS流');
      final m3u8Bytes = Uint8List.fromList(utf8.encode(resource.content));
      return await Media.memory(m3u8Bytes);
    }
  }

  /// 等待 duration > 0
  Future<void> _waitForDuration({Duration timeout = const Duration(seconds: 4)}) async {
    if (player.state.duration.inSeconds > 0) return;

    final completer = Completer<void>();
    StreamSubscription? sub;

    sub = player.stream.duration.listen((duration) {
      if (duration.inSeconds > 0 && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(timeout, onTimeout: () {
        debugPrint('⚠️ [WaitDuration] 等待超时，继续执行');
      });
    } finally {
      await sub.cancel();
    }
  }

  /// 【阻塞式校验栅栏】验证位置是否正确，不正确则 seek + 死等
  /// 返回 true 表示位置已正确，false 表示最终失败
  Future<bool> _blockingVerifyAndSeek(Duration targetPosition) async {
    // 先检查当前位置
    var currentPos = player.state.position;
    var diff = (currentPos.inSeconds - targetPosition.inSeconds).abs();

    if (diff <= 3) {
      debugPrint('✅ [Verify] 原生 start 生效，位置正确: ${currentPos.inSeconds}s');
      return true;
    }

    // 原生 start 未生效，执行阻塞式 Seek
    debugPrint('⚠️ [Verify] 原生 start 未生效 (当前=${currentPos.inSeconds}s)，执行阻塞 Seek');
    await player.seek(targetPosition);

    // 死循环等待，最多 3 秒 (30 * 100ms)
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 100));

      if (_isDisposed) return false;

      currentPos = player.state.position;
      diff = (currentPos.inSeconds - targetPosition.inSeconds).abs();

      if (diff <= 3) {
        debugPrint('✅ [Verify] 阻塞 Seek 成功: ${currentPos.inSeconds}s (耗时 ${(i + 1) * 100}ms)');
        return true;
      }

      // 如果等了 1.5 秒还没动，补发一次指令
      if (i == 15) {
        debugPrint('🔄 [Verify] 响应迟缓，补发 Seek 指令');
        await player.seek(targetPosition);
      }
    }

    // 最后的挣扎
    debugPrint('❌ [Verify] 阻塞 Seek 超时，最后一次尝试');
    await player.seek(targetPosition);
    return false;
  }

  /// 【行业标准】后台验证 seek 是否成功，失败则重试
  void _verifySeekInBackground(Duration targetPosition) {
    // 延迟 800ms 检查，给播放器一点缓冲时间
    Future.delayed(const Duration(milliseconds: 800), () async {
      if (_isDisposed) return;
      // 注意：不再检查 _isSeekingInitialPosition，因为主流程已经设为 false

      final currentPos = player.state.position;
      final diff = (currentPos.inSeconds - targetPosition.inSeconds).abs();

      debugPrint('🔍 [Verify] 检查进度: 当前=${currentPos.inSeconds}s, 目标=${targetPosition.inSeconds}s');

      if (diff <= 3) {
        // 成功，保护期已在主流程设置，这里只打印日志
        debugPrint('✅ [Verify] 后台验证: 进度正确 ${currentPos.inSeconds}s');
      } else {
        // 失败或尚未完成
        debugPrint('⚠️ [Verify] 后台验证: 进度偏差 ${diff}s，主动修复');
        // 刷新保护期并修复
        _confirmedSeekPosition = targetPosition;
        _seekProtectionEndTime = DateTime.now().add(const Duration(seconds: 10));
        player.seek(targetPosition);
      }
    });
  }

  // ============ 播放控制 ============
  void toggleLoopMode() {
    final newMode = loopMode.value.toggle();
    _saveLoopMode(newMode);
  }

  Future<void> play() async => await player.play();
  Future<void> pause() async => await player.pause();

  /// 快进/快退方法 - 带分片恢复保障 + 智能缓存检测
  ///
  /// 确保无论什么情况下,快进都不会丢失分片跳过
  /// 如果遇到加载失败,会尝试重新加载并恢复到目标位置
  /// 【优化】在已缓存范围内快进时，不显示加载动画
  Future<void> seek(Duration position) async {
    final targetPosition = position;
    final wasPlaying = player.state.playing;
    final currentPosition = player.state.position;

    // 【关键修复】立即记录用户的目标位置，防止切换清晰度时丢失
    // 这是最可靠的位置来源，因为它直接来自用户的操作意图
    if (targetPosition.inSeconds > 0) {
      _lastKnownGoodPosition = targetPosition;
      debugPrint('📍 [Seek] 记录目标位置: ${targetPosition.inSeconds}s');
    }

    // 【关键修复】用户主动 seek 时，清除之前的保护状态
    // 否则 ProgressGuard 会把用户的快进"修复"回原位置
    _seekProtectionEndTime = null;
    _confirmedSeekPosition = null;
    _lastSeekRecoveryTime = null;

    // 【关键】先设置保护标记，防止seek过程中的buffering事件触发加载动画
    // 这必须在任何异步操作之前完成
    _isSeekingWithinCache = true;
    _seekDebounceTimer?.cancel();

    try {
      // 【智能缓存检测】检查目标位置是否在MPV的缓冲范围内
      final isInBufferedRange = await _isPositionInBufferedRange(targetPosition);

      if (isInBufferedRange) {
        debugPrint('📍 目标位置在缓冲范围内，跳过加载动画');

        // 设置较短的超时保护（缓冲范围内应该很快完成）
        _seekDebounceTimer = Timer(const Duration(milliseconds: 500), () {
          _isSeekingWithinCache = false;
        });

        // 直接seek，不做额外检查
        await player.seek(targetPosition);
        return;
      }

      // 不在缓冲范围内
      final seekDistance = (targetPosition.inSeconds - currentPosition.inSeconds).abs();
      debugPrint('📍 快进到缓冲范围外（距离$seekDistance秒）');

      // 取消保护，允许显示加载动画
      _isSeekingWithinCache = false;

      // 1. 执行 seek 操作
      await player.seek(targetPosition);

      // 2. 等待一小段时间让播放器加载分片
      await Future.delayed(const Duration(milliseconds: 300));

      // 3. 检查是否成功到达目标位置
      final currentPos = player.state.position;
      final positionDiff = (currentPos.inSeconds - targetPosition.inSeconds).abs();

      // 如果位置偏差超过 3 秒,可能是分片加载失败
      if (positionDiff > 3) {
        debugPrint('⚠️ 快进位置偏差 ${positionDiff}s，重新加载');
        await _recoverSeekPosition(targetPosition, wasPlaying);
      }

    } catch (e) {
      debugPrint('❌ 快进失败: $e');
      _isSeekingWithinCache = false;
      await _recoverSeekPosition(targetPosition, wasPlaying);
    }
  }

  /// 检查目标位置是否在MPV的已缓冲范围内
  Future<bool> _isPositionInBufferedRange(Duration targetPosition) async {
    if (kIsWeb) return false;

    try {
      final nativePlayer = player.platform as NativePlayer?;
      if (nativePlayer == null) return false;

      final currentPos = player.state.position;

      // 方法1: 获取demuxer缓冲的前向时长
      final cacheTime = await nativePlayer.getProperty('demuxer-cache-time');

      // 方法2: 获取缓冲的字节范围（更准确）
      final cacheState = await nativePlayer.getProperty('demuxer-cache-state');

      double forwardCachedSeconds = 0;

      // 解析前向缓冲时长
      if (cacheTime.isNotEmpty) {
        forwardCachedSeconds = double.tryParse(cacheTime) ?? 0;
      }

      // 尝试从cache-state获取更详细的信息
      if (cacheState.isNotEmpty) {
        // cache-state 格式类似: "seekable-start=0.000000 seekable-end=120.000000 ..."
        // 我们主要关注 seekable-end
        final seekableEndMatch = RegExp(r'seekable-end=(\d+\.?\d*)').firstMatch(cacheState);
        if (seekableEndMatch != null) {
          final seekableEnd = double.tryParse(seekableEndMatch.group(1) ?? '0') ?? 0;
          if (seekableEnd > 0) {
            // seekable-end 是绝对时间点
            final targetSeconds = targetPosition.inMilliseconds / 1000.0;
            if (targetSeconds <= seekableEnd) {
              debugPrint('✅ 缓冲检测(seekable): 目标=${targetPosition.inSeconds}s, seekable-end=${seekableEnd.toStringAsFixed(1)}s');
              return true;
            }
          }
        }
      }

      // 使用前向缓冲时长计算
      if (forwardCachedSeconds > 0) {
        final bufferedEnd = currentPos + Duration(seconds: forwardCachedSeconds.toInt());

        // 前向：目标在 [当前位置, 缓冲结束] 范围内
        final isForwardInCache = targetPosition <= bufferedEnd && targetPosition >= Duration.zero;

        // 后向：允许往回拖动（MPV有后向缓冲，默认约50MB）
        final isBackwardInCache = targetPosition < currentPos &&
            targetPosition >= Duration.zero;

        if (isForwardInCache || isBackwardInCache) {
          debugPrint('✅ 缓冲检测: 目标=${targetPosition.inSeconds}s, 当前=${currentPos.inSeconds}s, 前向缓冲=${forwardCachedSeconds.toStringAsFixed(1)}s');
          return true;
        }
      }

      debugPrint('⚠️ 缓冲检测: 目标=${targetPosition.inSeconds}s 不在缓冲范围内 (当前=${currentPos.inSeconds}s, 前向=${forwardCachedSeconds.toStringAsFixed(1)}s)');
    } catch (e) {
      debugPrint('⚠️ 获取缓冲范围失败: $e');
    }

    return false;
  }

  /// 快进位置恢复机制
  /// 当快进遇到分片加载问题时,重新加载视频并恢复到目标位置
  Future<void> _recoverSeekPosition(Duration targetPosition, bool wasPlaying) async {
    if (_currentResourceId == null || currentQuality.value == null) {
      return;
    }

    try {
      // 直接使用目标位置，不做回退
      final safePosition = targetPosition;

      // 1. 暂停播放
      await player.pause();

      // 2. 重新加载视频资源（优先使用缓存）
      MediaSource mediaSource;
      final quality = currentQuality.value!;
      if (_qualityCache.containsKey(quality)) {
        mediaSource = _qualityCache[quality]!;
        debugPrint('📦 [RecoverSeek] 使用缓存的视频资源');
      } else {
        mediaSource = await _hlsService.getMediaSource(_currentResourceId!, quality);
        _qualityCache[quality] = mediaSource;
      }
      final media = await _createMediaFromResource(mediaSource, debugTag: 'RecoverSeek');

      // 3. 重新打开视频 (不自动播放)
      await player.open(media, play: false);
      await _waitForDuration(timeout: const Duration(seconds: 5));

      // 4. 跳转到目标位置
      await player.seek(safePosition);
      await Future.delayed(const Duration(milliseconds: 300));

      // 5. 恢复播放状态
      if (wasPlaying) {
        await player.play();
      }

    } catch (e) {
      debugPrint('❌ 快进位置恢复失败: $e');
      errorMessage.value = '快进失败，请重试';
    }
  }

  Future<void> setRate(double rate) async => await player.setRate(rate);

  // ============ 偏好设置与辅助方法 ============

  /// 获取当前解码模式设置（静态方法，供设置页面使用）
  /// 返回值：'no' = 软解码，'auto-copy' = 硬解码
  static Future<String> getDecodeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_decodeModeKey) ?? 'no'; // 默认软解码
  }

  /// 设置解码模式（静态方法，供设置页面使用）
  /// [mode] 'no' = 软解码，'auto-copy' = 硬解码
  static Future<void> setDecodeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_decodeModeKey, mode);
    debugPrint('🎬 解码模式已保存: ${mode == "no" ? "软解码" : "硬解码"}');
  }

  /// 获取解码模式显示名称
  static String getDecodeModeDisplayName(String mode) {
    return mode == 'no' ? '软解码' : '硬解码';
  }

  Future<void> _saveLoopMode(LoopMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loopModeKey, mode.toSavedString());
    loopMode.value = mode;
  }

  Future<String> _getPreferredQuality(List<String> availableQualitiesList) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferredDisplayName = prefs.getString(_preferredQualityKey);

      if (preferredDisplayName != null && preferredDisplayName.isNotEmpty) {
        for (final quality in availableQualitiesList) {
          if (getQualityDisplayName(quality) == preferredDisplayName) {
            return quality;
          }
        }
        final fallbackQuality = _findFallbackQuality(preferredDisplayName, availableQualitiesList);
        if (fallbackQuality != null) {
          return fallbackQuality;
        }
      }
      return HlsService.getDefaultQuality(availableQualitiesList);
    } catch (e) {
      return HlsService.getDefaultQuality(availableQualitiesList);
    }
  }

  String? _findFallbackQuality(String preferredDisplayName, List<String> availableQualitiesList) {
    final fallbackOrder = _getFallbackOrder(preferredDisplayName);
    for (final fallbackName in fallbackOrder) {
      for (final quality in availableQualitiesList) {
        if (getQualityDisplayName(quality) == fallbackName) {
          return quality;
        }
      }
    }
    return null;
  }

  List<String> _getFallbackOrder(String preferredDisplayName) {
    const allQualities = ['1080p60', '1080p', '720p60', '720p', '480p', '360p'];
    final startIndex = allQualities.indexOf(preferredDisplayName);
    if (startIndex == -1) return List.from(allQualities);
    return allQualities.sublist(startIndex + 1);
  }

  Future<void> _savePreferredQuality(String quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final displayName = getQualityDisplayName(quality);
      await prefs.setString(_preferredQualityKey, displayName);
    } catch (e) {
      debugPrint('⚠️ 保存清晰度偏好失败: $e');
    }
  }

  List<String> _sortQualitiesDescending(List<String> qualities) {
    final sorted = List<String>.from(qualities);
    sorted.sort((a, b) {
      final resA = _parseResolution(a);
      final resB = _parseResolution(b);
      if (resA != resB) return resB.compareTo(resA);
      final fpsA = _parseFrameRate(a);
      final fpsB = _parseFrameRate(b);
      return fpsB.compareTo(fpsA);
    });
    return sorted;
  }

  int _parseResolution(String quality) {
    try {
      final parts = quality.split('_');
      if (parts.isEmpty) return 0;
      final resolution = parts[0];
      final dims = resolution.split('x');
      if (dims.length != 2) return 0;
      final width = int.tryParse(dims[0]) ?? 0;
      final height = int.tryParse(dims[1]) ?? 0;
      return width * height;
    } catch (e) {
      return 0;
    }
  }

  int _parseFrameRate(String quality) {
    try {
      final parts = quality.split('_');
      if (parts.length >= 3) {
        return int.tryParse(parts[2]) ?? 30;
      }
      return 30;
    } catch (e) {
      return 30;
    }
  }

  String getQualityDisplayName(String quality) {
    const qualityMap = {
      '640x360_1000k_30': '360p',
      '854x480_1500k_30': '480p',
      '1280x720_3000k_30': '720p',
      '1920x1080_6000k_30': '1080p',
      '1920x1080_8000k_60': '1080p60',
    };

    if (qualityMap.containsKey(quality)) {
      return qualityMap[quality]!;
    }

    try {
      final parts = quality.split('_');
      if (parts.isEmpty) return quality;
      final resolution = parts[0];
      final fps = parts.length >= 3 ? int.tryParse(parts[2]) ?? 30 : 30;

      if (resolution.contains('x')) {
        final resolutionParts = resolution.split('x');
        if (resolutionParts.length == 2) {
          final height = int.tryParse(resolutionParts[1]);
          if (height != null) {
            final fpsSuffix = fps > 30 ? fps.toString() : '';
            if (height <= 360) {
              return fpsSuffix.isNotEmpty ? '360p$fpsSuffix' : '360p';
            } else if (height <= 480) {
              return fpsSuffix.isNotEmpty ? '480p$fpsSuffix' : '480p';
            } else if (height <= 720) {
              return fpsSuffix.isNotEmpty ? '720p$fpsSuffix' : '720p';
            } else if (height <= 1080) {
              return fpsSuffix.isNotEmpty ? '1080p$fpsSuffix' : '1080p';
            } else if (height <= 1440) {
              return fpsSuffix.isNotEmpty ? '2K$fpsSuffix' : '2K';
            } else {
              return fpsSuffix.isNotEmpty ? '4K$fpsSuffix' : '4K';
            }
          }
        }
      }
    } catch (e) {
      debugPrint('解析清晰度名称失败: $e');
    }
    return quality;
  }

  void handleAppLifecycleState(bool isPaused) {
    if (isPaused) {
      // 进入后台
      _wasPlayingBeforeBackground = player.state.playing;
      _positionBeforeBackground = player.state.position;
      debugPrint('📱 进入后台: playing=$_wasPlayingBeforeBackground, position=${_positionBeforeBackground?.inSeconds}s, backgroundPlay=${backgroundPlayEnabled.value}');

      if (backgroundPlayEnabled.value && _wasPlayingBeforeBackground) {
        // 后台播放模式：启用AudioService，保持播放
        // 【关键修复】使用同步方式确保 AudioService 在进入后台前就初始化
        _activateBackgroundPlayback();
      } else {
        // 非后台播放模式：暂停播放
        if (_wasPlayingBeforeBackground) player.pause();
      }
    } else {
      // 返回前台
      // 【关键修复】获取播放器的实际当前位置，而不是之前保存的位置
      final actualPosition = player.state.position;
      debugPrint('📱 返回前台: wasPlaying=$_wasPlayingBeforeBackground, savedPosition=${_positionBeforeBackground?.inSeconds}s, actualPosition=${actualPosition.inSeconds}s');

      if (backgroundPlayEnabled.value) {
        // 后台播放模式：同步UI到实际播放进度
        _syncUIAfterBackground(actualPosition);
      } else if (_wasPlayingBeforeBackground) {
        // 非后台播放模式：恢复到之前保存的位置
        _resumePlaybackAfterBackground();
        _wasPlayingBeforeBackground = false;
      }

      // 【关键】延迟检查并修复可能卡住的加载状态
      Future.delayed(const Duration(milliseconds: 500), () {
        if (player.state.playing && !player.state.buffering && isBuffering.value) {
          debugPrint('🔧 修复卡住的加载状态');
          isBuffering.value = false;
        }
      });
    }
  }

  /// 后台播放返回后同步UI进度
  /// 不做seek，只是让UI显示与实际播放进度一致
  void _syncUIAfterBackground(Duration actualPosition) {
    debugPrint('🔄 同步UI进度: ${actualPosition.inSeconds}s');

    // 【关键】强制重置buffering状态，防止后台期间卡住的加载动画
    // 检查播放器实际状态，如果正在播放则不应该显示加载动画
    if (player.state.playing && !player.state.buffering) {
      isBuffering.value = false;
    }

    // 强制发送一次当前位置到进度流，让UI更新
    _positionStreamController.add(actualPosition);

    // 清除保存的位置（不需要了）
    _positionBeforeBackground = null;
    _wasPlayingBeforeBackground = false;
  }

  /// 后台返回前台后恢复播放
  Future<void> _resumePlaybackAfterBackground() async {
    final savedPosition = _positionBeforeBackground;
    _positionBeforeBackground = null;

    try {
      // 检查播放器是否处于有效状态
      final duration = player.state.duration;
      if (duration.inSeconds <= 0) {
        debugPrint('⚠️ 播放器状态无效，尝试重新加载');
        await _reloadAndResumePlayback(savedPosition);
        return;
      }

      // 检查播放位置是否异常
      final currentPos = player.state.position;
      final positionDrift = savedPosition != null
          ? (currentPos.inMilliseconds - savedPosition.inMilliseconds).abs()
          : 0;

      if (savedPosition != null && positionDrift > 3000) {
        debugPrint('⚠️ 位置偏移: 保存=${savedPosition.inSeconds}s, 当前=${currentPos.inSeconds}s');
        await player.seek(savedPosition);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      await player.play();

      // 验证播放是否成功恢复
      await Future.delayed(const Duration(milliseconds: 500));
      if (!player.state.playing && errorMessage.value == null) {
        debugPrint('⚠️ 播放恢复失败，重试...');
        await _reloadAndResumePlayback(savedPosition);
      }
    } catch (e) {
      debugPrint('❌ 恢复播放异常: $e');
      await _reloadAndResumePlayback(savedPosition);
    }
  }

  /// 重新加载并恢复播放
  Future<void> _reloadAndResumePlayback(Duration? position) async {
    if (_currentResourceId == null || currentQuality.value == null) return;

    try {
      debugPrint('🔄 重新加载视频...');
      // 优先使用缓存的资源
      MediaSource mediaSource;
      final quality = currentQuality.value!;
      if (_qualityCache.containsKey(quality)) {
        mediaSource = _qualityCache[quality]!;
        debugPrint('📦 [ReloadResume] 使用缓存的视频资源');
      } else {
        mediaSource = await _hlsService.getMediaSource(_currentResourceId!, quality);
        _qualityCache[quality] = mediaSource;
      }
      final media = await _createMediaFromResource(mediaSource, debugTag: 'ReloadResume');

      await player.open(media, play: false);
      await _waitForDuration(timeout: const Duration(seconds: 5));

      if (position != null && position.inSeconds > 0) {
        await player.seek(position);
        await Future.delayed(const Duration(milliseconds: 200));
      }

      await player.play();
      debugPrint('✅ 播放已恢复');
    } catch (e) {
      debugPrint('❌ 重新加载失败: $e');
      errorMessage.value = '播放恢复失败，请重试';
    }
  }

  // 视频标题（用于后台播放通知显示）
  String? _videoTitle;
  String? _videoAuthor;
  Uri? _videoCoverUri;

  /// 设置视频元数据（供后台播放通知使用）
  void setVideoMetadata({
    required String title,
    String? author,
    Uri? coverUri,
  }) {
    _videoTitle = title;
    _videoAuthor = author;
    _videoCoverUri = coverUri;

    // 【关键修复】如果后台播放已启用，确保 AudioHandler 已初始化后再更新
    if (backgroundPlayEnabled.value) {
      _ensureAudioServiceReadyAndUpdate();
    }
  }

  /// 确保 AudioService 已准备好并更新通知栏信息
  Future<void> _ensureAudioServiceReadyAndUpdate() async {
    await _ensureAudioServiceReady();
    _updateNotificationMediaItem();
  }

  /// 更新通知栏的媒体信息
  /// 如果 duration 为 0，会延迟重试直到获取到有效时长
  void _updateNotificationMediaItem() {
    if (_audioHandler == null || _currentResourceId == null) return;
    if (_videoTitle == null) return;

    final duration = player.state.duration;

    // 立即更新（即使 duration 为 0，先显示标题等信息）
    _audioHandler!.setMediaItem(
      id: 'video_$_currentResourceId',
      title: _videoTitle!,
      artist: _videoAuthor,
      duration: duration,
      artUri: _videoCoverUri,
    );

    // 【关键】同时更新播放状态，强制通知栏刷新
    _audioHandler!.updatePlaybackState(
      playing: player.state.playing,
      position: player.state.position,
    );

    debugPrint('🎵 [AudioService] 更新媒体信息: $_videoTitle');

    // 如果 duration 还是 0，延迟重试（等待视频加载完成）
    if (duration.inSeconds <= 0) {
      Future.delayed(const Duration(milliseconds: 500), () {
        final newDuration = player.state.duration;
        if (newDuration.inSeconds > 0 && _audioHandler != null && _currentResourceId != null) {
          _audioHandler!.setMediaItem(
            id: 'video_$_currentResourceId',
            title: _videoTitle ?? '视频播放',
            artist: _videoAuthor,
            duration: newDuration,
            artUri: _videoCoverUri,
          );
          // 再次更新播放状态
          _audioHandler!.updatePlaybackState(
            playing: player.state.playing,
            position: player.state.position,
          );
          debugPrint('🎵 [AudioService] 延迟更新媒体信息: duration=${newDuration.inSeconds}s');
        }
      });
    }
  }



  /// 切换后台播放开关
  Future<void> toggleBackgroundPlay() async {
    backgroundPlayEnabled.value = !backgroundPlayEnabled.value;
    await _saveBackgroundPlaySetting(backgroundPlayEnabled.value);
    debugPrint('🎵 后台播放: ${backgroundPlayEnabled.value ? "开启" : "关闭"}');

    // 【关键】开启后台播放时，预先初始化 AudioService
    // 这样进入后台时通知栏可以立即显示
    if (backgroundPlayEnabled.value) {
      _ensureAudioServiceReady();
    }
  }

  /// 确保 AudioService 已准备好
  /// 逻辑：如果已初始化，只更新 player 实例；否则首次初始化
  Future<void> _ensureAudioServiceReady() async {
    try {
      // 【关键】AudioService.init 只能调用一次，后续复用静态实例
      if (_audioServiceInitialized && _audioHandler != null) {
        debugPrint('🎵 [AudioService] 已初始化，更新 player 实例');
        _audioHandler!.setPlayer(player);
        return;
      }

      // 首次初始化
      if (!_audioServiceInitialized) {
        debugPrint('🎵 [AudioService] 首次初始化...');
        _audioHandler = await AudioService.init(
          builder: () => VideoAudioHandler(player),
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.alnitak.video_playback',
            androidNotificationChannelName: '视频播放',
            androidNotificationOngoing: false, // 暂停时允许清除
            androidStopForegroundOnPause: false, // 暂停时保持通知显示
            androidNotificationIcon: 'mipmap/ic_launcher',
            androidShowNotificationBadge: true,
            fastForwardInterval: Duration(seconds: 10),
            rewindInterval: Duration(seconds: 10),
          ),
        );
        _audioServiceInitialized = true;
        debugPrint('🎵 [AudioService] 初始化完成');
      }
    } catch (e) {
      debugPrint('❌ [AudioService] 初始化失败: $e');
    }
  }

  /// 保存后台播放设置
  Future<void> _saveBackgroundPlaySetting(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundPlayKey, enabled);
  }

  /// 激活后台播放（进入后台时调用）
  /// 这个方法会立即启动后台播放流程，不阻塞主线程
  /// 激活后台播放（进入后台时调用）
  void _activateBackgroundPlayback() {
    debugPrint('🎵 [AudioService] 激活后台播放...');
    WakelockManager.enable();
    _lastWakelockState = true;

    if (_audioHandler != null) {
      _updateAudioServiceState();
      _ensureBackgroundPlaying();
      return;
    }

    // 如果还没初始化，尝试初始化并激活
    _ensureAudioServiceReady().then((_) {
      _updateAudioServiceState();
      _ensureBackgroundPlaying();
    });
  }
  /// 初始化 AudioService 并激活后台播放
  /// 只负责渲染通知栏组件，播放器自带后台播放功能

  /// 更新 AudioService 状态（媒体信息和播放状态）
  void _updateAudioServiceState() {
    if (_audioHandler == null || _currentResourceId == null) return;

    // 更新媒体信息（复用统一方法）
    _updateNotificationMediaItem();

    // 更新播放状态为 playing
    _audioHandler!.updatePlaybackState(
      playing: true,
      position: player.state.position,
    );

    debugPrint('🎵 [AudioService] 状态已更新: ${_videoTitle ?? "视频播放"}');
  }

  /// 确保后台持续播放（多次检测恢复）
  void _ensureBackgroundPlaying() {
    // 立即检查
    if (backgroundPlayEnabled.value && _wasPlayingBeforeBackground && !player.state.playing) {
      player.play();
      debugPrint('🎵 [AudioService] 立即恢复播放');
    }

    // 500ms 后再次检查
    Future.delayed(const Duration(milliseconds: 500), () {
      if (backgroundPlayEnabled.value && _wasPlayingBeforeBackground && !player.state.playing) {
        player.play();
        debugPrint('🎵 [AudioService] 500ms 后恢复播放');
      }
    });

    // 1500ms 后最后一次检查（防止系统延迟暂停）
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (backgroundPlayEnabled.value && _wasPlayingBeforeBackground && !player.state.playing) {
        player.play();
        debugPrint('🎵 [AudioService] 1500ms 后恢复播放');
      }
    });
  }

  /// 停止后台播放通知（退出播放页时调用）
  /// 注意：不销毁 AudioService，因为它是单例，下次会复用
  Future<void> stopBackgroundPlayback() async {
    if (_audioHandler != null) {
      await _audioHandler!.stop();
      debugPrint('🎵 [AudioService] 后台播放已停止（保留 Handler 供复用）');
    }
  }

  // 标记是否已开始清理，防止重复调用
  bool _isDisposing = false;

  /// 【关键修复】同步准备清理 - 必须在 dispose 之前调用
  /// 这个方法会立即禁用日志和取消订阅，防止回调崩溃
  void prepareDispose() {
    if (_isDisposing) return;
    _isDisposing = true;

    debugPrint('🗑️ [VideoPlayerController] 开始同步清理...');

    // 【关键修复】首先取消所有定时器
    _debounceTimer?.cancel();
    _stalledTimer?.cancel();
    _preloadTimer?.cancel();
    _seekDebounceTimer?.cancel();

    // 【最关键】立即取消所有 player.stream 的订阅
    // 这必须在任何其他操作之前完成，防止回调被调用
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _completedSubscription?.cancel();
    _completedSubscription = null;
    _playingSubscription?.cancel();
    _playingSubscription = null;
    _bufferingSubscription?.cancel();
    _bufferingSubscription = null;

    // 取消其他订阅
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _audioInterruptionSubscription?.cancel();
    _audioInterruptionSubscription = null;
    _callStateSubscription?.cancel();
    _callStateSubscription = null;

    // 【关键】同步停止播放器，防止热重载时 MPV 回调崩溃
    try {
      player.pause(); // 同步暂停（减少回调频率）

      // 【关键】尝试同步禁用 MPV 日志（防止日志线程回调崩溃）
      if (!kIsWeb) {
        final nativePlayer = player.platform as NativePlayer?;
        if (nativePlayer != null) {
          // 使用 unawaited 立即发送命令，不等待完成
          unawaited(nativePlayer.setProperty('msg-level', 'all=no'));
          unawaited(nativePlayer.setProperty('terminal', 'no'));
        }
      }
    } catch (e) {
      debugPrint('⚠️ 同步清理播放器失败: $e');
    }

    debugPrint('🗑️ [VideoPlayerController] 订阅已取消');
  }

  /// 【关键修复】异步清理方法，替代 dispose()
  /// 这个方法会：
  /// 1. 调用 prepareDispose() 同步取消订阅
  /// 2. 禁用 libmpv 日志（防止日志回调导致崩溃）
  /// 3. 停止播放器（让 native 层的线程完成工作）
  /// 4. 等待一段时间让 native 线程完成
  /// 5. 调用 player.dispose() 和其他清理
  ///
  /// 这可以防止 "Callback invoked after it has been deleted" 崩溃
  Future<void> disposeAsync() async {
    // 先执行同步清理
    prepareDispose();

    // 【关键修复】在停止播放器之前，先禁用 libmpv 的日志
    // 这可以防止日志线程在 dispose 后仍然尝试调用 Dart 回调
    try {
      if (!kIsWeb) {
        final nativePlayer = player.platform as NativePlayer?;
        if (nativePlayer != null) {
          // 设置 msg-level=all=no 禁用所有日志输出
          await nativePlayer.setProperty('msg-level', 'all=no');
          // 同时设置 terminal=no 禁用终端输出
          await nativePlayer.setProperty('terminal', 'no');
          debugPrint('🗑️ [VideoPlayerController] 日志已禁用');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [VideoPlayerController] 禁用日志失败: $e');
    }

    // 【关键修复】停止播放器
    try {
      await player.stop();
      debugPrint('🗑️ [VideoPlayerController] 播放器已停止');
    } catch (e) {
      debugPrint('⚠️ [VideoPlayerController] 停止播放器失败: $e');
    }

    // 【关键】等待 libmpv 的 native 线程完成
    // 增加等待时间到 500ms，确保日志线程完全停止
    await Future.delayed(const Duration(milliseconds: 500));

    // 清理 CallStateHandler
    _callStateHandler?.dispose();

    // 关闭自定义流控制器
    _positionStreamController.close();

    // 清理预加载缓存
    _qualityCache.clear();

    // 清理时禁用 wakelock
    WakelockManager.disable();

    // 停止后台播放通知
    if (_audioHandler != null) {
      await _audioHandler!.stop();
    }

    _hlsService.cleanupAllTempCache();

    // 【关键】再等待一下，确保所有 native 回调都已停止
    await Future.delayed(const Duration(milliseconds: 100));

    // 【关键】现在安全地 dispose player
    try {
      player.dispose();
      debugPrint('🗑️ [VideoPlayerController] player 已 dispose');
    } catch (e) {
      debugPrint('⚠️ [VideoPlayerController] player dispose 失败: $e');
    }

    // dispose ValueNotifiers
    availableQualities.dispose();
    currentQuality.dispose();
    isLoading.dispose();
    errorMessage.dispose();
    isPlayerInitialized.dispose();
    isSwitchingQuality.dispose();
    loopMode.dispose();
    backgroundPlayEnabled.dispose();
    isBuffering.dispose();

    debugPrint('🗑️ [VideoPlayerController] 异步清理完成');
  }

  @override
  void dispose() {
    if (_isDisposed) return; // 防止重复调用
    _isDisposed = true;      // 【关键】标记已销毁
    debugPrint('🗑️ [VideoPlayerController] 开始销毁...');

    // 1. 【同步切断】第一步：立即取消所有 Timer
    _debounceTimer?.cancel();
    _stalledTimer?.cancel();
    _preloadTimer?.cancel();
    _seekDebounceTimer?.cancel();
    _seekRetryTimer?.cancel();

    // 2. 【同步切断】第二步：立即取消所有 StreamSubscription
    // 这一步至关重要，必须同步执行，不能 await
    _positionSubscription?.cancel();
    _completedSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _audioInterruptionSubscription?.cancel();
    _callStateSubscription?.cancel();
    _callStateHandler?.dispose();
    _positionStreamController.close();

    // 3. 【同步切断】第三步：清理业务状态
    _qualityCache.clear();
    WakelockManager.disable();
    if (_audioHandler != null) {
      _audioHandler!.stop(); // 停止通知，但不销毁静态实例
    }
    _hlsService.cleanupAllTempCache();

    // 4. 【同步切断】第四步：销毁 Notifiers
    availableQualities.dispose();
    currentQuality.dispose();
    isLoading.dispose();
    errorMessage.dispose();
    isPlayerInitialized.dispose();
    isSwitchingQuality.dispose();
    loopMode.dispose();
    backgroundPlayEnabled.dispose();
    isBuffering.dispose();

    // 5. 【关键防御】将 player 的销毁放入 isolate 或延迟执行
    // 这里的逻辑是：先同步切断所有回调，Dart 层已经安全了。
    // 然后告诉底层 "停止工作"，并给它 100ms 的时间去处理未完成的帧。
    // 最后再销毁句柄。
    final playerToDispose = player; // 捕获引用

    // 立即停止（发送指令，不等待）
    playerToDispose.stop();

    // 延迟销毁（防止 Native 线程竞争）
    Future.delayed(const Duration(milliseconds: 200), () async {
      try {
        await playerToDispose.dispose();
        debugPrint('🗑️ [VideoPlayerController] 播放器底层资源已释放');
      } catch (e) {
        // 忽略销毁时的错误
      }
    });

    super.dispose();
  }
}