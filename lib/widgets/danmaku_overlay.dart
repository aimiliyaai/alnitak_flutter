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
/// - 暂停支持：暂停时弹幕静止
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
        final isPlaying = controller.isPlaying;

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
                  isPlaying: isPlaying,
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
  final bool isPlaying;

  const _DanmakuItemWidget({
    super.key,
    required this.item,
    required this.config,
    required this.screenWidth,
    required this.screenHeight,
    required this.isPlaying,
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
    _setupAnimation();
  }

  void _setupAnimation() {
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
    final initialProgress = (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);

    if (type == DanmakuType.scroll) {
      // 滚动弹幕：从右向左移动
      _animation = Tween<double>(
        begin: initialProgress,
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

    // 根据播放状态决定是否启动动画
    if (widget.isPlaying) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(_DanmakuItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 播放状态变化时控制动画
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _animationController.forward();
      } else {
        _animationController.stop();
      }
    }
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

    // 解析颜色 - 支持多种格式：#fff, #ffffff, fff, ffffff
    Color textColor = _parseColor(danmaku.color);

    // 应用透明度
    textColor = textColor.withValues(alpha: config.opacity);

    // 描边颜色（始终使用黑色描边，确保可读性）
    final strokeColor = Colors.black.withValues(alpha: config.opacity * 0.8);

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

  /// 解析颜色字符串
  /// 支持格式：#fff, #ffffff, fff, ffffff, #RRGGBB, RRGGBB
  Color _parseColor(String colorStr) {
    try {
      // 移除 # 前缀
      String hex = colorStr.replaceAll('#', '').trim();

      // 处理简写格式 (fff -> ffffff)
      if (hex.length == 3) {
        hex = hex.split('').map((c) => '$c$c').join();
      }

      // 确保是6位
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }

      // 如果是8位（包含透明度）
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (e) {
      // 解析失败，返回白色
    }
    return Colors.white;
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

/// 弹幕设置面板 - B站风格紧凑设计
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
        final filter = controller.filter;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.9),
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
                    Row(
                      children: [
                        const Text(
                          '弹幕设置',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${controller.totalCount}条',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (onClose != null)
                      GestureDetector(
                        onTap: onClose,
                        child: const Icon(Icons.close, color: Colors.white54, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // 弹幕类型屏蔽
                _buildSectionTitle('屏蔽类型'),
                const SizedBox(height: 6),
                _buildTypeFilterRow(controller, filter),
                const SizedBox(height: 10),

                // 屏蔽等级
                _buildSliderRow(
                  '屏蔽等级',
                  filter.disableLevel.toDouble(),
                  0,
                  10,
                  (value) => controller.setDisableLevel(value.toInt()),
                  showValue: true,
                  valueFormat: (v) => v.toInt().toString(),
                ),
                const SizedBox(height: 8),

                // 透明度
                _buildSliderRow(
                  '不透明度',
                  config.opacity,
                  0.2,
                  1.0,
                  (value) => controller.updateConfig(config.copyWith(opacity: value)),
                  showValue: true,
                  valueFormat: (v) => '${(v * 100).toInt()}%',
                ),
                const SizedBox(height: 8),

                // 字体大小
                _buildSliderRow(
                  '字体大小',
                  config.fontSize,
                  12,
                  28,
                  (value) => controller.updateConfig(config.copyWith(fontSize: value)),
                  showValue: true,
                  valueFormat: (v) => '${v.toInt()}',
                ),
                const SizedBox(height: 8),

                // 显示区域
                _buildSliderRow(
                  '显示区域',
                  config.displayArea,
                  0.25,
                  1.0,
                  (value) => controller.updateConfig(config.copyWith(displayArea: value)),
                  showValue: true,
                  valueFormat: (v) => _getDisplayAreaText(v),
                ),
                const SizedBox(height: 8),

                // 弹幕速度
                _buildSliderRow(
                  '弹幕速度',
                  config.speedMultiplier,
                  0.5,
                  2.0,
                  (value) {
                    final duration = Duration(milliseconds: (8000 / value).toInt());
                    controller.updateConfig(config.copyWith(
                      scrollDuration: duration,
                      speedMultiplier: value,
                    ));
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

  String _getDisplayAreaText(double value) {
    if (value >= 1.0) return '全屏';
    if (value >= 0.75) return '3/4屏';
    if (value >= 0.5) return '半屏';
    if (value >= 0.25) return '1/4屏';
    return '${(value * 100).toInt()}%';
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
        fontSize: 12,
      ),
    );
  }

  Widget _buildTypeFilterRow(DanmakuController controller, DanmakuFilter filter) {
    const types = [
      {'type': 0, 'label': '滚动'},
      {'type': 1, 'label': '顶部'},
      {'type': 2, 'label': '底部'},
      {'type': 3, 'label': '彩色'},
    ];

    return Row(
      children: types.map((item) {
        final type = item['type'] as int;
        final label = item['label'] as String;
        final isDisabled = filter.disabledTypes.contains(type);

        return Expanded(
          child: GestureDetector(
            onTap: () => controller.toggleTypeFilter(type),
            child: Container(
              margin: EdgeInsets.only(right: type < 3 ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isDisabled
                    ? Colors.blue.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDisabled ? Colors.blue : Colors.white24,
                  width: 1,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDisabled ? Colors.blue : Colors.white70,
                  fontSize: 12,
                  fontWeight: isDisabled ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
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
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.blue,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.blue.withValues(alpha: 0.2),
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        if (showValue && valueFormat != null)
          SizedBox(
            width: 40,
            child: Text(
              valueFormat(value),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

/// 弹幕发送输入框组件
class DanmakuSendBar extends StatefulWidget {
  final DanmakuController controller;
  final VoidCallback? onSendStart;
  final VoidCallback? onSendEnd;

  const DanmakuSendBar({
    super.key,
    required this.controller,
    this.onSendStart,
    this.onSendEnd,
  });

  @override
  State<DanmakuSendBar> createState() => _DanmakuSendBarState();
}

class _DanmakuSendBarState extends State<DanmakuSendBar> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // 弹幕发送设置
  int _danmakuType = 0; // 0滚动 1顶部 2底部
  String _danmakuColor = 'fff';
  bool _showStylePanel = false;
  bool _isSending = false;

  // 预设颜色
  static const List<String> _presetColors = [
    'fff', 'e54256', 'ffe133', 'ff7204', 'a0ee00',
    '64dd17', '39ccff', 'd500f9', 'fb7299', '9b9b9b',
  ];

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendDanmaku() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    widget.onSendStart?.call();

    try {
      final success = await widget.controller.sendDanmaku(
        text: text,
        type: _danmakuType,
        color: _danmakuColor,
      );

      if (success) {
        _textController.clear();
        _focusNode.unfocus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('弹幕发送成功'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('弹幕发送失败，请稍后重试'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
      widget.onSendEnd?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 弹幕样式设置面板
        if (_showStylePanel) _buildStylePanel(),
        // 输入栏
        _buildInputBar(),
      ],
    );
  }

  Widget _buildInputBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          // 弹幕数量
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              return Text(
                '${widget.controller.totalCount}条弹幕',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              );
            },
          ),
          const SizedBox(width: 12),

          // 样式设置按钮
          GestureDetector(
            onTap: () => setState(() => _showStylePanel = !_showStylePanel),
            child: Container(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.text_fields,
                color: _showStylePanel ? Colors.blue : Colors.white70,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 输入框
          Expanded(
            child: Container(
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '发个弹幕呗~',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  border: InputBorder.none,
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendDanmaku(),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 发送按钮
          GestureDetector(
            onTap: _isSending ? null : _sendDanmaku,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: _isSending ? Colors.grey : Colors.blue,
                borderRadius: BorderRadius.circular(14),
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      '发送',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),

          const SizedBox(width: 4),

          // Close Button
          IconButton(
            onPressed: () => widget.onSendEnd?.call(),
            icon: const Icon(
              Icons.close,
              color: Colors.white70,
              size: 20,
            ),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildStylePanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 弹幕颜色
          Row(
            children: [
              Text(
                '弹幕颜色',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              // 当前颜色预览
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Color(int.parse('FF$_danmakuColor', radix: 16)),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 颜色选择
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presetColors.map((color) {
              final isSelected = color == _danmakuColor;
              return GestureDetector(
                onTap: () => setState(() => _danmakuColor = color),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Color(int.parse('FF$color', radix: 16)),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.white30,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // 弹幕类型
          Text(
            '弹幕类型',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildTypeButton(0, '滚动'),
              const SizedBox(width: 8),
              _buildTypeButton(1, '顶部'),
              const SizedBox(width: 8),
              _buildTypeButton(2, '底部'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeButton(int type, String label) {
    final isSelected = _danmakuType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _danmakuType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.white24,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.blue : Colors.white70,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
