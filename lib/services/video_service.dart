import 'package:dio/dio.dart';
import '../models/video_detail.dart';
import '../models/comment.dart';
import '../utils/http_client.dart';

/// 视频服务 - 完全基于参考项目的API
class VideoService {
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  final Dio _dio = HttpClient().dio;

  /// 获取视频详情
  Future<VideoDetail?> getVideoDetail(int vid) async {
    try {
      final response = await _dio.get('/api/v1/video/getVideoById', queryParameters: {'vid': vid});
      if (response.data['code'] == 200) {
        return VideoDetail.fromJson(response.data['data']['video']);
      }
      return null;
    } catch (e) {
      print('获取视频详情失败: $e');
      return null;
    }
  }

  /// 获取视频统计信息
  Future<VideoStat?> getVideoStat(int vid) async {
    try {
      final response = await _dio.get('/api/v1/archive/video/stat', queryParameters: {'vid': vid});
      if (response.data['code'] == 200) {
        return VideoStat.fromJson(response.data['data']['stat']);
      }
      return null;
    } catch (e) {
      print('获取视频统计失败: $e');
      return null;
    }
  }

  /// 获取用户操作状态（点赞、收藏、关注）
  Future<UserActionStatus?> getUserActionStatus(int vid, int authorUid) async {
    try {
      // 并发请求点赞和收藏状态
      final results = await Future.wait([
        _dio.get('/api/v1/archive/video/hasLike', queryParameters: {'vid': vid}),
        _dio.get('/api/v1/archive/video/hasCollect', queryParameters: {'vid': vid}),
        _dio.get('/api/v1/relation/getUserRelation', queryParameters: {'userId': authorUid}),
      ]);

      print('🔍 hasLike响应: ${results[0].data}');
      print('🔍 hasCollect响应: ${results[1].data}');
      print('🔍 getUserRelation响应: ${results[2].data}');

      final hasLiked = results[0].data['code'] == 200 ? (results[0].data['data']['like'] ?? false) : false;
      final hasCollected = results[1].data['code'] == 200 ? (results[1].data['data']['collect'] ?? false) : false;
      final relationStatus = results[2].data['code'] == 200 ? (results[2].data['data']['relation'] ?? 0) : 0;

      print('🔍 解析后状态: hasLiked=$hasLiked, hasCollected=$hasCollected, relationStatus=$relationStatus');

      return UserActionStatus(
        hasLiked: hasLiked,
        hasCollected: hasCollected,
        relationStatus: relationStatus,
      );
    } catch (e) {
      print('获取用户操作状态失败: $e');
      // 出错时返回默认值
      return UserActionStatus(
        hasLiked: false,
        hasCollected: false,
        relationStatus: 0,
      );
    }
  }

  /// 点赞视频
  Future<bool> likeVideo(int vid) async {
    try {
      final response = await _dio.post(
        '/api/v1/archive/video/like',
        data: {'vid': vid},
      );
      print('🔍 点赞响应: code=${response.data['code']}, msg=${response.data['msg']}');
      return response.data['code'] == 200;
    } catch (e) {
      print('点赞失败: $e');
      return false;
    }
  }

  /// 取消点赞
  Future<bool> unlikeVideo(int vid) async {
    try {
      final response = await _dio.post(
        '/api/v1/archive/video/cancelLike',
        data: {'vid': vid},  // 参考PC端实现，使用 vid 参数
      );
      print('🔍 取消点赞响应: code=${response.data['code']}, msg=${response.data['msg']}');
      return response.data['code'] == 200;
    } catch (e) {
      print('取消点赞失败: $e');
      return false;
    }
  }

  /// 获取视频是否已收藏
  Future<bool> getCollectStatus(int vid) async {
    try {
      final response = await _dio.get('/api/v1/archive/video/hasCollect', queryParameters: {'vid': vid});
      if (response.data['code'] == 200) {
        return response.data['data']['collect'] ?? false;
      }
      return false;
    } catch (e) {
      print('获取收藏状态失败: $e');
      return false;
    }
  }

  /// 获取视频的收藏信息（收藏到了哪些收藏夹）
  Future<List<int>> getCollectInfo(int vid) async {
    try {
      final response = await _dio.get('/api/v1/archive/video/getCollectInfo', queryParameters: {'vid': vid});
      if (response.data['code'] == 200) {
        return List<int>.from(response.data['data']['collectionIds'] ?? []);
      }
      return [];
    } catch (e) {
      print('获取收藏信息失败: $e');
      return [];
    }
  }

  /// 收藏视频（参考PC端实现）
  Future<bool> collectVideo(int vid, List<int> addList, List<int> cancelList) async {
    try {
      final response = await _dio.post('/api/v1/archive/video/collect', data: {
        'vid': vid,
        'addList': addList,
        'cancelList': cancelList,
      });
      print('🔍 收藏响应: code=${response.data['code']}, msg=${response.data['msg']}');
      return response.data['code'] == 200;
    } catch (e) {
      print('收藏失败: $e');
      return false;
    }
  }

  /// 关注用户（参考PC端实现）
  Future<bool> followUser(int uid) async {
    try {
      final response = await _dio.post('/api/v1/relation/follow', data: {'id': uid});
      print('🔍 关注响应: code=${response.data['code']}, msg=${response.data['msg']}');
      return response.data['code'] == 200;
    } catch (e) {
      print('关注失败: $e');
      return false;
    }
  }

