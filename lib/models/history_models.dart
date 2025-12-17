// =======================
// 历史记录相关模型
// =======================

/// 添加历史记录请求
class AddHistoryRequest {
  final int vid;
  final int part;
  final double time;     // 播放进度(秒)，-1 = 已看完
  final int duration;    // ✅ 视频总时长(秒)

  AddHistoryRequest({
    required this.vid,
    required this.part,
    required this.time,
    required this.duration,
  });

  Map<String, dynamic> toJson() {
    return {
      'vid': vid,
      'part': part,
      'time': time,
      'duration': duration, // ✅ 新增
    };
  }
}

/// 播放进度响应
class PlayProgressData {
  final int part;
  final double progress; // 播放位置(秒)，-1 = 已看完
  final int duration;    // ✅ 当前分P总时长(秒)

  PlayProgressData({
    required this.part,
    required this.progress,
    required this.duration,
  });

  factory PlayProgressData.fromJson(Map<String, dynamic> json) {
    return PlayProgressData(
      part: json['part'] as int,
      progress: (json['progress'] as num).toDouble(),
      duration: json['duration'] ?? 0, // ✅ 兼容老接口
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
  final double time;     // 播放进度(秒)，-1 = 已看完
  final int duration;    // ✅ 视频总时长(秒)
  final String updatedAt;

  HistoryItem({
    required this.vid,
    required this.uid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.time,
    required this.duration,
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
      duration: json['duration'] ?? 0, // ✅ 核心字段
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
      videos: videosJson
          .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
    );
  }
}
