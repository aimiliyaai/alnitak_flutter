import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_response.dart';
import '../models/video_api_model.dart';
import 'logger_service.dart';

class VideoApiService {
  static const String baseUrl = 'http://anime.ayypd.cn:3000';
  static const int pageSize = 10;

  // 同步获取热门视频（用于初始加载）
  static Future<List<VideoApiModel>> asyncGetHotVideoAPI({
    int page = 1,
    int pageSize = VideoApiService.pageSize,
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/v1/video/getHotVideo?page=$page&pageSize=$pageSize',
    );

    try {
      LoggerService.instance.logDebug('🌐 请求URL: $url');
      
      final response = await http.get(url);
      
      LoggerService.instance.logDebug('📡 响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        LoggerService.instance.logDebug('📦 响应体长度: ${response.body.length}');

        try {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          LoggerService.instance.logDebug('✅ JSON解析成功，code: ${jsonData['code']}');

          final apiResponse = ApiResponse.fromJson(jsonData);

          if (apiResponse.isSuccess && apiResponse.data != null) {
            LoggerService.instance.logDebug('🎬 获取到 ${apiResponse.data!.videos.length} 个视频');
            return apiResponse.data!.videos;
          } else {
            final error = Exception('API返回错误: ${apiResponse.msg}');
            await LoggerService.instance.logApiError(
              apiName: 'asyncGetHotVideoAPI',
              url: url.toString(),
              statusCode: 200,
              responseBody: response.body,
              error: error,
              requestParams: {'page': page, 'pageSize': pageSize},
            );
            throw error;
          }
        } catch (e, stackTrace) {
          // JSON解析错误
          await LoggerService.instance.logApiError(
            apiName: 'asyncGetHotVideoAPI',
            url: url.toString(),
            statusCode: 200,
            responseBody: response.body,
            error: e,
            stackTrace: stackTrace,
            requestParams: {'page': page, 'pageSize': pageSize},
          );
          rethrow;
        }
      } else {
        final error = Exception('HTTP错误: ${response.statusCode}');
        await LoggerService.instance.logApiError(
          apiName: 'asyncGetHotVideoAPI',
          url: url.toString(),
          statusCode: response.statusCode,
          responseBody: response.body,
          error: error,
          requestParams: {'page': page, 'pageSize': pageSize},
        );
        throw error;
      }
    } catch (e, stackTrace) {
      // 网络错误或其他异常
      await LoggerService.instance.logApiError(
        apiName: 'asyncGetHotVideoAPI',
        url: url.toString(),
        error: e,
        stackTrace: stackTrace,
        requestParams: {'page': page, 'pageSize': pageSize},
      );
      rethrow;
    }
  }

  // 异步获取热门视频（用于滚动加载更多）
  static Future<List<VideoApiModel>> getHotVideoAPI({
    int page = 1,
    int pageSize = VideoApiService.pageSize,
  }) async {
    return await asyncGetHotVideoAPI(page: page, pageSize: pageSize);
  }
}
