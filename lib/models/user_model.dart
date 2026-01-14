// 用户信息数据模型

/// 用户基础信息
class UserBaseInfo {
  final int uid;
  final String name;
  final String sign;
  final String email;
  final String phone;
  final int status;
  final String avatar;
  final int gender;
  final String spaceCover;
  final String birthday;
  final DateTime createdAt;

  UserBaseInfo({
    required this.uid,
    required this.name,
    required this.sign,
    required this.email,
    required this.phone,
    required this.status,
    required this.avatar,
    required this.gender,
    required this.spaceCover,
    required this.birthday,
    required this.createdAt,
  });

  factory UserBaseInfo.fromJson(Map<String, dynamic> json) {
    return UserBaseInfo(
      uid: json['uid'] ?? 0,
      name: json['name'] ?? '',
      sign: json['sign'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      status: json['status'] ?? 0,
      avatar: json['avatar'] ?? '',
      gender: json['gender'] ?? 0,
      spaceCover: json['spaceCover'] ?? '',
      birthday: json['birthday'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'sign': sign,
      'email': email,
      'phone': phone,
      'status': status,
      'avatar': avatar,
      'gender': gender,
      'spaceCover': spaceCover,
      'birthday': birthday,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// 用户完整信息（个人）
class UserInfo {
  final UserBaseInfo userInfo;
  final BanInfo? ban; // 封禁信息，仅在被封禁时返回

  UserInfo({
    required this.userInfo,
    this.ban,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      userInfo: UserBaseInfo.fromJson(json['userInfo'] as Map<String, dynamic>),
      ban: json['ban'] != null ? BanInfo.fromJson(json['ban'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() {
    final data = {
      'userInfo': userInfo.toJson(),
    };
    if (ban != null) {
      data['ban'] = ban!.toJson();
    }
    return data;
  }
}

/// 封禁信息
class BanInfo {
  final String reason;
  final DateTime bannedUntil;

  BanInfo({
    required this.reason,
    required this.bannedUntil,
  });

  factory BanInfo.fromJson(Map<String, dynamic> json) {
    return BanInfo(
      reason: json['reason'] as String,
      bannedUntil: DateTime.parse(json['bannedUntil'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reason': reason,
      'bannedUntil': bannedUntil.toIso8601String(),
    };
  }
}

/// 编辑用户信息请求
class EditUserInfoRequest {
  final String avatar;
  final String name;
  final int? gender;
  final String birthday;
  final String? sign;
  final String spaceCover;

  EditUserInfoRequest({
    required this.avatar,
    required this.name,
    this.gender,
    required this.birthday,
    this.sign,
    required this.spaceCover,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'avatar': avatar,
      'name': name,
      'birthday': birthday,
      'spaceCover': spaceCover,
    };
    if (gender != null) {
      data['gender'] = gender!;
    }
    if (sign != null) {
      data['sign'] = sign!;
    }
    return data;
  }
}

/// 关注/粉丝统计
class FollowCount {
  final int followingCount;
  final int followerCount;

  FollowCount({
    required this.followingCount,
    required this.followerCount,
  });

  factory FollowCount.fromJson(Map<String, dynamic> json) {
    return FollowCount(
      followingCount: json['followingCount'] ?? 0,
      followerCount: json['followerCount'] ?? 0,
    );
  }
}

/// 用户视频列表响应
class UserVideoListResponse {
  final List<UserVideo> videos;
  final int total;

  UserVideoListResponse({
    required this.videos,
    required this.total,
  });

  factory UserVideoListResponse.fromJson(Map<String, dynamic> json) {
    return UserVideoListResponse(
      videos: (json['videos'] as List<dynamic>?)
              ?.map((e) => UserVideo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] ?? 0,
    );
  }
}

/// 用户视频
class UserVideo {
  final int vid;
  final String title;
  final String cover;
  final String desc;
  final int clicks;
  final int status;
  final DateTime createdAt;

  UserVideo({
    required this.vid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.clicks,
    required this.status,
    required this.createdAt,
  });

  factory UserVideo.fromJson(Map<String, dynamic> json) {
    return UserVideo(
      vid: json['vid'] ?? 0,
      title: json['title'] ?? '',
      cover: json['cover'] ?? '',
      desc: json['desc'] ?? '',
      clicks: json['clicks'] ?? 0,
      status: json['status'] ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

/// 关注/粉丝列表响应
class FollowListResponse {
  final List<FollowUser> list;
  final int total;

  FollowListResponse({
    required this.list,
    required this.total,
  });

  factory FollowListResponse.fromJson(Map<String, dynamic> json) {
    return FollowListResponse(
      list: (json['list'] as List<dynamic>?)
              ?.map((e) => FollowUser.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] ?? 0,
    );
  }
}

/// 关注/粉丝用户信息
class FollowUser {
  final FollowUserInfo user;
  final int relation; // 0未关注 1已关注 2互粉

  FollowUser({
    required this.user,
    required this.relation,
  });

  factory FollowUser.fromJson(Map<String, dynamic> json) {
    return FollowUser(
      user: FollowUserInfo.fromJson(json['user'] as Map<String, dynamic>),
      relation: json['relation'] ?? 0,
    );
  }
}

/// 关注/粉丝用户基本信息
class FollowUserInfo {
  final int uid;
  final String name;
  final String avatar;
  final String sign;

  FollowUserInfo({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.sign,
  });

  factory FollowUserInfo.fromJson(Map<String, dynamic> json) {
    return FollowUserInfo(
      uid: json['uid'] ?? 0,
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '',
      sign: json['sign'] ?? '',
    );
  }
}
