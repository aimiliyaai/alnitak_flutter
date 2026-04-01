import '../utils/image_utils.dart';
import '../utils/json_field.dart';

List<String> _parseTagsField(dynamic v) {
  if (v == null) return [];
  if (v is List) {
    return v.map((e) => e.toString().trim()).where((t) => t.isNotEmpty).toList();
  }
  if (v is String) {
    return v.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }
  return [];
}

/// 视频详情数据模型
class VideoDetail {
  final int vid;
  // 短 ID（后端返回 shortId，可选）
  final String? shortId;
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
    this.shortId,
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
      vid: jsonAsInt(json['vid']),
      shortId: jsonAsStringOrNull(json['shortId']),
      title: jsonAsString(json['title']),
      cover: ImageUtils.getFullImageUrl(jsonAsString(json['cover'])),
      desc: jsonAsString(json['desc']),
      tags: _parseTagsField(json['tags']),
      clicks: jsonAsInt(json['clicks']),
      copyright: json['copyright'] ?? false,
      duration: (json['duration'] ?? 0).toDouble(),
      author: UserInfo.fromJson(
        Map<String, dynamic>.from(json['author'] as Map? ?? {}),
      ),
      resources: (json['resources'] as List<dynamic>?)
              ?.map((e) => VideoResource.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ))
              .toList() ??
          [],
      createdAt: jsonAsDateTime(json['createdAt']),
      danmakuCount: jsonAsInt(json['danmakuCount'] ?? json['danmaku_count']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vid': vid,
      'shortId': shortId,
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
  final String? shortId;
  final String title;
  final String url;
  final double duration;
  final int status;
  final int quality;

  VideoResource({
    required this.id,
    this.shortId,
    required this.title,
    required this.url,
    required this.duration,
    required this.status,
    required this.quality,
  });

  factory VideoResource.fromJson(Map<String, dynamic> json) {
    final playOrUrl = json['playUrl'] ?? json['url'];
    return VideoResource(
      id: jsonAsInt(json['id']),
      shortId: jsonAsStringOrNull(json['shortId']),
      title: jsonAsString(json['title']),
      url: jsonAsString(playOrUrl),
      duration: (json['duration'] ?? 0).toDouble(),
      status: jsonAsInt(json['status']),
      quality: jsonAsInt(json['quality']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (shortId != null) 'shortId': shortId,
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
      uid: jsonAsInt(json['uid']),
      name: jsonAsString(json['name']),
      avatar: ImageUtils.getFullImageUrl(jsonAsString(json['avatar'])),
      sign: jsonAsString(json['sign']),
      fans: jsonAsInt(json['fans']),
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

  VideoStat({
    required this.like,
    required this.collect,
    required this.share,
  });

  factory VideoStat.fromJson(Map<String, dynamic> json) {
    return VideoStat(
      like: json['like'] ?? 0,
      collect: json['collect'] ?? 0,
      share: json['share'] ?? 0,
    );
  }

  VideoStat copyWith({
    int? like,
    int? collect,
    int? share,
  }) {
    return VideoStat(
      like: like ?? this.like,
      collect: collect ?? this.collect,
      share: share ?? this.share,
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
