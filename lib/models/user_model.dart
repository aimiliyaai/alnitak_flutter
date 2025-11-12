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
      uid: json['uid'] as int,
      name: json['name'] as String,
      sign: json['sign'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      status: json['status'] as int,
      avatar: json['avatar'] as String? ?? '',
      gender: json['gender'] as int? ?? 0,
      spaceCover: json['spaceCover'] as String? ?? '',
      birthday: json['birthday'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
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
