import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import '../../../controllers/video_player_controller.dart';

/// 自定义播放器 UI
///
/// 完全自主实现的播放器界面，包含：
/// - 顶部标题栏
/// - 底部控制栏（进度条、播放/暂停、清晰度、全屏）
/// - 手势控制（音量、亮度、进度、双击快进/快退/暂停）
/// - 手势反馈 UI
/// - 锁定功能
class CustomPlayerUI extends StatefulWidget {
  final VideoController controller;      // media_kit 的控制器 (用于渲染和播放控制)
  final VideoPlayerController logic;     // 业务控制器 (用于清晰度切换等业务逻辑)
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
  bool _showControls = true; // 是否显示控制栏
  bool _isLocked = false;    // 是否锁定手势
  Timer? _hideTimer;         // 自动隐藏计时器

  // ============ 手势反馈 ============
  bool _showFeedback = false;
  IconData? _feedbackIcon;
  String _feedbackText = '';
  double? _feedbackValue; // 0.0 - 1.0 (音量/亮度进度条)

  // ============ 拖拽逻辑 ============
  bool _isDragging = false;
  Offset _dragStartPos = Offset.zero;
  double _startVolume = 0.0;
  double _startBrightness = 0.5;
  int _gestureType = 0; // 0:无, 1:音量, 2:亮度, 3:进度
  Duration _seekPos = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  // ============ UI 控制逻辑 ============

