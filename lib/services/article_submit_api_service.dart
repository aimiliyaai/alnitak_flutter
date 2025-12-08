import 'package:dio/dio.dart';
import '../models/upload_article.dart';
import '../utils/http_client.dart';

/// 文章投稿API服务
class ArticleSubmitApiService {
  static final Dio _dio = HttpClient().dio;

  /// 上传文章（提交文章信息）
  static Future<int> uploadArticle(UploadArticle article) async {
    try {
      final response = await _dio.post(
        '/api/v1/article/uploadArticleInfo',
        data: article.toJson(),
      );

      if (response.data['code'] == 200) {
        return response.data['data']['aid'] as int;
      } else {
        throw Exception(response.data['msg'] ?? '上传文章失败');
      }
    } catch (e) {
      throw Exception('上传失败: $e');
    }
  }

  /// 编辑文章
  static Future<void> editArticle(EditArticle article) async {
    try {
      final response = await _dio.put(
        '/api/v1/article/editArticleInfo',
        data: article.toJson(),
      );

      if (response.data['code'] != 200) {
        throw Exception(response.data['msg'] ?? '编辑文章失败');
      }
    } catch (e) {
      throw Exception('编辑失败: $e');
    }
  }

  /// 获取文章状态
  static Future<ArticleStatus> getArticleStatus(int aid) async {
    try {
      final response = await _dio.get(
        '/api/v1/article/getArticleStatus',
        queryParameters: {'aid': aid},
      );

      if (response.data['code'] == 200) {
        return ArticleStatus.fromJson(response.data['data'] as Map<String, dynamic>);
      } else {
        throw Exception(response.data['msg'] ?? '获取文章状态失败');
      }
    } catch (e) {
      throw Exception('获取失败: $e');
    }
  }

  /// 获取用户投稿文章列表
  static Future<List<ManuscriptArticle>> getManuscriptArticles({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/article/getUploadArticle',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        final articleList = response.data['data']['articles'] as List<dynamic>?;
        if (articleList == null) {
          return [];
        }
        return articleList
            .map((item) => ManuscriptArticle.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception(response.data['msg'] ?? '获取投稿列表失败');
      }
    } catch (e) {
      throw Exception('获取失败: $e');
    }
  }

  /// 删除文章
  static Future<void> deleteArticle(int aid) async {
    try {
      final response = await _dio.delete('/api/v1/article/deleteArticle/$aid');

      if (response.data['code'] != 200) {
        throw Exception(response.data['msg'] ?? '删除文章失败');
      }
    } catch (e) {
      throw Exception('删除失败: $e');
    }
  }
}
