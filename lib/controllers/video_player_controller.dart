import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/hls_service.dart';
import '../services/logger_service.dart';
import '../models/loop_mode.dart';

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

  // ============ 状态 Notifiers ============
  final ValueNotifier<List<String>> availableQualities = ValueNotifier([]);
  final ValueNotifier<String?> currentQuality = ValueNotifier(null);
  final ValueNotifier<bool> isLoading = ValueNotifier(true);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<bool> isPlayerInitialized = ValueNotifier(false);
  final ValueNotifier<bool> isSwitchingQuality = ValueNotifier(false);
  final ValueNotifier<LoopMode> loopMode = ValueNotifier(LoopMode.off);
  final ValueNotifier<bool> backgroundPlayEnabled = ValueNotifier(false);

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
  int _retryCount = 0;
  static const int _maxRetryCount = 5;
  bool _wasPlayingBeforeBackground = false;

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
      await _configurePlayerProperties();

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

/// 配置播放器属性 (关键修复 + 雪花屏修复)
  Future<void> _configurePlayerProperties() async {
    if (kIsWeb) return;
    try {
      final nativePlayer = player.platform as NativePlayer?;
      if (nativePlayer == null) return;

      // 1. 设置 HLS 重连策略
      await nativePlayer.setProperty('stream-opts', 'reconnect=1:reconnect_streamed=1:reconnect_delay_max=10');

      // 2. 【关键】强制开启绝对精确跳转
      await nativePlayer.setProperty('hr-seek', 'absolute');

      // ============ 3. 新增：修复画面雪花/花屏问题 ============
      
      // 方案 A (推荐): 使用 auto-copy 模式
      // 原理：将解码后的帧从 GPU 显存拷贝回内存再渲染。
      // 优点：能解决绝大多数因显驱兼容性导致的画面破碎/雪花，且保留了硬件加速的性能优势。
      await nativePlayer.setProperty('hwdec', 'auto-copy');

      // 方案 B (辅助): 关闭直接渲染 (Direct Rendering)
      // 原理：某些 Android 设备在使用 mediacodec 直接渲染到 Surface 时会出错。
      await nativePlayer.setProperty('vd-lavc-dr', 'no');
      
      // 方案 C (仅作为最后手段): 纯软解
      // 如果上面两个配置加上后依然有雪花，解开下面这行的注释，强制使用 CPU 解码。
      // 缺点：发热大，耗电快，4K视频可能会卡顿。
      // await nativePlayer.setProperty('hwdec', 'no'); 

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
    
    print('⏳ 准备切换: $quality (Epoch: $myEpoch) 锚点: ${_anchorPosition!.inSeconds}s');

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

  /// 执行真正的切换逻辑 (修复暂停自动播放问题)
  Future<void> _performSwitch(String quality, Duration seekPos) async {
    print('🚀 开始执行切换: $quality -> 位置: ${seekPos.inSeconds}s');
    
    // 1. 获取当前是否正在播放（这是判断的依据）
    final bool wasPlaying = player.state.playing;

    // 2. 无论当前状态如何，先暂停播放器 (停止缓冲旧数据)
    //    这能确保后续操作都在一个干净的暂停状态下开始
    await player.pause();

    final m3u8Content = await _hlsService.getHlsStreamContent(_currentResourceId!, quality);
    final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

    // 【修复】await Media.memory，且不传 extras
    final media = await Media.memory(m3u8Bytes);

    // 3. 打开新视频，显式指定不播放
    await player.open(media, play: false);

    // 等待加载就绪
    await _waitForPlayerReady();
    
    // 显式 Seek (因为开启了 hr-seek=absolute，这里会非常准)
    await player.seek(seekPos);
    
    // 【核心修复】：
    // 某些平台或配置下，seek 操作可能隐式触发预加载播放状态。
    // 如果之前不是播放状态，这里强制再暂停一次，确保万无一失。
    if (!wasPlaying) {
      await player.pause();
    }

    // 5. 缓冲等待 (防止画面闪烁)
    await Future.delayed(const Duration(milliseconds: 500));

    // 更新状态
    currentQuality.value = quality;
    await _savePreferredQuality(quality);

    // 解除冻结
    _isFreezingPosition = false;
    isSwitchingQuality.value = false;
    // 【关键】清空锚点，为下一次全新的切换做准备
    _anchorPosition = null;

    // 6. 只有当之前确实在播放时，才恢复播放
    if (wasPlaying) {
      print('▶️ 恢复播放');
      await player.play();
    } else {
      print('⏸️ 保持暂停');
    }

    onQualityChanged?.call(quality);
    print('✅ 切换完成');
  }

  // ============ 基础加载与重试逻辑 ============

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

      // 【修复】await Media.memory
      final media = await Media.memory(m3u8Bytes);

      await player.open(media, play: false);
      await _waitForPlayerReady();
      await player.seek(position);

      // 重试逻辑中，只有非切换状态下才自动播放，避免冲突
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

  Future<void> _loadVideo(String quality, {bool isInitialLoad = false, double? initialPosition}) async {
    try {
      _hasTriggeredCompletion = false;
      final m3u8Content = await _hlsService.getHlsStreamContent(_currentResourceId!, quality);
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

      // 【修复】await Media.memory
      final media = await Media.memory(m3u8Bytes);

      // 初始加载根据是否在切换中决定是否播放，通常初始化是自动播放
      await player.open(media, play: !isSwitchingQuality.value);
      
      await _waitForPlayerReady();

      if (isInitialLoad && initialPosition != null) {
        await player.seek(Duration(seconds: initialPosition.toInt()));
      }
      print('✅ 视频加载成功: $quality');
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
    _debounceTimer?.cancel();
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