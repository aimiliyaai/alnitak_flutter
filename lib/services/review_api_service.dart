import 'package:dio/dio.dart';
import '../utils/http_client.dart';

/// 审核API服务 - 参考PC端实现
class ReviewApiService {
  static final Dio _dio = HttpClient().dio;

  /// 获取视频审核记录
  /// 参考PC端: revies.ts - getVideoReviewRecordAPI
  static Future<Map<String, dynamic>> getVideoReviewRecord(int vid) async {
    try {
      final response = await _dio.get(
        '/api/v1/review/getVideoReviewRecord',
        queryParameters: {'vid': vid},
      );

      if (response.data['code'] == 200) {
        return response.data['data']['review'] as Map<String, dynamic>;
      } else {
        throw Exception(response.data['msg'] ?? '获取审核记录失败');
      }
    } catch (e) {
      throw Exception('获取审核记录失败: $e');
    }
  }

  /// 获取文章审核记录
  static Future<Map<String, dynamic>> getArticleReviewRecord(int aid) async {
    try {
      final response = await _dio.get(
        '/api/v1/review/getArticleReviewRecord',
        queryParameters: {'aid': aid},
      );

      if (response.data['code'] == 200) {
        return response.data['data']['review'] as Map<String, dynamic>;
      } else {
        throw Exception(response.data['msg'] ?? '获取审核记录失败');
      }
    } catch (e) {
      throw Exception('获取审核记录失败: $e');
    }
  }
}
