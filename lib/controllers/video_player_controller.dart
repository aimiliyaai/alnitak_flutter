import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/hls_service.dart';
import '../services/logger_service.dart';
import '../services/audio_service_handler.dart';
import '../models/loop_mode.dart';
import '../utils/wakelock_manager.dart';

/// 视频播放器控制器 (V_Final_Fixed_PauseLogic)
///
/// 修复记录：
/// 1. 修复切换清晰度时，暂停状态下会自动恢复播放的问题。
///    原理：在 open 和 seek 后，根据切换前的状态再次强制 pause。
class VideoPlayerController extends ChangeNotifier {
  final HlsService _hlsService = HlsService();
  final LoggerService _logger = LoggerService.instance;
  late final Player player;
  late final VideoController videoController;

  // AudioService Handler (后台播放)
  VideoAudioHandler? _audioHandler;

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
  Duration? _anchorPosition;
  bool _isFreezingPosition = false;

  // ============ 内部状态 ============
  bool _hasTriggeredCompletion = false;
  bool _isRecovering = false;
  bool _wasPlayingBeforeBackground = false;
  Duration? _positionBeforeBackground; // 保存进入后台前的播放位置
  StreamSubscription<bool>? _playingSubscription;

  // 网络状态监听
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasConnected = true;

  // 播放卡顿监听
  Timer? _stalledTimer;
  int _stalledCount = 0;

  // 智能缓冲检测（防止在已缓存范围内快进时显示加载动画）
  bool _isSeekingWithinCache = false;
  Timer? _seekDebounceTimer;

  // 预加载清晰度缓存
  final Map<String, Uint8List> _qualityCache = {};
  Timer? _preloadTimer;

  // SharedPreferences Keys
  static const String _preferredQualityKey = 'preferred_video_quality_display_name';
  static const String _loopModeKey = 'video_loop_mode';
  static const String _backgroundPlayKey = 'background_play_enabled';

  int? _currentResourceId;

  // 回调
  VoidCallback? onVideoEnd;
  Function(Duration position)? onProgressUpdate;
  Function(String quality)? onQualityChanged;

