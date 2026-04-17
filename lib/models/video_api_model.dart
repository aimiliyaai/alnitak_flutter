import '../utils/json_field.dart';

List<String> _parseTags(dynamic v) {
  if (v == null) return [];
  if (v is List) {
    return v.map((e) => e.toString().trim()).where((t) => t.isNotEmpty).toList();
  }
  if (v is String) {
    return v.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }
  return [];
}

class VideoApiModel {
  final String vid;
  // 短 ID（后端返回 shortId，可选）
  final String? shortId;
  final int uid;
  final String title;
  final String cover;
  final String desc;
  final String createdAt;
  final bool copyright;
  final List<String> tags;
  final double duration;
  final int clicks;
  final int partitionId;
  final int danmakuCount; // 弹幕数量
  final AuthorModel author;
  final List<ResourceModel> resources;

  VideoApiModel({
    required this.vid,
    this.shortId,
    required this.uid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.createdAt,
    required this.copyright,
    required this.tags,
    required this.duration,
    required this.clicks,
    required this.partitionId,
    required this.danmakuCount,
    required this.author,
    required this.resources,
  });

  factory VideoApiModel.fromJson(Map<String, dynamic> json) {
    return VideoApiModel(
      vid: jsonAsString(json['vid']),
      shortId: jsonAsStringOrNull(json['shortId']),
      uid: jsonAsInt(json['uid']),
      title: jsonAsString(json['title']),
      cover: jsonAsString(json['cover']),
      desc: jsonAsString(json['desc']),
      createdAt: jsonAsString(json['createdAt']),
      copyright: json['copyright'] ?? false,
      tags: _parseTags(json['tags']),
      duration: (json['duration'] ?? 0).toDouble(),
      clicks: jsonAsInt(json['clicks']),
      partitionId: jsonAsInt(json['partitionId']),
      danmakuCount: jsonAsInt(json['danmakuCount'] ?? json['danmaku_count']),
      author: AuthorModel.fromJson(
        Map<String, dynamic>.from(json['author'] as Map? ?? {}),
      ),
      resources: (json['resources'] as List<dynamic>?)
              ?.map((r) => ResourceModel.fromJson(
                    Map<String, dynamic>.from(r as Map),
                  ))
              .toList() ??
          [],
    );
  }

  // 将时长（秒）转换为 "mm:ss" 格式
  String get formattedDuration {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class AuthorModel {
  final int uid;
  final String name;
  final String sign;
  final String email;
  final String phone;
  final String avatar;
  final int gender;
  final String spaceCover;
  final String birthday;
  final String createdAt;

  AuthorModel({
    required this.uid,
    required this.name,
    required this.sign,
    required this.email,
    required this.phone,
    required this.avatar,
    required this.gender,
    required this.spaceCover,
    required this.birthday,
    required this.createdAt,
  });

  factory AuthorModel.fromJson(Map<String, dynamic> json) {
    return AuthorModel(
      uid: jsonAsInt(json['uid']),
      name: jsonAsString(json['name']),
      sign: jsonAsString(json['sign']),
      email: jsonAsString(json['email']),
      phone: jsonAsString(json['phone']),
      avatar: jsonAsString(json['avatar']),
      gender: jsonAsInt(json['gender']),
      spaceCover: jsonAsString(json['spaceCover']),
      birthday: jsonAsString(json['birthday']),
      createdAt: jsonAsString(json['createdAt']),
    );
  }
}

class ResourceModel {
  final String id;
  // 资源短 ID（后端返回 shortId，可选）
  final String? shortId;
  final String createdAt;
  final String vid;
  final String title;
  final double duration;
  final int status;

  ResourceModel({
    required this.id,
    this.shortId,
    required this.createdAt,
    required this.vid,
    required this.title,
    required this.duration,
    required this.status,
  });

  factory ResourceModel.fromJson(Map<String, dynamic> json) {
    return ResourceModel(
      id: jsonAsString(json['id']),
      shortId: jsonAsStringOrNull(json['shortId']),
      createdAt: jsonAsString(json['createdAt']),
      vid: jsonAsString(json['vid']),
      title: jsonAsString(json['title']),
      duration: (json['duration'] ?? 0).toDouble(),
      status: jsonAsInt(json['status']),
    );
  }
}
