import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../services/hls_service.dart';
import '../../../services/logger_service.dart';
import '../../../models/loop_mode.dart';

/// 视频播放器组件
///
/// 使用 media_kit (基于 AndroidX Media3) 播放 HLS 视频流
/// 使用 media_kit 原生控制器
/// 功能:
/// - 清晰度切换(保持播放位置)
/// - 倍速播放
/// - 全屏控制
/// - 播放进度记忆
class MediaPlayerWidget extends StatefulWidget {
  final int resourceId; // 视频资源ID
  final double? initialPosition; // 初始播放位置（秒）
  final VoidCallback? onVideoEnd; // 视频播放结束回调
  final Function(Duration position)? onProgressUpdate; // 播放进度更新回调（每秒回调一次）
  final Function(String quality)? onQualityChanged; // 清晰度切换回调
  final String? title; // 视频标题
  final VoidCallback? onFullscreenToggle; // 全屏切换回调
  final int? totalParts; // 总分P数（用于列表循环）
  final int? currentPart; // 当前分P（用于列表循环）
  final Function(int part)? onPartChange; // 分P切换回调（用于列表循环）

  const MediaPlayerWidget({
    super.key,
    required this.resourceId,
    this.initialPosition,
    this.onVideoEnd,
    this.onProgressUpdate,
    this.onQualityChanged,
    this.title,
    this.onFullscreenToggle,
    this.totalParts,
    this.currentPart,
    this.onPartChange,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> with WidgetsBindingObserver {
  final HlsService _hlsService = HlsService();
  final LoggerService _logger = LoggerService.instance;

  // media_kit 播放器和控制器
  late final Player _player;
  late final VideoController _videoController;

  // 播放状态
  List<String> _availableQualities = [];
  String? _currentQuality;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isPlayerInitialized = false;
  bool _isSwitchingQuality = false;
  bool _hasTriggeredCompletion = false; // 标记是否已触发完播回调
  bool _isRecovering = false; // 分片恢复标志

  // 循环模式（默认关闭）
  LoopMode _loopMode = LoopMode.off;

  // 后台播放设置
  bool _backgroundPlayEnabled = false;
  bool _wasPlayingBeforeBackground = false; // 记录进入后台前的播放状态

  // 使用 ValueNotifier 来管理清晰度状态，确保UI能够响应变化
  final ValueNotifier<String?> _qualityNotifier = ValueNotifier<String?>(null);

  // 使用 ValueNotifier 来管理循环模式状态，确保UI能够响应变化
  final ValueNotifier<LoopMode> _loopModeNotifier = ValueNotifier<LoopMode>(LoopMode.off);

  // SharedPreferences 键名（全局清晰度偏好 - 保存显示名称如 1080p60）
  static const String _preferredQualityKey = 'preferred_video_quality_display_name';
  static const String _loopModeKey = 'video_loop_mode';
  static const String _backgroundPlayKey = 'background_play_enabled';

  @override
  void initState() {
    super.initState();
    print('📹 [initState] MediaPlayerWidget 初始化 - resourceId: ${widget.resourceId}, hashCode: $hashCode');
    // 创建播放器实例，配置缓冲策略
    // media_kit 基于 AndroidX Media3 (Android) 和底层播放器
    // 通过增大 bufferSize 来提升缓冲能力，确保更流畅的播放体验
    _player = Player(
      configuration: const PlayerConfiguration(
        // 标题（用于通知）
        title: '',
        // 启用更大的缓冲区以优化 HLS 播放
        // 128MB 缓冲区可以缓存更多 TS 分片，减少卡顿
        bufferSize: 128 * 1024 * 1024, // 128MB 缓冲区
        // 日志级别
        logLevel: MPVLogLevel.warn,
      ),
    );
    _videoController = VideoController(_player);
    _loadLoopMode();
    _loadBackgroundPlaySetting();
    _setupPlayerListeners();
    _initializePlayer();
    // 添加生命周期监听
    WidgetsBinding.instance.addObserver(this);
    // 启用屏幕唤醒锁（防止播放时息屏）
    WakelockPlus.enable();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
        // 应用进入后台
        print('📱 应用进入后台');
        if (!_backgroundPlayEnabled) {
          // 如果未启用后台播放，记录当前播放状态并暂停
          _wasPlayingBeforeBackground = _player.state.playing;
          if (_wasPlayingBeforeBackground) {
            print('⏸️ 后台播放未启用，暂停播放');
            _player.pause();
          }
        } else {
          print('▶️ 后台播放已启用，继续播放');
        }
        break;

      case AppLifecycleState.resumed:
        // 应用返回前台
        print('📱 应用返回前台');
        if (!_backgroundPlayEnabled && _wasPlayingBeforeBackground) {
          // 如果之前因为后台而暂停，现在恢复播放
          print('▶️ 恢复播放');
          _player.play();
          _wasPlayingBeforeBackground = false;
        }
        break;

      default:
        break;
    }
  }

  /// 加载后台播放设置
  Future<void> _loadBackgroundPlaySetting() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_backgroundPlayKey) ?? false;
    if (mounted) {
      setState(() {
        _backgroundPlayEnabled = enabled;
      });
    }
    print('🔊 后台播放设置: ${enabled ? "启用" : "禁用"}');
  }

