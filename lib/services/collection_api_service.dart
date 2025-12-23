import '../models/collection_models.dart';
import '../utils/http_client.dart';

/// 收藏API服务
class CollectionApiService {
  final HttpClient _httpClient = HttpClient();

  // ==================== 收藏夹管理 ====================

  /// 创建收藏夹
  Future<int?> createCollection(String name) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/collection/addCollection',
        data: {'name': name},
      );

      if (response.data['code'] == 200) {
        return response.data['data']['id'] as int?;
      }
      return null;
    } catch (e) {
      print('创建收藏夹失败: $e');
      return null;
    }
  }

  /// 获取收藏夹列表
  Future<List<CollectionItem>> getCollectionList() async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/collection/getCollectionList',
      );

      if (response.data['code'] == 200) {
        final list = response.data['data']['collections'] as List<dynamic>? ?? [];
        return list.map((e) => CollectionItem.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('获取收藏夹列表失败: $e');
      return [];
    }
  }

  /// 获取收藏夹详细信息
  Future<CollectionInfo?> getCollectionInfo(int id) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/collection/getCollectionInfo',
        queryParameters: {'id': id},
      );

      if (response.data['code'] == 200 && response.data['data'] != null) {
        return CollectionInfo.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      print('获取收藏夹信息失败: $e');
      return null;
    }
  }

  /// 获取收藏夹内的视频列表
  Future<({List<CollectionVideo> videos, int total})> getCollectionVideos({
    required int collectionId,
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/collection/getVideoList',
        queryParameters: {
          'cid': collectionId,
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        final data = response.data['data'];
        final list = data['videos'] as List<dynamic>? ?? [];
        final total = data['total'] as int? ?? 0;
        return (
          videos: list.map((e) => CollectionVideo.fromJson(e)).toList(),
          total: total,
        );
      }
      return (videos: <CollectionVideo>[], total: 0);
    } catch (e) {
      print('获取收藏夹视频列表失败: $e');
      return (videos: <CollectionVideo>[], total: 0);
    }
  }

  /// 编辑收藏夹
  Future<bool> editCollection({
    required int id,
    String? name,
    String? cover,
    String? desc,
    bool? open,
  }) async {
    try {
      final data = <String, dynamic>{'id': id};
      if (name != null) data['name'] = name;
      if (cover != null) data['cover'] = cover;
      if (desc != null) data['desc'] = desc;
      if (open != null) data['open'] = open;

      final response = await _httpClient.dio.put(
        '/api/v1/collection/editCollection',
        data: data,
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('编辑收藏夹失败: $e');
      return false;
    }
  }

  /// 删除收藏夹
  Future<bool> deleteCollection(int id) async {
    try {
      final response = await _httpClient.dio.delete(
        '/api/v1/collection/deleteCollection/$id',
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('删除收藏夹失败: $e');
      return false;
    }
  }

  // ==================== 视频收藏操作 ====================

  /// 检查视频是否被收藏
  Future<bool> hasCollectVideo(int vid) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/archive/video/hasCollect',
        queryParameters: {'vid': vid},
      );

      if (response.data['code'] == 200) {
        return response.data['data']['collect'] == true;
      }
      return false;
    } catch (e) {
      print('检查收藏状态失败: $e');
      return false;
    }
  }

  /// 获取视频被收藏到的收藏夹ID列表
  Future<List<int>> getVideoCollectInfo(int vid) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/archive/video/getCollectInfo',
        queryParameters: {'vid': vid},
      );

      if (response.data['code'] == 200) {
        final list = response.data['data']['collectionIds'] as List<dynamic>? ?? [];
        return list.map((e) => e as int).toList();
      }
      return [];
    } catch (e) {
      print('获取视频收藏信息失败: $e');
      return [];
    }
  }

  /// 收藏/取消收藏视频到多个收藏夹
  Future<bool> collectVideo(CollectVideoParams params) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/archive/video/collect',
        data: params.toJson(),
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('收藏视频失败: $e');
      return false;
    }
  }

  // ==================== 文章收藏操作 ====================

  /// 检查文章是否被收藏
  Future<bool> hasCollectArticle(int aid) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/archive/article/hasCollect',
        queryParameters: {'aid': aid},
      );

      if (response.data['code'] == 200) {
        return response.data['data']['collect'] == true;
      }
      return false;
    } catch (e) {
      print('检查文章收藏状态失败: $e');
      return false;
    }
  }

  /// 收藏文章
  Future<bool> collectArticle(int aid) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/archive/article/collect',
        data: {'aid': aid},
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('收藏文章失败: $e');
      return false;
    }
  }

  /// 取消收藏文章
  Future<bool> cancelCollectArticle(int aid) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/archive/article/cancelCollect',
        data: {'aid': aid},
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('取消收藏文章失败: $e');
      return false;
    }
  }
}