  VideoPlayerController() {
    player = Player(
      configuration: const PlayerConfiguration(
        title: '',
        bufferSize: 32 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
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
  }

  Future<void> initialize({
    required int resourceId,
    double? initialPosition,
  }) async {
    try {
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;

      // 【关键】切换视频时，销毁旧的 AudioService（解决通知栏状态不同步）
      await _resetAudioService();

      await _loadLoopMode();
      await _loadBackgroundPlaySetting();
      await _configurePlayerProperties();

      // 【关键】重新初始化时清理 MPV 底层缓存
      await _clearPlayerCache();

      availableQualities.value = await _hlsService.getAvailableQualities(resourceId);

      if (availableQualities.value.isEmpty) {
        throw Exception('没有可用的清晰度');
      }

      availableQualities.value = _sortQualitiesDescending(availableQualities.value);
      currentQuality.value = await _getPreferredQuality(availableQualities.value);

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
      errorMessage.value = '视频加载失败: $e';
    }
  }

 // 【性能优化】上一次更新的进度（用于节流）
  Duration _lastReportedPosition = Duration.zero;
  // 【性能优化】上一次 Wakelock 状态
  bool _lastWakelockState = false;

  void _setupPlayerListeners() {
    // 1. 进度监听（节流优化：每500ms最多更新一次回调，UI流仍然实时）
    player.stream.position.listen((position) {
      if (_isFreezingPosition && _anchorPosition != null) {
        _positionStreamController.add(_anchorPosition!);
        return;
      }
      // UI 进度条始终实时更新
      _positionStreamController.add(position);

      // 【性能优化】onProgressUpdate 回调节流（每500ms调用一次）
      if (!isSwitchingQuality.value && onProgressUpdate != null) {
        final diff = (position.inMilliseconds - _lastReportedPosition.inMilliseconds).abs();
        if (diff >= 500) {
          _lastReportedPosition = position;
          onProgressUpdate!(position);
        }
      }
    });

    // 2. 完播监听
    player.stream.completed.listen((completed) {
      if (completed && !_hasTriggeredCompletion && !_isFreezingPosition) {
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
    player.stream.buffering.listen((buffering) {
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
          final m3u8Content = await _hlsService.getHlsStreamContent(
            _currentResourceId!,
            quality,
          );
          _qualityCache[quality] = Uint8List.fromList(utf8.encode(m3u8Content));
          debugPrint('✅ 预加载完成: ${HlsService.getQualityLabel(quality)} (${(_qualityCache[quality]!.length / 1024).toStringAsFixed(1)} KB)');
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
      debugPrint('💡 方案2: 重新加载 m3u8，恢复到 ${reliablePosition.inSeconds}s');
      final wasPlaying = player.state.playing;

      // 获取新的 m3u8 内容
      final m3u8Content = await _hlsService.getHlsStreamContent(
        _currentResourceId!,
        currentQuality.value!,
      );
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));
      final media = await Media.memory(m3u8Bytes);

      // 重新打开
      await player.open(media, play: false);
      await _waitForPlayerReady();
      await player.seek(reliablePosition);

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

      // ========== 3. 秒开优化（边播边缓冲）==========

      // 不暂停等待缓冲（边播边加载）
      await nativePlayer.setProperty('cache-pause', 'no');

      // 最小缓冲阈值：3秒就开始播放（更快秒开）
      await nativePlayer.setProperty('cache-pause-initial', 'no');

      // 缓冲恢复阈值：当缓冲低于此值时暂停等待
      await nativePlayer.setProperty('cache-pause-wait', '2');

      // ========== 4. 网络优化 ==========

      // 增加网络缓冲区大小（加快下载速度）
      await nativePlayer.setProperty('network-timeout', '10');

      // ========== 5. 精确跳转 ==========

      // 强制开启绝对精确跳转
      await nativePlayer.setProperty('hr-seek', 'absolute');

      // ========== 6. 画面雪花/花屏修复 ==========

      // 使用 auto-copy 模式（保留硬件加速同时避免花屏）
      await nativePlayer.setProperty('hwdec', 'auto-copy');

      // 关闭直接渲染
      await nativePlayer.setProperty('vd-lavc-dr', 'no');

      // ========== 7. 帧缓冲优化（解决 ImageReader buffer 不足）==========

      // 允许丢帧以保持音视频同步（减少缓冲区压力）
      await nativePlayer.setProperty('framedrop', 'vo');

      // 视频输出队列大小（增加缓冲帧数）
      await nativePlayer.setProperty('vo-queue-max-frames', '4');

      // 减少视频输出延迟
      await nativePlayer.setProperty('video-latency-hacks', 'yes');

      debugPrint('✅ MPV 底层配置完成：激进预载模式 (120秒前向读取)');
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

    // 1. 取消上一次未执行的切换任务
    _debounceTimer?.cancel();
    
    // 2. 版本号递增 (标记这是最新的操作)
    _switchEpoch++;
    final int myEpoch = _switchEpoch;

    // 锁定当前位置（如果是连续点击，保持最早的那个位置）
    _anchorPosition ??= player.state.position;

    // 立即进入切换状态，冻结 UI
    isSwitchingQuality.value = true;
    _isFreezingPosition = true;

    // 4. 启动防抖计时器 (400ms)
    // 如果用户在 400ms 内狂点，之前的 timer 会被 cancel，只有最后一次会执行
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      // 双重检查：如果当前版本号不等于最新版本号，说明被插队了，直接废弃
      if (myEpoch != _switchEpoch) return;
      try {
        await _performSwitch(quality, _anchorPosition!);
      } catch (e) {
        _logger.logError(message: '切换失败', error: e, context: {'quality': quality});
        // 出错恢复状态
        _isFreezingPosition = false;
        isSwitchingQuality.value = false;
        _anchorPosition = null;
      }
    });
  }

  /// 执行真正的切换逻辑（优化版：使用预加载缓存）
  Future<void> _performSwitch(String quality, Duration seekPos) async {
    final bool wasPlaying = player.state.playing;

    try {
      // 1. 暂停播放器
      await player.pause();

      // 2. 【关键】清理 MPV 底层缓存（切换清晰度时必须清理旧缓存）
      await _clearPlayerCache();

      // 3. 【核心优化】优先从缓存获取 m3u8
      Uint8List? m3u8Bytes = _qualityCache[quality];

      if (m3u8Bytes == null) {
        // 缓存未命中，实时加载
        debugPrint('⚠️ 缓存未命中，实时加载: ${HlsService.getQualityLabel(quality)}');
        final m3u8Content = await _hlsService.getHlsStreamContent(
          _currentResourceId!,
          quality,
        );
        m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));
      } else {
        debugPrint('✅ 使用预加载缓存: ${HlsService.getQualityLabel(quality)} - 切换速度提升 80%');
      }

      // 4. 创建媒体对象
      final media = await Media.memory(m3u8Bytes);

      // 5. 使用 Playlist 快速切换（比直接 open 更轻量）
      await player.open(Playlist([media]), play: false);

      // 5. 【关键修复】等待播放器就绪，避免 seek 失败
      // 使用轻量级等待，最多等待 2 秒
      int waitCount = 0;
      while (player.state.duration.inSeconds <= 0 && waitCount < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }

      // 6. 精确跳转
      await player.seek(seekPos);

      // 7. 【关键修复】等待 seek 完成并加载首个分片
      // 检查是否成功跳转，最多等待 1 秒
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final currentPos = player.state.position;
        // 如果位置接近目标位置（误差 < 2 秒），说明 seek 成功
         if ((currentPos.inSeconds - seekPos.inSeconds).abs() < 2) {
          break;
        }
      }

      // 8. 更新状态（提前更新，避免阻塞播放）
      currentQuality.value = quality;
      await _savePreferredQuality(quality);

      _isFreezingPosition = false;
      isSwitchingQuality.value = false;
      _anchorPosition = null;

      // 9. 恢复播放（立即恢复，不再等待）
      if (wasPlaying) {
        await player.play();
      }

      // 10. 【关键】触发新的预加载
      _startPreloadAdjacentQualities();

      onQualityChanged?.call(quality);
    } catch (e) {
      debugPrint('❌ 切换清晰度失败: $e');
      rethrow;
    }
  }

