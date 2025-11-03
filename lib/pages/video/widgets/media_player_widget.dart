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

  // 手势控制状态
  double _normalPlaybackSpeed = 1.0; // 正常播放速度
  bool _isLongPressing = false; // 是否正在长按

  @override
  void initState() {
    super.initState();
    print('📹 [initState] MediaPlayerWidget 初始化 - resourceId: ${widget.resourceId}, hashCode: $hashCode');
    // 创建播放器实例
    _player = Player();
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
    // 监听播放完成事件
    _player.stream.completed.listen((completed) {
      if (completed) {
        print('📹 视频播放结束');
        widget.onVideoEnd?.call();
      }
    });

    // 监听播放进度
    _player.stream.position.listen((position) {
      if (mounted && widget.onProgressUpdate != null && !_isSwitchingQuality) {
        widget.onProgressUpdate!(position);
      }
    });

    // 监听播放状态
    _player.stream.playing.listen((playing) {
      print('📹 ${playing ? "开始播放" : "暂停播放"}');
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
      // 1. 获取本地 m3u8 文件路径
      final m3u8FilePath = await _hlsService.getLocalM3u8File(widget.resourceId, quality);

      // 2. 使用 media_kit 播放视频
      await _player.open(
        Media(m3u8FilePath),
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

  /// 切换清晰度（保持播放位置） - 优化版
  Future<void> changeQuality(String quality) async {
    if (_currentQuality == quality || _isSwitchingQuality) return;

    try {
      setState(() {
        _isSwitchingQuality = true;
      });

      // 1. 立即暂停并记录精确的当前位置
      final wasPlaying = _player.state.playing;
      if (wasPlaying) {
        await _player.pause();
        // 暂停后稍等确保位置稳定
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 2. 再次读取位置（确保是暂停后的准确位置）
      final currentPosition = _player.state.position;
      print('🔄 切换清晰度: $quality，保存位置: ${currentPosition.inSeconds}秒 (毫秒: ${currentPosition.inMilliseconds})');

      // 3. 加载新清晰度的视频（不自动播放）
      await _loadVideo(quality);

      // 4. 等待一小段时间让新视频完全加载
      await Future.delayed(const Duration(milliseconds: 100));

      // 5. 精确跳转到之前的播放位置
      await _player.seek(currentPosition);
      print('🎯 Seek到位置: ${currentPosition.inSeconds}秒');

      // 6. 再次等待seek完成
      await Future.delayed(const Duration(milliseconds: 150));

      // 7. 验证位置是否正确
      final actualPosition = _player.state.position;
      print('📍 实际位置: ${actualPosition.inSeconds}秒 (差异: ${(actualPosition - currentPosition).inSeconds}秒)');

      // 8. 如果之前在播放，继续播放
      if (wasPlaying) {
        await _player.play();
      }

      setState(() {
        _currentQuality = quality;
        _isSwitchingQuality = false;
      });

      widget.onQualityChanged?.call(quality);
      print('✅ 清晰度已切换: $quality');
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

  /// 双击切换播放/暂停
  void _handleDoubleTap() {
    if (_player.state.playing) {
      _player.pause();
      print('📹 双击暂停');
    } else {
      _player.play();
      print('📹 双击播放');
    }
  }

  /// 长按开始 - 2倍速播放
  void _handleLongPressStart() {
    if (!_isLongPressing) {
      setState(() {
        _isLongPressing = true;
        _normalPlaybackSpeed = _player.state.rate;
      });
      _player.setRate(2.0);
      print('📹 长按开始 - 2倍速播放');
    }
  }

  /// 长按结束 - 恢复正常速度
  void _handleLongPressEnd() {
    if (_isLongPressing) {
      setState(() {
        _isLongPressing = false;
      });
      _player.setRate(_normalPlaybackSpeed);
      print('📹 长按结束 - 恢复$_normalPlaybackSpeed倍速');
    }
  }

  /// 构建播放器主体 - 使用 media_kit 原生控制器
  Widget _buildPlayer() {
    return Container(
      color: Colors.black,
      child: GestureDetector(
        // 双击切换播放/暂停
        onDoubleTap: _handleDoubleTap,
        // 长按2倍速播放
        onLongPressStart: (_) => _handleLongPressStart(),
        onLongPressEnd: (_) => _handleLongPressEnd(),
        // 允许子widget接收手势事件
        behavior: HitTestBehavior.translucent,
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
                    const Spacer(),
                    // 清晰度切换按钮
                    if (_availableQualities.length > 1)
                      MaterialCustomButton(
                        icon: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white70),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _currentQuality ?? '画质',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        onPressed: () => _showQualityMenu(context),
                      ),
                  ],
                  // 底部按钮栏配置
                  bottomButtonBar: [
                    const MaterialPlayOrPauseButton(),
                    const MaterialPositionIndicator(),
                    const Spacer(),
                    const MaterialFullscreenButton(),
                  ],
                  // 播放器样式配置
                  seekBarMargin: const EdgeInsets.only(bottom: 40),
                  seekBarThumbColor: Colors.blue, // 进度条滑块颜色改为蓝色
                  seekBarPositionColor: Colors.blue, // 进度条已播放部分颜色改为蓝色
                  volumeGesture: true,
                  brightnessGesture: true,
                  seekGesture: true,
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
                  // 全屏时进度条位置往上移
                  seekBarMargin: EdgeInsets.only(
                    bottom: 60 + MediaQuery.of(context).padding.bottom,
                  ),
                  seekBarThumbColor: Colors.blue, // 全屏时进度条滑块颜色也改为蓝色
                  seekBarPositionColor: Colors.blue, // 全屏时进度条已播放部分颜色也改为蓝色
                  displaySeekBar: true,
                ),
                child: Video(
                  controller: _videoController,
                ),
              ),
            ),
          ),

          // 长按倍速指示器
          if (_isLongPressing)
            Center(
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fast_forward, color: Colors.white, size: 24),
                  SizedBox(width: 8),
                  Text(
                    '2倍速播放中...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
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
      ),
    );
  }

  /// 显示清晰度选择菜单
  void _showQualityMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => SafeArea(
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
            ..._availableQualities.map((quality) {
              final isSelected = quality == _currentQuality;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? Colors.blue : Colors.white70,
                ),
                title: Text(
                  quality,
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
            }),
            const SizedBox(height: 8),
          ],
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
