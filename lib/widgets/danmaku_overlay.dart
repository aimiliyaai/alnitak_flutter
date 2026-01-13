import 'package:flutter/material.dart';
import '../models/danmaku.dart';
import '../controllers/danmaku_controller.dart';

/// 弹幕渲染覆盖层
///
/// 商业级弹幕渲染方案：
/// - 高性能渲染：使用 AnimatedBuilder 和 Transform，避免不必要的重绘
/// - 轨道布局：滚动弹幕、顶部固定、底部固定分离渲染
/// - 描边文字：使用 Stack + 描边实现高可读性
/// - 平滑动画：使用 Tween 动画确保弹幕流畅移动
class DanmakuOverlay extends StatelessWidget {
  final DanmakuController controller;
  final double width;
  final double height;

  const DanmakuOverlay({
    super.key,
    required this.controller,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        if (!controller.isVisible) {
          return const SizedBox.shrink();
        }

        final config = controller.config;
        final displayHeight = height * config.displayArea;
        final activeDanmakus = controller.activeDanmakus;

        return ClipRect(
          child: SizedBox(
            width: width,
            height: displayHeight,
            child: Stack(
              children: activeDanmakus.map((item) {
                return _DanmakuItemWidget(
                  key: ValueKey('danmaku_${item.danmaku.id}_${item.startTime}'),
                  item: item,
                  config: config,
                  screenWidth: width,
                  screenHeight: displayHeight,
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

/// 单个弹幕组件
class _DanmakuItemWidget extends StatefulWidget {
  final DanmakuItem item;
  final DanmakuConfig config;
  final double screenWidth;
  final double screenHeight;

  const _DanmakuItemWidget({
    super.key,
    required this.item,
    required this.config,
    required this.screenWidth,
    required this.screenHeight,
  });

  @override
  State<_DanmakuItemWidget> createState() => _DanmakuItemWidgetState();
}

class _DanmakuItemWidgetState extends State<_DanmakuItemWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    final type = widget.item.danmaku.danmakuType;
    final duration = type == DanmakuType.scroll
        ? widget.config.scrollDuration
        : widget.config.fixedDuration;

    // 计算已经过去的时间
    final elapsed = DateTime.now().millisecondsSinceEpoch - widget.item.startTime;
    final remaining = duration.inMilliseconds - elapsed;

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: remaining > 0 ? remaining : 0),
    );

    // 计算初始进度
    final initialProgress = elapsed / duration.inMilliseconds;

    if (type == DanmakuType.scroll) {
      // 滚动弹幕：从右向左移动
      _animation = Tween<double>(
        begin: initialProgress.clamp(0.0, 1.0),
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.linear,
      ));
    } else {
      // 固定弹幕：不移动，只控制显示时间
      _animation = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(_animationController);
    }

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.item.danmaku.danmakuType;
    final config = widget.config;
    final trackIndex = widget.item.trackIndex;

    // 计算轨道高度
    final trackHeight = config.fontSize * 1.5;
    final topOffset = trackIndex * trackHeight;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        double left = 0;
        double? top;
        double? bottom;

        switch (type) {
          case DanmakuType.scroll:
            // 滚动弹幕位置计算
            // progress: 0 -> 弹幕在屏幕右侧外
            // progress: 1 -> 弹幕完全移出屏幕左侧
            final progress = _animation.value;
            // 弹幕移动距离 = 屏幕宽度 + 弹幕宽度（估算300像素）
            final totalDistance = widget.screenWidth + 300;
            left = widget.screenWidth - progress * totalDistance;
            top = topOffset;
            break;

          case DanmakuType.top:
            // 顶部固定弹幕：居中显示
            top = topOffset;
            break;

          case DanmakuType.bottom:
            // 底部固定弹幕：从底部向上排列
            bottom = topOffset;
            break;
        }

        return Positioned(
          left: type == DanmakuType.scroll ? left : null,
          top: top,
          bottom: bottom,
          right: type != DanmakuType.scroll ? null : null,
          child: type == DanmakuType.scroll
              ? child!
              : Center(
                  child: SizedBox(
                    width: widget.screenWidth,
                    child: Center(child: child),
                  ),
                ),
        );
      },
      child: _buildDanmakuText(),
    );
  }

  Widget _buildDanmakuText() {
    final danmaku = widget.item.danmaku;
    final config = widget.config;

    // 解析颜色
    Color textColor;
    try {
      final colorStr = danmaku.color.replaceAll('#', '');
      textColor = Color(int.parse('FF$colorStr', radix: 16));
    } catch (e) {
      textColor = Colors.white;
    }

    // 应用透明度
    textColor = textColor.withOpacity(config.opacity);

    // 描边颜色（深色背景用白色描边，浅色用黑色）
    final strokeColor = _isLightColor(textColor)
        ? Colors.black.withOpacity(config.opacity * 0.8)
        : Colors.black.withOpacity(config.opacity * 0.8);

    return Stack(
      children: [
        // 描边层（4个方向偏移）
        ..._buildStrokeTexts(danmaku.text, config.fontSize, strokeColor),
        // 主文字
        Text(
          danmaku.text,
          style: TextStyle(
            fontSize: config.fontSize,
            color: textColor,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.visible,
        ),
      ],
    );
  }

  /// 判断是否为浅色
  bool _isLightColor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.5;
  }

  /// 构建描边文字
  List<Widget> _buildStrokeTexts(String text, double fontSize, Color strokeColor) {
    const offsets = [
      Offset(-1, -1),
      Offset(1, -1),
      Offset(-1, 1),
      Offset(1, 1),
    ];

    return offsets.map((offset) {
      return Transform.translate(
        offset: offset,
        child: Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            color: strokeColor,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.visible,
        ),
      );
    }).toList();
  }
}

/// 弹幕设置面板
class DanmakuSettingsPanel extends StatelessWidget {
  final DanmakuController controller;
  final VoidCallback? onClose;

