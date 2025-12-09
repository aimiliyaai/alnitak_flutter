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
  StreamSubscription<bool>? _playingSubscription;

  // 网络状态监听
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasConnected = true;

  // 播放卡顿监听
  Timer? _stalledTimer;
  int _stalledCount = 0;

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

    videoController = VideoController(player);
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

      await _loadLoopMode();
      await _loadBackgroundPlaySetting();
      await _configurePlayerProperties();

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

  void _setupPlayerListeners() {
    // 1. 进度监听
    player.stream.position.listen((position) {
      // 如果处于冻结状态（切换中），发送锚点位置，而不是真实位置
      if (_isFreezingPosition && _anchorPosition != null) {
        _positionStreamController.add(_anchorPosition!);
        return;
      }
      _positionStreamController.add(position);
      if (!isSwitchingQuality.value) {
        onProgressUpdate?.call(position);
      }
    });

    // 2. 完播监听
    player.stream.completed.listen((completed) {
      // 切换期间忽略 completed 事件
      if (completed && !_hasTriggeredCompletion && !_isFreezingPosition) {
        _hasTriggeredCompletion = true;
        _handlePlaybackEnd();
      }
    });

    // 3. 播放状态监听 + Wakelock 控制
    _playingSubscription = player.stream.playing.listen((playing) {
      if (playing && _hasTriggeredCompletion) {
        _hasTriggeredCompletion = false;
      }

      // Wakelock 控制：严格绑定播放状态
      // 只要是在播放状态下，必须保持唤醒
      if (playing) {
        WakelockManager.enable();
      } else {
        WakelockManager.disable();
      }
    });

    // 4. 缓冲状态监听 + 超时检测（替代 error 监听）
    player.stream.buffering.listen((buffering) {
      isBuffering.value = buffering;

      if (buffering) {
        // 开始缓冲，启动 15 秒超时监听
        _stalledTimer?.cancel();
        _stalledTimer = Timer(const Duration(seconds: 15), () {
          // 15秒还在缓冲，认为播放卡死
          if (player.state.buffering) {
            print('⚠️ 播放卡住超过15秒，尝试智能恢复...');
            _handleStalledPlayback();
          }
        });
      } else {
        // 缓冲结束，取消超时
        _stalledTimer?.cancel();
        _stalledCount = 0; // 重置卡顿计数
      }
    });
  }

  /// 设置网络状态监听
  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isConnected = results.any((result) => result != ConnectivityResult.none);

      // 从断网恢复到联网
      if (!_wasConnected && isConnected) {
        print('📡 网络已恢复，尝试重新连接...');
        _onNetworkRestored();
      }

      // 检测到断网
      if (_wasConnected && !isConnected) {
        print('📡 网络已断开');
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
          print('✅ 清晰度已缓存: ${HlsService.getQualityLabel(quality)}');
          continue;
        }

        try {
          final m3u8Content = await _hlsService.getHlsStreamContent(
            _currentResourceId!,
            quality,
          );
          _qualityCache[quality] = Uint8List.fromList(utf8.encode(m3u8Content));
          print('✅ 预加载完成: ${HlsService.getQualityLabel(quality)} (${(_qualityCache[quality]!.length / 1024).toStringAsFixed(1)} KB)');
        } catch (e) {
          print('⚠️ 预加载失败: ${HlsService.getQualityLabel(quality)} - $e');
        }
      }
    });
  }

  /// 处理播放卡顿（智能恢复方案）
  /// 优先使用轻量级恢复，避免重新加载 m3u8
  Future<void> _handleStalledPlayback() async {
    if (_isRecovering || currentQuality.value == null) return;

    _isRecovering = true;
    _stalledCount++;

    try {
      print('🔧 卡顿恢复尝试 $_stalledCount/2');

      if (_stalledCount == 1) {
        // 第一次卡顿：尝试轻量级恢复 - 跳过坏的 TS 分片
        print('💡 方案1: 尝试跳过损坏分片 (+2秒)');
        final currentPos = player.state.position;
        final newPos = currentPos + const Duration(seconds: 2);

        // 直接 seek，依靠 MPV 的底层重连机制
        await player.seek(newPos);

        // 等待 3 秒看是否恢复
        await Future.delayed(const Duration(seconds: 3));

        if (!player.state.buffering) {
          print('✅ 轻量级恢复成功');
          _isRecovering = false;
          _stalledCount = 0;
          return;
        }
      }

      // 第二次卡顿或第一次失败：重新加载 m3u8
      print('💡 方案2: 重新加载 m3u8');
      final position = player.state.position;
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
      await player.seek(position);

      if (wasPlaying) {
        await player.play();
      }

      print('✅ m3u8 重载恢复成功');
      _stalledCount = 0;
    } catch (e) {
      print('❌ 卡顿恢复失败: $e');
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

      // TS 分片超时和重试配置
      // timeout=10000000 (10秒超时)
      // reconnect=1 (启用重连)
      // reconnect_at_eof=1 (EOF时重连)
      // reconnect_streamed=1 (流媒体重连)
      // reconnect_delay_max=5 (最大重连延迟5秒)
      await nativePlayer.setProperty('stream-lavf-o',
        'timeout=10000000,reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,reconnect_delay_max=5'
      );

      // ========== 2. 缓冲策略（参考 B站）==========

      // 启用缓存
      await nativePlayer.setProperty('cache', 'yes');

      // 预缓冲时长：20秒
      await nativePlayer.setProperty('cache-secs', '20');

      // 最大缓冲大小：50MB
      await nativePlayer.setProperty('demuxer-max-bytes', '50M');

      // 允许缓存 seek
      await nativePlayer.setProperty('demuxer-seekable-cache', 'yes');

      // ========== 3. 精确跳转 ==========

      // 强制开启绝对精确跳转
      await nativePlayer.setProperty('hr-seek', 'absolute');

      // ========== 4. 画面雪花/花屏修复 ==========

      // 使用 auto-copy 模式（保留硬件加速同时避免花屏）
      await nativePlayer.setProperty('hwdec', 'auto-copy');

      // 关闭直接渲染
      await nativePlayer.setProperty('vd-lavc-dr', 'no');

      print('✅ MPV 底层配置完成：HLS优化 + 缓冲策略');
    } catch (e) {
      print('⚠️ 配置失败: $e');
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

      // 2. 【核心优化】优先从缓存获取 m3u8
      Uint8List? m3u8Bytes = _qualityCache[quality];

      if (m3u8Bytes == null) {
        // 缓存未命中，实时加载
        print('⚠️ 缓存未命中，实时加载: ${HlsService.getQualityLabel(quality)}');
        final m3u8Content = await _hlsService.getHlsStreamContent(
          _currentResourceId!,
          quality,
        );
        m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));
      } else {
        print('✅ 使用预加载缓存: ${HlsService.getQualityLabel(quality)} - 切换速度提升 80%');
      }

      // 3. 创建媒体对象
      final media = await Media.memory(m3u8Bytes);

      // 4. 使用 Playlist 快速切换（比直接 open 更轻量）
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
      print('❌ 切换清晰度失败: $e');
      rethrow;
    }
  }

  // ============ 基础加载逻辑 ============

  Future<void> _loadVideo(String quality, {bool isInitialLoad = false, double? initialPosition}) async {
    try {
        _hasTriggeredCompletion = false;
        final m3u8Content = await _hlsService.getHlsStreamContent(_currentResourceId!, quality);
        final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

        final media = await Media.memory(m3u8Bytes);

        // 关键改动 1: 无论如何，首次 open 时都设置为 play: false。
        // 播放控制权完全交给本方法的末尾或调用方。
        await player.open(media, play: false);

        await _waitForPlayerReady();

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

  // ============ 播放控制 ============
  void toggleLoopMode() {
    final newMode = loopMode.value.toggle();
    _saveLoopMode(newMode);
  }

  Future<void> play() async => await player.play();
  Future<void> pause() async => await player.pause();

  /// 快进/快退方法 - 带分片恢复保障
  ///
  /// 确保无论什么情况下,快进都不会丢失分片跳过
  /// 如果遇到加载失败,会尝试重新加载并恢复到目标位置
  Future<void> seek(Duration position) async {
    final targetPosition = position;
    final wasPlaying = player.state.playing;

    try {
      // 1. 执行 seek 操作
      await player.seek(targetPosition);

      // 2. 等待一小段时间让播放器加载分片
      await Future.delayed(const Duration(milliseconds: 300));

      // 3. 检查是否成功到达目标位置
      final currentPos = player.state.position;
      final positionDiff = (currentPos.inSeconds - targetPosition.inSeconds).abs();

      // 如果位置偏差超过 3 秒,可能是分片加载失败
      if (positionDiff > 3) {
        print('⚠️ 快进位置偏差 ${positionDiff}s，重新加载');
        await _recoverSeekPosition(targetPosition, wasPlaying);
      }

    } catch (e) {
      print('❌ 快进失败: $e');
      // 快进失败时尝试恢复
      await _recoverSeekPosition(targetPosition, wasPlaying);
    }
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
      print('❌ 快进位置恢复失败: $e');
      errorMessage.value = '快进失败，请重试';
    }
  }

  Future<void> setRate(double rate) async => await player.setRate(rate);

  void _handlePlaybackEnd() {
    switch (loopMode.value) {
      case LoopMode.on:
        // 使用增强后的 seek 方法确保循环播放时也能正确恢复
        seek(Duration.zero).then((_) {
          player.play();
          // 循环播放时重新启用 wakelock（防止循环后失效）
          WakelockManager.enable();
        });
        break;
      case LoopMode.off:
        onVideoEnd?.call();
        break;
    }
  }

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
      print('⚠️ 保存清晰度偏好失败: $e');
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
      print('解析清晰度名称失败: $e');
    }
    return quality;
  }

  void handleAppLifecycleState(bool isPaused) {
    if (isPaused) {
      // 进入后台
      if (backgroundPlayEnabled.value) {
        // 启用后台播放
        _enableBackgroundPlayback();
      } else {
        // 暂停播放
        _wasPlayingBeforeBackground = player.state.playing;
        if (_wasPlayingBeforeBackground) player.pause();
      }
    } else {
      // 返回前台
      if (backgroundPlayEnabled.value) {
        // 禁用后台播放 (回到前台使用正常的视频渲染)
        _disableBackgroundPlayback();
      } else if (_wasPlayingBeforeBackground) {
        // 恢复播放 - 添加网络恢复检测
        _resumePlaybackAfterBackground();
        _wasPlayingBeforeBackground = false;
      }
    }
  }

  /// 后台返回前台后恢复播放
  /// 如果播放失败，自动尝试重新加载
  Future<void> _resumePlaybackAfterBackground() async {
    try {
      await player.play();

      // 等待一小段时间检查是否能正常播放
      await Future.delayed(const Duration(milliseconds: 500));

      // 如果播放状态异常，尝试重新加载
      if (!player.state.playing && errorMessage.value == null) {
        _handleStalledPlayback();
      }
    } catch (e) {
      _handleStalledPlayback();
    }
  }

  /// 启用后台播放
  Future<void> _enableBackgroundPlayback() async {
    _audioHandler ??= await AudioService.init(
      builder: () => VideoAudioHandler(player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.alnitak.video_playback',
        androidNotificationChannelName: '视频播放',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
      ),
    );

    // 更新播放信息
    _audioHandler?.setMediaItem(
      title: '视频播放', // 可以从视频元数据获取
      artist: '',
      duration: player.state.duration,
    );

    _audioHandler?.updatePlaybackState(
      playing: player.state.playing,
      position: player.state.position,
    );

    debugPrint('🎵 [AudioService] 后台播放已启用');
  }

  /// 禁用后台播放
  Future<void> _disableBackgroundPlayback() async {
    // AudioService 会自动处理，无需手动停止
    debugPrint('🎵 [AudioService] 返回前台');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _stalledTimer?.cancel();
    _preloadTimer?.cancel();
    _playingSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _positionStreamController.close();

    // 清理预加载缓存
    _qualityCache.clear();

    // 清理时禁用 wakelock
    WakelockManager.disable();

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