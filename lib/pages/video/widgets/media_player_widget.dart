import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import '../../../controllers/video_player_controller.dart';
import '../../../models/loop_mode.dart';

/// 手势类型
enum _GestureType { none, volume, brightness, seek }

/// 视频播放器组件
///
/// 使用 media_kit (基于 AndroidX Media3) 播放 HLS 视频流
/// 使用 VideoPlayerController 管理业务逻辑
/// Widget 只负责 UI 渲染和手势处理
class MediaPlayerWidget extends StatefulWidget {
  final int resourceId;
  final double? initialPosition;
  final VoidCallback? onVideoEnd;
  final Function(Duration position)? onProgressUpdate;
  final Function(String quality)? onQualityChanged;
  final String? title;
  final VoidCallback? onFullscreenToggle;
  final int? totalParts;
  final int? currentPart;
  final Function(int part)? onPartChange;

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
  late final VideoPlayerController _controller;

  // 手势相关状态
  bool _showGestureFeedback = false;
  _GestureType _gestureType = _GestureType.none;
  String _feedbackText = '';
  IconData? _feedbackIcon;
  double _gestureValue = 0.0; // 0.0 - 1.0 (音量/亮度) 或用于显示
  Timer? _hideTimer;

  // 进度调节相关
  Duration _seekTargetPosition = Duration.zero;
  Duration _seekStartPosition = Duration.zero;

  // 系统控制
  double _brightness = 0.5;
  double _volume = 0.5;

  // 手势检测
  Offset _dragStartPosition = Offset.zero; // 记录手指按下的位置
  bool _isDragging = false; // 是否正在拖拽
  DateTime? _lastTapTime; // 双击检测时间
  bool _lockGesture = false; // 锁定手势，防止误触底部控制栏

  @override
  void initState() {
    super.initState();
    print('📹 [MediaPlayerWidget] 初始化 - resourceId: ${widget.resourceId}');

    // 初始化系统控制
    _initSystemControls();

    // 创建 Controller
    _controller = VideoPlayerController();

    // 设置回调
    _controller.onVideoEnd = widget.onVideoEnd;
    _controller.onProgressUpdate = widget.onProgressUpdate;
    _controller.onQualityChanged = widget.onQualityChanged;

    // 初始化播放器
    _controller.initialize(
      resourceId: widget.resourceId,
      initialPosition: widget.initialPosition,
    );

    // 添加生命周期监听
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    print('📹 [didUpdateWidget] old resourceId: ${oldWidget.resourceId}, new resourceId: ${widget.resourceId}');

    if (oldWidget.resourceId != widget.resourceId) {
      print('📹 resourceId 改变，重新初始化');
      _controller.initialize(
        resourceId: widget.resourceId,
        initialPosition: widget.initialPosition,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _controller.handleAppLifecycleState(state == AppLifecycleState.paused);
  }

  @override
  void dispose() {
    print('📹 [MediaPlayerWidget] 销毁');
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _hideTimer?.cancel();

    // 退出时恢复系统UI
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  // ============ 系统控制初始化 ============

  /// 初始化系统音量和亮度控制
  Future<void> _initSystemControls() async {
    try {
      // 初始化音量控制
      _volume = await VolumeController.instance.getVolume();

      // 初始化亮度
      _brightness = await ScreenBrightness().application;
    } catch (e) {
      print('⚠️ 初始化系统控制失败: $e');
    }
  }

  // ============ 手势处理逻辑 ============

  /// 显示手势反馈面板
  void _showFeedbackPanel() {
    setState(() => _showGestureFeedback = true);
    _hideTimer?.cancel();
  }

  /// 隐藏手势反馈面板
  void _hideFeedbackPanel() {
    _hideTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showGestureFeedback = false);
    });
  }

