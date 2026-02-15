import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../utils/token_manager.dart';

/// 合集创建/编辑结果
class PlaylistResult {
  final bool success;
  final String? errorMessage;
  final dynamic data;

  PlaylistResult({
    required this.success,
    this.errorMessage,
    this.data,
  });
}

/// 合集(Playlist) API 服务
class PlaylistApiService {
  static final PlaylistApiService _instance = PlaylistApiService._internal();
  factory PlaylistApiService() => _instance;
  PlaylistApiService._internal();

  final Dio _dio = HttpClient().dio;
  final TokenManager _tokenManager = TokenManager();

  // ==================== 公开接口 ====================

  /// 获取视频所属的合集列表
  Future<List<Map<String, dynamic>>> getVideoPlaylists(int vid) async {
    try {
      final response = await _dio.get(
        '/api/v1/playlist/video/playlists',
        queryParameters: {'vid': vid},
      );
      if (response.data['code'] == 200) {
        final playlists = response.data['data']['playlists'] as List<dynamic>?;
        return playlists?.cast<Map<String, dynamic>>() ?? [];
      }
      return [];
    } catch (e) {
      print('获取视频合集失败: $e');
      return [];
    }
  }

  /// 获取合集的视频列表
  Future<List<Map<String, dynamic>>> getPlaylistVideos(
    int playlistId, {
    int page = 1,
    int pageSize = 200,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/playlist/video/list',
        queryParameters: {
          'playlistId': playlistId,
          'page': page,
          'pageSize': pageSize,
        },
      );
      if (response.data['code'] == 200) {
        final videos = response.data['data']['videos'] as List<dynamic>?;
        return videos?.cast<Map<String, dynamic>>() ?? [];
      }
      return [];
    } catch (e) {
      print('获取合集视频列表失败: $e');
      return [];
    }
  }

  // ==================== 管理接口（需要登录） ====================

  /// 获取自己的合集列表
  Future<List<Map<String, dynamic>>> getMyPlaylists() async {
    if (!_tokenManager.canMakeAuthenticatedRequest) return [];
    try {
      final response = await _dio.get('/api/v1/playlist/myList');
      if (response.data['code'] == 200) {
        final playlists = response.data['data']['playlists'] as List<dynamic>?;
        return playlists?.cast<Map<String, dynamic>>() ?? [];
      }
      return [];
    } catch (e) {
      print('获取我的合集列表失败: $e');
      return [];
    }
  }

  /// 创建合集
  Future<PlaylistResult> addPlaylist({
    required String title,
    String cover = '',
    String desc = '',
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return PlaylistResult(
        success: false,
        errorMessage: '未登录',
      );
    }

    try {
      final response = await _dio.post(
        '/api/v1/playlist/add',
        data: {'title': title, 'cover': cover, 'desc': desc},
      );
      
      if (response.data['code'] == 200) {
        return PlaylistResult(
          success: true,
          data: response.data['data'],
        );
      } else {
        return PlaylistResult(
          success: false,
          errorMessage: response.data['msg']?.toString() ?? '创建失败',
        );
      }
    } catch (e) {
      print('创建合集失败: $e');
      return PlaylistResult(
        success: false,
        errorMessage: '网络错误，请稍后重试',
      );
    }
  }

  /// 编辑合集
  Future<PlaylistResult> editPlaylist({
    required int id,
    required String title,
    String cover = '',
    String desc = '',
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return PlaylistResult(
        success: false,
        errorMessage: '未登录',
      );
    }

    try {
      final response = await _dio.put(
        '/api/v1/playlist/edit',
        data: {
          'id': id,
          'title': title,
          'cover': cover,
          'desc': desc,
        },
      );
      
      if (response.data['code'] == 200) {
        return PlaylistResult(success: true);
      } else {
        return PlaylistResult(
          success: false,
          errorMessage: response.data['msg']?.toString() ?? '编辑失败',
        );
      }
    } catch (e) {
      print('编辑合集失败: $e');
      return PlaylistResult(
        success: false,
        errorMessage: '网络错误，请稍后重试',
      );
    }
  }

  /// 删除合集
  Future<bool> deletePlaylist(int id) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) return false;
    try {
      final response = await _dio.delete('/api/v1/playlist/del/$id');
      return response.data['code'] == 200;
    } catch (e) {
      print('删除合集失败: $e');
      return false;
    }
  }

  /// 添加视频到合集
  Future<bool> addPlaylistVideos({
    required int playlistId,
    required List<int> vids,
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) return false;
    try {
      final response = await _dio.post(
        '/api/v1/playlist/video/add',
        data: {'playlistId': playlistId, 'vids': vids},
      );
      return response.data['code'] == 200;
    } catch (e) {
      print('添加视频到合集失败: $e');
      return false;
    }
  }

  /// 从合集移除视频
  Future<bool> delPlaylistVideos({
    required int playlistId,
    required List<int> vids,
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) return false;
    try {
      final response = await _dio.post(
        '/api/v1/playlist/video/del',
        data: {'playlistId': playlistId, 'vids': vids},
      );
      return response.data['code'] == 200;
    } catch (e) {
      print('从合集移除视频失败: $e');
      return false;
    }
  }

  /// 调整合集视频排序
  Future<bool> sortPlaylistVideos({
    required int playlistId,
    required List<int> vids,
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) return false;
    try {
      final response = await _dio.post(
        '/api/v1/playlist/video/sort',
        data: {'playlistId': playlistId, 'vids': vids},
      );
      return response.data['code'] == 200;
    } catch (e) {
      print('调整合集视频排序失败: $e');
      return false;
    }
  }

  /// 获取合集审核记录
  Future<String> getPlaylistReviewRecord(int id) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) return '未登录';
    try {
      final response = await _dio.get(
        '/api/v1/playlist/getPlaylistReviewRecord',
        queryParameters: {'id': id},
      );
      if (response.data['code'] == 200) {
        return response.data['data']['remark'] ?? '暂无原因说明';
      }
      return '暂无原因说明';
    } catch (e) {
      print('获取合集审核记录失败: $e');
      return '获取失败';
    }
  }

  /// 获取用户所有合集中的视频ID映射（vid -> playlistId）
  Future<Map<int, int>> getMyPlaylistVideoIds() async {
    if (!_tokenManager.canMakeAuthenticatedRequest) return {};
    try {
      final response = await _dio.get('/api/v1/playlist/video/myVideoIds');
      if (response.data['code'] == 200) {
        final map = response.data['data']['videoPlaylistMap'] as Map<String, dynamic>?;
        if (map == null) return {};
        return map.map((key, value) => MapEntry(int.parse(key), (value as num).toInt()));
      }
      return {};
    } catch (e) {
      print('获取合集视频映射失败: $e');
      return {};
    }
  }

  /// 获取用户所有视频（用于添加到合集的选择列表）
  Future<List<Map<String, dynamic>>> getAllVideoList() async {
    if (!_tokenManager.canMakeAuthenticatedRequest) return [];
    try {
      final response = await _dio.get('/api/v1/video/getAllVideoList');
      if (response.data['code'] == 200) {
        final videos = response.data['data']['videos'] as List<dynamic>?;
        return videos?.cast<Map<String, dynamic>>() ?? [];
      }
      return [];
    } catch (e) {
      print('获取所有视频列表失败: $e');
      return [];
    }
  }

  /// 获取合集视频列表（包含多分P展开和当前视频分P）
  Future<Map<String, dynamic>?> getPlaylistVideoListWithParts(int vid) async {
    try {
      final response = await _dio.get(
        '/api/v1/playlist/video/listWithParts',
        queryParameters: {'vid': vid},
      );
      if (response.data['code'] == 200) {
        return response.data['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      print('获取合集视频列表（含分P）失败: $e');
      return null;
    }
  }
}
