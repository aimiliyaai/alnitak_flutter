class VideoApiModel {
  final int vid;
  final int uid;
  final String title;
  final String cover;
  final String desc;
  final String createdAt;
  final bool copyright;
  final String tags;
  final double duration;
  final int clicks;
  final int partitionId;
  final int danmakuCount; // 弹幕数量
  final AuthorModel author;
  final List<ResourceModel> resources;

  VideoApiModel({
    required this.vid,
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
      vid: json['vid'] ?? 0,
      uid: json['uid'] ?? 0,
      title: json['title'] ?? '',
      cover: json['cover'] ?? '',
      desc: json['desc'] ?? '',
      createdAt: json['createdAt'] ?? '',
      copyright: json['copyright'] ?? false,
      tags: json['tags'] ?? '',
      duration: (json['duration'] ?? 0).toDouble(),
      clicks: json['clicks'] ?? 0,
      partitionId: json['partitionId'] ?? 0,
      danmakuCount: json['danmakuCount'] ?? 0,
      author: AuthorModel.fromJson(json['author'] ?? {}),
      resources: (json['resources'] as List<dynamic>?)
              ?.map((r) => ResourceModel.fromJson(r as Map<String, dynamic>))
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
      uid: json['uid'] ?? 0,
      name: json['name'] ?? '',
      sign: json['sign'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      avatar: json['avatar'] ?? '',
      gender: json['gender'] ?? 0,
      spaceCover: json['spaceCover'] ?? '',
      birthday: json['birthday'] ?? '',
      createdAt: json['createdAt'] ?? '',
    );
  }
}

class ResourceModel {
  final int id;
  final String createdAt;
  final int vid;
  final String title;
  final double duration;
  final int status;

  ResourceModel({
    required this.id,
    required this.createdAt,
    required this.vid,
    required this.title,
    required this.duration,
    required this.status,
  });

  factory ResourceModel.fromJson(Map<String, dynamic> json) {
    return ResourceModel(
      id: json['id'] ?? 0,
      createdAt: json['createdAt'] ?? '',
      vid: json['vid'] ?? 0,
      title: json['title'] ?? '',
      duration: (json['duration'] ?? 0).toDouble(),
      status: json['status'] ?? 0,
    );
  }
}