  /// 处理双击 - 左侧快退，中间暂停/播放，右侧快进（手动双击检测）
  void _handleDoubleTapRaw(Offset localPosition, double screenWidth) {
    final double leftThreshold = screenWidth * 0.3;  // 左侧 30% 区域
    final double rightThreshold = screenWidth * 0.7; // 右侧 30% 区域

    // 判断点击区域：左侧、中间、右侧
    if (localPosition.dx < leftThreshold) {
      // 左侧：快退 10 秒
      final currentPos = _controller.player.state.position;
      final totalDur = _controller.player.state.duration;
      Duration targetPos = currentPos - const Duration(seconds: 10);

      if (targetPos < Duration.zero) targetPos = Duration.zero;
      _controller.seek(targetPos);

      setState(() {
        _gestureType = _GestureType.seek;
        _feedbackText = '-10秒';
        _feedbackIcon = Icons.fast_rewind;
        _showGestureFeedback = true;
      });
      _hideFeedbackPanel();

    } else if (localPosition.dx > rightThreshold) {
      // 右侧：快进 10 秒
      final currentPos = _controller.player.state.position;
      final totalDur = _controller.player.state.duration;
      Duration targetPos = currentPos + const Duration(seconds: 10);

      if (targetPos > totalDur) targetPos = totalDur;
      _controller.seek(targetPos);

      setState(() {
        _gestureType = _GestureType.seek;
        _feedbackText = '+10秒';
        _feedbackIcon = Icons.fast_forward;
        _showGestureFeedback = true;
      });
      _hideFeedbackPanel();

    } else {
      // 中间：暂停/播放切换
      final isPlaying = _controller.player.state.playing;
      if (isPlaying) {
        _controller.pause();
        setState(() {
          _feedbackText = '暂停';
          _feedbackIcon = Icons.pause;
          _showGestureFeedback = true;
        });
      } else {
        _controller.play();
        setState(() {
          _feedbackText = '播放';
          _feedbackIcon = Icons.play_arrow;
          _showGestureFeedback = true;
        });
      }
      _hideFeedbackPanel();
    }
  }

