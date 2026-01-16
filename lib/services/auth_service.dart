import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../utils/token_manager.dart';
import '../models/auth_models.dart';

/// 需要人机验证异常（登录用）
class CaptchaRequiredException implements Exception {
  final String captchaId;

  CaptchaRequiredException(this.captchaId);

  @override
  String toString() => '需要人机验证';
}

/// 重置密码验证需要人机验证异常
class ResetPasswordCaptchaRequiredException implements Exception {
  final String captchaId;

  ResetPasswordCaptchaRequiredException(this.captchaId);

  @override
  String toString() => '需要人机验证';
}

/// 认证服务
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final HttpClient _httpClient = HttpClient();
  final TokenManager _tokenManager = TokenManager();

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
      final refreshToken = _tokenManager.refreshToken;
      if (refreshToken == null) {
        return null;
      }

      final response = await _httpClient.dio.post(
        '/api/v1/auth/updateToken',
        data: {'refreshToken': refreshToken},
      );

      if (response.data['code'] == 200) {
        final newToken = response.data['data']['token'] as String;
        await _tokenManager.updateToken(newToken);
        return newToken;
      } else if (response.data['code'] == 2000) {
        // Token 失效，触发自动退出
        await _tokenManager.handleTokenExpired();
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
      final token = _tokenManager.token;
      final refreshToken = _tokenManager.refreshToken;

      if (token == null || refreshToken == null) {
        await _tokenManager.clearTokens();
        return true;
      }

      final response = await _httpClient.dio.post(
        '/api/v1/auth/logout',
        data: {'refreshToken': refreshToken},
        options: Options(
          headers: {'Authorization': token},
        ),
      );

      await _tokenManager.clearTokens();
      return response.data['code'] == 200;
    } catch (e) {
      print('❌ 退出登录失败: $e');
      await _tokenManager.clearTokens(); // 即使请求失败，也清除本地 token
      return false;
    }
  }

  /// 修改密码验证
  /// 抛出 [ResetPasswordCaptchaRequiredException] 表示需要人机验证
  Future<bool> resetPasswordCheck({
    required String email,
    String? captchaId,
  }) async {
    try {
      final data = <String, dynamic>{'email': email};
      if (captchaId != null && captchaId.isNotEmpty) {
        data['captchaId'] = captchaId;
      }

      final response = await _httpClient.dio.post(
        '/api/v1/auth/resetpwdCheck',
        data: data,
      );

      if (response.data['code'] == 200) {
        return true;
      } else if (response.data['code'] == -1) {
        // 需要人机验证
        final serverCaptchaId = response.data['data']?['captchaId'] as String? ?? '';
        if (serverCaptchaId.isNotEmpty) {
          throw ResetPasswordCaptchaRequiredException(serverCaptchaId);
        }
      }
      print('❌ 修改密码验证失败: ${response.data['msg']}');
      return false;
    } catch (e) {
      if (e is ResetPasswordCaptchaRequiredException) {
        rethrow;
      }
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

  // ========== Token 管理（统一使用 TokenManager）==========

  /// 保存 Tokens（登录成功后调用）
  Future<void> _saveTokens(LoginResponse loginResponse) async {
    await _tokenManager.saveTokens(
      token: loginResponse.token,
      refreshToken: loginResponse.refreshToken,
    );
  }

  /// 获取 Token（同步）
  String? getToken() {
    return _tokenManager.token;
  }

  /// 获取 Refresh Token（同步）
  String? getRefreshToken() {
    return _tokenManager.refreshToken;
  }

  /// 清除 Tokens
  Future<void> clearTokens() async {
    await _tokenManager.clearTokens();
  }

  /// 检查是否已登录（同步，基于内存缓存）
  bool isLoggedIn() {
    return _tokenManager.isLoggedIn;
  }

  /// 检查是否已登录（异步版本，确保 TokenManager 已初始化）
  Future<bool> isLoggedInAsync() async {
    if (!_tokenManager.isInitialized) {
      await _tokenManager.initialize();
    }
    return _tokenManager.isLoggedIn;
  }
}
