// =======================
// 历史记录相关模型
// =======================

/// 添加历史记录请求
class AddHistoryRequest {
  final String vid;
  final String? rid;  // 分P的shortId
  final int part;
  final double time;     // 播放进度(秒)，-1 = 已看完
  final int duration;    // ✅ 视频总时长(秒)
  final int? clientSequence;
  final int? clientTimestampMs;

  AddHistoryRequest({
    required this.vid,
    this.rid,
    required this.part,
    required this.time,
    required this.duration,
    this.clientSequence,
    this.clientTimestampMs,
  });

  Map<String, dynamic> toJson() {
    return {
      'vid': vid,
      if (rid != null) 'rid': rid,
      'part': part,
      'time': time,
      'duration': duration, // ✅ 新增
      if (clientSequence != null) 'clientSequence': clientSequence,
      if (clientTimestampMs != null) 'clientTimestampMs': clientTimestampMs,
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
      duration: (json['duration'] as num?)?.toInt() ?? 0,// ✅ 核心字段
    );
  }
}

/// 历史记录项
class HistoryItem {
  final String vid;
  final String? shortId;
  final String? rid;  // 分P的shortId
  final int uid;
  final String title;
  final String cover;
  final String desc;
  final double time;     // 播放进度(秒)，-1 = 已看完
  final int duration;    // ✅ 视频总时长(秒)
  final String updatedAt;

  /// 服务端：绑定 PGC 剧集的视频；与 [epId] 配合用于 `pgc:<vid>:<epId>` 播放入口
  final bool pgcAttached;
  final String? pgcTitle;
  final String? episodeTitle;
  final int episodeNumber;
  final int epId;

  HistoryItem({
    required this.vid,
    this.shortId,
    this.rid,
    required this.uid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.time,
    required this.duration,
    required this.updatedAt,
    this.pgcAttached = false,
    this.pgcTitle,
    this.episodeTitle,
    this.episodeNumber = 0,
    this.epId = 0,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      vid: json['vid']?.toString() ?? '',
      shortId: json['shortId'] as String?,
      rid: json['rid'] as String?,
      uid: json['uid'] as int,
      title: json['title'] as String,
      cover: json['cover'] as String,
      desc: json['desc'] as String,
      time: (json['time'] as num).toDouble(),
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      updatedAt: json['updatedAt'] as String,
      pgcAttached: json['pgcAttached'] as bool? ?? false,
      pgcTitle: json['pgcTitle'] as String?,
      episodeTitle: json['episodeTitle'] as String?,
      episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 0,
      epId: (json['epId'] as num?)?.toInt() ?? 0,
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