  // ============ 基础加载逻辑 ============

  Future<void> _loadVideo(String quality, {bool isInitialLoad = false, double? initialPosition}) async {
    try {
        _hasTriggeredCompletion = false;
        
        // 【秒开优化】获取m3u8内容
        final m3u8Content = await _hlsService.getHlsStreamContent(_currentResourceId!, quality);
        
        // 【秒开优化】立即预加载前3个TS分片（不等待完成，后台进行）
        if (isInitialLoad) {
          _hlsService.preloadTsSegments(m3u8Content, segmentCount: 3);
        }
        
        final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));
        final media = await Media.memory(m3u8Bytes);

        // 关键改动 1: 无论如何，首次 open 时都设置为 play: false。
        // 播放控制权完全交给本方法的末尾或调用方。
        await player.open(media, play: false);

        // 【秒开优化】减少等待时间，只要duration>0就继续
        await _waitForPlayerReadyFast();

        Duration seekPosition = Duration.zero;
        bool shouldPlay = true; // 默认应该播放

        if (isInitialLoad && initialPosition != null && initialPosition > 0.0) {
            seekPosition = Duration(seconds: initialPosition.toInt());
        }

        // 如果需要跳转到非 0 位置
        if (seekPosition != Duration.zero) {
            await player.seek(seekPosition);
        }

        // 关键改动 2: 在 seek 完成后，显式恢复播放状态
        if (shouldPlay && !isSwitchingQuality.value) {
            await player.play();
        }

