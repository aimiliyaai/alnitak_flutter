import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../models/auth_models.dart';

/// 需要人机验证异常
class CaptchaRequiredException implements Exception {
  final String captchaId;

  CaptchaRequiredException(this.captchaId);

  @override
  String toString() => '需要人机验证';
}

/// 认证服务
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final HttpClient _httpClient = HttpClient();

  // Token 存储键
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';

  /// 用户注册
  Future<bool> register({
    required String email,
    required String password,
    required String code,
  }) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/auth/register',
        data: RegisterRequest(
          email: email,
          password: password,
          code: code,
        ).toJson(),
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('❌ 注册失败: $e');
      return false;
    }
  }

  /// 账号密码登录
  Future<LoginResponse?> login({
    required String email,
    required String password,
    String? captchaId,
  }) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/auth/login',
        data: LoginRequest(
          email: email,
          password: password,
          captchaId: captchaId,
        ).toJson(),
      );

      if (response.data['code'] == 200) {
        final loginResponse = LoginResponse.fromJson(response.data['data']);
        await _saveTokens(loginResponse);
        return loginResponse;
      } else if (response.data['code'] == -1) {
        // 需要人机验证，从服务端返回的 data 中获取 captchaId
        final serverCaptchaId = response.data['data']?['captchaId'] as String? ?? '';
        throw CaptchaRequiredException(serverCaptchaId);
      }
      return null;
    } catch (e) {
      print('❌ 登录失败: $e');
      rethrow;
    }
  }

  /// 邮箱验证码登录
  Future<LoginResponse?> loginWithEmail({
    required String email,
    required String code,
    String? captchaId,
  }) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/auth/login/email',
        data: EmailLoginRequest(
          email: email,
          code: code,
          captchaId: captchaId,
        ).toJson(),
      );

      if (response.data['code'] == 200) {
        final loginResponse = LoginResponse.fromJson(response.data['data']);
        await _saveTokens(loginResponse);
        return loginResponse;
      }
      return null;
    } catch (e) {
      print('❌ 邮箱登录失败: $e');
      rethrow;
    }
  }

  /// 更新 Token
  Future<String?> updateToken() async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) {
        return null;
      }

      final response = await _httpClient.dio.post(
        '/api/v1/auth/updateToken',
        data: {'refreshToken': refreshToken},
      );

      if (response.data['code'] == 200) {
        final newToken = response.data['data']['token'] as String;
        await saveToken(newToken);
        return newToken;
      } else if (response.data['code'] == 2000) {
        // Token 失效，清除本地存储
        await clearTokens();
        return null;
      }
      return null;
    } catch (e) {
      print('❌ 更新 Token 失败: $e');
      return null;
    }
  }

  /// 退出登录
  Future<bool> logout() async {
    try {
      final token = await getToken();
      final refreshToken = await getRefreshToken();

      if (token == null || refreshToken == null) {
        await clearTokens();
        return true;
      }

      final response = await _httpClient.dio.post(
        '/api/v1/auth/logout',
        data: {'refreshToken': refreshToken},
        options: Options(
          headers: {'Authorization': token},
        ),
      );

      await clearTokens();
      return response.data['code'] == 200;
    } catch (e) {
      print('❌ 退出登录失败: $e');
      await clearTokens(); // 即使请求失败，也清除本地 token
      return false;
    }
  }

  /// 修改密码验证
  Future<bool> resetPasswordCheck({
    required String email,
    String? captchaId,
  }) async {
    try {
      final data = {'email': email};
      if (captchaId != null) {
        data['captchaId'] = captchaId;
      }

      final response = await _httpClient.dio.post(
        '/api/v1/auth/resetpwdCheck',
        data: data,
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('❌ 修改密码验证失败: $e');
      return false;
    }
  }

  /// 修改密码
  Future<bool> modifyPassword({
    required String email,
    required String password,
    required String code,
    String? captchaId,
  }) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/auth/modifyPwd',
        data: ModifyPasswordRequest(
          email: email,
          password: password,
          code: code,
          captchaId: captchaId,
        ).toJson(),
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('❌ 修改密码失败: $e');
      return false;
    }
  }

  // ========== Token 管理 ==========

  /// 保存 Tokens
  Future<void> _saveTokens(LoginResponse loginResponse) async {
    await saveToken(loginResponse.token);
    await saveRefreshToken(loginResponse.refreshToken);
  }

  /// 保存 Token
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// 保存 Refresh Token
  Future<void> saveRefreshToken(String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  /// 获取 Token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// 获取 Refresh Token
  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  /// 清除 Tokens
  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
