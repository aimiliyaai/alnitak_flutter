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
      print('🔍 请求验证码，captchaId: $captchaId');
      final response = await _httpClient.dio.get(
        '/api/v1/verify/captcha/get',
        queryParameters: {'captchaId': captchaId},
      );

      print('📡 验证码API响应: ${response.data}');

      if (response.data['code'] == 200) {
        print('✅ 验证码API返回200，开始解析data字段');
        print('   data字段内容: ${response.data['data']}');
        return CaptchaData.fromJson(response.data['data']);
      } else {
        print('⚠️ 验证码API返回非200: code=${response.data['code']}, msg=${response.data['msg']}');
      }
      return null;
    } catch (e, stackTrace) {
      print('❌ 获取验证码失败: $e');
      print('   Stack: $stackTrace');
      return null;
    }
  }

  /// 验证滑块
  Future<bool> validateCaptcha({
    required String captchaId,
    required int x,
  }) async {
    try {
      print('🔍 发送验证请求:');
      print('   - captchaId: $captchaId');
      print('   - x坐标: $x');

      final requestData = CaptchaValidateRequest(
        captchaId: captchaId,
        x: x,
      ).toJson();

      print('   - 请求数据: $requestData');

      final response = await _httpClient.dio.post(
        '/api/v1/verify/captcha/validate',
        data: requestData,
      );

      print('📡 验证响应:');
      print('   - code: ${response.data['code']}');
      print('   - msg: ${response.data['msg']}');
      print('   - 完整响应: ${response.data}');

      final success = response.data['code'] == 200;
      if (success) {
        print('✅ 服务端验证通过');
      } else {
        print('❌ 服务端验证失败: ${response.data['msg']}');
      }

      return success;
    } catch (e, stackTrace) {
      print('❌ 验证滑块请求异常: $e');
      print('   Stack: $stackTrace');
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
