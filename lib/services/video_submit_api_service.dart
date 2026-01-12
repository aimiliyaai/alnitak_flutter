import 'package:dio/dio.dart';
import '../models/upload_video.dart';
import '../utils/http_client.dart';

/// 视频投稿API服务
class VideoSubmitApiService {
  static final Dio _dio = HttpClient().dio;

  /// 上传视频（提交视频信息）
  static Future<void> uploadVideo(UploadVideo video) async {
    try {
      final response = await _dio.post(
        '/api/v1/video/uploadVideoInfo',
        data: video.toJson(),
      );

      if (response.data['code'] != 200) {
        throw Exception(response.data['msg'] ?? '上传视频失败');
      }
    } catch (e) {
      throw Exception('上传失败: $e');
    }
  }

  /// 编辑视频
  static Future<void> editVideo(EditVideo video) async {
    try {
      final response = await _dio.put(
        '/api/v1/video/editVideoInfo',
        data: video.toJson(),
      );

      if (response.data['code'] != 200) {
        throw Exception(response.data['msg'] ?? '编辑视频失败');
      }
    } catch (e) {
      throw Exception('编辑失败: $e');
    }
  }

  /// 获取视频状态
  static Future<VideoStatus> getVideoStatus(int vid) async {
    try {
      final response = await _dio.get(
        '/api/v1/video/getVideoStatus',
        queryParameters: {'vid': vid},
      );

      if (response.data['code'] == 200) {
        // PC端返回格式: data.data.video
        final videoData = response.data['data']['video'] as Map<String, dynamic>;
        return VideoStatus.fromJson(videoData);
      } else {
        throw Exception(response.data['msg'] ?? '获取视频状态失败');
      }
    } catch (e) {
      throw Exception('获取失败: $e');
    }
  }

  /// 获取用户投稿视频列表
  static Future<List<ManuscriptVideo>> getManuscriptVideos({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/video/getUploadVideo',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        final videoList = response.data['data']['videos'] as List<dynamic>?;
        if (videoList == null) {
          return [];
        }
        // 【调试】打印原始视频数据中的状态
        for (final item in videoList) {
          final video = item as Map<String, dynamic>;
          print('📹 [API] 视频: ${video['title']}, status=${video['status']} (type: ${video['status'].runtimeType})');
        }
        return videoList
            .map((item) => ManuscriptVideo.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception(response.data['msg'] ?? '获取投稿列表失败');
      }
    } catch (e) {
      throw Exception('获取失败: $e');
    }
  }

  /// 删除视频
  static Future<void> deleteVideo(int vid) async {
    try {
      final response = await _dio.delete('/api/v1/video/deleteVideo/$vid');

      if (response.data['code'] != 200) {
        throw Exception(response.data['msg'] ?? '删除视频失败');
      }
    } catch (e) {
      throw Exception('删除失败: $e');
    }
  }

  /// 添加视频资源
  static Future<void> addVideoResource({
    required int vid,
    required int resourceId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/video/upload/add/resource',
        data: {
          'vid': vid,
          'resourceId': resourceId,
        },
      );

      if (response.data['code'] != 200) {
        throw Exception(response.data['msg'] ?? '添加视频资源失败');
      }
    } catch (e) {
      throw Exception('添加失败: $e');
    }
  }

  /// 删除视频资源
  static Future<void> deleteVideoResource({
    required int vid,
    required int resourceId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/video/upload/delete/resource',
        data: {
          'vid': vid,
          'resourceId': resourceId,
        },
      );

      if (response.data['code'] != 200) {
        throw Exception(response.data['msg'] ?? '删除视频资源失败');
      }
    } catch (e) {
      throw Exception('删除失败: $e');
    }
  }
}
