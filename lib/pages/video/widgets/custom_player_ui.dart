import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../controllers/video_player_controller.dart';
import '../../../controllers/danmaku_controller.dart';
import '../../../widgets/danmaku_overlay.dart';
import 'player_quality_panel.dart';
import 'player_speed_panel.dart';
import 'player_progress_slider.dart';
import 'player_top_bar.dart';
import 'player_bottom_bar.dart';

/// 手势反馈数据（不可变，用于 ValueNotifier 驱动局部重建）
class _GestureFeedback {
  final IconData icon;
  final String text;
  final double? value;

  const _GestureFeedback({required this.icon, required this.text, this.value});
}

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

class _CustomPlayerUIState extends State<CustomPlayerUI> with SingleTickerProviderStateMixin {
  static const String _volumeKey = 'player_volume';
  static const String _brightnessKey = 'player_brightness';

  SharedPreferences? _prefs;

  ButtonStyle get _lockButtonStyle => IconButton.styleFrom(
    backgroundColor: Colors.black.withValues(alpha: 0.5),
    padding: const EdgeInsets.all(12),
  );

  // ============ UI 状态 ============
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideTimer;

  // ============ 标题滚动动画 ============
  bool _hasPlayedTitleAnimation = false;
  late AnimationController _titleScrollController;
  late Animation<double> _titleScrollAnimation;
  bool _wasFullscreen = false;

  // ============ 手势反馈（ValueNotifier 避免 60fps setState） ============
  final ValueNotifier<_GestureFeedback?> _gestureFeedback = ValueNotifier(null);

  // ============ 拖拽逻辑 ============
  Offset _dragStartPos = Offset.zero;
  int _gestureType = 0;

  double _playerBrightness = 1.0;
  double _startVolumeSnapshot = 1.0;
  double _startBrightnessSnapshot = 1.0;
  Duration _seekPos = Duration.zero;

  // ============ 长按倍速（ValueNotifier 避免 setState） ============
  final ValueNotifier<bool> _isLongPressing = ValueNotifier(false);
  double _normalSpeed = 1.0;

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
    _loadSettings();

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

  /// 加载保存的音量和亮度设置
  Future<void> _loadSettings() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();

      final savedVolume = _prefs!.getDouble(_volumeKey) ?? 100.0;
      widget.controller.player.setVolume(savedVolume);

