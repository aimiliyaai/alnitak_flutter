import 'package:dio/dio.dart';
import '../models/collection.dart';
import '../utils/http_client.dart';
import '../utils/token_manager.dart';

/// 收藏夹服务
class CollectionService {
  static final CollectionService _instance = CollectionService._internal();
  factory CollectionService() => _instance;
  CollectionService._internal();

  final Dio _dio = HttpClient().dio;
  final TokenManager _tokenManager = TokenManager();

  /// 获取收藏夹列表
  Future<List<Collection>?> getCollectionList() async {
    // 【新增】检查是否可以进行认证请求
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      print('⏭️ 跳过获取收藏夹列表：未登录或token已失效');
      return null;
    }

    try {
      final response = await _dio.get('/api/v1/collection/getCollectionList');
      if (response.data['code'] == 200) {
        final collections = response.data['data']['collections'] as List<dynamic>?;
        if (collections != null) {
          return collections.map((e) => Collection.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
      return null;
    } catch (e) {
      print('获取收藏夹列表失败: $e');
      return null;
    }
  }

  /// 创建收藏夹
  Future<int?> addCollection(String name) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      print('⏭️ 跳过创建收藏夹：未登录或token已失效');
      return null;
    }

    try {
      print('📁 CollectionService: 开始创建收藏夹 "$name"');
      final response = await _dio.post('/api/v1/collection/addCollection', data: {'name': name});
      print('📁 CollectionService: 响应 code=${response.data['code']}, data=${response.data}');
      if (response.data['code'] == 200) {
        final id = response.data['data']['id'] as int?;
        print('📁 CollectionService: 创建成功，ID=$id');
        // 如果没有返回ID，返回一个特殊值（-1）表示创建成功但需要重新获取列表
        return id ?? -1;
      }
      print('📁 CollectionService: 创建失败，code=${response.data['code']}');
      return null;
    } catch (e) {
      print('📁 CollectionService: 创建收藏夹失败: $e');
      return null;
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
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return false;
    }

    try {
      final response = await _dio.put('/api/v1/collection/editCollection', data: {
        'id': id,
        if (name != null) 'name': name,
        if (cover != null) 'cover': cover,
        if (desc != null) 'desc': desc,
        if (open != null) 'open': open,
      });
      return response.data['code'] == 200;
    } catch (e) {
      print('编辑收藏夹失败: $e');
      return false;
    }
  }

  /// 删除收藏夹
  Future<bool> deleteCollection(int id) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return false;
    }

    try {
      final response = await _dio.delete('/api/v1/collection/deleteCollection/$id');
      return response.data['code'] == 200;
    } catch (e) {
      print('删除收藏夹失败: $e');
      return false;
    }
  }

  /// 获取收藏夹详情
  Future<Collection?> getCollectionInfo(int id) async {
    try {
      final response = await _dio.get('/api/v1/collection/getCollectionInfo', queryParameters: {'id': id});
      if (response.data['code'] == 200) {
        return Collection.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      print('获取收藏夹详情失败: $e');
      return null;
    }
  }

  /// 获取收藏夹内的视频列表
  Future<List<Map<String, dynamic>>> getCollectVideos({
    required int collectionId,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get('/api/v1/collection/getVideoList', queryParameters: {
        'cid': collectionId,
        'page': page,
        'pageSize': pageSize,
      });
      if (response.data['code'] == 200) {
        return List<Map<String, dynamic>>.from(response.data['data']['videos'] ?? []);
      }
      return [];
    } catch (e) {
      print('获取收藏夹视频列表失败: $e');
      return [];
    }
  }
}
