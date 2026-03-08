import 'package:flutter/material.dart';
import '../models/partition.dart';
import '../theme/theme_extensions.dart';

/// 视频/文章投稿页共享的分区选择区块（主分区 + 子分区，支持锁定）
class PartitionSection extends StatelessWidget {
  final List<Partition> parentPartitions;
  final List<Partition> subPartitions;
  final Partition? selectedParent;
  final Partition? selectedSub;
  final bool isLocked;
  final ValueChanged<Partition?> onParentChanged;
  final ValueChanged<Partition?> onSubChanged;
  /// 主分区校验：返回错误文案，null 表示通过。参数为当前主分区与当前子分区。
  final String? Function(Partition? parent, Partition? sub)? parentValidator;

  const PartitionSection({
    super.key,
    required this.parentPartitions,
    required this.subPartitions,
    required this.selectedParent,
    required this.selectedSub,
    required this.isLocked,
    required this.onParentChanged,
    required this.onSubChanged,
    this.parentValidator,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '分区',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (isLocked) ...[
              const SizedBox(width: 8),
              Icon(Icons.lock, size: 16, color: colors.textTertiary),
              const SizedBox(width: 4),
              Text(
                '(分区已锁定，不可修改)',
                style: TextStyle(fontSize: 12, color: colors.textTertiary),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<Partition>(
          initialValue: selectedParent,
          decoration: InputDecoration(
            labelText: '主分区',
            border: const OutlineInputBorder(),
            filled: isLocked,
            fillColor: isLocked ? colors.inputBackground : null,
          ),
          items: parentPartitions.map((partition) {
            return DropdownMenuItem(
              value: partition,
              child: Text(partition.name),
            );
          }).toList(),
          onChanged: isLocked ? null : onParentChanged,
          validator: (value) => parentValidator?.call(value, selectedSub),
        ),
        if (subPartitions.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<Partition>(
            initialValue: selectedSub,
            decoration: InputDecoration(
              labelText: '子分区',
              border: const OutlineInputBorder(),
              filled: isLocked,
              fillColor: isLocked ? colors.inputBackground : null,
            ),
            items: subPartitions.map((partition) {
              return DropdownMenuItem(
                value: partition,
                child: Text(partition.subpartition ?? partition.name),
              );
            }).toList(),
            onChanged: isLocked ? null : onSubChanged,
          ),
        ],
      ],
    );
  }
}
