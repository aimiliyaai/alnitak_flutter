import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../services/hls_service.dart';
import '../../../services/logger_service.dart';

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

  const MediaPlayerWidget({
    super.key,
    required this.resourceId,
    this.initialPosition,
    this.onVideoEnd,
    this.onProgressUpdate,
    this.onQualityChanged,
    this.title,
    this.onFullscreenToggle,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
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

  // 使用 ValueNotifier 来管理清晰度状态，确保UI能够响应变化
  final ValueNotifier<String?> _qualityNotifier = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    print('📹 [initState] MediaPlayerWidget 初始化 - resourceId: ${widget.resourceId}, hashCode: $hashCode');
    // 创建播放器实例，配置网络重试参数
    _player = Player(
      configuration: const PlayerConfiguration(
        // 标题（用于通知）
        title: '',
        // 启用更激进的缓冲策略
        bufferSize: 64 * 1024 * 1024, // 64MB 缓冲区
        // 日志级别
        logLevel: MPVLogLevel.warn,
      ),
    );
    _videoController = VideoController(_player);
    _setupPlayerListeners();
    _initializePlayer();
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
          widget.onVideoEnd?.call();
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

    // 监听错误
    _player.stream.error.listen((error) {
      _logger.logError(
        message: '播放器错误',
        error: error,
        stackTrace: StackTrace.current,
        context: {'resourceId': widget.resourceId},
      );
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

      // 2. 选择默认清晰度（720P优先）
      _currentQuality = HlsService.getDefaultQuality(_availableQualities);
      _qualityNotifier.value = _currentQuality; // 同步到 notifier

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

  /// 加载视频
  Future<void> _loadVideo(String quality, {bool isInitialLoad = false}) async {
    try {
      // 重置完播标志（加载新视频时）
      _hasTriggeredCompletion = false;

      // 1. 获取本地 m3u8 文件路径
      final m3u8FilePath = await _hlsService.getLocalM3u8File(widget.resourceId, quality);

      // 2. 使用 media_kit 播放视频，配置网络选项
      await _player.open(
        Media(
          m3u8FilePath,
          // 配置 HTTP 请求头和网络选项
          httpHeaders: {
            'User-Agent': 'AlnitakFlutterPlayer/1.0',
            'Connection': 'keep-alive',
          },
          // 传递给底层播放器的额外选项
          extras: {
            // ExoPlayer (Android) 的网络重试配置
            // 注意：这些是推荐的配置，实际效果取决于 media_kit 的实现
            'network-timeout': '60', // 网络超时60秒（增加到60秒）
            'http-reconnect': 'yes', // 启用HTTP重连
            'cache': 'yes', // 启用缓存
            'cache-secs': '300', // 缓存5分钟
            'demuxer-max-bytes': '128MiB', // 解复用器最大缓冲128MB
            'demuxer-max-back-bytes': '64MiB', // 向后缓冲64MB
          },
        ),
        play: false, // 不自动播放，手动控制播放时机
      );

      // 3. 等待视频准备好
      await _waitForPlayerReady();

      // 4. 如果是初始加载且有初始播放位置，跳转到该位置
      if (isInitialLoad && widget.initialPosition != null) {
        final initialDuration = Duration(seconds: widget.initialPosition!.toInt());
        await _player.seek(initialDuration);
      }

      // 5. 开始播放
      if (!_isSwitchingQuality) {
        await _player.play();
      }

      print('✅ 视频加载成功: $quality (网络重试已启用)');
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

  /// 等待播放器准备就绪
  Future<void> _waitForPlayerReady() async {
    // 等待播放器状态变为非 buffering
    await for (final buffering in _player.stream.buffering) {
      if (!buffering) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 额外延迟确保媒体属性加载完成
    await Future.delayed(const Duration(milliseconds: 200));
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

      print('═══════════════════════════════════════════════════════');
      print('🔄 [清晰度切换] 开始切换到: $quality');
      print('───────────────────────────────────────────────────────');

      // 1. 立即暂停并记录当前位置
      final wasPlaying = _player.state.playing;
      print('📊 [步骤1] 当前播放状态: ${wasPlaying ? "播放中" : "已暂停"}');

      final positionBeforePause = _player.state.position;
      print('📊 [步骤1] 暂停前位置: ${positionBeforePause.inMilliseconds}ms (${positionBeforePause.inSeconds}秒)');

      await _player.pause();
      await Future.delayed(const Duration(milliseconds: 500));

      final positionAfterPause = _player.state.position;
      print('📊 [步骤1] 暂停后位置: ${positionAfterPause.inMilliseconds}ms (${positionAfterPause.inSeconds}秒)');

      // 2. 读取当前位置(HLS只能精确到秒级,不要期望毫秒级精度)
      final currentPosition = _player.state.position;
      print('📊 [步骤2] 记录的目标位置: ${currentPosition.inMilliseconds}ms (${currentPosition.inSeconds}秒)');

      // 3. 获取新清晰度的 m3u8 文件路径
      print('📊 [步骤3] 开始获取新清晰度的 m3u8 文件...');
      final m3u8FilePath = await _hlsService.getLocalM3u8File(widget.resourceId, quality);
      print('📊 [步骤3] m3u8 文件路径: $m3u8FilePath');

      // 4. 打开新视频，明确指定不自动播放
      print('📊 [步骤4] 打开新清晰度视频 (play=false)...');
      await _player.open(
        Media(
          m3u8FilePath,
          httpHeaders: {
            'User-Agent': 'AlnitakFlutterPlayer/1.0',
            'Connection': 'keep-alive',
          },
          extras: {
            'network-timeout': '60',
            'http-reconnect': 'yes',
            'cache': 'yes',
            'cache-secs': '300',
            'demuxer-max-bytes': '128MiB',
            'demuxer-max-back-bytes': '64MiB',
          },
        ),
        play: false, // 明确不自动播放
      );

      final positionAfterOpen = _player.state.position;
      print('📊 [步骤4] 打开后位置: ${positionAfterOpen.inMilliseconds}ms (${positionAfterOpen.inSeconds}秒)');

      // 5. 等待播放器准备就绪
      print('📊 [步骤5] 等待播放器准备就绪...');
      await _waitForPlayerReady();

      final positionAfterReady = _player.state.position;
      print('📊 [步骤5] 准备就绪后位置: ${positionAfterReady.inMilliseconds}ms (${positionAfterReady.inSeconds}秒)');

      // 6. 使用时间记录法直接seek到目标位置
      // 不使用关键帧偏移补偿，直接seek到记录的位置
      // HLS会自动对齐到最近的关键帧，但我们记录的是精确时间
      print('📊 [步骤6] 时间记录法 - 目标位置: ${currentPosition.inMilliseconds}ms (${currentPosition.inSeconds}秒)');
      await _player.seek(currentPosition);

      final positionAfterSeek = _player.state.position;
      print('📊 [步骤6] Seek后立即读取位置: ${positionAfterSeek.inMilliseconds}ms (${positionAfterSeek.inSeconds}秒)');

      // 等待更长时间让播放器完成seek
      await Future.delayed(const Duration(milliseconds: 800));

      final positionAfterDelay = _player.state.position;
      print('📊 [步骤6] 延迟800ms后位置: ${positionAfterDelay.inMilliseconds}ms (${positionAfterDelay.inSeconds}秒)');

      // 计算偏移量
      final offsetMs = positionAfterDelay.inMilliseconds - currentPosition.inMilliseconds;
      final offsetSeconds = offsetMs / 1000.0;
      print('───────────────────────────────────────────────────────');
      print('📊 [结果分析]');
      print('   目标位置: ${currentPosition.inSeconds}秒 (${currentPosition.inMilliseconds}ms)');
      print('   实际位置: ${positionAfterDelay.inSeconds}秒 (${positionAfterDelay.inMilliseconds}ms)');
      print('   偏移量: ${offsetSeconds.toStringAsFixed(2)}秒 (${offsetMs}ms)');
      print('   偏移方向: ${offsetMs > 0 ? "往后" : offsetMs < 0 ? "往前" : "精确"}');

      // 7. 先重置切换标志，确保后续的进度回调能正常工作
      print('📊 [步骤7] 重置切换标志...');
      setState(() {
        _currentQuality = quality;
        _qualityNotifier.value = quality; // 同步到 notifier
        _isSwitchingQuality = false;
      });

      // 8. 如果之前在播放，继续播放（在标志重置后）
      if (wasPlaying) {
        print('📊 [步骤8] 恢复播放...');
        await _player.play();

        // 播放后再次检查位置
        await Future.delayed(const Duration(milliseconds: 200));
        final positionAfterPlay = _player.state.position;
        print('📊 [步骤8] 恢复播放后位置: ${positionAfterPlay.inMilliseconds}ms (${positionAfterPlay.inSeconds}秒)');

        final finalOffsetMs = positionAfterPlay.inMilliseconds - currentPosition.inMilliseconds;
        final finalOffsetSeconds = finalOffsetMs / 1000.0;
        print('📊 [步骤8] 最终偏移量: ${finalOffsetSeconds.toStringAsFixed(2)}秒 (${finalOffsetMs}ms)');
      }

      widget.onQualityChanged?.call(quality);
      print('───────────────────────────────────────────────────────');
      print('✅ [清晰度切换] 完成，新清晰度: $quality');
      print('═══════════════════════════════════════════════════════');
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
    _player.dispose();
    _qualityNotifier.dispose(); // 销毁 ValueNotifier
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
      child: Stack(
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
                      Expanded(
                        child: Padding(
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
                      Expanded(
                        child: Padding(
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
      ),
    );
  }

  /// 显示清晰度选择菜单
  void _showQualityMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6, // 最大高度为屏幕的60%
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  '选择清晰度',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _availableQualities.map((quality) {
                    final isSelected = quality == _currentQuality;
                    final displayName = getQualityDisplayName(quality);
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: isSelected ? Colors.blue : Colors.white70,
                      ),
                      title: Text(
                        displayName,
                        style: TextStyle(
                          color: isSelected ? Colors.blue : Colors.white,
                          fontSize: 16,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        changeQuality(quality);
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
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