  /// 启动/重置自动隐藏计时器
  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_isLocked) return; // 锁定状态下不自动隐藏

    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  /// 切换 UI 显示
  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  // ============ 手势处理逻辑 ============

  Future<void> _onDragStart(DragStartDetails details, double width) async {
    if (_isLocked) return;
    _isDragging = true;
    _dragStartPos = details.localPosition;
    setState(() => _showControls = false); // 拖拽时隐藏 UI 防遮挡

    try {
      _startVolume = await VolumeController.instance.getVolume();
      _startBrightness = await ScreenBrightness().application;
    } catch (_) {}
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (_isLocked) return;
    final delta = details.localPosition - _dragStartPos;

    // 防抖动阈值
    if (_gestureType == 0 && delta.distance < 10) return;

    // 判断手势方向
    if (_gestureType == 0) {
      if (delta.dx.abs() > delta.dy.abs()) {
        _gestureType = 3; // 水平滑动 -> 进度调节
      } else {
        // 垂直滑动 -> 左半屏亮度，右半屏音量
        _gestureType = _dragStartPos.dx < width / 2 ? 2 : 1;
      }
    }

    // 执行对应手势逻辑
    if (_gestureType == 1) {
      // 音量调节
      final val = (_startVolume - delta.dy / 200).clamp(0.0, 1.0);
      VolumeController.instance.setVolume(val);
      _showFeedbackUI(Icons.volume_up, '音量 ${(val * 100).toInt()}%', val);
    } else if (_gestureType == 2) {
      // 亮度调节
      final val = (_startBrightness - delta.dy / 200).clamp(0.0, 1.0);
      try {
        ScreenBrightness().setApplicationScreenBrightness(val);
      } catch(_) {}
      _showFeedbackUI(Icons.brightness_medium, '亮度 ${(val * 100).toInt()}%', val);
    } else if (_gestureType == 3) {
      // 进度调节
      final total = widget.controller.player.state.duration.inSeconds;
      final current = widget.controller.player.state.position.inSeconds;
      final seekDelta = (delta.dx / width) * 90; // 全屏滑动约等于 90 秒
      final target = (current + seekDelta).clamp(0, total);
      _seekPos = Duration(seconds: target.toInt());

      final diff = _seekPos.inSeconds - current;
      final sign = diff > 0 ? '+' : '';
      _showFeedbackUI(
        diff > 0 ? Icons.fast_forward : Icons.fast_rewind,
        '${_formatDuration(_seekPos)} / ${_formatDuration(widget.controller.player.state.duration)}\n($sign${diff}秒)',
        null,
      );
    }
  }

  void _onDragEnd() {
    if (_gestureType == 3) {
      widget.controller.player.seek(_seekPos);
    }
    _isDragging = false;
    _gestureType = 0;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _showFeedback = false);
    });
  }

  /// 双击手势处理
  void _onDoubleTap(Offset pos, double width) {
    if (_isLocked) return;
    final leftZone = width * 0.3;
    final rightZone = width * 0.7;

    if (pos.dx < leftZone) {
      // 左侧：快退 10 秒
      final newPos = widget.controller.player.state.position - const Duration(seconds: 10);
      widget.controller.player.seek(newPos < Duration.zero ? Duration.zero : newPos);
      _showFeedbackUI(Icons.fast_rewind, '-10秒', null);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showFeedback = false);
      });
    } else if (pos.dx > rightZone) {
      // 右侧：快进 10 秒
      final newPos = widget.controller.player.state.position + const Duration(seconds: 10);
      final maxPos = widget.controller.player.state.duration;
      widget.controller.player.seek(newPos > maxPos ? maxPos : newPos);
      _showFeedbackUI(Icons.fast_forward, '+10秒', null);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showFeedback = false);
      });
    } else {
      // 中间：暂停/播放切换
      widget.controller.player.playOrPause();
      _toggleControls(); // 双击中间顺便切换 UI 显示状态
    }
  }

  /// 显示手势反馈 UI
  void _showFeedbackUI(IconData icon, String text, double? value) {
    setState(() {
      _showFeedback = true;
      _feedbackIcon = icon;
      _feedbackText = text;
      _feedbackValue = value;
    });
  }

  // ============ 辅助方法 ============

  /// 格式化时长显示 (HH:MM:SS 或 MM:SS)
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

        return Stack(
          fit: StackFit.expand,
          children: [
            // ============================
            // Layer 1: 手势检测层（最底层，铺满全屏）
            // ============================
            GestureDetector(
              behavior: HitTestBehavior.translucent, // 关键：允许点击穿透
              onTap: _toggleControls,
              onDoubleTapDown: (d) => _onDoubleTap(d.localPosition, width),
              onVerticalDragStart: (d) => _onDragStart(d, width),
              onVerticalDragUpdate: (d) => _onDragUpdate(d, width),
              onVerticalDragEnd: (_) => _onDragEnd(),
              onHorizontalDragStart: (d) => _onDragStart(d, width),
              onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
              onHorizontalDragEnd: (_) => _onDragEnd(),
              child: Container(color: Colors.transparent),
            ),

            // ============================
            // Layer 2: 锁定按钮（独立层，锁定时始终显示）
            // ============================
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
                      backgroundColor: Colors.black.withOpacity(0.5),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              ),

            // ============================
            // Layer 3: 手势反馈层（居中显示）
            // ============================
            if (_showFeedback)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
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
                            backgroundColor: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // ============================
            // Layer 4: UI 控制层（最顶层）
            // ============================
            IgnorePointer(
              ignoring: !_showControls, // 隐藏时点击穿透到底层手势层
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Stack(
                  children: [
                    // --- 顶部栏 ---
                    if (!_isLocked) _buildTopBar(),

                    // --- 左侧锁定按钮 ---
                    if (!_isLocked) _buildLockButton(),

                    // --- 中间播放/暂停按钮 ---
                    if (!_isLocked) _buildCenterPlayButton(),

                    // --- 底部控制栏 ---
                    if (!_isLocked) _buildBottomBar(),
                  ],
                ),
              ),
            ),

            // ============================
            // Layer 5: 清晰度切换加载指示器
            // ============================
            ValueListenableBuilder<bool>(
              valueListenable: widget.logic.isSwitchingQuality,
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
                        Text('切换清晰度中...', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ============ UI 组件构建方法 ============

  /// 构建顶部标题栏
  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black.withOpacity(0.6), Colors.transparent],
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
              // 可以在这里添加更多按钮（设置、投屏等）
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建左侧锁定按钮
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
            backgroundColor: Colors.black.withOpacity(0.5),
            padding: const EdgeInsets.all(12),
          ),
        ),
      ),
    );
  }

  /// 构建中间播放/暂停按钮
  Widget _buildCenterPlayButton() {
    return Center(
      child: StreamBuilder<bool>(
        stream: widget.controller.player.stream.playing,
        builder: (context, snapshot) {
          final playing = snapshot.data ?? widget.controller.player.state.playing;
          // 只在暂停时显示中间按钮
          if (playing) return const SizedBox.shrink();

          return IconButton(
            iconSize: 64,
            icon: Icon(
              Icons.play_circle_fill,
              color: Colors.white.withOpacity(0.9),
            ),
            onPressed: () {
              widget.controller.player.play();
              _startHideTimer();
            },
          );
        },
      ),
    );
  }

  /// 构建底部控制栏
  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
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
                      size: 24,
                    ),
                    onPressed: () {
                      widget.controller.player.playOrPause();
                      _startHideTimer();
                    },
                  );
                },
              ),

              // 进度条（缩小版）
              Expanded(child: _buildCompactProgressBar()),

              // 清晰度按钮
              ValueListenableBuilder<List<String>>(
                valueListenable: widget.logic.availableQualities,
                builder: (context, qualities, _) {
                  if (qualities.length <= 1) return const SizedBox.shrink();

                  return ValueListenableBuilder<String?>(
                    valueListenable: widget.logic.currentQuality,
                    builder: (context, currentQuality, _) {
                      return TextButton(
                        onPressed: () => _showQualityDialog(),
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

              // 全屏按钮
              IconButton(
                icon: const Icon(Icons.fullscreen, color: Colors.white, size: 24),
                onPressed: () {
                  // media_kit 会自动处理全屏逻辑
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建进度条行
  Widget _buildProgressRow() {
    return StreamBuilder<Duration>(
      stream: widget.controller.player.stream.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final dur = widget.controller.player.state.duration;
        final bufferDur = widget.controller.player.state.buffer;

        return Row(
          children: [
            // 当前时间
            Text(
              _formatDuration(pos),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),

            // 进度条
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.blue,
                  inactiveTrackColor: Colors.white.withOpacity(0.3),
                  thumbColor: Colors.white,
                  secondaryActiveTrackColor: Colors.white.withOpacity(0.5), // 缓冲进度颜色
                ),
                child: Slider(
                  value: pos.inSeconds.toDouble().clamp(0.0, dur.inSeconds.toDouble()),
                  min: 0,
                  max: dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1.0,
                  secondaryTrackValue: bufferDur.inSeconds.toDouble().clamp(0.0, dur.inSeconds.toDouble()),
                  onChanged: (v) {
                    widget.controller.player.seek(Duration(seconds: v.toInt()));
                    _startHideTimer(); // 拖动时重置隐藏计时
                  },
                ),
              ),
            ),

            // 总时长
            Text(
              _formatDuration(dur),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        );
      },
    );
  }

  /// 构建紧凑版进度条（仅滑块，无时间显示）
  Widget _buildCompactProgressBar() {
    return StreamBuilder<Duration>(
      stream: widget.controller.player.stream.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final dur = widget.controller.player.state.duration;
        final bufferDur = widget.controller.player.state.buffer;

        return SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.blue,
            inactiveTrackColor: Colors.white.withOpacity(0.3),
            thumbColor: Colors.white,
            secondaryActiveTrackColor: Colors.white.withOpacity(0.5),
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
        );
      },
    );
  }

  /// 构建功能按钮行
  Widget _buildButtonRow() {
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
                size: 24,
              ),
              onPressed: () {
                widget.controller.player.playOrPause();
                _startHideTimer();
              },
            );
          },
        ),

        const Spacer(),

        // 清晰度按钮
        ValueListenableBuilder<List<String>>(
          valueListenable: widget.logic.availableQualities,
          builder: (context, qualities, _) {
            if (qualities.length <= 1) return const SizedBox.shrink();

            return ValueListenableBuilder<String?>(
              valueListenable: widget.logic.currentQuality,
              builder: (context, currentQuality, _) {
                return TextButton(
                  onPressed: () => _showQualityDialog(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentQuality != null
                          ? widget.logic.getQualityDisplayName(currentQuality)
                          : '画质',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                );
              },
            );
          },
        ),

        const SizedBox(width: 8),

        // 全屏按钮
        IconButton(
          icon: const Icon(Icons.fullscreen, color: Colors.white, size: 24),
          onPressed: () {
            // media_kit 会自动处理全屏逻辑
            // 如果需要自定义全屏逻辑，可以在这里调用
          },
        ),
      ],
    );
  }

  /// 显示清晰度选择对话框
  void _showQualityDialog() {
    final qualities = widget.logic.availableQualities.value;
    final currentQuality = widget.logic.currentQuality.value;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择清晰度'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: qualities.map((quality) {
            final isSelected = quality == currentQuality;
            final displayName = widget.logic.getQualityDisplayName(quality);

            return ListTile(
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? Colors.blue : Colors.grey,
              ),
              title: Text(
                displayName,
                style: TextStyle(
                  color: isSelected ? Colors.blue : Colors.black87,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              onTap: () {
                if (!isSelected) {
                  widget.logic.changeQuality(quality);
                }
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
