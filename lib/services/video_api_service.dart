import 'package:dio/dio.dart';
import '../models/api_response.dart';
import '../models/video_api_model.dart';
import '../utils/http_client.dart';

class VideoApiService {
  static final Dio _dio = HttpClient().dio;
  static const int pageSize = 10;

  static Future<List<VideoApiModel>> asyncGetHotVideoAPI({
    int page = 1,
    int pageSize = VideoApiService.pageSize,
  }) async {
    final response = await _dio.get(
      '/api/v1/video/getHotVideo',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );

    final apiResponse = ApiResponse.fromJson(response.data as Map<String, dynamic>);
    if (apiResponse.isSuccess && apiResponse.data != null) {
      return apiResponse.data!.videos;
    } else {
      throw Exception('API返回错误: ${apiResponse.msg}');
    }
  }

  static Future<List<VideoApiModel>> getHotVideoAPI({
    int page = 1,
    int pageSize = VideoApiService.pageSize,
  }) async {
    return await asyncGetHotVideoAPI(page: page, pageSize: pageSize);
  }

  static Future<List<VideoApiModel>> getVideoByPartition({
    required int partitionId,
    int page = 1,
    int pageSize = VideoApiService.pageSize,
  }) async {
    if (partitionId == 0) {
      return asyncGetHotVideoAPI(page: page, pageSize: pageSize);
    }

    if (page > 1) {
      return [];
    }

    final response = await _dio.get(
      '/api/v1/video/getVideoListByPartition',
      queryParameters: {'partitionId': partitionId, 'size': pageSize},
    );

    final apiResponse = ApiResponse.fromJson(response.data as Map<String, dynamic>);
    if (apiResponse.isSuccess && apiResponse.data != null) {
      return apiResponse.data!.videos;
    } else {
      throw Exception('API返回错误: ${apiResponse.msg}');
    }
  }

static Future<List<VideoApiModel>> searchVideo({
    required String keywords,
    int page = 1,
    int pageSize = 30,
    String sort = 'relevance',
    String timeRange = 'all',
    CancelToken? cancelToken,
  }) async {
final response = await _dio.post(
      '/api/v1/video/searchVideo',
      data: {
        'page': page,
        'pageSize': pageSize > 30 ? 30 : pageSize,
        'keywords': keywords,
        'sort': sort,
        'timeRange': timeRange,
      },
      cancelToken: cancelToken,
    );

    final apiResponse = ApiResponse.fromJson(response.data as Map<String, dynamic>);
    if (apiResponse.isSuccess && apiResponse.data != null) {
      return apiResponse.data!.videos;
    } else {
      throw Exception('搜索API返回错误: ${apiResponse.msg}');
    }
  }
}
