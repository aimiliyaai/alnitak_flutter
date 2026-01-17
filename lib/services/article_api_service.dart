import 'package:flutter/foundation.dart';
import '../models/article_list_model.dart';
import '../utils/http_client.dart';

/// 文章/专栏列表 API 服务
///
/// 后端 API 说明：
/// - getRandomArticleList: 获取随机文章列表（参数: size）
/// - 后端没有热门文章或按分区获取文章的接口
/// - 所有文章请求都使用随机列表接口
class ArticleApiService {
  static final HttpClient _httpClient = HttpClient();
  static const int pageSize = 10;

  /// 获取随机文章列表
  /// [size] 获取数量
  static Future<List<ArticleListItem>> getRandomArticles({
    int size = ArticleApiService.pageSize,
  }) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/article/getRandomArticleList',
        queryParameters: {
          'size': size > 30 ? 30 : size,
        },
      );

      final apiResponse = ArticleListResponse.fromJson(response.data);

      if (apiResponse.isSuccess) {
        return apiResponse.articles;
      } else {
        throw Exception('API返回错误: ${apiResponse.msg}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 获取随机文章失败: $e');
      }
      rethrow;
    }
  }

  /// 按分区获取文章列表
  /// 注：后端没有按分区获取文章的接口，统一使用随机文章列表
  /// [partitionId] 分区ID（暂不使用）
  /// [page] 页码（随机列表不支持分页，仅第一页有数据）
  /// [pageSize] 每页数量
  static Future<List<ArticleListItem>> getArticleByPartition({
    required int partitionId,
    int page = 1,
    int pageSize = ArticleApiService.pageSize,
  }) async {
    // 后端不支持分页，只在第一页时请求数据
    if (page > 1) {
      return [];
    }

    // 后端没有分区接口，统一使用随机文章列表
    return getRandomArticles(size: pageSize);
  }
}
