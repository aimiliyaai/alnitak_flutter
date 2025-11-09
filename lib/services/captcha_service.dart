import 'package:uuid/uuid.dart';
import '../utils/http_client.dart';
import '../models/captcha_models.dart';

/// 人机验证服务
class CaptchaService {
  static final CaptchaService _instance = CaptchaService._internal();
  factory CaptchaService() => _instance;
  CaptchaService._internal();

  final HttpClient _httpClient = HttpClient();
  final Uuid _uuid = const Uuid();

  /// 生成验证码ID
  String generateCaptchaId() {
    return _uuid.v4();
  }

  /// 获取滑块验证数据
  Future<CaptchaData?> getCaptcha(String captchaId) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/verify/captcha/get',
        queryParameters: {'captchaId': captchaId},
      );

      if (response.data['code'] == 200) {
        return CaptchaData.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      print('❌ 获取验证码失败: $e');
      return null;
    }
  }

  /// 验证滑块
  Future<bool> validateCaptcha({
    required String captchaId,
    required int x,
  }) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/verify/captcha/validate',
        data: CaptchaValidateRequest(
          captchaId: captchaId,
          x: x,
        ).toJson(),
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('❌ 验证滑块失败: $e');
      return false;
    }
  }

  /// 发送邮箱验证码
  Future<bool> sendEmailCode({
    required String email,
    required String captchaId,
  }) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/verify/getEmailCode',
        data: EmailCodeRequest(
          email: email,
          captchaId: captchaId,
        ).toJson(),
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('❌ 发送邮箱验证码失败: $e');
      return false;
    }
  }
}
