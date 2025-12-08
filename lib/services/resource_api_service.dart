import 'package:dio/dio.dart';
import '../utils/http_client.dart';

/// 资源API服务
class ResourceApiService {
  static final Dio _dio = HttpClient().dio;

  /// 修改资源标题
  static Future<void> modifyTitle({
    required int id,
    required String title,
  }) async {
    try {
      final response = await _dio.put(
        '/api/v1/resource/modifyTitle',
        data: {
          'id': id,
          'title': title,
        },
      );

      if (response.data['code'] != 200) {
        throw Exception(response.data['msg'] ?? '修改标题失败');
      }
    } catch (e) {
      throw Exception('修改失败: $e');
    }
  }

  /// 删除资源
  static Future<void> deleteResource(int id) async {
    try {
      final response = await _dio.delete(
        '/api/v1/resource/deleteResource/$id',
      );

      if (response.data['code'] != 200) {
        throw Exception(response.data['msg'] ?? '删除资源失败');
      }
    } catch (e) {
      throw Exception('删除失败: $e');
    }
  }
}
