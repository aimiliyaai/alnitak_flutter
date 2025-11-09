/// 人机验证相关模型

/// 滑块验证响应
class CaptchaData {
  final String sliderImg; // base64滑块图
  final String bgImg; // base64背景图
  final int y; // 滑块左上角y坐标

  CaptchaData({
    required this.sliderImg,
    required this.bgImg,
    required this.y,
  });

  factory CaptchaData.fromJson(Map<String, dynamic> json) {
    return CaptchaData(
      sliderImg: json['slider_img'] as String,
      bgImg: json['bg_img'] as String,
      y: json['y'] as int,
    );
  }
}

/// 滑块验证请求
class CaptchaValidateRequest {
  final String captchaId;
  final int x; // 滑块左上角x坐标

  CaptchaValidateRequest({
    required this.captchaId,
    required this.x,
  });

  Map<String, dynamic> toJson() {
    return {
      'captchaId': captchaId,
      'x': x,
    };
  }
}

/// 邮箱验证码请求
class EmailCodeRequest {
  final String email;
  final String captchaId;

  EmailCodeRequest({
    required this.email,
    required this.captchaId,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'captchaId': captchaId,
    };
  }
}
