import 'package:dio/dio.dart';
import '../models/comment_manage.dart';
import '../utils/http_client.dart';

/// 评论管理服务
class CommentManageService {
  static final CommentManageService _instance = CommentManageService._internal();
  factory CommentManageService() => _instance;
  CommentManageService._internal();

  final Dio _dio = HttpClient().dio;

  /// 获取用户的所有视频列表（用于筛选）
  Future<List<UserVideoItem>> getAllVideoList() async {
    try {
      final response = await _dio.get('/api/v1/video/getAllVideoList');

      if (response.data['code'] == 200) {
        final videoList = response.data['data']['videos'] as List<dynamic>? ?? [];
        return videoList
            .map((e) => UserVideoItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('获取视频列表失败: $e');
      return [];
    }
  }

  /// 获取用户的所有文章列表（用于筛选）
  Future<List<UserArticleItem>> getAllArticleList() async {
    try {
      final response = await _dio.get('/api/v1/article/getAllArticleList');

      if (response.data['code'] == 200) {
        final articleList = response.data['data']['articles'] as List<dynamic>? ?? [];
        return articleList
            .map((e) => UserArticleItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('获取文章列表失败: $e');
      return [];
    }
  }

  /// 获取视频评论列表
  /// [vid] 视频ID，0表示全部视频
  /// [page] 页码
  /// [pageSize] 每页数量
  Future<ManageCommentListResponse?> getVideoCommentList({
    int vid = 0,
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/comment/video/getCommentList',
        queryParameters: {
          'vid': vid,
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        return ManageCommentListResponse.fromVideoJson(response.data['data']);
      }
      print('获取视频评论失败: ${response.data['msg']}');
      return null;
    } catch (e) {
      print('获取视频评论异常: $e');
      return null;
    }
  }

  /// 获取文章评论列表
  /// [aid] 文章ID，0表示全部文章
  /// [page] 页码
  /// [pageSize] 每页数量
  Future<ManageCommentListResponse?> getArticleCommentList({
    int aid = 0,
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/comment/article/getCommentList',
        queryParameters: {
          'aid': aid,
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        return ManageCommentListResponse.fromArticleJson(response.data['data']);
      }
      print('获取文章评论失败: ${response.data['msg']}');
      return null;
    } catch (e) {
      print('获取文章评论异常: $e');
      return null;
    }
  }

  /// 删除视频评论
  Future<bool> deleteVideoComment(int commentId) async {
    try {
      final response = await _dio.delete(
        '/api/v1/comment/video/deleteComment/$commentId',
      );

      if (response.data['code'] == 200) {
        return true;
      }
      print('删除视频评论失败: ${response.data['msg']}');
      return false;
    } catch (e) {
      print('删除视频评论异常: $e');
      return false;
    }
  }

  /// 删除文章评论
  Future<bool> deleteArticleComment(int commentId) async {
    try {
      final response = await _dio.delete(
        '/api/v1/comment/article/deleteComment/$commentId',
      );

      if (response.data['code'] == 200) {
        return true;
      }
      print('删除文章评论失败: ${response.data['msg']}');
      return false;
    } catch (e) {
      print('删除文章评论异常: $e');
      return false;
    }
  }
}