  /// 加载循环模式
  Future<void> _loadLoopMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_loopModeKey);
    final mode = LoopModeExtension.fromString(savedMode);
    setState(() {
      _loopMode = mode;
    });
    _loopModeNotifier.value = mode; // 同步到 notifier
  }

  /// 保存循环模式
  Future<void> _saveLoopMode(LoopMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loopModeKey, mode.toSavedString());
    setState(() {
      _loopMode = mode;
    });
    _loopModeNotifier.value = mode; // 同步到 notifier
    print('💾 已保存循环模式: ${mode.displayName}');
  }

  /// 处理播放结束
  void _handlePlaybackEnd() {
    print('🔁 播放结束，循环模式: ${_loopMode.displayName}');

    switch (_loopMode) {
      case LoopMode.on:
        // 单集循环：从头播放当前视频
        print('🔂 单集循环：重新播放');
        _hasTriggeredCompletion = false; // 先重置标志
        _player.seek(Duration.zero);
        _player.play();
        break;

      case LoopMode.off:
        // 关闭循环：停止播放
        print('⏹️ 循环已关闭：停止播放');
        widget.onVideoEnd?.call();
        break;
    }
  }

  @override
  void deactivate() {
    print('📹 [deactivate] Widget 被停用但未销毁 - resourceId: ${widget.resourceId}');
    super.deactivate();
  }

  @override
  void didUpdateWidget(MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    print('📹 [didUpdateWidget] old resourceId: ${oldWidget.resourceId}, new resourceId: ${widget.resourceId}');
    // 只有当 resourceId 改变时才重新初始化播放器
    // 这样可以避免全屏切换导致的重建
    if (oldWidget.resourceId != widget.resourceId) {
      print('📹 [didUpdateWidget] resourceId 改变，重新初始化播放器');
      _initializePlayer();
    } else {
      print('📹 [didUpdateWidget] resourceId 未改变，跳过重新初始化');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 每次重建时重新加载后台播放设置（以防用户在设置页修改）
    _loadBackgroundPlaySetting();
  }

  /// 配置 libmpv 分片重试（不跳过失败的分片）
  Future<void> _configureSegmentRetry() async {
    if (kIsWeb) return;

    try {
      final nativePlayer = _player.platform as NativePlayer?;
      if (nativePlayer == null) return;

      // 配置 FFmpeg 自动重连（失败后持续重试）
      await nativePlayer.setProperty(
        'stream-opts',
        'reconnect=1:reconnect_streamed=1:reconnect_delay_max=10',
      );

      print('✅ 已配置分片重试');
    } catch (e) {
      print('⚠️ 配置失败: $e');
    }
  }

  /// 分片加载失败时重新加载播放列表（不跳过）
  Future<void> _retrySegmentLoad() async {
    if (_isRecovering || _currentQuality == null) return;

    _isRecovering = true;
    final position = _player.state.position;

    try {
      print('🔄 分片加载失败，重新加载: ${position.inSeconds}s');

      // 等待网络稳定
      await Future.delayed(const Duration(seconds: 1));

      // 重新加载 M3U8
      final m3u8Content = await _hlsService.getHlsStreamContent(
        widget.resourceId,
        _currentQuality!,
      );
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

      await _player.open(await Media.memory(m3u8Bytes), play: false);
      await _waitForPlayerReady();
      await _player.seek(position);

      if (!_isSwitchingQuality) {
        await _player.play();
      }

      print('✅ 重新加载成功');
    } catch (e) {
      print('❌ 重新加载失败，将再次重试: $e');
      // 失败后再次重试，直到成功
      await Future.delayed(const Duration(seconds: 2));
      _retrySegmentLoad();
    } finally {
      _isRecovering = false;
    }
  }

  /// 设置播放器事件监听
  void _setupPlayerListeners() {
    // 监听播放进度，并在此判断是否完播
    _player.stream.position.listen((position) {
      if (mounted && !_isSwitchingQuality) {
        // 回调进度更新
        if (widget.onProgressUpdate != null) {
          widget.onProgressUpdate!(position);
        }

        // 判断是否完播：当前位置 >= 总时长 - 1秒 且播放器已停止
        final duration = _player.state.duration;
        final isPlaying = _player.state.playing;

        if (duration.inSeconds > 0 &&
            position.inSeconds >= duration.inSeconds - 1 &&
            !isPlaying &&
            !_hasTriggeredCompletion) {
          print('📹 检测到视频播放结束: position=${position.inSeconds}s, duration=${duration.inSeconds}s, playing=$isPlaying');
          _hasTriggeredCompletion = true;
          _handlePlaybackEnd();
        }
      }
    });

    // 监听播放状态（用于重置完播标志）
    _player.stream.playing.listen((playing) {
      print('📹 ${playing ? "开始播放" : "暂停播放"}');
      // 当重新开始播放时，重置完播标志
      if (playing && _hasTriggeredCompletion) {
        _hasTriggeredCompletion = false;
        print('📹 重置完播标志');
      }
    });

    // 监听缓冲状态（用于调试和优化）
    _player.stream.buffering.listen((buffering) {
      if (buffering) {
        print('⏸️ 播放缓冲中...');
      } else {
        print('▶️ 缓冲完成，继续播放');
      }
    });

    // 监听错误并重试分片加载
    _player.stream.error.listen((error) {
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
        context: {'resourceId': widget.resourceId},
      );

      if (isSegmentError && mounted) {
        print('⚠️ 分片加载失败，开始重试');
        _retrySegmentLoad();
      }
    });
  }

  /// 初始化播放器
  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // 1. 获取可用清晰度列表
      _availableQualities = await _hlsService.getAvailableQualities(widget.resourceId);

      if (_availableQualities.isEmpty) {
        throw Exception('没有可用的清晰度');
      }

      // 1.5. 对清晰度列表进行排序(从高到低)
      _availableQualities = _sortQualitiesDescending(_availableQualities);

      // 2. 选择默认清晰度（优先使用记忆的清晰度，其次720P）
      _currentQuality = await _getPreferredQuality(_availableQualities);
      _qualityNotifier.value = _currentQuality; // 同步到 notifier

      print('📹 使用清晰度: $_currentQuality (${getQualityDisplayName(_currentQuality!)})');

      // 2.5. 配置分片重试
      await _configureSegmentRetry();

      // 3. 加载视频
      await _loadVideo(_currentQuality!, isInitialLoad: true);

      setState(() {
        _isLoading = false;
        _isPlayerInitialized = true;
      });

      print('📹 播放器初始化完成');
    } catch (e) {
      _logger.logError(
        message: '初始化播放器失败',
        error: e,
        stackTrace: StackTrace.current,
        context: {'resourceId': widget.resourceId},
      );
      setState(() {
        _isLoading = false;
        _errorMessage = '视频加载失败: $e';
      });
    }
  }

  /// 获取用户偏好的清晰度
  /// 根据保存的显示名称（如 1080p60）智能匹配可用清晰度，支持降级策略
  /// 降级顺序：1080p60 → 1080p → 720p60 → 720p → 480p → 360p
  Future<String> _getPreferredQuality(List<String> availableQualities) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferredDisplayName = prefs.getString(_preferredQualityKey);

      print('📝 清晰度偏好检查:');
      print('   - 保存的偏好: $preferredDisplayName');
      print('   - 可用清晰度: ${availableQualities.map((q) => getQualityDisplayName(q)).toList()}');

      // 如果有保存的偏好，尝试智能匹配（支持降级）
      if (preferredDisplayName != null && preferredDisplayName.isNotEmpty) {
        // 1. 先尝试完全匹配
        for (final quality in availableQualities) {
          if (getQualityDisplayName(quality) == preferredDisplayName) {
            print('   ✅ 完全匹配: $quality ($preferredDisplayName)');
            return quality;
          }
        }

        // 2. 没有完全匹配，尝试智能降级
        print('   ⚠️ 未找到完全匹配的 $preferredDisplayName，尝试降级匹配...');
        final fallbackQuality = _findFallbackQuality(preferredDisplayName, availableQualities);
        if (fallbackQuality != null) {
          print('   ✅ 降级匹配: $fallbackQuality (${getQualityDisplayName(fallbackQuality)})');
          return fallbackQuality;
        }
      } else {
        print('   ℹ️ 未找到保存的清晰度偏好（首次使用）');
      }

      // 3. 没有偏好或降级失败，使用默认清晰度（720P优先）
      final defaultQuality = HlsService.getDefaultQuality(availableQualities);
      print('   📌 使用默认清晰度: $defaultQuality (${getQualityDisplayName(defaultQuality)})');
      return defaultQuality;
    } catch (e) {
      print('⚠️ 读取清晰度偏好失败: $e');
      return HlsService.getDefaultQuality(availableQualities);
    }
  }

  /// 智能降级匹配清晰度
  /// 例如：用户偏好1080p60，降级顺序为 1080p → 720p60 → 720p → 480p → 360p
  String? _findFallbackQuality(String preferredDisplayName, List<String> availableQualities) {
    // 定义降级规则：从用户偏好逐步降级
    final fallbackOrder = _getFallbackOrder(preferredDisplayName);

    print('   降级顺序: ${fallbackOrder.join(" → ")}');

    // 按降级顺序查找第一个可用的清晰度
    for (final fallbackName in fallbackOrder) {
      for (final quality in availableQualities) {
        if (getQualityDisplayName(quality) == fallbackName) {
          return quality;
        }
      }
    }

    return null;
  }

  /// 获取清晰度的降级顺序
  /// 规则：
  /// - 1080p60 → 1080p → 720p60 → 720p → 480p → 360p
  /// - 1080p → 720p60 → 720p → 480p → 360p
  /// - 720p60 → 720p → 480p → 360p
  /// - 720p → 480p → 360p
  List<String> _getFallbackOrder(String preferredDisplayName) {
    // 定义通用降级链：从高到低
    const allQualities = ['1080p60', '1080p', '720p60', '720p', '480p', '360p'];

    // 找到用户偏好在降级链中的位置
    final startIndex = allQualities.indexOf(preferredDisplayName);

    // 如果找不到（比如用户偏好是2K、4K等），返回完整降级链
    if (startIndex == -1) {
      return List.from(allQualities);
    }

    // 返回从偏好之后开始的降级顺序（不包括偏好本身，因为已经尝试过完全匹配了）
    return allQualities.sublist(startIndex + 1);
  }

  /// 保存用户偏好的清晰度（全局设置）
  /// 保存显示名称（如 1080p60）而非具体编码参数
  Future<void> _savePreferredQuality(String quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final displayName = getQualityDisplayName(quality);
      await prefs.setString(_preferredQualityKey, displayName);
      print('💾 已保存全局清晰度偏好: $displayName');
      print('   下次播放任何视频时将优先使用 $displayName 清晰度');
    } catch (e) {
      print('⚠️ 保存清晰度偏好失败: $e');
    }
  }

  /// 加载视频
  Future<void> _loadVideo(String quality, {bool isInitialLoad = false}) async {
    try {
      // 重置完播标志（加载新视频时）
      _hasTriggeredCompletion = false;

      // 1. 获取 HLS 内容
      final m3u8Content = await _hlsService.getHlsStreamContent(widget.resourceId, quality);
      // 将 m3u8 内容编码为字节数组（Uint8List 来自 flutter/services.dart）
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

      // 2. 使用 media_kit 从内存播放视频
      await _player.open(
        await Media.memory(m3u8Bytes),
        play: false, // 不自动播放，手动控制播放时机
      );

      // 3. 等待视频准备好
      await _waitForPlayerReady();

      // 4. 如果是初始加载且有初始播放位置，跳转到该位置
      if (isInitialLoad && widget.initialPosition != null) {
        final initialDuration = Duration(seconds: widget.initialPosition!.toInt());
        // 如果初始位置接近视频末尾（距离结束<2秒），说明上次已看完，应该从头开始
        if (_player.state.duration.inSeconds > 0 &&
            initialDuration.inSeconds >= _player.state.duration.inSeconds - 2) {
          print('📺 检测到位置接近末尾(${initialDuration.inSeconds}s/${_player.state.duration.inSeconds}s)，从头开始');
          await _player.seek(Duration.zero);
          _hasTriggeredCompletion = false; // 重置完播标志
        } else {
          await _player.seek(initialDuration);
        }
      }

      // 5. 开始播放
      if (!_isSwitchingQuality) {
        await _player.play();
      }

      print('✅ 视频加载成功: $quality');
    } catch (e) {
      _logger.logError(
        message: '加载视频失败',
        error: e,
        stackTrace: StackTrace.current,
        context: {
          'resourceId': widget.resourceId,
          'quality': quality,
        },
      );
      rethrow;
    }
  }

  /// 等待播放器准备就绪 - 确保充分缓冲
  Future<void> _waitForPlayerReady() async {
    print('⏳ 等待播放器准备就绪...');

    // 1. 等待播放器完成初始缓冲
    int bufferingCount = 0;
    await for (final buffering in _player.stream.buffering) {
      if (buffering) {
        bufferingCount++;
        print('📦 正在缓冲... ($bufferingCount)');
      } else {
        print('✅ 缓冲完成');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 2. 等待视频时长信息加载完成
    int waitCount = 0;
    const maxWaitCount = 50; // 最多等待5秒
    while (_player.state.duration.inSeconds <= 0 && waitCount < maxWaitCount) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (_player.state.duration.inSeconds > 0) {
      print('📺 视频时长: ${_player.state.duration.inSeconds}秒');
    } else {
      print('⚠️ 无法获取视频时长，继续播放');
    }

    print('🎬 播放器准备完成');
  }

  /// 获取清晰度的友好显示名称
  /// 参考PC端逻辑: E:\web\alnitak\web\web-client\src\components\video-player\index.vue
  String getQualityDisplayName(String quality) {
    // 静态映射表 - 常见清晰度
    const qualityMap = {
      '640x360_1000k_30': '360p',
      '854x480_1500k_30': '480p',
      '1280x720_3000k_30': '720p',
      '1920x1080_6000k_30': '1080p',
      '1920x1080_8000k_60': '1080p60',
    };

    // 如果在静态映射表中，直接返回
    if (qualityMap.containsKey(quality)) {
      return qualityMap[quality]!;
    }

    // 解析格式: "widthxheight_bitratek_framerate"
    try {
      final parts = quality.split('_');
      if (parts.isEmpty) return quality;

      final resolution = parts[0]; // 如 "1280x720"
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

    // 无法解析时返回原始值
    return quality;
  }

  /// 切换清晰度（保持播放位置） - 优化版
  Future<void> changeQuality(String quality) async {
    if (_currentQuality == quality || _isSwitchingQuality) return;

    try {
      // 重置完播标志（切换清晰度时）
      _hasTriggeredCompletion = false;

      setState(() {
        _isSwitchingQuality = true;
      });

      print('🔄 切换清晰度: $quality');

      // 【完全冻结方案】立即读取→强制暂停→等待→二次读取→取最小值
      final wasPlaying = _player.state.playing;

      // 1. 立即读取第一次位置（播放时可能不准）
      final pos1 = _player.state.position;

      // 2. 强制暂停
      if (wasPlaying) {
        await _player.pause();
        // 等待暂停生效
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // 3. 暂停后再次读取位置
      final pos2 = _player.state.position;

      // 4. 取两次读取的最小值（防止位置前移）
      final targetPosition = pos1.inSeconds <= pos2.inSeconds ? pos1 : pos2;
      print('📍 位置冻结: pos1=${pos1.inSeconds}s, pos2=${pos2.inSeconds}s, 使用=${targetPosition.inSeconds}s');

      // 3. 获取新清晰度
      final m3u8Content = await _hlsService.getHlsStreamContent(widget.resourceId, quality);
      final m3u8Bytes = Uint8List.fromList(utf8.encode(m3u8Content));

      // 4. 快速切换源
      await _player.open(
        await Media.memory(m3u8Bytes),
        play: false,
      );

      // 5. 等待准备就绪
      await _waitForPlayerReady();

      // 6. 精确seek
      await _player.seek(targetPosition);

      // 7. 等待seek完成
      await Future.delayed(const Duration(milliseconds: 200));

      // 8. 更新状态
      setState(() {
        _currentQuality = quality;
        _qualityNotifier.value = quality;
        _isSwitchingQuality = false;
      });

      // 9. 保存清晰度偏好
      await _savePreferredQuality(quality);

      // 10. 恢复播放
      if (wasPlaying) {
        await _player.play();
      }

      widget.onQualityChanged?.call(quality);
      print('✅ 切换完成');
    } catch (e) {
      _logger.logError(
        message: '切换清晰度失败',
        error: e,
        stackTrace: StackTrace.current,
        context: {'quality': quality},
      );

      setState(() {
        _isSwitchingQuality = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('切换清晰度失败'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    print('📹 [dispose] 销毁播放器');
    // 移除生命周期监听
    WidgetsBinding.instance.removeObserver(this);
    // 禁用屏幕唤醒锁
    WakelockPlus.disable();
    _player.dispose();
    _qualityNotifier.dispose(); // 销毁 ValueNotifier
    _loopModeNotifier.dispose(); // 销毁循环模式 ValueNotifier
    // 退出时恢复系统UI
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingWidget();
    }

    if (_errorMessage != null) {
      return _buildErrorWidget();
    }

    if (!_isPlayerInitialized) {
      return _buildLoadingWidget();
    }

    return _buildPlayer();
  }

  /// 构建播放器主体 - 使用 media_kit 原生控制器
  Widget _buildPlayer() {
    return Container(
      color: Colors.black,
      // 使用 ClipRect 裁剪溢出内容，防止布局警告
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand, // 确保子元素填满父容器
              children: [
                // 视频播放区域 - 使用 MaterialVideoControlsTheme 来使用原生控制器
                Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: MaterialVideoControlsTheme(
                normal: MaterialVideoControlsThemeData(
                  // 顶部按钮栏配置
                  topButtonBar: [
                    // 返回按钮
                    MaterialCustomButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    // 标题
                    if (widget.title != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          widget.title!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const Spacer(), // 将循环按钮推到最右边
                    // 循环模式切换按钮 - 使用 ValueListenableBuilder 监听状态变化
                    ValueListenableBuilder<LoopMode>(
                      valueListenable: _loopModeNotifier,
                      builder: (context, loopMode, child) {
                        return MaterialCustomButton(
                          icon: Icon(_getLoopModeIconForMode(loopMode)),
                          onPressed: _toggleLoopMode,
                        );
                      },
                    ),
                  ],
                  // 底部按钮栏配置
                  bottomButtonBar: [
                    const MaterialPlayOrPauseButton(),
                    const MaterialPositionIndicator(),
                    const Spacer(),
                    // 清晰度切换按钮（移到右下角）- 使用 ValueListenableBuilder 监听状态变化
                    if (_availableQualities.length > 1)
                      ValueListenableBuilder<String?>(
                        valueListenable: _qualityNotifier,
                        builder: (context, currentQuality, child) {
                          return MaterialCustomButton(
                            icon: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white60, width: 0.8),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                currentQuality != null
                                    ? getQualityDisplayName(currentQuality)
                                    : '画质',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            onPressed: () => _showQualityMenu(context),
                          );
                        },
                      ),
                    const MaterialFullscreenButton(),
                  ],
                  // 播放器样式配置
                  bottomButtonBarMargin: const EdgeInsets.only(bottom: 0, left: 8, right: 8),
                  seekBarMargin: const EdgeInsets.only(bottom: 44),
                  seekBarThumbColor: Colors.blue, // 进度条滑块颜色改为蓝色
                  seekBarPositionColor: Colors.blue, // 进度条已播放部分颜色改为蓝色
                  // 移除UI显示时的暗淡遮罩
                  backdropColor: Colors.transparent,
                  // 启用所有手势控制
                  volumeGesture: true,
                  brightnessGesture: true,
                  seekGesture: true,
                  // 禁用中间的主按钮区域，让手势更容易触发
                  primaryButtonBar: [],
                  // 不自动显示跳过按钮
                  automaticallyImplySkipNextButton: false,
                  automaticallyImplySkipPreviousButton: false,
                  // 显示缓冲指示器
                  bufferingIndicatorBuilder: (context) => const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
                ),
                fullscreen: MaterialVideoControlsThemeData(
                  // 全屏模式下适配安全区域（刘海、挖孔、水滴屏）
                  topButtonBarMargin: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top,
                    left: 8,
                    right: 8,
                  ),
                  bottomButtonBarMargin: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom,
                    left: 8,
                    right: 8,
                  ),
                  // 顶部按钮栏配置（全屏模式）
                  topButtonBar: [
                    // 返回按钮
                    MaterialCustomButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    // 标题
                    if (widget.title != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          widget.title!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const Spacer(), // 将循环按钮推到最右边
                    // 循环模式切换按钮（全屏）- 使用 ValueListenableBuilder 监听状态变化
                    ValueListenableBuilder<LoopMode>(
                      valueListenable: _loopModeNotifier,
                      builder: (context, loopMode, child) {
                        return MaterialCustomButton(
                          icon: Icon(_getLoopModeIconForMode(loopMode)),
                          onPressed: _toggleLoopMode,
                        );
                      },
                    ),
                  ],
                  // 底部按钮栏配置（全屏模式）
                  bottomButtonBar: [
                    const MaterialPlayOrPauseButton(),
                    const MaterialPositionIndicator(),
                    const Spacer(),
                    // 清晰度切换按钮（移到右下角）- 使用 ValueListenableBuilder 监听状态变化
                    if (_availableQualities.length > 1)
                      ValueListenableBuilder<String?>(
                        valueListenable: _qualityNotifier,
                        builder: (context, currentQuality, child) {
                          return MaterialCustomButton(
                            icon: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white70),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                currentQuality != null
                                    ? getQualityDisplayName(currentQuality)
                                    : '画质',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            onPressed: () => _showQualityMenu(context),
                          );
                        },
                      ),
                    const MaterialFullscreenButton(),
                  ],
                  // 全屏时进度条位置往上移
                  seekBarMargin: EdgeInsets.only(
                    bottom: 60 + MediaQuery.of(context).padding.bottom,
                  ),
                  seekBarThumbColor: Colors.blue, // 全屏时进度条滑块颜色也改为蓝色
                  seekBarPositionColor: Colors.blue, // 全屏时进度条已播放部分颜色也改为蓝色
                  displaySeekBar: true,
                  // 移除UI显示时的暗淡遮罩
                  backdropColor: Colors.transparent,
                  // 全屏模式下也启用所有手势控制
                  volumeGesture: true,
                  brightnessGesture: true,
                  seekGesture: true,
                  // 禁用中间的主按钮区域
                  primaryButtonBar: [],
                  // 不自动显示跳过按钮
                  automaticallyImplySkipNextButton: false,
                  automaticallyImplySkipPreviousButton: false,
                ),
                child: Video(
                  controller: _videoController,
                ),
              ),
            ),
          ),

          // 加载中指示器（切换清晰度时）
          if (_isSwitchingQuality)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      '切换中...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 对清晰度列表进行排序（从高到低）
  /// 解析格式: "1920x1080_6000k_30" -> 按分辨率(宽×高)降序排序，相同分辨率时按帧率降序排序
  List<String> _sortQualitiesDescending(List<String> qualities) {
    final sorted = List<String>.from(qualities);
    sorted.sort((a, b) {
      final resA = _parseResolution(a);
      final resB = _parseResolution(b);

      // 先按分辨率降序排序（高清晰度在前）
      if (resA != resB) {
        return resB.compareTo(resA);
      }

      // 分辨率相同时，按帧率降序排序（高帧率在前，如 1080p60 在 1080p 前）
      final fpsA = _parseFrameRate(a);
      final fpsB = _parseFrameRate(b);
      return fpsB.compareTo(fpsA);
    });
    return sorted;
  }

  /// 从清晰度字符串中解析分辨率（宽×高）
  /// 格式: "1920x1080_6000k_30" -> 返回 1920 * 1080 = 2073600
  int _parseResolution(String quality) {
    try {
      final parts = quality.split('_');
      if (parts.isEmpty) return 0;
      final resolution = parts[0]; // "1920x1080"
      final dims = resolution.split('x');
      if (dims.length != 2) return 0;
      final width = int.tryParse(dims[0]) ?? 0;
      final height = int.tryParse(dims[1]) ?? 0;
      return width * height;
    } catch (e) {
      return 0;
    }
  }

  /// 从清晰度字符串中解析帧率
  /// 格式: "1920x1080_6000k_30" -> 返回 30
  int _parseFrameRate(String quality) {
    try {
      final parts = quality.split('_');
      if (parts.length >= 3) {
        return int.tryParse(parts[2]) ?? 30;
      }
      return 30; // 默认帧率
    } catch (e) {
      return 30;
    }
  }

  /// 显示清晰度选择菜单(紧贴按钮的小悬浮菜单)
  void _showQualityMenu(BuildContext context) {
    // 创建一个小的悬浮菜单,使用PopupMenuButton的样式
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      color: Colors.black.withValues(alpha: 0.5), // 更透明（从0.7降到0.5）
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: _availableQualities.map((quality) {
        final isSelected = quality == _currentQuality;
        final displayName = getQualityDisplayName(quality);

        return PopupMenuItem(
          value: quality,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? Colors.blue : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 12),
              Text(
                displayName,
                style: TextStyle(
                  color: isSelected ? Colors.blue : Colors.white,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((selectedQuality) {
      if (selectedQuality != null && selectedQuality != _currentQuality) {
        changeQuality(selectedQuality);
      }
    });
  }

  /// 获取循环模式图标（根据传入的模式）
  IconData _getLoopModeIconForMode(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return Icons.repeat;
      case LoopMode.on:
        return Icons.repeat_one;
    }
  }

  /// 切换循环模式
  void _toggleLoopMode() {
    final newMode = _loopMode.toggle();
    _saveLoopMode(newMode);
  }

  /// 加载中界面
  Widget _buildLoadingWidget() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                '加载中...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 错误界面
  Widget _buildErrorWidget() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage ?? '加载失败',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _initializePlayer,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
