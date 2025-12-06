import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../controllers/video_player_controller.dart';

/// 自定义播放器 UI (V8 完整版)
///
/// 包含修改：
/// 1. 进度条 Stream 监听 `logic.positionStream` (防跳变关键)。
/// 2. 清晰度切换时隐藏播放按钮。
/// 3. 清晰度 UI 更透明。
/// 4. 面板右对齐、手势优化等所有累积修复。
class CustomPlayerUI extends StatefulWidget {
  final VideoController controller;      
  final VideoPlayerController logic;     
  final String title;
  final VoidCallback? onBack;

  const CustomPlayerUI({
    super.key,
    required this.controller,
    required this.logic,
    this.title = '',
    this.onBack,
  });

  @override
  State<CustomPlayerUI> createState() => _CustomPlayerUIState();
}

class _CustomPlayerUIState extends State<CustomPlayerUI> {
  // ============ UI 状态 ============
  bool _showControls = true; 
  bool _isLocked = false;    
  Timer? _hideTimer;         

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

  @override
  void initState() {
    super.initState();
    _startHideTimer();
    _playerBrightness = 1.0; 
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  // ============ UI 控制逻辑 ============

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_isLocked) return; 

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
    } else {
      final RenderBox? buttonBox = _qualityButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final RenderBox? overlayBox = context.findRenderObject() as RenderBox?;

      if (buttonBox != null && overlayBox != null) {
        final Offset buttonPos = buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox);
        final Size buttonSize = buttonBox.size;
        final Size overlaySize = overlayBox.size;

        setState(() {
          // 右对齐
          double distFromRight = overlaySize.width - (buttonPos.dx + buttonSize.width);
          _panelRight = distFromRight.clamp(0.0, overlaySize.width);
          
          _panelBottom = overlaySize.height - buttonPos.dy + 4;
          _showQualityPanel = true;
        });
        _hideTimer?.cancel();
      }
    }
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
      final val = (_startVolumeSnapshot - delta.dy / sensitivity).clamp(0.0, 1.0);
      widget.controller.player.setVolume(val * 100); 
      _showFeedbackUI(Icons.volume_up, '音量 ${(val * 100).toInt()}%', val);

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
      widget.controller.player.seek(_seekPos);
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
    _showFeedbackUI(Icons.fast_forward, '2.0x 倍速播放', null);
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
      final currentPos = widget.controller.player.state.position;
      final newPos = currentPos - const Duration(seconds: 10);
      widget.controller.player.seek(newPos < Duration.zero ? Duration.zero : newPos);
      _showFeedbackUI(Icons.fast_rewind, '-10秒', null);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showFeedback = false);
      });
    } else if (pos.dx > rightZone) {
      final currentPos = widget.controller.player.state.position;
      final maxPos = widget.controller.player.state.duration;
      final newPos = currentPos + const Duration(seconds: 10);
      widget.controller.player.seek(newPos > maxPos ? maxPos : newPos);
      _showFeedbackUI(Icons.fast_forward, '+10秒', null);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showFeedback = false);
      });
    } else {
      widget.controller.player.playOrPause();
      _toggleControls(); 
    }
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
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(alpha: 0.5),
                            padding: const EdgeInsets.all(12),
                          ),
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

                  // 4. 控制 UI
                  IgnorePointer(
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
                            color: Colors.black.withValues(alpha: 0.5), // 更透
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

                  // 6. 清晰度面板
                  if (_showQualityPanel && _showControls && _panelRight != null)
                    _buildQualityPanel(),
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
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
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
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.5),
            padding: const EdgeInsets.all(12),
          ),
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
            builder: (context, snapshot) {
              final playing = snapshot.data ?? widget.controller.player.state.playing;
              if (playing) return const SizedBox.shrink();

              return IconButton(
                iconSize: 64,
                icon: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                onPressed: () {
                  widget.controller.player.play();
                  _startHideTimer();
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              StreamBuilder<bool>(
                stream: widget.controller.player.stream.playing,
                builder: (context, snapshot) {
                  final playing = snapshot.data ?? widget.controller.player.state.playing;
                  return IconButton(
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      widget.controller.player.playOrPause();
                      _startHideTimer();
                    },
                  );
                },
              ),

              Expanded(child: _buildCompactProgressBar()),

              ValueListenableBuilder<List<String>>(
                valueListenable: widget.logic.availableQualities,
                builder: (context, qualities, _) {
                  if (qualities.length <= 1) return const SizedBox.shrink();

                  return ValueListenableBuilder<String?>(
                    valueListenable: widget.logic.currentQuality,
                    builder: (context, currentQuality, _) {
                      return TextButton(
                        key: _qualityButtonKey, 
                        onPressed: _toggleQualityPanel, 
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          currentQuality != null
                              ? widget.logic.getQualityDisplayName(currentQuality)
                              : '画质',
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    },
                  );
                },
              ),

              ValueListenableBuilder(
                valueListenable: widget.logic.loopMode,
                builder: (context, loopMode, _) {
                  return IconButton(
                    icon: Icon(
                      loopMode.index == 1 ? Icons.repeat_one : Icons.repeat,
                      color: loopMode.index == 1 ? Colors.blue : Colors.white,
                      size: 22,
                    ),
                    onPressed: () {
                      widget.logic.toggleLoopMode();
                      _startHideTimer();
                    },
                  );
                },
              ),

              Builder(
                builder: (context) {
                  final fullscreen = isFullscreen(context);
                  return IconButton(
                    icon: Icon(
                      fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () async {
                      await toggleFullscreen(context);
                      await Future.delayed(const Duration(milliseconds: 100));
                      if (mounted) _startHideTimer();
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactProgressBar() {
    // 【关键修改】使用 widget.logic.positionStream 而不是原生的 player stream
    // 这样在切换清晰度时，可以接收到 Controller 发送的"静止"位置，防止跳变
    return StreamBuilder<Duration>(
      stream: widget.logic.positionStream, 
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final dur = widget.controller.player.state.duration;
        final bufferDur = widget.controller.player.state.buffer;

        return Row(
          children: [
            Text(
              _formatDuration(pos),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.blue,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                  thumbColor: Colors.white,
                  secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.5),
                ),
                child: Slider(
                  value: pos.inSeconds.toDouble().clamp(0.0, dur.inSeconds.toDouble()),
                  min: 0,
                  max: dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1.0,
                  secondaryTrackValue: bufferDur.inSeconds.toDouble().clamp(0.0, dur.inSeconds.toDouble()),
                  onChanged: (v) {
                    widget.controller.player.seek(Duration(seconds: v.toInt()));
                    _startHideTimer();
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(dur),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        );
      },
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
                    child: Text(
                      displayName,
                      style: TextStyle(
                        color: isSelected ? Colors.blue : Colors.white,
                        fontSize: 13,
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