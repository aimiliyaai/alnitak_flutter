import 'package:flutter/material.dart';

/// 媒体进度条滑块
/// 支持拖动、预览时间、缓冲进度显示
class MediaProgressSlider extends StatefulWidget {
  final Duration currentPosition;  // 当前播放位置
  final Duration totalDuration;    // 总时长
  final Duration bufferedPosition; // 缓冲位置
  final ValueChanged<Duration> onChanged;       // 拖动中回调
  final ValueChanged<Duration>? onChangeEnd;    // 拖动结束回调
  final bool enabled;

  const MediaProgressSlider({
    super.key,
    required this.currentPosition,
    required this.totalDuration,
    required this.bufferedPosition,
    required this.onChanged,
    this.onChangeEnd,
    this.enabled = true,
  });

  @override
  State<MediaProgressSlider> createState() => _MediaProgressSliderState();
}

class _MediaProgressSliderState extends State<MediaProgressSlider> {
  double? _draggingValue; // 拖动时的临时值
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMillis = widget.totalDuration.inMilliseconds.toDouble();
    final currentMillis = widget.currentPosition.inMilliseconds.toDouble();
    final bufferedMillis = widget.bufferedPosition.inMilliseconds.toDouble();

    // 当前显示的值（拖动时使用拖动值，否则使用实际播放位置）
    final displayValue = _draggingValue ?? (totalMillis > 0 ? currentMillis / totalMillis : 0.0);

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3.0,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 6.0,
          elevation: 0,
          pressedElevation: 0,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
        activeTrackColor: theme.colorScheme.primary,
        inactiveTrackColor: theme.colorScheme.onSurface.withOpacity(0.2),
        thumbColor: theme.colorScheme.primary,
        overlayColor: theme.colorScheme.primary.withOpacity(0.2),
        // 自定义轨道形状以显示缓冲进度
        trackShape: _CustomTrackShape(
          bufferedValue: totalMillis > 0 ? bufferedMillis / totalMillis : 0.0,
          bufferedColor: theme.colorScheme.onSurface.withOpacity(0.4),
        ),
      ),
      child: Slider(
        value: displayValue.clamp(0.0, 1.0),
        onChanged: widget.enabled
            ? (value) {
                setState(() {
                  _draggingValue = value;
                  _isDragging = true;
                });
                final position = Duration(
                  milliseconds: (value * totalMillis).round(),
                );
                widget.onChanged(position);
              }
            : null,
        onChangeEnd: widget.enabled
            ? (value) {
                setState(() {
                  _draggingValue = null;
                  _isDragging = false;
                });
                final position = Duration(
                  milliseconds: (value * totalMillis).round(),
                );
                widget.onChangeEnd?.call(position);
              }
            : null,
      ),
    );
  }
}

/// 自定义轨道形状，支持显示缓冲进度
class _CustomTrackShape extends RoundedRectSliderTrackShape {
  final double bufferedValue;
  final Color bufferedColor;

  const _CustomTrackShape({
    required this.bufferedValue,
    required this.bufferedColor,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    // 先绘制原始轨道
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );

    // 绘制缓冲进度
    if (bufferedValue > 0) {
      final trackRect = getPreferredRect(
        parentBox: parentBox,
        offset: offset,
        sliderTheme: sliderTheme,
        isEnabled: isEnabled,
        isDiscrete: isDiscrete,
      );

      final bufferedWidth = trackRect.width * bufferedValue;
      final bufferedRect = Rect.fromLTRB(
        trackRect.left,
        trackRect.top,
        trackRect.left + bufferedWidth,
        trackRect.bottom,
      );

      final paint = Paint()
        ..color = bufferedColor
        ..style = PaintingStyle.fill;

      final radius = sliderTheme.trackHeight! / 2;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(bufferedRect, Radius.circular(radius)),
        paint,
      );
    }
  }
}

/// 时间显示文本（00:00 / 00:00 格式）
class MediaProgressIndicatorText extends StatelessWidget {
  final Duration currentPosition;
  final Duration totalDuration;
  final TextStyle? style;

  const MediaProgressIndicatorText({
    super.key,
    required this.currentPosition,
    required this.totalDuration,
    this.style,
  });

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = style ??
        theme.textTheme.bodySmall?.copyWith(
          color: Colors.white,
          shadows: [
            const Shadow(
              color: Colors.black87,
              offset: Offset(0.5, 0.5),
              blurRadius: 2,
            ),
          ],
        );

    final currentText = _formatDuration(currentPosition);
    final totalText = _formatDuration(totalDuration);

    return Text(
      '$currentText / $totalText',
      style: textStyle,
    );
  }
}
