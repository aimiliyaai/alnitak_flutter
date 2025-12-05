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
/// 负责管理播放器的核心业务逻辑：
/// - 播放器生命周期管理
/// - 清晰度切换和偏好保存
/// - 错误重试和分片恢复
/// - 循环模式和后台播放
/// - 播放状态监听
class VideoPlayerController extends ChangeNotifier {
  final HlsService _hlsService = HlsService();
  final LoggerService _logger = LoggerService.instance;

  // media_kit 播放器
  late final Player player;
  late final VideoController videoController;

  // 播放状态
  final ValueNotifier<List<String>> availableQualities = ValueNotifier([]);
  final ValueNotifier<String?> currentQuality = ValueNotifier(null);
  final ValueNotifier<bool> isLoading = ValueNotifier(true);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<bool> isPlayerInitialized = ValueNotifier(false);
  final ValueNotifier<bool> isSwitchingQuality = ValueNotifier(false);
  final ValueNotifier<LoopMode> loopMode = ValueNotifier(LoopMode.off);
  final ValueNotifier<bool> backgroundPlayEnabled = ValueNotifier(false);

  // 内部状态
  bool _hasTriggeredCompletion = false;
  bool _isRecovering = false;
  int _retryCount = 0;
  static const int _maxRetryCount = 5;
  bool _wasPlayingBeforeBackground = false;

  // SharedPreferences 键名
  static const String _preferredQualityKey = 'preferred_video_quality_display_name';
  static const String _loopModeKey = 'video_loop_mode';
  static const String _backgroundPlayKey = 'background_play_enabled';

  // 当前资源ID
  int? _currentResourceId;

  // 回调
  VoidCallback? onVideoEnd;
  Function(Duration position)? onProgressUpdate;
  Function(String quality)? onQualityChanged;

  VideoPlayerController() {
    // 创建播放器实例
    player = Player(
      configuration: const PlayerConfiguration(
        title: '',
        bufferSize: 32 * 1024 * 1024, // 32MB 缓冲区
        logLevel: MPVLogLevel.warn,
      ),
    );
    videoController = VideoController(player);
    _setupPlayerListeners();
  }

