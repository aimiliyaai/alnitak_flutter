// 收藏相关数据模型

/// 收藏夹信息
class CollectionInfo {
  final int id;
  final String name;
  final String cover;
  final String desc;
  final bool open; // 是否公开
  final String createdAt;
  final CollectionAuthor? author;

  CollectionInfo({
    required this.id,
    required this.name,
    required this.cover,
    required this.desc,
    required this.open,
    required this.createdAt,
    this.author,
  });

  factory CollectionInfo.fromJson(Map<String, dynamic> json) {
    return CollectionInfo(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      cover: json['cover'] ?? '',
      desc: json['desc'] ?? '',
      open: json['open'] ?? false,
      createdAt: json['createdAt'] ?? '',
      author: json['author'] != null ? CollectionAuthor.fromJson(json['author']) : null,
    );
  }
}

/// 收藏夹作者信息
class CollectionAuthor {
  final int uid;
  final String name;
  final String avatar;

  CollectionAuthor({
    required this.uid,
    required this.name,
    required this.avatar,
  });

  factory CollectionAuthor.fromJson(Map<String, dynamic> json) {
    return CollectionAuthor(
      uid: json['uid'] ?? 0,
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '',
    );
  }
}

/// 收藏夹列表项（带选中状态，用于收藏弹窗）
class CollectionItem {
  final int id;
  final String name;
  final String cover;
  final String desc;
  final bool open;
  final String createdAt;
  bool checked; // UI状态：是否选中

  CollectionItem({
    required this.id,
    required this.name,
    required this.cover,
    required this.desc,
    required this.open,
    required this.createdAt,
    this.checked = false,
  });

  factory CollectionItem.fromJson(Map<String, dynamic> json) {
    return CollectionItem(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      cover: json['cover'] ?? '',
      desc: json['desc'] ?? '',
      open: json['open'] ?? false,
      createdAt: json['createdAt'] ?? '',
      checked: false,
    );
  }

  CollectionItem copyWith({bool? checked}) {
    return CollectionItem(
      id: id,
      name: name,
      cover: cover,
      desc: desc,
      open: open,
      createdAt: createdAt,
      checked: checked ?? this.checked,
    );
  }
}

/// 收藏夹内的视频
class CollectionVideo {
  final int vid;
  final String title;
  final String cover;
  final String desc;
  final int clicks;
  final double duration;
  final CollectionVideoAuthor author;

  CollectionVideo({
    required this.vid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.clicks,
    required this.duration,
    required this.author,
  });

  factory CollectionVideo.fromJson(Map<String, dynamic> json) {
    return CollectionVideo(
      vid: json['vid'] ?? 0,
      title: json['title'] ?? '',
      cover: json['cover'] ?? '',
      desc: json['desc'] ?? '',
      clicks: json['clicks'] ?? 0,
      duration: (json['duration'] ?? 0).toDouble(),
      author: CollectionVideoAuthor.fromJson(json['author'] ?? {}),
    );
  }

  /// 格式化时长 "mm:ss"
  String get formattedDuration {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 格式化播放次数
  String get formattedClicks {
    if (clicks < 1000) {
      return clicks.toString();
    } else if (clicks < 10000) {
      return '${(clicks / 1000).toStringAsFixed(1)}k';
    } else if (clicks < 100000000) {
      return '${(clicks / 10000).toStringAsFixed(1)}万';
    } else {
      return '${(clicks / 100000000).toStringAsFixed(1)}亿';
    }
  }
}

/// 收藏视频的作者信息
class CollectionVideoAuthor {
  final int uid;
  final String name;
  final String avatar;

  CollectionVideoAuthor({
    required this.uid,
    required this.name,
    required this.avatar,
  });

  factory CollectionVideoAuthor.fromJson(Map<String, dynamic> json) {
    return CollectionVideoAuthor(
      uid: json['uid'] ?? 0,
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '',
    );
  }
}

/// 收藏操作参数
class CollectVideoParams {
  final int vid;
  final List<int> addList; // 新增到的收藏夹ID
  final List<int> cancelList; // 移除的收藏夹ID

  CollectVideoParams({
    required this.vid,
    required this.addList,
    required this.cancelList,
  });

  Map<String, dynamic> toJson() {
    return {
      'vid': vid,
      'addList': addList,
      'cancelList': cancelList,
    };
  }
}
