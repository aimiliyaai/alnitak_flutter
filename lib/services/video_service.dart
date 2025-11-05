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
  /// 注意：参考项目中没有这些批量查询的API，需要登录后才能使用
  /// 暂时返回默认值
  Future<UserActionStatus?> getUserActionStatus(int vid, int authorUid) async {
    // 参考项目中这些API需要登录才能访问
    // 暂时返回默认值
    return UserActionStatus(
      hasLiked: false,
      hasCollected: false,
      relationStatus: 0,
    );
  }

  /// 点赞视频
  Future<bool> likeVideo(int vid) async {
    try {
      final response = await _dio.post('/api/v1/like/video/$vid');
      return response.data['code'] == 200;
    } catch (e) {
      print('点赞失败: $e');
      return false;
    }
  }

  /// 取消点赞
  Future<bool> unlikeVideo(int vid) async {
    try {
      final response = await _dio.delete('/api/v1/like/video/$vid');
      return response.data['code'] == 200;
    } catch (e) {
      print('取消点赞失败: $e');
      return false;
    }
  }

  /// 收藏视频
  Future<bool> collectVideo(int vid, List<int> addList, List<int> cancelList) async {
    try {
      final response = await _dio.post('/api/v1/collect/video', data: {
        'vid': vid,
        'add_list': addList,
        'cancel_list': cancelList,
      });
      return response.data['code'] == 200;
    } catch (e) {
      print('收藏失败: $e');
      return false;
    }
  }

  /// 关注用户
  Future<bool> followUser(int uid) async {
    try {
      final response = await _dio.post('/api/v1/relation/follow/$uid');
      return response.data['code'] == 200;
    } catch (e) {
      print('关注失败: $e');
      return false;
    }
  }

  /// 取消关注
  Future<bool> unfollowUser(int uid) async {
    try {
      final response = await _dio.delete('/api/v1/relation/follow/$uid');
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

  /// 获取播放进度
  Future<int?> getPlayProgress(int vid, int part) async {
    try {
      final response = await _dio.get(
        '/api/v1/history/video/getProgress',
        queryParameters: {'vid': vid, 'part': part},
      );
      if (response.data['code'] == 200) {
        return response.data['data']['progress'];
      }
      return null;
    } catch (e) {
      print('获取播放进度失败: $e');
      return null;
    }
  }

  /// 上报播放进度
  Future<bool> reportPlayProgress(int vid, int part, int time) async {
    try {
      final response = await _dio.post('/api/v1/history/video/addHistory', data: {
        'vid': vid,
        'part': part,
        'time': time,
      });
      return response.data['code'] == 200;
    } catch (e) {
      print('上报播放进度失败: $e');
      return false;
    }
  }

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

  /// 发表评论
  Future<bool> postComment({
    required int vid,
    required String content,
    int? replyToId, // 回复的评论ID，如果为null则是直接评论视频
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/comment/video',
        data: {
          'vid': vid,
          'content': content,
          if (replyToId != null) 'reply_to': replyToId,
        },
      );
      return response.data['code'] == 200;
    } catch (e) {
      print('发表评论失败: $e');
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