  /// 取消关注（参考PC端实现）
  Future<bool> unfollowUser(int uid) async {
    try {
      final response = await _dio.post('/api/v1/relation/unfollow', data: {'id': uid});
      print('🔍 取消关注响应: code=${response.data['code']}, msg=${response.data['msg']}');
      return response.data['code'] == 200;
    } catch (e) {
      print('取消关注失败: $e');
      return false;
    }
  }

  /// 获取推荐视频列表
  Future<List<Map<String, dynamic>>> getRecommendedVideos(int vid) async {
    try {
      final response = await _dio.get('/api/v1/video/getRelatedVideoList', queryParameters: {'vid': vid});
      if (response.data['code'] == 200) {
        return List<Map<String, dynamic>>.from(response.data['data']['videos'] ?? []);
      }
      return [];
    } catch (e) {
      print('获取推荐视频失败: $e');
      return [];
    }
  }

  // 历史记录相关功能已移至 HistoryService
  // 请使用 HistoryService().getProgress() 和 HistoryService().addHistory()

  /// 获取视频文件URL
  /// 根据参考项目，视频URL格式为: /api/v1/video/getVideoFile?resourceId=xxx&quality=xxx
  ///
  /// 注意：服务器返回 HLS 流 (m3u8)，但 Content-Type 是 text/plain
  /// better_player 能够自动检测和处理 HLS 流，无需特殊配置
  String getVideoFileUrl(int resourceId, String quality) {
    final baseUrl = HttpClient().dio.options.baseUrl;
    return '$baseUrl/api/v1/video/getVideoFile?resourceId=$resourceId&quality=$quality';
  }

  /// 获取资源支持的清晰度
  Future<List<String>> getResourceQuality(int resourceId) async {
    try {
      final response = await _dio.get('/api/v1/video/getResourceQuality',
        queryParameters: {'resourceId': resourceId});
      if (response.data['code'] == 200) {
        return List<String>.from(response.data['data']['quality'] ?? []);
      }
      return [];
    } catch (e) {
      print('获取清晰度失败: $e');
      return [];
    }
  }

  /// 获取视频评论列表
  /// [vid] 视频ID
  /// [page] 页码，从1开始
  /// [pageSize] 每页数量
  Future<CommentListResponse?> getComments({
    required int vid,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/comment/video/getComment',
        queryParameters: {
          'vid': vid,
          'page': page,
          'pageSize': pageSize,
        },
      );
      if (response.data['code'] == 200) {
        final data = response.data['data'] as Map<String, dynamic>;
        // 计算是否还有更多（如果返回的评论数等于pageSize，可能还有更多）
        final comments = data['comments'] as List<dynamic>? ?? [];
        final hasMore = comments.length >= pageSize;
        
        return CommentListResponse(
          comments: comments
              .map((e) => Comment.fromJson(e as Map<String, dynamic>))
              .toList(),
          total: data['total'] ?? 0,
          hasMore: hasMore,
        );
      }
      return null;
    } catch (e) {
      print('获取评论列表失败: $e');
      return null;
    }
  }

  /// 发表评论或回复
  /// [cid] 视频ID
  /// [content] 评论内容
  /// [parentID] 所属评论ID（回复时必填）
  /// [replyUserID] 回复用户的ID（回复时必填）
  /// [replyUserName] 回复用户的用户名（回复时必填）
  /// [replyContent] 回复的评论或回复的内容（可选，用于发送通知）
  /// [at] @的用户名数组（可选）
  Future<bool> postComment({
    required int cid,
    required String content,
    int? parentID,
    int? replyUserID,
    String? replyUserName,
    String? replyContent,
    List<String>? at,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/comment/video/addComment',
        data: {
          'cid': cid,
          'content': content,
          if (parentID != null) 'parentID': parentID,
          if (replyUserID != null) 'replyUserID': replyUserID,
          if (replyUserName != null) 'replyUserName': replyUserName,
          if (replyContent != null) 'replyContent': replyContent,
          if (at != null && at.isNotEmpty) 'at': at,
        },
      );
      return response.data['code'] == 200;
    } catch (e) {
      print('发表评论失败: $e');
      return false;
    }
  }

  /// 删除评论或回复
  /// [commentId] 评论或回复的ID
  Future<bool> deleteComment(int commentId) async {
    try {
      final response = await _dio.delete(
        '/api/v1/comment/video/deleteComment/$commentId',
      );
      return response.data['code'] == 200;
    } catch (e) {
      print('删除评论失败: $e');
      return false;
    }
  }

  /// 点赞/取消点赞评论
  Future<bool> likeComment(int commentId, bool like) async {
    try {
      final response = like
          ? await _dio.post('/api/v1/comment/like/$commentId')
          : await _dio.delete('/api/v1/comment/like/$commentId');
      return response.data['code'] == 200;
    } catch (e) {
      print('${like ? '点赞' : '取消点赞'}评论失败: $e');
      return false;
    }
  }

  /// 获取评论的回复列表
  Future<List<Comment>?> getCommentReplies({
    required int commentId,
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/comment/video/getReply',
        queryParameters: {
          'commentId': commentId,
          'page': page,
          'pageSize': pageSize,
        },
      );
      if (response.data['code'] == 200) {
        final data = response.data['data'] as Map<String, dynamic>;
        final replies = data['replies'] as List<dynamic>? ?? [];
        return replies
            .map((e) => Comment.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return null;
    } catch (e) {
      print('获取回复列表失败: $e');
      return null;
    }
  }
}
