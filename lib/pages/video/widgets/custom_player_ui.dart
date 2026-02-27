import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../controllers/video_player_controller.dart';
import '../../../controllers/danmaku_controller.dart';
import '../../../widgets/danmaku_overlay.dart';

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

  const CustomPlayerUI({
    super.key,
    required this.controller,
    required this.logic,
    this.title = '',
    this.onBack,
    this.danmakuController,
    this.onlineCount,
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

  // ============ 手势反馈 ============
  bool _showFeedback = false;
  IconData? _feedbackIcon;
  String _feedbackText = '';
  double? _feedbackValue;

  // ============ 拖拽逻辑 ============
  Offset _dragStartPos = Offset.zero;
  int _gestureType = 0;

  double _playerBrightness = 1.0;
  double _startVolumeSnapshot = 1.0;
  double _startBrightnessSnapshot = 1.0;
  Duration _seekPos = Duration.zero;

  // ============ 长按倍速 ============
  bool _isLongPressing = false;
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
    super.dispose();
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

  void _toggleQualityPanel() {
    if (_showQualityPanel) {
      setState(() => _showQualityPanel = false);
      _startHideTimer();
      return;
    }

    final buttonBox = _qualityButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox == null) return;

    final isFull = isFullscreen(context);
    final buttonGlobalPos = buttonBox.localToGlobal(Offset.zero);
    final buttonSize = buttonBox.size;
    final overlaySize = (context.findRenderObject() as RenderBox).size;

    setState(() {
      final distFromRight = overlaySize.width - (buttonGlobalPos.dx + buttonSize.width);
      _panelRight = (distFromRight - 15.0).clamp(0.0, overlaySize.width - 76);

      final buttonBottomToScreenBottom = overlaySize.height - (buttonGlobalPos.dy + buttonSize.height);
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
      if (mounted) setState(() => _showFeedback = false);
    });
  }

  void _onLongPressStart() {
    if (_isLocked) return;
    _isLongPressing = true;
    _normalSpeed = widget.controller.player.state.rate;
    widget.controller.player.setRate(2.0);
    // 长按倍速不使用大的反馈UI，而是使用顶部小标签
    setState(() {});
  }

  void _onLongPressEnd() {
    if (!_isLongPressing) return;
    _isLongPressing = false;
    widget.controller.player.setRate(_normalSpeed);
    setState(() => _showFeedback = false);
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
      widget.controller.player.playOrPause();
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
      if (mounted) setState(() => _showFeedback = false);
    });
  }

  void _showFeedbackUI(IconData icon, String text, double? value) {
    setState(() {
      _showFeedback = true;
      _feedbackIcon = icon;
      _feedbackText = text;
      _feedbackValue = value;
    });
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

                  // 1.5 亮度遮罩
                  if (_playerBrightness < 1.0)
                    IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(alpha: (1.0 - _playerBrightness).clamp(0.0, 0.8)),
                      ),
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

                  // 3. 手势反馈
                  if (_showFeedback)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_feedbackIcon, color: Colors.white, size: 40),
                            const SizedBox(height: 8),
                            Text(
                              _feedbackText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (_feedbackValue != null) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: 100,
                                height: 4,
                                child: LinearProgressIndicator(
                                  value: _feedbackValue,
                                  color: Colors.blue,
                                  backgroundColor: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  // 3.5 长按倍速小标签（顶部居中）
                  if (_isLongPressing)
                    Positioned(
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
                            // 重播按钮始终显示
                            Center(child: _buildCenterPlayButton()),
                            // 控制UI可切换显示/隐藏
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

                  // 5.5 缓冲/加载中提示
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.logic.isBuffering,
                    builder: (context, isBuffering, _) {
                      // 只有在缓冲且不在切换清晰度时才显示
                      final isSwitching = widget.logic.isSwitchingQuality.value;
                      if (!isBuffering || isSwitching) return const SizedBox.shrink();

                      return Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                '加载中...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // 6. 清晰度面板
                  if (_showQualityPanel && _showControls && _panelRight != null)
                    _buildQualityPanel(),

                  // 6.5 倍速选择面板
                  if (_showSpeedPanel && _showControls)
                    _buildSpeedPanel(),

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

  Widget _buildTopBar() {
    // 在顶层获取全屏状态，供所有子组件使用
    final fullscreen = isFullscreen(context);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
              ),
              // 【修改】仅在全屏模式下显示标题，限制宽度不超过屏幕中间
              Expanded(
                child: Builder(
                  builder: (context) {
                    // 检测全屏状态变化
                    if (fullscreen && !_wasFullscreen) {
                      // 刚进入全屏，重置动画状态并延迟启动
                      _wasFullscreen = true;
                      _hasPlayedTitleAnimation = false;
                      _titleScrollController.reset();
                      // 延迟启动动画
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && widget.title.isNotEmpty) {
                          _checkAndStartTitleAnimation();
                        }
                      });
                    } else if (!fullscreen && _wasFullscreen) {
                      // 退出全屏，重置状态
                      _wasFullscreen = false;
                      _hasPlayedTitleAnimation = false;
                      _titleScrollController.reset();
                    }

                    // 只在全屏时显示标题
                    if (!fullscreen || widget.title.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    // 限制标题最大宽度为可用宽度的 50%（不超过中间位置）
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final maxTitleWidth = constraints.maxWidth * 0.5;
                        return _buildScrollableTitle(maxTitleWidth);
                      },
                    );
                  },
                ),
              ),
              // 在看人数（右侧，仅全屏时显示）
              if (widget.onlineCount != null && fullscreen)
                ValueListenableBuilder<int>(
                  valueListenable: widget.onlineCount!,
                  builder: (context, count, _) {
                    // count=0 时也显示，便于确认 WebSocket 是否工作
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.remove_red_eye_outlined,
                            color: Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            count > 0 ? '$count人在看' : '连接中...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 检查标题是否需要滚动动画，并启动
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

  /// 构建可滚动的标题组件
  Widget _buildScrollableTitle(double maxWidth) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AnimatedBuilder(
        animation: _titleScrollAnimation,
        builder: (context, child) {
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

          final isOverflow = textPainter.width > maxWidth;

          // 如果不溢出或动画已完成，显示带省略号的静态文本
          if (!isOverflow || _titleScrollController.isCompleted) {
            return Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            );
          }

          // 溢出且动画进行中，显示滚动文本
          final scrollDistance = textPainter.width - maxWidth + 30;
          final offset = _titleScrollAnimation.value * scrollDistance;

          return ClipRect(
            child: Transform.translate(
              offset: Offset(-offset, 0),
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          );
        },
      ),
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
                        widget.logic.seek(Duration.zero);
                        widget.controller.player.play();
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
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        // 进度条和控制按钮的容器
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            // 从透明到黑色渐变
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 第一行：进度条
              _buildProgressRow(),
              //进度条间距
              const SizedBox(height: 2),
              // 第二行：控制按钮
              _buildControlButtonsRow(),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建进度条行（时间 + 进度条 + 时间）
  ///
  /// pili_plus 风格：使用 ValueListenableBuilder + 秒级 ValueNotifier，
  /// 最多 1Hz 更新，拖拽时冻结不接收 mpv 回报的位置。
  Widget _buildProgressRow() {
    return ValueListenableBuilder<int>(
      valueListenable: widget.logic.sliderPositionSeconds,
      builder: (context, posSeconds, _) {
        return ValueListenableBuilder<int>(
          valueListenable: widget.logic.durationSeconds,
          builder: (context, durSeconds, _) {
            return ValueListenableBuilder<int>(
              valueListenable: widget.logic.bufferedSeconds,
              builder: (context, bufSeconds, _) {
                final maxVal = durSeconds > 0 ? durSeconds.toDouble() : 1.0;
                final displayPos = Duration(seconds: posSeconds);
                final displayDur = Duration(seconds: durSeconds);

                return Row(
                  children: [
                    Text(
                      _formatDuration(displayPos),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4.0,
                          thumbShape: const _CustomSliderThumbShape(
                            enabledThumbRadius: 7,
                            thumbColor: Colors.blue,
                            borderColor: Colors.white,
                            borderWidth: 2,
                          ),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
                          activeTrackColor: Colors.blue,
                          inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                          thumbColor: Colors.blue,
                          secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.5),
                        ),
                        child: Slider(
                          value: posSeconds.toDouble().clamp(0.0, maxVal),
                          min: 0,
                          max: maxVal,
                          secondaryTrackValue: bufSeconds.toDouble().clamp(0.0, maxVal),
                          onChangeStart: (_) {
                            widget.logic.onSliderDragStart();
                          },
                          onChanged: (v) {
                            widget.logic.onSliderDragUpdate(Duration(seconds: v.toInt()));
                            _startHideTimer();
                          },
                          onChangeEnd: (v) {
                            widget.logic.onSliderDragEnd(Duration(seconds: v.toInt()));
                            _startHideTimer();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(displayDur),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// 构建控制按钮行
  Widget _buildControlButtonsRow() {
    final fullscreen = isFullscreen(context);

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
                widget.controller.player.playOrPause();
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
                  child: _buildQualityLabel(qualityDisplayName, false),
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
            await toggleFullscreen(context);
            await Future.delayed(const Duration(milliseconds: 100));
            if (mounted) _startHideTimer();
          },
        ),
      ],
    );
  }

  Widget _buildQualityPanel() {
    final qualities = widget.logic.availableQualities.value;
    final currentQuality = widget.logic.currentQuality.value;

    return Positioned(
      right: _panelRight ?? 16,
      bottom: _panelBottom ?? 50,
      child: GestureDetector(
        onTap: () {}, // 拦截点击穿透
        child: Container(
          width: 76,
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: qualities.map((quality) {
                final isSelected = quality == currentQuality;
                final displayName = widget.logic.getQualityDisplayName(quality);

                return InkWell(
                  onTap: () {
                    if (!isSelected) widget.logic.changeQuality(quality);
                    setState(() => _showQualityPanel = false);
                    _startHideTimer();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    alignment: Alignment.center,
                    child: _buildQualityLabel(displayName, isSelected),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建清晰度标签，高帧率后缀（如"60"）使用特殊样式
  Widget _buildQualityLabel(String displayName, bool isSelected) {
    // 匹配末尾的帧率数字，如 "1080P60" → base="1080P", fps="60"
    final match = RegExp(r'^(.+?P|[24]K)(\d+)$').firstMatch(displayName);
    if (match == null) {
      return Text(
        displayName,
        style: TextStyle(
          color: isSelected ? Colors.blue : Colors.white,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
      );
    }

    final base = match.group(1)!;
    final fps = match.group(2)!;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: base,
            style: TextStyle(
              color: isSelected ? Colors.blue : Colors.white,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          TextSpan(
            text: fps,
            style: TextStyle(
              color: isSelected ? Colors.blue : const Color(0xFF4FC3F7),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  void _toggleSpeedPanel() {
    // 计算按钮位置
    if (!_showSpeedPanel) {
      final RenderBox? renderBox = _speedButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final buttonPosition = renderBox.localToGlobal(Offset.zero);
        final screenWidth = MediaQuery.of(context).size.width;
        // 面板右边缘对齐按钮右边缘
        _speedPanelRight = screenWidth - buttonPosition.dx - renderBox.size.width;
      }
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

  Widget _buildSpeedPanel() {
    return Positioned(
      right: (_speedPanelRight ?? 100) - 12, // 向右偏移
      bottom: 50, // 对齐底部控制栏上方
      child: GestureDetector(
        onTap: () {}, // 拦截点击穿透
        child: Container(
          width: 64,
          constraints: const BoxConstraints(maxHeight: 180), // 降低最大高度
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _speedOptions.map((speed) {
                final isSelected = speed == _currentSpeed;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _currentSpeed = speed;
                      _showSpeedPanel = false;
                    });
                    widget.controller.player.setRate(speed);
                    _startHideTimer();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    alignment: Alignment.center,
                    child: Text(
                      speed == 1.0 ? '正常' : '${speed}x',
                      style: TextStyle(
                        color: isSelected ? Colors.blue : Colors.white,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomSliderThumbShape extends SliderComponentShape {
  final double enabledThumbRadius;
  final Color thumbColor;
  final Color borderColor;
  final double borderWidth;

  const _CustomSliderThumbShape({
    this.enabledThumbRadius = 7.0,
    this.thumbColor = Colors.blue,
    this.borderColor = Colors.white,
    this.borderWidth = 2.0,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(enabledThumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Paint paint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;

    final radius = enabledThumbRadius;
    final path = Path()..addOval(Rect.fromCircle(center: center, radius: radius));

    canvas.drawPath(path, borderPaint);
    canvas.drawPath(path, paint);
  }
}