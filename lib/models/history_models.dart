// 历史记录相关模型

/// 添加历史记录请求
class AddHistoryRequest {
  final int vid;
  final int part;
  final double time; // 播放进度(秒)

  AddHistoryRequest({
    required this.vid,
    required this.part,
    required this.time,
  });

  Map<String, dynamic> toJson() {
    return {
      'vid': vid,
      'part': part,
      'time': time,
    };
  }
}

/// 播放进度响应
class PlayProgressData {
  final int part;
  final double progress; // 播放位置(秒)

  PlayProgressData({
    required this.part,
    required this.progress,
  });

  factory PlayProgressData.fromJson(Map<String, dynamic> json) {
    return PlayProgressData(
      part: json['part'] as int,
      progress: (json['progress'] as num).toDouble(),
    );
  }
}

/// 历史记录项
class HistoryItem {
  final int vid;
  final int uid;
  final String title;
  final String cover;
  final String desc;
  final double time; // 播放进度
  final String updatedAt; // 更新时间

  HistoryItem({
    required this.vid,
    required this.uid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.time,
    required this.updatedAt,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      vid: json['vid'] as int,
      uid: json['uid'] as int,
      title: json['title'] as String,
      cover: json['cover'] as String,
      desc: json['desc'] as String,
      time: (json['time'] as num).toDouble(),
      updatedAt: json['updatedAt'] as String,
    );
  }
}

/// 历史记录列表响应
class HistoryListResponse {
  final List<HistoryItem> videos;
  final int total;

  HistoryListResponse({
    required this.videos,
    required this.total,
  });

  factory HistoryListResponse.fromJson(Map<String, dynamic> json) {
    final videosJson = json['videos'] as List<dynamic>? ?? [];
    return HistoryListResponse(
      videos: videosJson.map((e) => HistoryItem.fromJson(e as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
    );
  }
}
