import 'package:flutter/material.dart';
import '../controllers/danmaku_controller.dart';

/// 弹幕输入组件
///
/// 功能特性：
/// - 输入框样式：半透明背景，圆角设计
/// - 颜色选择：预设常用颜色
/// - 类型选择：滚动、顶部、底部
/// - 发送按钮：带加载状态
class DanmakuInput extends StatefulWidget {
  final DanmakuController controller;
  final VoidCallback? onSendSuccess;
  final bool compact; // 紧凑模式（用于全屏播放）

  const DanmakuInput({
    super.key,
    required this.controller,
    this.onSendSuccess,
    this.compact = false,
  });

  @override
  State<DanmakuInput> createState() => _DanmakuInputState();
}

class _DanmakuInputState extends State<DanmakuInput> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _selectedColor = '#ffffff';
  int _selectedType = 0; // 0-滚动, 1-顶部, 2-底部
  bool _isSending = false;
  bool _showOptions = false;

  /// 预设颜色列表
  static const List<String> _presetColors = [
    '#ffffff', // 白色
    '#ff0000', // 红色
    '#ff7204', // 橙色
    '#ffaa02', // 金色
    '#ffff00', // 黄色
    '#00ff00', // 绿色
    '#00ffff', // 青色
    '#0000ff', // 蓝色
    '#aa00ff', // 紫色
    '#ff69b4', // 粉色
  ];

  /// 弹幕类型
  static const List<Map<String, dynamic>> _danmakuTypes = [
    {'type': 0, 'label': '滚动', 'icon': Icons.arrow_forward},
    {'type': 1, 'label': '顶部', 'icon': Icons.vertical_align_top},
    {'type': 2, 'label': '底部', 'icon': Icons.vertical_align_bottom},
  ];

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendDanmaku() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);

    try {
      final success = await widget.controller.sendDanmaku(
        text: text,
        type: _selectedType,
        color: _selectedColor,
      );

      if (success) {
        _textController.clear();
        _focusNode.unfocus();
        setState(() => _showOptions = false);
        widget.onSendSuccess?.call();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('弹幕发送失败')),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompactInput();
    }
    return _buildNormalInput();
  }

  /// 紧凑模式输入框（全屏播放时使用）
  Widget _buildCompactInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // 弹幕开关
          _buildDanmakuToggle(),
          const SizedBox(width: 8),

          // 输入框
          Expanded(
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: '发个弹幕...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                onSubmitted: (_) => _sendDanmaku(),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 设置按钮
          _buildOptionsButton(),
          const SizedBox(width: 4),

          // 发送按钮
          _buildSendButton(compact: true),
        ],
      ),
    );
  }

  /// 普通模式输入框
  Widget _buildNormalInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 输入行
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              // 弹幕开关
              _buildDanmakuToggle(),
              const SizedBox(width: 8),

              // 输入框
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '发个弹幕吧~',
                      hintStyle: TextStyle(
                        color: Theme.of(context).hintColor,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendDanmaku(),
                    onTap: () {
                      setState(() => _showOptions = true);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 设置按钮
              _buildOptionsButton(),
              const SizedBox(width: 8),

              // 发送按钮
              _buildSendButton(),
            ],
          ),
        ),

        // 选项面板
        if (_showOptions) _buildOptionsPanel(),
      ],
    );
  }

  /// 弹幕开关按钮
  Widget _buildDanmakuToggle() {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final isVisible = widget.controller.isVisible;
        return GestureDetector(
          onTap: () => widget.controller.toggleVisibility(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isVisible
                  ? Colors.blue.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '弹',
              style: TextStyle(
                color: isVisible ? Colors.blue : Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 设置按钮
  Widget _buildOptionsButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _showOptions = !_showOptions);
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _showOptions
              ? Colors.blue.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Icons.tune,
          size: 20,
          color: _showOptions
              ? Colors.blue
              : (widget.compact ? Colors.white70 : Colors.grey),
        ),
      ),
    );
  }

  /// 发送按钮
  Widget _buildSendButton({bool compact = false}) {
    return GestureDetector(
      onTap: _isSending ? null : _sendDanmaku,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: _isSending ? Colors.grey : Colors.blue,
          borderRadius: BorderRadius.circular(compact ? 14 : 18),
        ),
        child: _isSending
            ? SizedBox(
                width: compact ? 14 : 16,
                height: compact ? 14 : 16,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                '发送',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  /// 选项面板
  Widget _buildOptionsPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 颜色选择
          Row(
            children: [
              Text(
                '颜色',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: _presetColors.map((color) {
                    final isSelected = color == _selectedColor;
                    Color displayColor;
                    try {
                      final colorStr = color.replaceAll('#', '');
                      displayColor = Color(int.parse('FF$colorStr', radix: 16));
                    } catch (e) {
                      displayColor = Colors.white;
                    }

                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: displayColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.blue : Colors.grey.withValues(alpha: 0.3),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 类型选择
          Row(
            children: [
              Text(
                '位置',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(width: 12),
              ...List.generate(_danmakuTypes.length, (index) {
                final typeInfo = _danmakuTypes[index];
                final isSelected = typeInfo['type'] == _selectedType;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedType = typeInfo['type']),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blue.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            typeInfo['icon'],
                            size: 14,
                            color: isSelected ? Colors.blue : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            typeInfo['label'],
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.blue : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

/// 全屏模式弹幕输入弹窗
class DanmakuInputDialog extends StatelessWidget {
  final DanmakuController controller;

  const DanmakuInputDialog({
    super.key,
    required this.controller,
  });

  static Future<void> show(BuildContext context, DanmakuController controller) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DanmakuInputDialog(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: DanmakuInput(
            controller: controller,
            onSendSuccess: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}
