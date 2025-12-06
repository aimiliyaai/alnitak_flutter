import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/hls_service.dart';
import '../services/logger_service.dart';
import '../models/loop_mode.dart';

/// 视频播放器控制器
///
/// 修复记录：
/// 1. 修复清晰度切换时的"跳分片"问题 (10秒偏差)。
/// 2. 移除 open(start) 参数，改为显式 seek。
/// 3. 强制 hr-seek 策略为 absolute，确保 HLS 时间轴精准对齐。
class VideoPlayerController extends ChangeNotifier {
  final HlsService _hlsService = HlsService();
  final LoggerService _logger = LoggerService.instance;

  late final Player player;
  late final VideoController videoController;

  // ============ 状态 Notifiers ============
  final ValueNotifier<List<String>> availableQualities = ValueNotifier([]);
  final ValueNotifier<String?> currentQuality = ValueNotifier(null);
  final ValueNotifier<bool> isLoading = ValueNotifier(true);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<bool> isPlayerInitialized = ValueNotifier(false);
  final ValueNotifier<bool> isSwitchingQuality = ValueNotifier(false);
  final ValueNotifier<LoopMode> loopMode = ValueNotifier(LoopMode.off);
  final ValueNotifier<bool> backgroundPlayEnabled = ValueNotifier(false);

  // ============ 自定义进度流 (防止 UI 跳变) ============
  final StreamController<Duration> _positionStreamController = StreamController.broadcast();
  Stream<Duration> get positionStream => _positionStreamController.stream;

  // ============ 内部状态 ============
  bool _hasTriggeredCompletion = false;
  
  // 重试相关
  bool _isRecovering = false;
  int _retryCount = 0;
  static const int _maxRetryCount = 5;
  
  bool _wasPlayingBeforeBackground = false;
  
