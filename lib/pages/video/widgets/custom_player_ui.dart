import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../controllers/video_player_controller.dart';
import '../../../controllers/danmaku_controller.dart';
import '../../../widgets/danmaku_overlay.dart';
import 'player_gesture_handler.dart';
import 'player_quality_panel.dart';
import 'player_speed_panel.dart';
import 'player_progress_slider.dart';
import 'player_top_bar.dart';
import 'player_bottom_bar.dart';
import 'player_control_buttons.dart';

/// 自定义播放器 UI (V8 完整版)
///
/// 包含修改：
/// 1. 进度条使用 pili_plus 风格秒级 ValueNotifier（sliderPositionSeconds），最多 1Hz 更新。
/// 2. 拖拽时冻结 position 更新（onSliderDragStart/Update/End），防止 thumb 跳变。
/// 3. 清晰度切换时隐藏播放按钮。
/// 4. 面板右对齐、手势优化等所有累积修复。
class CustomPlayerUI extends StatefulWidget {
  final VideoController controller;
  final VideoPlayerController logic;
  final String title;
  final VoidCallback? onBack;
  /// 弹幕控制器（可选，不传则不显示弹幕）
  final DanmakuController? danmakuController;
  /// 在看人数（可选）
  final ValueNotifier<int>? onlineCount;
  /// 强制全屏状态（与 onFullscreenToggle 配套，用于自管全屏时不依赖 media_kit 的 InheritedWidget）
  final bool? forceFullscreen;
  /// 全屏切换回调（若提供则用此替代 media_kit 的 toggleFullscreen）
  final VoidCallback? onFullscreenToggle;
  /// 用户点击「重播」（从播放结束态从头播放）时回调，用于页面侧重置进度上报状态等
  final VoidCallback? onReplayFromEnd;

  const CustomPlayerUI({
    super.key,
    required this.controller,
    required this.logic,
    this.title = '',
    this.onBack,
    this.danmakuController,
    this.onlineCount,
    this.forceFullscreen,
    this.onFullscreenToggle,
    this.onReplayFromEnd,
  });

  @override
  State<CustomPlayerUI> createState() => _CustomPlayerUIState();
}