  /// 初始化播放器
  Future<void> initialize({
    required int resourceId,
    double? initialPosition,
  }) async {
    try {
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;
      _retryCount = 0; // 重置重试计数

      // 加载设置
      await _loadLoopMode();
      await _loadBackgroundPlaySetting();

      // 配置分片重试
      await _configureSegmentRetry();

      // 获取可用清晰度列表
      availableQualities.value = await _hlsService.getAvailableQualities(resourceId);

      if (availableQualities.value.isEmpty) {
        throw Exception('没有可用的清晰度');
      }

      // 对清晰度列表进行排序(从高到低)
      availableQualities.value = _sortQualitiesDescending(availableQualities.value);

      // 选择默认清晰度
      currentQuality.value = await _getPreferredQuality(availableQualities.value);

      print('📹 使用清晰度: ${currentQuality.value} (${getQualityDisplayName(currentQuality.value!)})');

      // 加载视频
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

  /// 设置播放器事件监听
  void _setupPlayerListeners() {
    // 监听播放进度
    player.stream.position.listen((position) {
      if (!isSwitchingQuality.value) {
        onProgressUpdate?.call(position);
      }
    });

    // 使用 completed 事件检测完播
    player.stream.completed.listen((completed) {
      if (completed && !_hasTriggeredCompletion) {
        print('📹 检测到视频播放结束 (completed 事件)');
        _hasTriggeredCompletion = true;
        _handlePlaybackEnd();
      }
    });

    // 监听播放状态
    player.stream.playing.listen((playing) {
      print('📹 ${playing ? "开始播放" : "暂停播放"}');
      if (playing && _hasTriggeredCompletion) {
        _hasTriggeredCompletion = false;
        print('📹 重置完播标志');
      }
    });

    // 监听缓冲状态
    player.stream.buffering.listen((buffering) {
      if (buffering) {
        print('⏸️ 播放缓冲中...');
      } else {
        print('▶️ 缓冲完成，继续播放');
      }
    });

    // 监听错误并重试
    player.stream.error.listen((error) {
      final errorStr = error.toString().toLowerCase();
      final isSegmentError = errorStr.contains('segment') ||
          errorStr.contains('hls') ||
          errorStr.contains('http') ||
          errorStr.contains('connection') ||
          errorStr.contains('stream') ||
          errorStr.contains('timeout');

      _logger.logError(
        message: '播放器错误${isSegmentError ? '(分片)' : ''}',
        error: error,
        stackTrace: StackTrace.current,
        context: {'resourceId': _currentResourceId},
      );

      if (isSegmentError) {
        print('⚠️ 分片加载失败，开始重试');
        _retrySegmentLoad();
      }
    });
  }

  /// 配置分片重试
  Future<void> _configureSegmentRetry() async {
    if (kIsWeb) return;

    try {
      final nativePlayer = player.platform as NativePlayer?;
      if (nativePlayer == null) return;

      await nativePlayer.setProperty(
        'stream-opts',
        'reconnect=1:reconnect_streamed=1:reconnect_delay_max=10',
      );

      print('✅ 已配置分片重试');
    } catch (e) {
      print('⚠️ 配置失败: $e');
    }
  }

  /// 分片加载失败时重新加载
  Future<void> _retrySegmentLoad() async {
    if (_isRecovering || currentQuality.value == null) return;

    if (_retryCount >= _maxRetryCount) {
      print('❌ 已达到最大重试次数 ($_maxRetryCount)，停止重试');
      errorMessage.value = '网络连接失败，请检查网络后重试';
      isLoading.value = false;
      return;
    }

    _isRecovering = true;
    _retryCount++;
    final position = player.state.position;

    try {
      print('🔄 分片加载失败，重新加载 (第 $_retryCount/$_maxRetryCount 次): ${position.inSeconds}s');

      await Future.delayed(const Duration(seconds: 1));

      final m3u8Content = await _hlsService.getHlsStreamContent(
        _currentResourceId!,
        currentQuality.value!,
      );
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

      await player.open(await Media.memory(m3u8Bytes), play: false);
      await _waitForPlayerReady();
      await player.seek(position);

      if (!isSwitchingQuality.value) {
        await player.play();
      }

      print('✅ 重新加载成功');
      _retryCount = 0;
    } catch (e) {
      print('❌ 重新加载失败 (第 $_retryCount/$_maxRetryCount 次): $e');
      if (_retryCount < _maxRetryCount) {
        await Future.delayed(const Duration(seconds: 2));
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

      await player.open(await Media.memory(m3u8Bytes), play: false);
      await _waitForPlayerReady();

      if (isInitialLoad && initialPosition != null) {
        final initialDuration = Duration(seconds: initialPosition.toInt());
        if (player.state.duration.inSeconds > 0 &&
            initialDuration.inSeconds >= player.state.duration.inSeconds - 2) {
          print('📺 检测到位置接近末尾，从头开始');
          await player.seek(Duration.zero);
          _hasTriggeredCompletion = false;
        } else {
          await player.seek(initialDuration);
        }
      }

      if (!isSwitchingQuality.value) {
        await player.play();
      }

      print('✅ 视频加载成功: $quality');
    } catch (e) {
      _logger.logError(
        message: '加载视频失败',
        error: e,
        stackTrace: StackTrace.current,
        context: {'resourceId': _currentResourceId, 'quality': quality},
      );
      rethrow;
    }
  }

  /// 等待播放器准备就绪
  Future<void> _waitForPlayerReady() async {
    print('⏳ 等待播放器准备就绪...');

    int bufferingCount = 0;
    await for (final buffering in player.stream.buffering) {
      if (buffering) {
        bufferingCount++;
        print('📦 正在缓冲... ($bufferingCount)');
      } else {
        print('✅ 缓冲完成');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    int waitCount = 0;
    const maxWaitCount = 50;
    while (player.state.duration.inSeconds <= 0 && waitCount < maxWaitCount) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (player.state.duration.inSeconds > 0) {
      print('📺 视频时长: ${player.state.duration.inSeconds}秒');
    } else {
      print('⚠️ 无法获取视频时长，继续播放');
    }

    print('🎬 播放器准备完成');
  }

  /// 切换清晰度
  Future<void> changeQuality(String quality) async {
    if (currentQuality.value == quality || isSwitchingQuality.value) return;

    try {
      _hasTriggeredCompletion = false;
      isSwitchingQuality.value = true;

      print('🔄 切换清晰度: $quality');

      final wasPlaying = player.state.playing;
      final pos1 = player.state.position;

      if (wasPlaying) {
        await player.pause();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final pos2 = player.state.position;
      final targetPosition = pos1.inSeconds <= pos2.inSeconds ? pos1 : pos2;
      print('📍 位置冻结: pos1=${pos1.inSeconds}s, pos2=${pos2.inSeconds}s, 使用=${targetPosition.inSeconds}s');

      final m3u8Content = await _hlsService.getHlsStreamContent(_currentResourceId!, quality);
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

      await player.open(await Media.memory(m3u8Bytes), play: false);
      await _waitForPlayerReady();
      await player.seek(targetPosition);
      await Future.delayed(const Duration(milliseconds: 200));

      currentQuality.value = quality;
      isSwitchingQuality.value = false;

      await _savePreferredQuality(quality);

      if (wasPlaying) {
        await player.play();
      }

      onQualityChanged?.call(quality);
      print('✅ 切换完成');
    } catch (e) {
      _logger.logError(
        message: '切换清晰度失败',
        error: e,
        stackTrace: StackTrace.current,
        context: {'quality': quality},
      );
      isSwitchingQuality.value = false;
      rethrow;
    }
  }

  /// 切换循环模式
  void toggleLoopMode() {
    final newMode = loopMode.value.toggle();
    _saveLoopMode(newMode);
  }

  /// 播放
  Future<void> play() async {
    await player.play();
  }

  /// 暂停
  Future<void> pause() async {
    await player.pause();
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  /// 设置播放速度
  Future<void> setRate(double rate) async {
    await player.setRate(rate);
  }

  /// 处理播放结束
  void _handlePlaybackEnd() {
    print('🔁 播放结束，循环模式: ${loopMode.value.displayName}');

    switch (loopMode.value) {
      case LoopMode.on:
        print('🔂 单集循环：重新播放');
        _hasTriggeredCompletion = false;
        player.seek(Duration.zero);
        player.play();
        break;
      case LoopMode.off:
        print('⏹️ 循环已关闭：停止播放');
        onVideoEnd?.call();
        break;
    }
  }

  /// 处理应用生命周期变化
  void handleAppLifecycleState(bool isPaused) {
    if (isPaused) {
      print('📱 应用进入后台');
      if (!backgroundPlayEnabled.value) {
        _wasPlayingBeforeBackground = player.state.playing;
        if (_wasPlayingBeforeBackground) {
          print('⏸️ 后台播放未启用，暂停播放');
          player.pause();
        }
      } else {
        print('▶️ 后台播放已启用，继续播放');
      }
    } else {
      print('📱 应用返回前台');
      if (!backgroundPlayEnabled.value && _wasPlayingBeforeBackground) {
        print('▶️ 恢复播放');
        player.play();
        _wasPlayingBeforeBackground = false;
      }
    }
  }

  // ============ 偏好设置相关 ============

  Future<void> _loadLoopMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_loopModeKey);
    loopMode.value = LoopModeExtension.fromString(savedMode);
  }

  Future<void> _saveLoopMode(LoopMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loopModeKey, mode.toSavedString());
    loopMode.value = mode;
    print('💾 已保存循环模式: ${mode.displayName}');
  }

  Future<void> _loadBackgroundPlaySetting() async {
    final prefs = await SharedPreferences.getInstance();
    backgroundPlayEnabled.value = prefs.getBool(_backgroundPlayKey) ?? false;
    print('🔊 后台播放设置: ${backgroundPlayEnabled.value ? "启用" : "禁用"}');
  }

  Future<String> _getPreferredQuality(List<String> availableQualitiesList) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferredDisplayName = prefs.getString(_preferredQualityKey);

      print('📝 清晰度偏好检查:');
      print('   - 保存的偏好: $preferredDisplayName');
      print('   - 可用清晰度: ${availableQualitiesList.map((q) => getQualityDisplayName(q)).toList()}');

      if (preferredDisplayName != null && preferredDisplayName.isNotEmpty) {
        for (final quality in availableQualitiesList) {
          if (getQualityDisplayName(quality) == preferredDisplayName) {
            print('   ✅ 完全匹配: $quality ($preferredDisplayName)');
            return quality;
          }
        }

        print('   ⚠️ 未找到完全匹配的 $preferredDisplayName，尝试降级匹配...');
        final fallbackQuality = _findFallbackQuality(preferredDisplayName, availableQualitiesList);
        if (fallbackQuality != null) {
          print('   ✅ 降级匹配: $fallbackQuality (${getQualityDisplayName(fallbackQuality)})');
          return fallbackQuality;
        }
      } else {
        print('   ℹ️ 未找到保存的清晰度偏好（首次使用）');
      }

      final defaultQuality = HlsService.getDefaultQuality(availableQualitiesList);
      print('   📌 使用默认清晰度: $defaultQuality (${getQualityDisplayName(defaultQuality)})');
      return defaultQuality;
    } catch (e) {
      print('⚠️ 读取清晰度偏好失败: $e');
      return HlsService.getDefaultQuality(availableQualitiesList);
    }
  }

  String? _findFallbackQuality(String preferredDisplayName, List<String> availableQualitiesList) {
    final fallbackOrder = _getFallbackOrder(preferredDisplayName);
    print('   降级顺序: ${fallbackOrder.join(" → ")}');

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
      print('💾 已保存全局清晰度偏好: $displayName');
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

  @override
  void dispose() {
    print('📹 [VideoPlayerController] 销毁控制器');
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
