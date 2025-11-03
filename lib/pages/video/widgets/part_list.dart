import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/video_detail.dart';

/// 分集列表组件
class PartList extends StatefulWidget {
  final List<VideoResource> resources;
  final int currentPart;
  final Function(int) onPartChange;

  const PartList({
    super.key,
    required this.resources,
    required this.currentPart,
    required this.onPartChange,
  });

  @override
  State<PartList> createState() => _PartListState();
}

class _PartListState extends State<PartList> {
  bool _showTitleMode = true; // true: 显示标题, false: 显示数字网格
  bool _autoNext = true; // 自动连播下一集

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showTitleMode = prefs.getBool('video_part_show_title') ?? true;
      _autoNext = prefs.getBool('video_part_auto_next') ?? true;
    });
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('video_part_show_title', _showTitleMode);
    await prefs.setBool('video_part_auto_next', _autoNext);
  }

  /// 格式化时长
  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    }
  }

  /// 切换显示模式
  void _toggleViewMode() {
    setState(() {
      _showTitleMode = !_showTitleMode;
    });
    _saveSettings();
  }

  /// 切换自动连播
  void _toggleAutoNext() {
    setState(() {
      _autoNext = !_autoNext;
    });
    _saveSettings();
  }

  /// 获取下一集编号
  int? getNextPart() {
    if (!_autoNext) return null;
    final currentIndex = widget.currentPart - 1;
    if (currentIndex < widget.resources.length - 1) {
      return currentIndex + 2; // 返回下一集的编号（从1开始）
    }
    return null;
  }

  /// 构建标题模式
  Widget _buildTitleMode() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.resources.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final part = widget.resources[index];
        final partNumber = index + 1;
        final isCurrentPart = partNumber == widget.currentPart;

        return ListTile(
          selected: isCurrentPart,
          selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isCurrentPart
                  ? Theme.of(context).primaryColor
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                'P$partNumber',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isCurrentPart ? Colors.white : Colors.grey[700],
                ),
              ),
            ),
          ),
          title: Text(
            part.title.isNotEmpty ? part.title : 'P$partNumber',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isCurrentPart ? FontWeight.bold : FontWeight.normal,
              color: isCurrentPart ? Theme.of(context).primaryColor : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _formatDuration(part.duration),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          trailing: isCurrentPart
              ? Icon(Icons.play_circle, color: Theme.of(context).primaryColor)
              : null,
          onTap: () {
            if (!isCurrentPart) {
              widget.onPartChange(partNumber);
            }
          },
        );
      },
    );
  }

  /// 构建网格模式
  Widget _buildGridMode() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.5,
      ),
      itemCount: widget.resources.length,
      itemBuilder: (context, index) {
        final partNumber = index + 1;
        final isCurrentPart = partNumber == widget.currentPart;

        return InkWell(
          onTap: () {
            if (!isCurrentPart) {
              widget.onPartChange(partNumber);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: isCurrentPart
                  ? Theme.of(context).primaryColor
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
              border: isCurrentPart
                  ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                  : null,
            ),
            child: Center(
              child: Text(
                '$partNumber',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isCurrentPart ? Colors.white : Colors.grey[700],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.resources.length <= 1) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部
            Row(
              children: [
                Expanded(
                  child: Text(
                    '合集 (${widget.resources.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // 自动连播开关
                Row(
                  children: [
                    Text(
                      '自动连播',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 4),
                    Switch(
                      value: _autoNext,
                      onChanged: (value) => _toggleAutoNext(),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),

                // 视图切换按钮
                IconButton(
                  icon: Icon(
                    _showTitleMode ? Icons.grid_view : Icons.list,
                    size: 20,
                  ),
                  onPressed: _toggleViewMode,
                  tooltip: _showTitleMode ? '网格视图' : '列表视图',
                ),
              ],
            ),
            const Divider(height: 16),

            // 分集列表
            _showTitleMode ? _buildTitleMode() : _buildGridMode(),
          ],
        ),
      ),
    );
  }
}
