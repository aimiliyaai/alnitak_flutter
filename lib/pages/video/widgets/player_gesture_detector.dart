import 'package:flutter/material.dart';
import 'player_controller_state.dart';

/// 手势指示器类型
enum GestureIndicatorType {
  none,
  volume,      // 音量
  brightness,  // 亮度
  seeking,     // 快进/快退
}

/// 播放器手势检测器
/// 支持:
/// - 单击显示/隐藏控制器
/// - 双击播放/暂停
/// - 左侧上下滑动调节亮度
/// - 右侧上下滑动调节音量
/// - 左右滑动快进/快退
class PlayerGestureDetector extends StatefulWidget {
  final Widget child;
  final PlayerControllerState controllerState;
  final VoidCallback? onPlayPause;
  final ValueChanged<double>? onVolumeChange;      // 0.0 - 1.0
  final ValueChanged<double>? onBrightnessChange;  // 0.0 - 1.0
  final ValueChanged<Duration>? onSeek;
  final Duration currentPosition;
  final Duration totalDuration;

  const PlayerGestureDetector({
    super.key,
    required this.child,
    required this.controllerState,
    required this.currentPosition,
    required this.totalDuration,
    this.onPlayPause,
    this.onVolumeChange,
    this.onBrightnessChange,
    this.onSeek,
  });

  @override
  State<PlayerGestureDetector> createState() => _PlayerGestureDetectorState();
}

class _PlayerGestureDetectorState extends State<PlayerGestureDetector> {
  // 手势指示器状态
  GestureIndicatorType _indicatorType = GestureIndicatorType.none;
  double _indicatorValue = 0.0; // 0.0 - 1.0
  Duration _seekDelta = Duration.zero;

  // 手势检测相关
  Offset? _dragStartPosition;
  double _initialValue = 0.0;
  DateTime? _lastTapTime;

  // 音量和亮度的当前值
  double _currentVolume = 0.5;
  double _currentBrightness = 0.5;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      onVerticalDragStart: _handleVerticalDragStart,
      onVerticalDragUpdate: _handleVerticalDragUpdate,
      onVerticalDragEnd: _handleVerticalDragEnd,
      onHorizontalDragStart: _handleHorizontalDragStart,
      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: Stack(
        children: [
          widget.child,
          // 手势指示器
          if (_indicatorType != GestureIndicatorType.none)
            _buildGestureIndicator(),
        ],
      ),
    );
  }

  void _handleTap() {
    final now = DateTime.now();
    final isDoubleTap = _lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 300);

    if (isDoubleTap) {
      // 双击播放/暂停
      widget.onPlayPause?.call();
      _lastTapTime = null;
    } else {
      // 单击切换控制器显示
      widget.controllerState.toggleVisibility();
      _lastTapTime = now;
    }
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    _dragStartPosition = details.globalPosition;
    final screenWidth = MediaQuery.of(context).size.width;
    final isLeftSide = details.globalPosition.dx < screenWidth / 2;

    if (isLeftSide) {
      // 左侧 - 亮度
      _indicatorType = GestureIndicatorType.brightness;
      _initialValue = _currentBrightness;
    } else {
      // 右侧 - 音量
      _indicatorType = GestureIndicatorType.volume;
      _initialValue = _currentVolume;
    }

    setState(() {
      _indicatorValue = _initialValue;
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_dragStartPosition == null) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final dragDistance = _dragStartPosition!.dy - details.globalPosition.dy;
    final delta = dragDistance / (screenHeight * 0.5); // 屏幕一半高度为满量程

    final newValue = (_initialValue + delta).clamp(0.0, 1.0);

    setState(() {
      _indicatorValue = newValue;
    });

    if (_indicatorType == GestureIndicatorType.volume) {
      _currentVolume = newValue;
      widget.onVolumeChange?.call(newValue);
    } else if (_indicatorType == GestureIndicatorType.brightness) {
      _currentBrightness = newValue;
      widget.onBrightnessChange?.call(newValue);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    setState(() {
      _indicatorType = GestureIndicatorType.none;
    });
    _dragStartPosition = null;
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    _dragStartPosition = details.globalPosition;
    _seekDelta = Duration.zero;
    setState(() {
      _indicatorType = GestureIndicatorType.seeking;
    });
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (_dragStartPosition == null) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final dragDistance = details.globalPosition.dx - _dragStartPosition!.dx;
    final percentage = dragDistance / screenWidth;

    // 最大滑动90秒
    final maxSeekSeconds = 90;
    final seekSeconds = (percentage * maxSeekSeconds).round();

    setState(() {
      _seekDelta = Duration(seconds: seekSeconds);
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_seekDelta != Duration.zero) {
      final newPosition = widget.currentPosition + _seekDelta;
      final clampedPosition = Duration(
        milliseconds: newPosition.inMilliseconds.clamp(
          0,
          widget.totalDuration.inMilliseconds,
        ),
      );
      widget.onSeek?.call(clampedPosition);
    }

    setState(() {
      _indicatorType = GestureIndicatorType.none;
      _seekDelta = Duration.zero;
    });
    _dragStartPosition = null;
  }

  Widget _buildGestureIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIndicatorIcon(),
            const SizedBox(height: 12),
            _buildIndicatorContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicatorIcon() {
    IconData icon;
    switch (_indicatorType) {
      case GestureIndicatorType.volume:
        if (_indicatorValue > 0.66) {
          icon = Icons.volume_up;
        } else if (_indicatorValue > 0.33) {
          icon = Icons.volume_down;
        } else if (_indicatorValue > 0) {
          icon = Icons.volume_mute;
        } else {
          icon = Icons.volume_off;
        }
        break;
      case GestureIndicatorType.brightness:
        if (_indicatorValue > 0.66) {
          icon = Icons.brightness_high;
        } else if (_indicatorValue > 0.33) {
          icon = Icons.brightness_medium;
        } else {
          icon = Icons.brightness_low;
        }
        break;
      case GestureIndicatorType.seeking:
        icon = _seekDelta.isNegative ? Icons.fast_rewind : Icons.fast_forward;
        break;
      default:
        icon = Icons.info;
    }

    return Icon(
      icon,
      size: 40,
      color: Colors.white,
    );
  }

  Widget _buildIndicatorContent() {
    if (_indicatorType == GestureIndicatorType.seeking) {
      final seconds = _seekDelta.inSeconds.abs();
      final sign = _seekDelta.isNegative ? '-' : '+';
      return Text(
        '$sign${seconds}秒',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      );
    } else {
      // 音量/亮度进度条
      return SizedBox(
        width: 120,
        child: Column(
          children: [
            LinearProgressIndicator(
              value: _indicatorValue,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              minHeight: 4,
            ),
            const SizedBox(height: 8),
            Text(
              '${(_indicatorValue * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
  }
}