  const DanmakuSettingsPanel({
    super.key,
    required this.controller,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final config = controller.config;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题栏
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '弹幕设置',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (onClose != null)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: onClose,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // 弹幕开关
                _buildSwitchRow(
                  '显示弹幕',
                  controller.isVisible,
                  (value) => controller.setVisibility(value),
                ),
                const SizedBox(height: 12),

                // 透明度
                _buildSliderRow(
                  '透明度',
                  config.opacity,
                  0.2,
                  1.0,
                  (value) => controller.updateConfig(
                    config.copyWith(opacity: value),
                  ),
                ),
                const SizedBox(height: 12),

                // 字体大小
                _buildSliderRow(
                  '字体大小',
                  config.fontSize,
                  12,
                  28,
                  (value) => controller.updateConfig(
                    config.copyWith(fontSize: value),
                  ),
                  showValue: true,
                  valueFormat: (v) => '${v.toInt()}',
                ),
                const SizedBox(height: 12),

                // 显示区域
                _buildSliderRow(
                  '显示区域',
                  config.displayArea,
                  0.25,
                  1.0,
                  (value) => controller.updateConfig(
                    config.copyWith(displayArea: value),
                  ),
                  showValue: true,
                  valueFormat: (v) => '${(v * 100).toInt()}%',
                ),
                const SizedBox(height: 12),

                // 弹幕速度
                _buildSliderRow(
                  '弹幕速度',
                  config.speedMultiplier,
                  0.5,
                  2.0,
                  (value) {
                    final duration = Duration(
                      milliseconds: (8000 / value).toInt(),
                    );
                    controller.updateConfig(
                      config.copyWith(
                        scrollDuration: duration,
                        speedMultiplier: value,
                      ),
                    );
                  },
                  showValue: true,
                  valueFormat: (v) => '${v.toStringAsFixed(1)}x',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSwitchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.blue,
        ),
      ],
    );
  }

  Widget _buildSliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    bool showValue = false,
    String Function(double)? valueFormat,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (showValue && valueFormat != null)
              Text(
                valueFormat(value),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: Colors.blue,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayColor: Colors.blue.withOpacity(0.2),
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
