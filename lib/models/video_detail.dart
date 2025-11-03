import '../utils/image_utils.dart';

/// 视频详情数据模型
class VideoDetail {
  final int vid;
  final String title;
  final String cover;
  final String desc;
  final List<String> tags;
  final int clicks;
  final bool copyright;
  final double duration;
  final UserInfo author;
  final List<VideoResource> resources;
  final DateTime createdAt;
  final int danmakuCount;

  VideoDetail({
    required this.vid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.tags,
    required this.clicks,
    required this.copyright,
    required this.duration,
    required this.author,
    required this.resources,
    required this.createdAt,
    required this.danmakuCount,
  });

  factory VideoDetail.fromJson(Map<String, dynamic> json) {
    return VideoDetail(
      vid: json['vid'] ?? 0,
      title: json['title'] ?? '',
      cover: ImageUtils.getFullImageUrl(json['cover']),
      desc: json['desc'] ?? '',
      tags: json['tags'] != null
          ? (json['tags'] as String).split(',').where((t) => t.isNotEmpty).toList()
          : [],
      clicks: json['clicks'] ?? 0,
      copyright: json['copyright'] ?? false,
      duration: (json['duration'] ?? 0).toDouble(),
      author: UserInfo.fromJson(json['author'] ?? {}),
      resources: (json['resources'] as List<dynamic>?)
              ?.map((e) => VideoResource.fromJson(e))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      danmakuCount: json['danmaku_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vid': vid,
      'title': title,
      'cover': cover,
      'desc': desc,
      'tags': tags.join(','),
      'clicks': clicks,
      'copyright': copyright,
      'duration': duration,
      'author': author.toJson(),
      'resources': resources.map((e) => e.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'danmaku_count': danmakuCount,
    };
  }
}

/// 视频资源（分P）
class VideoResource {
  final int id;
  final String title;
  final String url;
  final double duration;
  final int status;
  final int quality;

  VideoResource({
    required this.id,
    required this.title,
    required this.url,
    required this.duration,
    required this.status,
    required this.quality,
  });

  factory VideoResource.fromJson(Map<String, dynamic> json) {
    return VideoResource(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      url: json['url'] ?? '',
      duration: (json['duration'] ?? 0).toDouble(),
      status: json['status'] ?? 0,
      quality: json['quality'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'duration': duration,
      'status': status,
      'quality': quality,
    };
  }
}

/// 用户信息
class UserInfo {
  final int uid;
  final String name;
  final String avatar;
  final String sign;
  final int fans;

  UserInfo({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.sign,
    required this.fans,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      uid: json['uid'] ?? 0,
      name: json['name'] ?? '',
      avatar: ImageUtils.getFullImageUrl(json['avatar']),
      sign: json['sign'] ?? '',
      fans: json['fans'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'avatar': avatar,
      'sign': sign,
      'fans': fans,
    };
  }
}

/// 视频统计信息
class VideoStat {
  final int like;
  final int collect;
  final int share;
  final int onlineCount;

  VideoStat({
    required this.like,
    required this.collect,
    required this.share,
    this.onlineCount = 0,
  });

  factory VideoStat.fromJson(Map<String, dynamic> json) {
    return VideoStat(
      like: json['like'] ?? 0,
      collect: json['collect'] ?? 0,
      share: json['share'] ?? 0,
      onlineCount: json['online_count'] ?? 0,
    );
  }

  VideoStat copyWith({
    int? like,
    int? collect,
    int? share,
    int? onlineCount,
  }) {
    return VideoStat(
      like: like ?? this.like,
      collect: collect ?? this.collect,
      share: share ?? this.share,
      onlineCount: onlineCount ?? this.onlineCount,
    );
  }
}

/// 用户操作状态
class UserActionStatus {
  final bool hasLiked;
  final bool hasCollected;
  final int relationStatus; // 0: 未关注, 1: 已关注, 2: 互粉

  UserActionStatus({
    required this.hasLiked,
    required this.hasCollected,
    required this.relationStatus,
  });

  factory UserActionStatus.fromJson(Map<String, dynamic> json) {
    return UserActionStatus(
      hasLiked: json['has_liked'] ?? false,
      hasCollected: json['has_collected'] ?? false,
      relationStatus: json['relation_status'] ?? 0,
    );
  }

  UserActionStatus copyWith({
    bool? hasLiked,
    bool? hasCollected,
    int? relationStatus,
  }) {
    return UserActionStatus(
      hasLiked: hasLiked ?? this.hasLiked,
      hasCollected: hasCollected ?? this.hasCollected,
      relationStatus: relationStatus ?? this.relationStatus,
    );
  }
}
