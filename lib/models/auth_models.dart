// 认证相关数据模型

/// 登录响应
class LoginResponse {
  final String token;
  final String refreshToken;

  LoginResponse({
    required this.token,
    required this.refreshToken,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'refreshToken': refreshToken,
    };
  }
}

/// 注册请求
class RegisterRequest {
  final String email;
  final String password;
  final String code;

  RegisterRequest({
    required this.email,
    required this.password,
    required this.code,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
      'code': code,
    };
  }
}

/// 登录请求（密码登录）
class LoginRequest {
  final String email;
  final String password;
  final String? captchaId;

  LoginRequest({
    required this.email,
    required this.password,
    this.captchaId,
  });

  Map<String, dynamic> toJson() {
    final data = {
      'email': email,
      'password': password,
    };
    if (captchaId != null) {
      data['captchaId'] = captchaId!;
    }
    return data;
  }
}

/// 邮箱验证码登录请求
class EmailLoginRequest {
  final String email;
  final String code;
  final String? captchaId;

  EmailLoginRequest({
    required this.email,
    required this.code,
    this.captchaId,
  });

  Map<String, dynamic> toJson() {
    final data = {
      'email': email,
      'code': code,
    };
    if (captchaId != null) {
      data['captchaId'] = captchaId!;
    }
    return data;
  }
}

/// 修改密码请求
class ModifyPasswordRequest {
  final String email;
  final String password;
  final String code;
  final String? captchaId;

  ModifyPasswordRequest({
    required this.email,
    required this.password,
    required this.code,
    this.captchaId,
  });

  Map<String, dynamic> toJson() {
    final data = {
      'email': email,
      'password': password,
      'code': code,
    };
    if (captchaId != null) {
      data['captchaId'] = captchaId!;
    }
    return data;
  }
}
