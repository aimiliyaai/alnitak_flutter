import 'package:uuid/uuid.dart';
import '../utils/http_client.dart';
import '../models/captcha_models.dart';

/// 发送验证码时需要人机验证异常
class SendCodeCaptchaRequiredException implements Exception {
  final String captchaId;

  SendCodeCaptchaRequiredException(this.captchaId);

  @override
  String toString() => '需要人机验证';
}

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
      } else {
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 验证滑块
  Future<bool> validateCaptcha({
    required String captchaId,
    required int x,
  }) async {
    try {

      final requestData = CaptchaValidateRequest(
        captchaId: captchaId,
        x: x,
      ).toJson();


      final response = await _httpClient.dio.post(
        '/api/v1/verify/captcha/validate',
        data: requestData,
      );


      final success = response.data['code'] == 200;
      if (success) {
      } else {
      }

      return success;
    } catch (e) {
      return false;
    }
  }

  /// 发送邮箱验证码
  /// [captchaId] 可选，首次调用可不传，如果服务端要求验证会抛出异常
  /// 抛出 [SendCodeCaptchaRequiredException] 表示需要人机验证
  Future<bool> sendEmailCode({
    required String email,
    String? captchaId,
  }) async {
    try {
      final data = <String, dynamic>{'email': email};
      if (captchaId != null && captchaId.isNotEmpty) {
        data['captchaId'] = captchaId;
      }

      final response = await _httpClient.dio.post(
        '/api/v1/verify/getEmailCode',
        data: data,
      );

      if (response.data['code'] == 200) {
        return true;
      } else if (response.data['code'] == -1) {
        // 需要人机验证，服务端返回 captchaId
        final serverCaptchaId = response.data['data']?['captchaId'] as String? ?? '';
        if (serverCaptchaId.isNotEmpty) {
          throw SendCodeCaptchaRequiredException(serverCaptchaId);
        }
      }
      return false;
    } catch (e) {
      if (e is SendCodeCaptchaRequiredException) {
        rethrow;
      }
      return false;
    }
  }
}