  /// 手指按下 - 记录初始位置，检测双击
  void _onPointerDown(PointerDownEvent event, BoxConstraints constraints) {
    // 区域保护：如果点击的是底部 80px（控制栏区域），直接锁定手势
    if (event.localPosition.dy > constraints.maxHeight - 80) {
      _lockGesture = true;
      return;
    }

    _lockGesture = false;
    _dragStartPosition = event.localPosition;
    _isDragging = false; // 重置拖拽状态

    // 手动双击检测
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 300)) {
      // 触发双击逻辑
      _handleDoubleTapRaw(event.localPosition, constraints.maxWidth);
    }
    _lastTapTime = now;
  }

  /// 手指移动 - 计算偏移，判断是否触发拖拽
  void _onPointerMove(PointerMoveEvent event, double screenWidth) {
    // 如果手势已锁定，跳过处理
    if (_lockGesture) return;

    // 如果已经判定为拖拽，直接更新逻辑
    if (_isDragging) {
      _updateDragLogic(
        event.localPosition,
        screenWidth,
        event.delta.dy,
        event.delta.dx,
      );
      return;
    }

    // 如果还没判定为拖拽，计算移动距离是否超过阈值（防误触）
    final offset = event.localPosition - _dragStartPosition;
    if (offset.distance > 10.0) {
      // 阈值设为 10 像素
      _isDragging = true;
      // 刚开始拖拽时，初始化系统音量/亮度值
      _startDragInit(event.localPosition, screenWidth);
    }
  }

  /// 手指抬起 - 结束拖拽
  void _onPointerUp(PointerUpEvent event) {
    // 如果手势已锁定，跳过处理
    if (_lockGesture) {
      _lockGesture = false; // 重置锁定状态
      return;
    }

    if (_isDragging) {
      if (_gestureType == _GestureType.seek) {
        _controller.seek(_seekTargetPosition);
      }
      _hideFeedbackPanel();
      // 延迟重置手势类型，避免状态污染
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _gestureType = _GestureType.none;
      });
    }
    _isDragging = false;
    // 注意：这里什么都不做就是让点击事件"穿透"的关键
    // 单击事件会自然传递给底层的 media_kit，触发 UI 显示
  }

  /// 辅助：拖拽开始时的初始化（同步系统状态）
  Future<void> _startDragInit(Offset position, double screenWidth) async {
    try {
      if (position.dx >= screenWidth / 2) {
        _volume = await VolumeController.instance.getVolume();
      } else {
        _brightness = await ScreenBrightness().application;
      }
    } catch (e) {
      print('⚠️ 同步系统状态失败: $e');
    }
  }

  /// 辅助：拖拽更新的具体业务逻辑
  void _updateDragLogic(
      Offset position, double screenWidth, double deltaY, double deltaX) {
    const double sensitivity = 0.003;

    // 如果还没确定手势类型，根据移动方向决定（水平还是垂直）
    if (_gestureType == _GestureType.none) {
      if (deltaX.abs() > deltaY.abs()) {
        // 水平移动 -> 进度
        _gestureType = _GestureType.seek;
        _seekStartPosition = _controller.player.state.position;
        _seekTargetPosition = _seekStartPosition;
      } else {
        // 垂直移动 -> 音量/亮度
        if (position.dx < screenWidth / 2) {
          _gestureType = _GestureType.brightness;
        } else {
          _gestureType = _GestureType.volume;
        }
      }
      _showFeedbackPanel();
    }

    // 根据类型执行逻辑
    if (_gestureType == _GestureType.volume) {
      // 调节系统音量
      _volume -= deltaY * sensitivity;
      _volume = _volume.clamp(0.0, 1.0);
      VolumeController.instance.setVolume(_volume);

      setState(() {
        _feedbackIcon = _volume == 0 ? Icons.volume_off : Icons.volume_up;
        _feedbackText = '${(_volume * 100).toInt()}%';
        _gestureValue = _volume;
      });
    } else if (_gestureType == _GestureType.brightness) {
      // 调节系统亮度
      _brightness -= deltaY * sensitivity;
      _brightness = _brightness.clamp(0.0, 1.0);

      try {
        ScreenBrightness().setApplicationScreenBrightness(_brightness);
      } catch (e) {
        print('⚠️ 设置亮度失败: $e');
      }

      setState(() {
        _feedbackIcon = _brightness < 0.5 ? Icons.brightness_low : Icons.brightness_high;
        _feedbackText = '${(_brightness * 100).toInt()}%';
        _gestureValue = _brightness;
      });
    } else if (_gestureType == _GestureType.seek) {
      // 进度调节
      final totalSeconds = _controller.player.state.duration.inSeconds;
      if (totalSeconds > 0) {
        final maxSeekRange = (totalSeconds * 0.2).clamp(0, 90);
        final secondsPerPixel = maxSeekRange / screenWidth;
        final deltaSeconds = deltaX * secondsPerPixel;
        final newSeconds = (_seekTargetPosition.inSeconds + deltaSeconds).clamp(0, totalSeconds);
        _seekTargetPosition = Duration(seconds: newSeconds.toInt());

        setState(() {
          final diff = _seekTargetPosition.inSeconds - _seekStartPosition.inSeconds;
          final sign = diff > 0 ? '+' : '';
          _feedbackIcon = diff > 0 ? Icons.fast_forward : Icons.fast_rewind;
          _feedbackText =
              '${_formatDuration(_seekTargetPosition)} / ${_formatDuration(_controller.player.state.duration)}';
          if (diff != 0) {
            _feedbackText += '\n($sign$diff秒)';
          }
        });
      }
    }
  }

  /// 格式化时长显示
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return hours > 0
        ? '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}'
        : '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  // ============ UI 构建 ============

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.isLoading,
      builder: (context, isLoading, _) {
        if (isLoading) {
          return _buildLoadingWidget();
        }

        return ValueListenableBuilder<String?>(
          valueListenable: _controller.errorMessage,
          builder: (context, errorMessage, _) {
            if (errorMessage != null) {
              return _buildErrorWidget(errorMessage);
            }

            return ValueListenableBuilder<bool>(
              valueListenable: _controller.isPlayerInitialized,
              builder: (context, isInitialized, _) {
                if (!isInitialized) {
                  return _buildLoadingWidget();
                }

                return _buildPlayerWithGestures();
              },
            );
          },
        );
      },
    );
  }

  /// 构建带手势的播放器
  Widget _buildPlayerWithGestures() {
    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. 视频播放器 + 手势检测（嵌套方式，非层叠）
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Listener(
                    // translucent 确保事件能被捕获同时传递给底层 Video
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (event) => _onPointerDown(event, constraints),
                    onPointerMove: (event) => _onPointerMove(event, constraints.maxWidth),
                    onPointerUp: _onPointerUp,
                    child: MaterialVideoControlsTheme(
                      normal: _buildNormalControls(),
                      fullscreen: _buildFullscreenControls(),
                      child: Video(controller: _controller.videoController),
                    ),
                  ),
                ),
              ),

              // 2. 手势反馈 UI（覆盖层）
              if (_showGestureFeedback) _buildGestureFeedback(),

              // 3. 切换清晰度加载指示器（覆盖层）
              ValueListenableBuilder<bool>(
                valueListenable: _controller.isSwitchingQuality,
                builder: (context, isSwitching, _) {
                  if (!isSwitching) return const SizedBox.shrink();

                  return Center(
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
                          Text('切换中...', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// 构建手势反馈 UI
  Widget _buildGestureFeedback() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_feedbackIcon != null)
              Icon(_feedbackIcon, color: Colors.white, size: 48),
            const SizedBox(height: 12),
            Text(
              _feedbackText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            // 音量/亮度显示进度条
            if (_gestureType == _GestureType.volume || _gestureType == _GestureType.brightness) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 120,
                height: 4,
                child: LinearProgressIndicator(
                  value: _gestureValue,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建普通模式控制栏
  MaterialVideoControlsThemeData _buildNormalControls() {
    return MaterialVideoControlsThemeData(
      topButtonBar: [
        MaterialCustomButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
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
        const Spacer(),
        ValueListenableBuilder<LoopMode>(
          valueListenable: _controller.loopMode,
          builder: (context, loopMode, _) {
            return MaterialCustomButton(
              icon: Icon(_getLoopModeIcon(loopMode)),
              onPressed: _controller.toggleLoopMode,
            );
          },
        ),
      ],
      bottomButtonBar: [
        const MaterialPlayOrPauseButton(),
        const MaterialPositionIndicator(),
        const Spacer(),
        _buildQualityButton(),
        const MaterialFullscreenButton(),
      ],
      bottomButtonBarMargin: const EdgeInsets.only(bottom: 0, left: 8, right: 8),
      seekBarMargin: const EdgeInsets.only(bottom: 44),
      seekBarThumbColor: Colors.blue,
      seekBarPositionColor: Colors.blue,
      backdropColor: Colors.transparent,
      // 禁用自带手势，使用自定义手势
      volumeGesture: false,
      brightnessGesture: false,
      seekGesture: false,
      primaryButtonBar: [],
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
      bufferingIndicatorBuilder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }

  /// 构建全屏模式控制栏
  MaterialVideoControlsThemeData _buildFullscreenControls() {
    return MaterialVideoControlsThemeData(
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
      topButtonBar: [
        MaterialCustomButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
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
        const Spacer(),
        ValueListenableBuilder<LoopMode>(
          valueListenable: _controller.loopMode,
          builder: (context, loopMode, _) {
            return MaterialCustomButton(
              icon: Icon(_getLoopModeIcon(loopMode)),
              onPressed: _controller.toggleLoopMode,
            );
          },
        ),
      ],
      bottomButtonBar: [
        const MaterialPlayOrPauseButton(),
        const MaterialPositionIndicator(),
        const Spacer(),
        _buildQualityButton(isFullscreen: true),
        const MaterialFullscreenButton(),
      ],
      seekBarMargin: EdgeInsets.only(
        bottom: 60 + MediaQuery.of(context).padding.bottom,
      ),
      seekBarThumbColor: Colors.blue,
      seekBarPositionColor: Colors.blue,
      displaySeekBar: true,
      backdropColor: Colors.transparent,
      // 禁用自带手势，使用自定义手势
      volumeGesture: false,
      brightnessGesture: false,
      seekGesture: false,
      primaryButtonBar: [],
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
    );
  }

  /// 构建清晰度按钮
  Widget _buildQualityButton({bool isFullscreen = false}) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: _controller.availableQualities,
      builder: (context, qualities, _) {
        if (qualities.length <= 1) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<String?>(
          valueListenable: _controller.currentQuality,
          builder: (context, currentQuality, _) {
            return MaterialCustomButton(
              icon: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isFullscreen ? 8 : 6,
                  vertical: isFullscreen ? 4 : 2,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isFullscreen ? Colors.white70 : Colors.white60,
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  currentQuality != null
                      ? _controller.getQualityDisplayName(currentQuality)
                      : '画质',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isFullscreen ? 12 : 11,
                  ),
                ),
              ),
              onPressed: () => _showQualityMenu(context),
            );
          },
        );
      },
    );
  }

  /// 显示清晰度选择菜单
  void _showQualityMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final qualities = _controller.availableQualities.value;
    final currentQuality = _controller.currentQuality.value;

    showMenu(
      context: context,
      position: position,
      color: Colors.black.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: qualities.map((quality) {
        final isSelected = quality == currentQuality;
        final displayName = _controller.getQualityDisplayName(quality);

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
      if (selectedQuality != null && selectedQuality != currentQuality) {
        _controller.changeQuality(selectedQuality);
      }
    });
  }

  /// 获取循环模式图标
  IconData _getLoopModeIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return Icons.repeat;
      case LoopMode.on:
        return Icons.repeat_one;
    }
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
  Widget _buildErrorWidget(String errorMessage) {
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
                  errorMessage,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  _controller.initialize(
                    resourceId: widget.resourceId,
                    initialPosition: widget.initialPosition,
                  );
                },
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
