import 'package:flutter/foundation.dart';
import '../models/article_list_model.dart';
import '../models/article_detail_model.dart';
import '../utils/http_client.dart';

/// 文章/专栏列表 API 服务
///
/// 后端 API 说明：
/// - getRandomArticleList: 获取随机文章列表（参数: size）
/// - getArticleById: 获取文章详情（参数: aid）
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

  /// 获取文章详情
  /// [aid] 文章ID
  static Future<ArticleDetail> getArticleById(int aid) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/article/getArticleById',
        queryParameters: {'aid': aid},
      );

      final apiResponse = ArticleDetailResponse.fromJson(response.data);

      if (apiResponse.isSuccess && apiResponse.article != null) {
        return apiResponse.article!;
      } else {
        throw Exception('获取文章详情失败: ${apiResponse.msg}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 获取文章详情失败: $e');
      }
      rethrow;
    }
  }

  /// 获取文章统计信息
  static Future<ArticleStat?> getArticleStat(int aid) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/archive/article/stat',
        queryParameters: {'aid': aid},
      );
      if (response.data['code'] == 200 && response.data['data'] != null) {
        return ArticleStat.fromJson(response.data['data']['stat']);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 获取文章统计失败: $e');
      }
      return null;
    }
  }

  /// 文章分享计数+1
  static Future<bool> shareArticle(int aid) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/archive/article/share',
        data: {'aid': aid},
      );
      return response.data['code'] == 200;
    } catch (e) {
      print('文章分享计数失败: $e');
      return false;
    }
  }

  /// 获取文章点赞状态
  static Future<bool> hasLikedArticle(int aid) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/archive/article/hasLike',
        queryParameters: {'aid': aid},
      );
      if (response.data['code'] == 200 && response.data['data'] != null) {
        return response.data['data']['like'] == true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 获取文章点赞状态失败: $e');
      }
      return false;
    }
  }

  /// 点赞文章
  static Future<bool> likeArticle(int aid) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/archive/article/like',
        data: {'aid': aid},
      );
      return response.data['code'] == 200;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 文章点赞失败: $e');
      }
      return false;
    }
  }

  /// 取消点赞文章
  static Future<bool> cancelLikeArticle(int aid) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/archive/article/cancelLike',
        data: {'aid': aid},
      );
      return response.data['code'] == 200;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 文章取消点赞失败: $e');
      }
      return false;
    }
  }

  /// 获取文章收藏状态
  static Future<bool> hasCollectedArticle(int aid) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/archive/article/hasCollect',
        queryParameters: {'aid': aid},
      );
      if (response.data['code'] == 200 && response.data['data'] != null) {
        return response.data['data']['collect'] == true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 获取文章收藏状态失败: $e');
      }
      return false;
    }
  }

  /// 收藏文章
  static Future<bool> collectArticle(int aid) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/archive/article/collect',
        data: {'aid': aid},
      );
      return response.data['code'] == 200;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 文章收藏失败: $e');
      }
      return false;
    }
  }

  /// 取消收藏文章
  static Future<bool> cancelCollectArticle(int aid) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/archive/article/cancelCollect',
        data: {'aid': aid},
      );
      return response.data['code'] == 200;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 文章取消收藏失败: $e');
      }
      return false;
    }
  }

  /// 获取文章评论列表
  static Future<ArticleCommentResponse?> getArticleComments({
    required int aid,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/comment/article/getCommentList',
        queryParameters: {
          'aid': aid,
          'page': page,
          'pageSize': pageSize,
        },
      );
      if (response.data['code'] == 200 && response.data['data'] != null) {
        return ArticleCommentResponse.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 获取文章评论失败: $e');
      }
      return null;
    }
  }

  /// 获取文章评论的回复列表
  static Future<List<ArticleComment>?> getCommentReplies({
    required int commentId,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/comment/article/getReplyList',
        queryParameters: {
          'commentId': commentId,
          'page': page,
          'pageSize': pageSize,
        },
      );
      if (response.data['code'] == 200 && response.data['data'] != null) {
        final replies = response.data['data']['replies'] as List<dynamic>? ?? [];
        return replies.map((e) => ArticleComment.fromJson(e)).toList();
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 获取评论回复失败: $e');
      }
      return null;
    }
  }

  /// 发表文章评论
  static Future<bool> postArticleComment({
    required int aid,
    required String content,
    int? parentID,
    int? replyUserID,
    String? replyUserName,
    String? replyContent,
  }) async {
    try {
      final data = <String, dynamic>{
        'aid': aid,
        'content': content,
      };
      if (parentID != null) data['parentID'] = parentID;
      if (replyUserID != null) data['replyUserID'] = replyUserID;
      if (replyUserName != null) data['replyUserName'] = replyUserName;
      if (replyContent != null) data['replyContent'] = replyContent;

      final response = await _httpClient.dio.post(
        '/api/v1/comment/article/addComment',
        data: data,
      );
      return response.data['code'] == 200;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 发表文章评论失败: $e');
      }
      return false;
    }
  }

  /// 删除文章评论
  static Future<bool> deleteArticleComment(int commentId) async {
    try {
      final response = await _httpClient.dio.delete(
        '/api/v1/comment/article/deleteComment/$commentId',
      );
      return response.data['code'] == 200;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 删除文章评论失败: $e');
      }
      return false;
    }
  }
}
