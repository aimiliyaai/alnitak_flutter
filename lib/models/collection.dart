/// 收藏夹模型
class Collection {
  final int id;
  final String name;
  final String? cover;
  final String? desc;
  final bool? open;
  final String? createdAt;
  bool checked; // UI状态，是否选中

  Collection({
    required this.id,
    required this.name,
    this.cover,
    this.desc,
    this.open,
    this.createdAt,
    this.checked = false,
  });

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      id: json['id'] as int,
      name: json['name'] as String,
      cover: json['cover'] as String?,
      desc: json['desc'] as String?,
      open: json['open'] as bool?,
      createdAt: json['createdAt'] as String?,
      checked: false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (cover != null) 'cover': cover,
      if (desc != null) 'desc': desc,
      if (open != null) 'open': open,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  Collection copyWith({
    int? id,
    String? name,
    String? cover,
    String? desc,
    bool? open,
    String? createdAt,
    bool? checked,
  }) {
    return Collection(
      id: id ?? this.id,
      name: name ?? this.name,
      cover: cover ?? this.cover,
      desc: desc ?? this.desc,
      open: open ?? this.open,
      createdAt: createdAt ?? this.createdAt,
      checked: checked ?? this.checked,
    );
  }
}