class _CustomPlayerUIState extends State<CustomPlayerUI>
    with SingleTickerProviderStateMixin, PlayerGestureHandler<CustomPlayerUI> {

  ButtonStyle get _lockButtonStyle => IconButton.styleFrom(
    backgroundColor: Colors.black.withValues(alpha: 0.5),
    padding: const EdgeInsets.all(12),
  );

  // ============ mixin 依赖 ============
  @override
  Player get gesturePlayer => widget.controller.player;
  @override
  VideoPlayerController get gestureLogic => widget.logic;
  @override
  bool get isLocked => _isLocked;

  // ============ UI 状态 ============
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideTimer;

  // ============ 标题滚动动画 ============
  bool _hasPlayedTitleAnimation = false;
  late AnimationController _titleScrollController;
  late Animation<double> _titleScrollAnimation;
  bool _wasFullscreen = false;


  // ============ 清晰度面板 ============
  bool _showQualityPanel = false;
  final GlobalKey _qualityButtonKey = GlobalKey();
  double? _panelRight;
  double? _panelBottom;

  // ============ 弹幕设置面板 ============
  bool _showDanmakuSettings = false;

  // ============ 弹幕发送输入框 ============
  bool _showDanmakuInput = false;

  // ============ 倍速选择 ============
  bool _showSpeedPanel = false;
  double _currentSpeed = 1.0;
  static const List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
  final GlobalKey _speedButtonKey = GlobalKey();
  double? _speedPanelRight;

  /// 当前是否全屏：优先使用外部传入的 forceFullscreen，否则走 media_kit 的 isFullscreen(context)
  bool get _fullscreen => widget.forceFullscreen ?? isFullscreen(context);

  // ============ 播放状态订阅 ============
  StreamSubscription<bool>? _playingSubscription;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
    // 加载保存的音量和亮度设置
    loadGestureSettings();

    // 初始化标题滚动动画控制器
    _titleScrollController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _titleScrollAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _titleScrollController, curve: Curves.easeInOut),
    );

    // 监听播放状态变化，当视频开始播放且控制UI显示时，启动自动隐藏计时器
    _playingSubscription = widget.controller.player.stream.playing.listen((isPlaying) {
      if (isPlaying && _showControls && mounted) {
        _startHideTimer();
      }
    });
  }


  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingSubscription?.cancel();
    _titleScrollController.dispose();
    disposeGesture();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CustomPlayerUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.forceFullscreen != widget.forceFullscreen) {
      if (!_fullscreen) {
        _showQualityPanel = false;
        _showSpeedPanel = false;
        _showDanmakuSettings = false;
      }
      _wasFullscreen = _fullscreen;
      if (_showControls) {
        _startHideTimer();
      }
    }
  }

  // ============ UI 控制逻辑 ============

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_isLocked) return;

    // 只有在视频正在播放时才自动隐藏控制UI
    // 暂停或播放结束时不自动隐藏
    final isPlaying = widget.controller.player.state.playing;
    final isCompleted = widget.controller.player.state.completed;
    if (!isPlaying || isCompleted) return;

    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    if (_showQualityPanel) {
      setState(() => _showQualityPanel = false);
      _startHideTimer();
      return;
    }

    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  /// 计算面板右边缘距离（对齐按钮右边缘）
  double? _calcPanelRight(GlobalKey buttonKey) {
    final renderBox = buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    final buttonPos = renderBox.localToGlobal(Offset.zero);
    final screenWidth = (context.findRenderObject() as RenderBox).size.width;
    return screenWidth - buttonPos.dx - renderBox.size.width;
  }

  void _toggleQualityPanel() {
    if (_showQualityPanel) {
      setState(() => _showQualityPanel = false);
      _startHideTimer();
      return;
    }

    final buttonBox = _qualityButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox == null) return;

    final isFull = _fullscreen;
    final overlaySize = (context.findRenderObject() as RenderBox).size;
    final distFromRight = _calcPanelRight(_qualityButtonKey);
    if (distFromRight == null) return;

    final buttonGlobalPos = buttonBox.localToGlobal(Offset.zero);
    final buttonBottomToScreenBottom = overlaySize.height - (buttonGlobalPos.dy + buttonBox.size.height);

    setState(() {
      _panelRight = (distFromRight - 15.0).clamp(0.0, overlaySize.width - 76);
      _panelBottom = buttonBottomToScreenBottom + (isFull ? 30.0 : 55.0);
      _showQualityPanel = true;
    });
    _hideTimer?.cancel();
  }

  // ============ PlayerGestureHandler 回调 ============

  @override
  void onGestureDragStarted() {
    setState(() => _showControls = false);
  }

  @override
  void onDoubleTapCenter() {
    _toggleControls();
  }

  // ============ UI 构建 ============

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return Scaffold(
          backgroundColor: Colors.transparent, 
          body: ClipRect(
            child: Container(
              color: Colors.transparent, 
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 0. 弹幕层（在手势层下方，不阻挡手势）
                  if (widget.danmakuController != null)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return IgnorePointer(
                          child: DanmakuOverlay(
                            controller: widget.danmakuController!,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                          ),
                        );
                      },
                    ),

                  // 1. 手势检测层
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleControls,
                    onDoubleTapDown: (d) => onDoubleTap(d.localPosition, width),
                    onLongPressStart: (_) => onLongPressStart(),
                    onLongPressEnd: (_) => onLongPressEnd(),
                    onVerticalDragStart: (d) => onDragStart(d, width),
                    onVerticalDragUpdate: (d) => onDragUpdate(d, width),
                    onVerticalDragEnd: (_) => onDragEnd(),
                    onHorizontalDragStart: (d) => onDragStart(d, width),
                    onHorizontalDragUpdate: (d) => onDragUpdate(d, width),
                    onHorizontalDragEnd: (_) => onDragEnd(),
                    child: Container(color: Colors.transparent),
                  ),

                  // 2. 锁定按钮
                  if (_isLocked && !_showControls)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: IconButton(
                          onPressed: () {
                            setState(() {
                              _isLocked = false;
                              _showControls = true;
                            });
                            _startHideTimer();
                          },
                          icon: const Icon(Icons.lock_outline, color: Colors.white, size: 24),
                          style: _lockButtonStyle,
                        ),
                      ),
                    ),

                  // 3. 手势反馈（ValueNotifier 驱动，避免拖拽时全树重建）
                  ValueListenableBuilder<GestureFeedback?>(
                    valueListenable: gestureFeedback,
                    builder: (context, feedback, _) {
                      if (feedback == null) return const SizedBox.shrink();
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(feedback.icon, color: Colors.white, size: 40),
                              const SizedBox(height: 8),
                              Text(
                                feedback.text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (feedback.value != null) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: 100,
                                  height: 4,
                                  child: LinearProgressIndicator(
                                    value: feedback.value,
                                    color: Colors.blue,
                                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // 3.5 长按倍速小标签（ValueNotifier 驱动）
                  ValueListenableBuilder<bool>(
                    valueListenable: isLongPressing,
                    builder: (context, isLongPressing, _) {
                      if (!isLongPressing) return const SizedBox.shrink();
                      return Positioned(
                        top: 50,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fast_forward, color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  '2.0x',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // 4. 控制 UI
                  StreamBuilder<bool>(
                    stream: widget.controller.player.stream.completed,
                    builder: (context, completedSnapshot) {
                      final isCompleted = completedSnapshot.data ?? widget.controller.player.state.completed;

                      if (isCompleted) {
                        // 播放结束：始终显示重播按钮，点击空白可切换控制UI
                        return Stack(
                          children: [
                            Center(child: _buildCenterPlayButton()),
                            IgnorePointer(
                              ignoring: !_showControls,
                              child: AnimatedOpacity(
                                opacity: _showControls ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 300),
                                child: Stack(
                                  children: [
                                    if (!_isLocked) _buildTopBar(),
                                    if (!_isLocked) _buildBottomBar(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      // 正常播放时显示完整控制UI
                      return IgnorePointer(
                        ignoring: !_showControls,
                        child: AnimatedOpacity(
                          opacity: _showControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: Stack(
                            children: [
                              if (!_isLocked) _buildTopBar(),
                              if (!_isLocked) _buildLockButton(),
                              if (!_isLocked) _buildCenterPlayButton(),
                              if (!_isLocked) _buildBottomBar(),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // 5. 清晰度加载 (透明度0.5)
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.logic.isSwitchingQuality,
                    builder: (context, isSwitching, _) {
                      if (!isSwitching) return const SizedBox.shrink();
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
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
                              Text('切换清晰度中...', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // 缓冲/加载中已合并到 MediaPlayerWidget 统一显示（方案 D），此处不再重复

                  // 6. 清晰度面板
                  if (_showQualityPanel && _showControls && _panelRight != null)
                    PlayerQualityPanel(
                      qualities: widget.logic.availableQualities.value,
                      currentQuality: widget.logic.currentQuality.value,
                      getQualityDisplayName: widget.logic.getQualityDisplayName,
                      onSelect: (quality) {
                        if (quality != widget.logic.currentQuality.value) {
                          widget.logic.changeQuality(quality);
                        }
                        setState(() => _showQualityPanel = false);
                        _startHideTimer();
                      },
                      right: _panelRight!,
                      bottom: _panelBottom ?? 50,
                    ),

                  // 6.5 倍速选择面板
                  if (_showSpeedPanel && _showControls)
                    PlayerSpeedPanel(
                      speeds: _speedOptions,
                      currentSpeed: _currentSpeed,
                      onSelect: (speed) {
                        setState(() {
                          _currentSpeed = speed;
                          _showSpeedPanel = false;
                        });
                        widget.controller.player.setRate(speed);
                        _startHideTimer();
                      },
                      right: _speedPanelRight ?? 100,
                      bottom: 50,
                    ),

                  // 7. 弹幕设置面板
                  if (_showDanmakuSettings && widget.danmakuController != null)
                    Positioned(
                      right: 16,
                      top: 60,
                      bottom: 60,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300), // 限制最大宽度
                        child: DanmakuSettingsPanel(
                          controller: widget.danmakuController!,
                          onClose: () => setState(() => _showDanmakuSettings = false),
                        ),
                      ),
                    ),

                  // 8. 弹幕发送输入框（全屏模式下显示）
                  if (_showDanmakuInput && widget.danmakuController != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: DanmakuSendBar(
                          controller: widget.danmakuController!,
                          onSendStart: () {
                            _hideTimer?.cancel();
                          },
                          onSendEnd: () {
                            setState(() => _showDanmakuInput = false);
                            _startHideTimer();
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============ UI 组件构建 ============

  /// 检查标题是否需要滚动动画，并启动（供 PlayerTopBar 回调）
  void _checkAndStartTitleAnimation() {
    if (_hasPlayedTitleAnimation || !mounted) return;

    // 计算文本实际宽度
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    // 获取屏幕宽度的 50% 作为最大标题宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final maxTitleWidth = screenWidth * 0.5 - 60; // 减去按钮和边距

    if (textPainter.width > maxTitleWidth) {
      _hasPlayedTitleAnimation = true;

      // 延迟 500ms 后开始滚动动画
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _wasFullscreen) {
          _titleScrollController.forward();
        }
      });
    }
  }

  Widget _buildTopBar() {
    return PlayerTopBar(
      title: widget.title,
      onBack: widget.onBack,
      fullscreen: _fullscreen,
      wasFullscreen: _wasFullscreen,
      onFullscreenEnter: () {
        setState(() {
          _wasFullscreen = true;
          _hasPlayedTitleAnimation = false;
          _titleScrollController.reset();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.title.isNotEmpty) {
            _checkAndStartTitleAnimation();
          }
        });
      },
      onFullscreenExit: () {
        setState(() {
          _wasFullscreen = false;
          _hasPlayedTitleAnimation = false;
          _titleScrollController.reset();
        });
      },
      titleScrollController: _titleScrollController,
      titleScrollAnimation: _titleScrollAnimation,
      checkAndStartTitleAnimation: _checkAndStartTitleAnimation,
      onlineCount: widget.onlineCount,
    );
  }

  Widget _buildLockButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 20),
        child: IconButton(
          icon: Icon(
            _isLocked ? Icons.lock : Icons.lock_open,
            color: Colors.white,
            size: 24,
          ),
          onPressed: () {
            setState(() => _isLocked = !_isLocked);
            if (_isLocked) {
              setState(() => _showControls = false);
            } else {
              _startHideTimer();
            }
          },
          style: _lockButtonStyle,
        ),
      ),
    );
  }

  Widget _buildCenterPlayButton() {
    // 【关键】增加监听：切换清晰度时不显示播放按钮
    return ValueListenableBuilder<bool>(
      valueListenable: widget.logic.isSwitchingQuality,
      builder: (context, isSwitching, _) {
        if (isSwitching) return const SizedBox.shrink();

        return Center(
          child: StreamBuilder<bool>(
            stream: widget.controller.player.stream.playing,
            builder: (context, playingSnapshot) {
              final playing = playingSnapshot.data ?? widget.controller.player.state.playing;
              if (playing) return const SizedBox.shrink();

              // 只在播放完成时显示重播按钮，暂停时不显示大号播放按钮
              return StreamBuilder<bool>(
                stream: widget.controller.player.stream.completed,
                builder: (context, completedSnapshot) {
                  final completed = completedSnapshot.data ?? widget.controller.player.state.completed;

                  if (completed) {
                    return GestureDetector(
                      onTap: () {
                        // 必须先通知页面层：结束态已解除，否则进度上报会因「已上报完成」被永久跳过
                        widget.logic.onReplayAfterCompletion?.call();
                        widget.logic.seek(Duration.zero);
                        widget.logic.play();
                        _startHideTimer();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.replay,
                              color: Colors.white,
                              size: 28,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '重播',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return PlayerBottomBar(
      progressSlider: PlayerProgressSlider(
        sliderPositionSeconds: widget.logic.sliderPositionSeconds,
        durationSeconds: widget.logic.durationSeconds,
        bufferedSeconds: widget.logic.bufferedSeconds,
        onSliderDragStart: widget.logic.onSliderDragStart,
        onSliderDragUpdate: widget.logic.onSliderDragUpdate,
        onSliderDragEnd: widget.logic.onSliderDragEnd,
        formatDuration: formatDuration,
        onInteraction: _startHideTimer,
      ),
      controlRow: PlayerControlButtons(
        player: widget.controller.player,
        logic: widget.logic,
        danmakuController: widget.danmakuController,
        fullscreen: _fullscreen,
        showDanmakuSettings: _showDanmakuSettings,
        showDanmakuInput: _showDanmakuInput,
        currentSpeed: _currentSpeed,
        qualityButtonKey: _qualityButtonKey,
        speedButtonKey: _speedButtonKey,
        onPlayPause: () {
          if (widget.controller.player.state.playing) {
            widget.logic.pause();
          } else {
            widget.logic.play();
          }
        },
        onToggleDanmakuSettings: () {
          setState(() {
            _showDanmakuSettings = !_showDanmakuSettings;
            _showDanmakuInput = false;
            if (_showDanmakuSettings) {
              _showQualityPanel = false;
            }
          });
          if (!_showDanmakuSettings) {
            _startHideTimer();
          } else {
            _hideTimer?.cancel();
          }
        },
        onToggleDanmakuInput: () {
          setState(() {
            _showDanmakuInput = !_showDanmakuInput;
            _showDanmakuSettings = false;
            _showQualityPanel = false;
            _showControls = false;
          });
          if (_showDanmakuInput) {
            _hideTimer?.cancel();
          } else {
            _startHideTimer();
          }
        },
        onToggleSpeedPanel: _toggleSpeedPanel,
        onToggleQualityPanel: _toggleQualityPanel,
        onToggleFullscreen: () async {
          if (widget.onFullscreenToggle != null) {
            widget.onFullscreenToggle!();
          } else {
            await toggleFullscreen(context);
          }
          await Future.delayed(const Duration(milliseconds: 100));
          if (mounted) _startHideTimer();
        },
        onInteraction: _startHideTimer,
      ),
    );
  }

  void _toggleSpeedPanel() {
    if (!_showSpeedPanel) {
      _speedPanelRight = _calcPanelRight(_speedButtonKey);
    }

    setState(() {
      _showSpeedPanel = !_showSpeedPanel;
      if (_showSpeedPanel) {
        _showQualityPanel = false;
        _showDanmakuSettings = false;
        _hideTimer?.cancel();
      } else {
        _startHideTimer();
      }
    });
  }

}