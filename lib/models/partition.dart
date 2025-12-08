/// 分区模型
class Partition {
  final int id;
  final String name;
  final String? subpartition; // 子分区名称
  final int? parentId; // 父分区ID

  Partition({
    required this.id,
    required this.name,
    this.subpartition,
    this.parentId,
  });

  factory Partition.fromJson(Map<String, dynamic> json) {
    final parentId = json['parentId'] as int?;
    return Partition(
      id: json['id'] as int,
      name: json['name'] as String,
      subpartition: json['subpartition'] as String?,
      // 如果 parentId 为 0，视为 null（顶级分区）
      parentId: (parentId == null || parentId == 0) ? null : parentId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (subpartition != null) 'subpartition': subpartition,
      if (parentId != null) 'parentId': parentId,
    };
  }
}

/// 分区响应模型
class PartitionResponse {
  final List<Partition> partitions;

  PartitionResponse({required this.partitions});

  factory PartitionResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final List<dynamic> partitionList = data['partitions'] as List<dynamic>;
    return PartitionResponse(
      partitions: partitionList
          .map((item) => Partition.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