  // 切换清晰度状态锁
  bool _isInternallySwitching = false;
  Duration _lastKnownPosition = Duration.zero;

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
  }

  Future<void> initialize({
    required int resourceId,
    double? initialPosition,
  }) async {
    try {
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;
      _retryCount = 0;

      await _loadLoopMode();
      await _loadBackgroundPlaySetting();
      await _configureSegmentRetry();

      availableQualities.value = await _hlsService.getAvailableQualities(resourceId);

      if (availableQualities.value.isEmpty) {
        throw Exception('没有可用的清晰度');
      }

      availableQualities.value = _sortQualitiesDescending(availableQualities.value);
      currentQuality.value = await _getPreferredQuality(availableQualities.value);

      print('📹 使用清晰度: ${currentQuality.value} (${getQualityDisplayName(currentQuality.value!)})');

      await _loadVideo(currentQuality.value!, isInitialLoad: true, initialPosition: initialPosition);

      isLoading.value = false;
      isPlayerInitialized.value = true;

      print('📹 播放器初始化完成');
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
      if (_isInternallySwitching) {
        _positionStreamController.add(_lastKnownPosition);
        return;
      }
      _lastKnownPosition = position;
      _positionStreamController.add(position);
      
      if (!isSwitchingQuality.value) {
        onProgressUpdate?.call(position);
      }
    });

    // 2. 完播监听
    player.stream.completed.listen((completed) {
      if (completed && !_hasTriggeredCompletion && !_isInternallySwitching) {
        _hasTriggeredCompletion = true;
        _handlePlaybackEnd();
      }
    });

    // 3. 播放状态监听
    player.stream.playing.listen((playing) {
      if (playing && _hasTriggeredCompletion) {
        _hasTriggeredCompletion = false;
      }
    });

    // 4. 错误监听
    player.stream.error.listen((error) {
      final errorStr = error.toString().toLowerCase();
      final isSegmentError = errorStr.contains('segment') ||
          errorStr.contains('hls') ||
          errorStr.contains('http') ||
          errorStr.contains('connection') ||
          errorStr.contains('stream') ||
          errorStr.contains('timeout');

      if (isSegmentError) {
        print('⚠️ 分片加载失败，开始重试');
        _retrySegmentLoad(); 
      }
    });
  }

  /// 配置参数：开启 hr-seek (精确跳转)
  Future<void> _configureSegmentRetry() async {
    if (kIsWeb) return;
    try {
      final nativePlayer = player.platform as NativePlayer?;
      if (nativePlayer == null) return;
      
      // 1. 重连策略
      await nativePlayer.setProperty('stream-opts', 'reconnect=1:reconnect_streamed=1:reconnect_delay_max=10');
      
      // 2. 【关键】强制开启绝对精确跳转
      // 'yes' 可能在某些情况下还是会吸附
      // 'absolute' 强制播放器解码到准确时间戳
      await nativePlayer.setProperty('hr-seek', 'absolute');
      
    } catch (e) {
      print('⚠️ 配置失败: $e');
    }
  }

  Future<void> _retrySegmentLoad() async {
    if (_isRecovering || currentQuality.value == null) return;

    if (_retryCount >= _maxRetryCount) {
      print('❌ 已达到最大重试次数，停止重试');
      errorMessage.value = '网络连接失败，请检查网络后重试';
      isLoading.value = false;
      return;
    }

    _isRecovering = true;
    _retryCount++;
    final position = player.state.position;

    try {
      print('🔄 分片重试 (第 $_retryCount/$_maxRetryCount 次): ${position.inSeconds}s');
      await Future.delayed(const Duration(seconds: 30));

      final m3u8Content = await _hlsService.getHlsStreamContent(
        _currentResourceId!,
        currentQuality.value!,
      );
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

      // 修复：先 await
      final media = await Media.memory(m3u8Bytes);
      await player.open(media, play: false);
      
      await _waitForPlayerReady();
      await player.seek(position);

      if (!isSwitchingQuality.value) {
        await player.play();
      }

      print('✅ 重新加载成功');
      _retryCount = 0;
    } catch (e) {
      print('❌ 重试失败: $e');
      if (_retryCount < _maxRetryCount) {
        await Future.delayed(const Duration(seconds: 30));
        _isRecovering = false;
        _retrySegmentLoad();
      } else {
        errorMessage.value = '网络连接失败，请检查网络后重试';
        isLoading.value = false;
      }
    } finally {
      if (_retryCount >= _maxRetryCount || _retryCount == 0) {
        _isRecovering = false;
      }
    }
  }

  /// 加载视频
  Future<void> _loadVideo(String quality, {bool isInitialLoad = false, double? initialPosition}) async {
    try {
      _hasTriggeredCompletion = false;

      final m3u8Content = await _hlsService.getHlsStreamContent(_currentResourceId!, quality);
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

      final media = await Media.memory(m3u8Bytes);
      
      // 初始加载可以使用 seek
      await player.open(media, play: false);
      await _waitForPlayerReady();

      if (isInitialLoad && initialPosition != null) {
        await player.seek(Duration(seconds: initialPosition.toInt()));
      }

      if (!isSwitchingQuality.value) {
        await player.play();
      }

      print('✅ 视频加载成功: $quality');
    } catch (e) {
      rethrow;
    }
  }

  /// 切换清晰度 (修复跳进度核心逻辑)
  Future<void> changeQuality(String quality) async {
    if (currentQuality.value == quality || isSwitchingQuality.value) return;

    try {
      _hasTriggeredCompletion = false;
      isSwitchingQuality.value = true;
      _isInternallySwitching = true; // 开启拦截锁

      print('🔄 切换清晰度: $quality');

      final wasPlaying = player.state.playing;
      // 记录精确位置
      _lastKnownPosition = player.state.position;
      print('📍 锚定位置: ${_lastKnownPosition.inSeconds}s (ms: ${_lastKnownPosition.inMilliseconds})');

      if (wasPlaying) {
        await player.pause();
      }

      final m3u8Content = await _hlsService.getHlsStreamContent(_currentResourceId!, quality);
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

      final media = await Media.memory(m3u8Bytes);
      
      // 【核心修复】
      // 1. 不使用 extras: {'start': ...}，因为这可能导致吸附到最近的关键帧。
      // 2. 先 open，加载元数据。
      await player.open(media, play: false);

      // 3. 等待元数据加载完成 (Duration > 0)
      await _waitForPlayerReady();
      
      // 4. 显式 Seek
      // 因为开启了 hr-seek=absolute，这里的 seek 将会非常精确
      await player.seek(_lastKnownPosition);
      
      // 5. 缓冲等待
      // 给一点时间让缓冲区填充，避免播放瞬间画面卡顿
      await Future.delayed(const Duration(milliseconds: 300));

      currentQuality.value = quality;
      _isInternallySwitching = false; // 解除拦截锁
      isSwitchingQuality.value = false;

      await _savePreferredQuality(quality);

      if (wasPlaying) {
        await player.play();
      }

      onQualityChanged?.call(quality);
      print('✅ 切换完成');
    } catch (e) {
      _isInternallySwitching = false;
      isSwitchingQuality.value = false;
      _logger.logError(
        message: '切换清晰度失败',
        error: e,
        stackTrace: StackTrace.current,
        context: {'quality': quality},
      );
      rethrow;
    }
  }

  // ============ 辅助方法 ============

  Future<void> _waitForPlayerReady() async {
    int waitCount = 0;
    while (player.state.duration.inSeconds <= 0 && waitCount < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }
  }

  void toggleLoopMode() {
    final newMode = loopMode.value.toggle();
    _saveLoopMode(newMode);
  }

  Future<void> play() async => await player.play();
  Future<void> pause() async => await player.pause();
  Future<void> seek(Duration position) async => await player.seek(position);
  Future<void> setRate(double rate) async => await player.setRate(rate);

  void _handlePlaybackEnd() {
    switch (loopMode.value) {
      case LoopMode.on:
        player.seek(Duration.zero);
        player.play();
        break;
      case LoopMode.off:
        onVideoEnd?.call();
        break;
    }
  }

  // ============ 偏好设置 ============

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

  // ============ 工具方法 ============

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
      if (!backgroundPlayEnabled.value) {
        _wasPlayingBeforeBackground = player.state.playing;
        if (_wasPlayingBeforeBackground) player.pause();
      }
    } else {
      if (!backgroundPlayEnabled.value && _wasPlayingBeforeBackground) {
        player.play();
        _wasPlayingBeforeBackground = false;
      }
    }
  }

  @override
  void dispose() {
    print('📹 [VideoPlayerController] 销毁控制器');
    _positionStreamController.close();
    player.dispose();
    availableQualities.dispose();
    currentQuality.dispose();
    isLoading.dispose();
    errorMessage.dispose();
    isPlayerInitialized.dispose();
    isSwitchingQuality.dispose();
    loopMode.dispose();
    backgroundPlayEnabled.dispose();
    super.dispose();
  }
}