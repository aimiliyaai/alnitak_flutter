import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../models/user_model.dart';
import 'auth_service.dart';

/// 用户服务
class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final HttpClient _httpClient = HttpClient();
  final AuthService _authService = AuthService();

  /// 根据用户ID获取用户基础信息
  Future<UserBaseInfo?> getUserBaseInfo(int userId) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/user/getUserBaseInfo',
        queryParameters: {'userId': userId},
      );

      if (response.data['code'] == 200) {
        return UserBaseInfo.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      print('❌ 获取用户基础信息失败: $e');
      return null;
    }
  }

  /// 获取个人用户信息（需要登录）
  Future<UserInfo?> getUserInfo() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('❌ 未登录，无法获取个人信息');
        return null;
      }

      final response = await _httpClient.dio.get(
        '/api/v1/user/getUserInfo',
        options: Options(
          headers: {
            'Authorization': token,
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.data['code'] == 200) {
        return UserInfo.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      print('❌ 获取个人信息失败: $e');
      return null;
    }
  }

  /// 编辑个人用户信息（需要登录）
  Future<bool> editUserInfo({
    required String avatar,
    required String name,
    int? gender,
    required String birthday,
    String? sign,
    required String spaceCover,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('❌ 未登录，无法编辑个人信息');
        return false;
      }

      final response = await _httpClient.dio.put(
        '/api/v1/user/editUserInfo',
        data: EditUserInfoRequest(
          avatar: avatar,
          name: name,
          gender: gender,
          birthday: birthday,
          sign: sign,
          spaceCover: spaceCover,
        ).toJson(),
        options: Options(
          headers: {
            'Authorization': token,
            'Content-Type': 'application/json',
          },
        ),
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('❌ 编辑个人信息失败: $e');
      return false;
    }
  }
}