      final savedBrightness = _prefs!.getDouble(_brightnessKey) ?? 1.0;
      setState(() {
        _playerBrightness = savedBrightness;
      });
    } catch (e) {
      // 加载播放器设置失败
    }
  }

  Future<void> _saveVolume(double volume) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setDouble(_volumeKey, volume);
    } catch (e) {
      // 保存音量设置失败
    }
  }

  Future<void> _saveBrightness(double brightness) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setDouble(_brightnessKey, brightness);
    } catch (e) {
      // 保存亮度设置失败
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingSubscription?.cancel();
    _titleScrollController.dispose();
    _gestureFeedback.dispose();
    _isLongPressing.dispose();
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

  // ============ 手势处理逻辑 ============

  void _onDragStart(DragStartDetails details, double width) {
    if (_isLocked) return;
    _dragStartPos = details.localPosition;
    setState(() => _showControls = false); 
    
    _startVolumeSnapshot = widget.controller.player.state.volume / 100.0;
    _startBrightnessSnapshot = _playerBrightness;
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (_isLocked) return;
    final delta = details.localPosition - _dragStartPos;

    if (_gestureType == 0 && delta.distance < 10) return;

    if (_gestureType == 0) {
      if (delta.dx.abs() > delta.dy.abs()) {
        _gestureType = 3; 
      } else {
        _gestureType = _dragStartPos.dx < width / 2 ? 2 : 1;
      }
    }

    const double sensitivity = 600.0;

    if (_gestureType == 1) {
      // 音量调节
      final val = (_startVolumeSnapshot - delta.dy / sensitivity).clamp(0.0, 1.0);
      final volumePercent = val * 100;
      widget.controller.player.setVolume(volumePercent);
      _showFeedbackUI(Icons.volume_up, '音量 ${volumePercent.toInt()}%', val);

    } else if (_gestureType == 2) {
      // 亮度调节 (灵敏度 1200)
      final val = (_startBrightnessSnapshot - delta.dy / 1200).clamp(0.0, 1.0);
      _playerBrightness = val;
      setState(() {});
      _showFeedbackUI(Icons.brightness_medium, '亮度 ${(val * 100).toInt()}%', val);

    } else if (_gestureType == 3) {
      final total = widget.controller.player.state.duration.inSeconds;
      final current = widget.controller.player.state.position.inSeconds;
      final seekDelta = (delta.dx / width) * 90; 
      final target = (current + seekDelta).clamp(0, total);
      _seekPos = Duration(seconds: target.toInt());

      final diff = _seekPos.inSeconds - current;
      final sign = diff > 0 ? '+' : '';
      _showFeedbackUI(
        diff > 0 ? Icons.fast_forward : Icons.fast_rewind,
        '${_formatDuration(_seekPos)} / ${_formatDuration(widget.controller.player.state.duration)}\n($sign$diff秒)',
        null,
    );
  }
}

  void _onDragEnd() {
    if (_gestureType == 3) {
      // 使用封装的seek方法，支持缓冲检测
      widget.logic.seek(_seekPos);
    } else if (_gestureType == 1) {
      // 音量调节结束，保存设置
      final currentVolume = widget.controller.player.state.volume;
      _saveVolume(currentVolume);
    } else if (_gestureType == 2) {
      // 亮度调节结束，保存设置
      _saveBrightness(_playerBrightness);
    }
    _gestureType = 0;

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _gestureFeedback.value = null;
    });
  }

  void _onLongPressStart() {
    if (_isLocked) return;
    _isLongPressing.value = true;
    _normalSpeed = widget.controller.player.state.rate;
    widget.controller.player.setRate(2.0);
  }

  void _onLongPressEnd() {
    if (!_isLongPressing.value) return;
    _isLongPressing.value = false;
    widget.controller.player.setRate(_normalSpeed);
    _gestureFeedback.value = null;
  }

  void _onDoubleTap(Offset pos, double width) {
    if (_isLocked) return;
    final leftZone = width * 0.3;
    final rightZone = width * 0.7;

    if (pos.dx < leftZone) {
      _seekRelative(-10, Icons.fast_rewind, '-10秒');
    } else if (pos.dx > rightZone) {
      _seekRelative(10, Icons.fast_forward, '+10秒');
    } else {
      if (widget.controller.player.state.playing) {
        widget.logic.pause();
      } else {
        widget.logic.play();
      }
      _toggleControls();
    }
  }

  void _seekRelative(int seconds, IconData icon, String label) {
    final currentPos = widget.controller.player.state.position;
    final maxPos = widget.controller.player.state.duration;
    final newPos = currentPos + Duration(seconds: seconds);
    final clampedPos = Duration(
      milliseconds: newPos.inMilliseconds.clamp(0, maxPos.inMilliseconds),
    );
    widget.logic.seek(clampedPos);
    _showFeedbackUI(icon, label, null);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _gestureFeedback.value = null;
    });
  }

  void _showFeedbackUI(IconData icon, String text, double? value) {
    _gestureFeedback.value = _GestureFeedback(icon: icon, text: text, value: value);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}'
        : '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
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
                    onDoubleTapDown: (d) => _onDoubleTap(d.localPosition, width),
                    onLongPressStart: (_) => _onLongPressStart(),
                    onLongPressEnd: (_) => _onLongPressEnd(),
                    onVerticalDragStart: (d) => _onDragStart(d, width),
                    onVerticalDragUpdate: (d) => _onDragUpdate(d, width),
                    onVerticalDragEnd: (_) => _onDragEnd(),
                    onHorizontalDragStart: (d) => _onDragStart(d, width),
                    onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
                    onHorizontalDragEnd: (_) => _onDragEnd(),
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
                  ValueListenableBuilder<_GestureFeedback?>(
                    valueListenable: _gestureFeedback,
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
                    valueListenable: _isLongPressing,
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
        formatDuration: _formatDuration,
        onInteraction: _startHideTimer,
      ),
      controlRow: _buildControlButtonsRow(),
    );
  }

  /// 构建控制按钮行
  Widget _buildControlButtonsRow() {
    final fullscreen = _fullscreen;

    return Row(
      children: [
        // 播放/暂停按钮
        StreamBuilder<bool>(
          stream: widget.controller.player.stream.playing,
          builder: (context, snapshot) {
            final playing = snapshot.data ?? widget.controller.player.state.playing;
            return IconButton(
              icon: Icon(
                playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: fullscreen ? 24 : 22,
              ),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: fullscreen ? 36 : 32, minHeight: 32),
              onPressed: () {
                if (widget.controller.player.state.playing) {
                  widget.logic.pause();
                } else {
                  widget.logic.play();
                }
                _startHideTimer();
              },
            );
          },
        ),

        // 弹幕控制按钮
        if (widget.danmakuController != null)
          ListenableBuilder(
            listenable: widget.danmakuController!,
            builder: (context, _) {
              final isVisible = widget.danmakuController!.isVisible;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 弹幕开关
                  GestureDetector(
                    onTap: () {
                      widget.danmakuController!.toggleVisibility();
                      _startHideTimer();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: isVisible
                            ? Colors.blue.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isVisible ? Colors.blue : Colors.white54,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '弹',
                        style: TextStyle(
                          color: isVisible ? Colors.blue : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 弹幕设置
                  IconButton(
                    icon: Icon(
                      Icons.tune,
                      color: _showDanmakuSettings ? Colors.blue : Colors.white,
                      size: fullscreen ? 20 : 18,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: fullscreen ? 32 : 28, minHeight: 28),
                    onPressed: () {
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
                  ),
                ],
              );
            },
          ),

        // 弹幕发送按钮（全屏时显示）
        if (widget.danmakuController != null && fullscreen)
          GestureDetector(
            onTap: () {
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: _showDanmakuInput
                    ? Colors.blue.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _showDanmakuInput ? Colors.blue : Colors.white54,
                  width: 1,
                ),
              ),
              child: Text(
                '发弹幕',
                style: TextStyle(
                  color: _showDanmakuInput ? Colors.blue : Colors.white70,
                  fontSize: 11,
                ),
              ),
            ),
          ),

        const Spacer(),

        // 倍速选择
        TextButton(
          key: _speedButtonKey,
          onPressed: _toggleSpeedPanel,
          style: TextButton.styleFrom(
            foregroundColor: _currentSpeed != 1.0 ? Colors.blue : Colors.white,
            padding: EdgeInsets.symmetric(horizontal: fullscreen ? 8 : 4, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            _currentSpeed == 1.0 ? '倍速' : '${_currentSpeed}x',
            style: TextStyle(fontSize: fullscreen ? 13 : 12),
          ),
        ),

        // 清晰度选择
        ValueListenableBuilder<List<String>>(
          valueListenable: widget.logic.availableQualities,
          builder: (context, qualities, _) {
            if (qualities.length <= 1) return const SizedBox.shrink();

            return ValueListenableBuilder<String?>(
              valueListenable: widget.logic.currentQuality,
              builder: (context, currentQuality, _) {
                final qualityDisplayName = currentQuality != null
                    ? widget.logic.getQualityDisplayName(currentQuality)
                    : '画质';
                return TextButton(
                  key: _qualityButtonKey,
                  onPressed: _toggleQualityPanel,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: fullscreen ? 8 : 4, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: PlayerQualityPanel.buildQualityLabel(qualityDisplayName, false),
                );
              },
            );
          },
        ),

        // 后台播放按钮（全屏时显示）
        if (fullscreen)
          ValueListenableBuilder<bool>(
            valueListenable: widget.logic.backgroundPlayEnabled,
            builder: (context, bgEnabled, _) {
              return IconButton(
                icon: Icon(
                  bgEnabled ? Icons.headphones : Icons.headphones_outlined,
                  color: bgEnabled ? Colors.blue : Colors.white,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: bgEnabled ? '后台播放：开' : '后台播放：关',
                onPressed: () {
                  widget.logic.toggleBackgroundPlay();
                  _startHideTimer();
                },
              );
            },
          ),

        // 循环模式按钮（全屏时显示）
        if (fullscreen)
          ValueListenableBuilder(
            valueListenable: widget.logic.loopMode,
            builder: (context, loopMode, _) {
              return IconButton(
                icon: Icon(
                  loopMode.index == 1 ? Icons.repeat_one : Icons.repeat,
                  color: loopMode.index == 1 ? Colors.blue : Colors.white,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  widget.logic.toggleLoopMode();
                  _startHideTimer();
                },
              );
            },
          ),

        // 全屏按钮
        IconButton(
          icon: Icon(
            fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            color: Colors.white,
            size: fullscreen ? 24 : 22,
          ),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: fullscreen ? 36 : 32, minHeight: 32),
          onPressed: () async {
            if (widget.onFullscreenToggle != null) {
              widget.onFullscreenToggle!();
            } else {
              await toggleFullscreen(context);
            }
            await Future.delayed(const Duration(milliseconds: 100));
            if (mounted) _startHideTimer();
          },
        ),
      ],
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