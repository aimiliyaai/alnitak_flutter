import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../utils/token_manager.dart';
import '../models/user_model.dart';
import 'logger_service.dart';
/// 用户服务
class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final HttpClient _httpClient = HttpClient();
  final TokenManager _tokenManager = TokenManager();

  /// 根据用户ID获取用户基础信息
  Future<UserBaseInfo?> getUserBaseInfo(int userId) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/user/getUserBaseInfo',
        queryParameters: {'userId': userId},
      );

      if (response.data['code'] == 200) {
        final data = response.data['data'];
        // API 返回的数据可能在 userInfo 字段中
        if (data is Map<String, dynamic>) {
          if (data.containsKey('userInfo')) {
            return UserBaseInfo.fromJson(data['userInfo'] as Map<String, dynamic>);
          }
          return UserBaseInfo.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      LoggerService.instance.logWarning('获取用户基础信息失败: $e', tag: 'UserService');
      return null;
    }
  }

  /// 获取个人用户信息（需要登录）
  Future<UserInfo?> getUserInfo() async {
    // 【新增】检查是否可以进行认证请求
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return null;
    }

    try {
      final token = _tokenManager.token;
      if (token == null) {
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
      LoggerService.instance.logWarning('获取个人用户信息失败: $e', tag: 'UserService');
      return null;
    }
  }

  /// 获取用户关注/粉丝统计
  Future<FollowCount?> getFollowCount(int userId) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/relation/getFollowCount',
        queryParameters: {'userId': userId},
      );

      if (response.data['code'] == 200) {
        return FollowCount.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      LoggerService.instance.logWarning('获取关注粉丝统计失败: $e', tag: 'UserService');
      return null;
    }
  }

  /// 获取用户与当前登录用户的关系
  Future<int> getUserRelation(int userId) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/relation/getUserRelation',
        queryParameters: {'userId': userId},
      );

      if (response.data['code'] == 200) {
        return response.data['data']['relation'] ?? 0;
      }
      return 0;
    } catch (e) {
      LoggerService.instance.logWarning('获取用户关系失败: $e', tag: 'UserService');
      return 0;
    }
  }

  /// 获取指定用户上传的视频列表
  Future<UserVideoListResponse?> getVideoByUser(int userId, int page, int pageSize) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/video/getVideoByUser',
        queryParameters: {
          'userId': userId,
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        return UserVideoListResponse.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      LoggerService.instance.logWarning('获取用户视频列表失败: $e', tag: 'UserService');
      return null;
    }
  }

  /// 获取用户关注列表
  Future<FollowListResponse?> getFollowings(int userId, int page, int pageSize) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/relation/getFollowings',
        queryParameters: {
          'userId': userId,
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        return FollowListResponse.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      LoggerService.instance.logWarning('获取用户关注列表失败: $e', tag: 'UserService');
      return null;
    }
  }

  /// 获取用户粉丝列表
  Future<FollowListResponse?> getFollowers(int userId, int page, int pageSize) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/relation/getFollowers',
        queryParameters: {
          'userId': userId,
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        return FollowListResponse.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      LoggerService.instance.logWarning('获取用户粉丝列表失败: $e', tag: 'UserService');
      return null;
    }
  }

  /// 关注用户
  Future<bool> followUser(int userId) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return false;
    }

    try {
      final response = await _httpClient.dio.post(
        '/api/v1/relation/follow',
        data: {'id': userId},
      );
      return response.data['code'] == 200;
    } catch (e) {
      LoggerService.instance.logWarning('关注用户失败: $e', tag: 'UserService');
      return false;
    }
  }

  /// 取消关注
  Future<bool> unfollowUser(int userId) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return false;
    }

    try {
      final response = await _httpClient.dio.post(
        '/api/v1/relation/unfollow',
        data: {'id': userId},
      );
      return response.data['code'] == 200;
    } catch (e) {
      LoggerService.instance.logWarning('取消关注失败: $e', tag: 'UserService');
      return false;
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
    // 【新增】检查是否可以进行认证请求
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return false;
    }

    try {
      final token = _tokenManager.token;
      if (token == null) {
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
      LoggerService.instance.logWarning('编辑用户信息失败: $e', tag: 'UserService');
      return false;
    }
  }
}