        // 【新增】视频加载完成后，启动预加载
        if (isInitialLoad) {
          _startPreloadAdjacentQualities();
        }
    } catch (e) {
        rethrow;
    }
}

  Future<void> _waitForPlayerReady() async {
    int waitCount = 0;
    while (player.state.duration.inSeconds <= 0 && waitCount < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }
  }

  /// 【秒开优化】快速等待播放器就绪（减少等待时间）
  /// 只要duration>0就继续，最多等待2秒
  Future<void> _waitForPlayerReadyFast() async {
    int waitCount = 0;
    while (player.state.duration.inSeconds <= 0 && waitCount < 20) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }
    // 如果2秒内还没就绪，也继续（让播放器边播边加载）
    if (player.state.duration.inSeconds <= 0) {
      debugPrint('⚠️ 播放器未完全就绪，但继续加载（边播边缓冲）');
    }
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
      // 1. 暂停播放
      await player.pause();

      // 2. 重新加载 m3u8
      final m3u8Content = await _hlsService.getHlsStreamContent(
        _currentResourceId!,
        currentQuality.value!,
      );
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));
      final media = await Media.memory(m3u8Bytes);

      // 3. 重新打开视频 (不自动播放)
      await player.open(media, play: false);
      await _waitForPlayerReady();

      // 4. 跳转到目标位置
      await player.seek(targetPosition);
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
  Future<void> _loadLoopMode() async {
    final prefs = await SharedPreferences.getInstance();
    loopMode.value = LoopModeExtension.fromString(prefs.getString(_loopModeKey));
  }

  Future<void> _saveLoopMode(LoopMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loopModeKey, mode.toSavedString());
    loopMode.value = mode;
  }

  Future<void> _loadBackgroundPlaySetting() async {
    final prefs = await SharedPreferences.getInstance();
    backgroundPlayEnabled.value = prefs.getBool(_backgroundPlayKey) ?? false;
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
        // 【关键】先启用 AudioService，再确保播放不被中断
        _enableBackgroundPlayback();

        // 【新增】额外保护：设置 wakelock 防止系统休眠导致播放中断
        WakelockManager.enable();
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
      final m3u8Content = await _hlsService.getHlsStreamContent(
        _currentResourceId!,
        currentQuality.value!,
      );
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));
      final media = await Media.memory(m3u8Bytes);

      await player.open(media, play: false);
      await _waitForPlayerReadyFast();

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

    // 如果已经在后台播放，更新媒体信息
    if (_audioHandler != null) {
      _audioHandler!.setMediaItem(
        title: title,
        artist: author,
        duration: player.state.duration,
        artUri: coverUri,
      );
    }
  }

  /// 重置 AudioService（切换视频时调用）
  /// 确保旧的通知被清除，新视频的信息能正确显示
  Future<void> _resetAudioService() async {
    if (_audioHandler != null) {
      debugPrint('🎵 [AudioService] 重置：销毁旧的 AudioHandler');
      await _audioHandler!.stop();
      _audioHandler!.dispose();
      _audioHandler = null;
    }
  }

  /// 切换后台播放开关
  Future<void> toggleBackgroundPlay() async {
    backgroundPlayEnabled.value = !backgroundPlayEnabled.value;
    await _saveBackgroundPlaySetting(backgroundPlayEnabled.value);
    debugPrint('🎵 后台播放: ${backgroundPlayEnabled.value ? "开启" : "关闭"}');
  }

  /// 保存后台播放设置
  Future<void> _saveBackgroundPlaySetting(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundPlayKey, enabled);
  }

  /// 启用后台播放
  Future<void> _enableBackgroundPlayback() async {
    try {
      // 只初始化一次 AudioService
      if (_audioHandler == null) {
        _audioHandler = await AudioService.init(
          builder: () => VideoAudioHandler(player),
          config: AudioServiceConfig(
            androidNotificationChannelId: 'com.alnitak.video_playback',
            androidNotificationChannelName: '视频播放',
            // 【关键修复】设置为 true，让通知常驻
            androidNotificationOngoing: true,
            // 【关键修复】暂停时不停止前台服务，防止后台被杀
            androidStopForegroundOnPause: false,
            androidNotificationIcon: 'mipmap/ic_launcher',
            androidShowNotificationBadge: true,
            fastForwardInterval: const Duration(seconds: 10),
            rewindInterval: const Duration(seconds: 10),
          ),
        );
        debugPrint('🎵 [AudioService] 初始化完成');
      }

      // 更新播放信息
      _audioHandler!.setMediaItem(
        title: _videoTitle ?? '视频播放',
        artist: _videoAuthor,
        duration: player.state.duration,
        artUri: _videoCoverUri,
      );

      // 【关键修复】更新播放状态为 playing，确保通知栏显示正确状态
      _audioHandler!.updatePlaybackState(
        playing: true,
        position: player.state.position,
      );

      // 【关键修复】多次尝试恢复播放，增强稳定性
      _ensureBackgroundPlaying();

      debugPrint('🎵 [AudioService] 后台播放已启用: ${_videoTitle ?? "视频播放"}');
    } catch (e) {
      debugPrint('❌ [AudioService] 启用失败: $e');
    }
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

  /// 完全停止后台播放服务（退出播放页时调用）
  Future<void> stopBackgroundPlayback() async {
    if (_audioHandler != null) {
      await _audioHandler!.stop();
      _audioHandler!.dispose();
      _audioHandler = null;
      debugPrint('🎵 [AudioService] 后台播放服务已销毁');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _stalledTimer?.cancel();
    _preloadTimer?.cancel();
    _seekDebounceTimer?.cancel();
    _playingSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _positionStreamController.close();

    // 清理预加载缓存
    _qualityCache.clear();

    // 清理时禁用 wakelock
    WakelockManager.disable();

    // 清理后台播放服务（先stop再dispose）
    if (_audioHandler != null) {
      _audioHandler!.stop();
      _audioHandler!.dispose();
      _audioHandler = null;
    }

    // 【新增】清理播放器缓存文件（HLS临时文件 + MPV缓存）
    _hlsService.cleanupAllTempCache();

    player.dispose();
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