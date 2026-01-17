import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_response.dart';
import '../models/video_api_model.dart';
import '../config/api_config.dart';
import 'logger_service.dart';

class VideoApiService {
  static String get baseUrl => ApiConfig.baseUrl;
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

  /// 按分区获取视频列表
  /// [partitionId] 分区ID，0表示推荐/全部
  /// [page] 页码（仅推荐模式支持分页）
  /// [pageSize] 每页数量
  /// 注：后端分区接口不支持分页，使用 size 参数获取指定数量
  static Future<List<VideoApiModel>> getVideoByPartition({
    required int partitionId,
    int page = 1,
    int pageSize = VideoApiService.pageSize,
  }) async {
    // 如果是推荐（partitionId=0），使用热门视频接口（支持分页）
    if (partitionId == 0) {
      return asyncGetHotVideoAPI(page: page, pageSize: pageSize);
    }

    // 分区接口不支持分页，只在第一页时请求数据
    // 后续页返回空列表表示没有更多数据
    if (page > 1) {
      return [];
    }

    final url = Uri.parse(
      '$baseUrl/api/v1/video/getVideoListByPartition?partitionId=$partitionId&size=$pageSize',
    );

    try {
      LoggerService.instance.logDebug('🌐 按分区获取视频: partitionId=$partitionId, size=$pageSize');

      final response = await http.get(url);

      LoggerService.instance.logDebug('📡 响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
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
              apiName: 'getVideoByPartition',
              url: url.toString(),
              statusCode: 200,
              responseBody: response.body,
              error: error,
              requestParams: {'partitionId': partitionId, 'page': page, 'pageSize': pageSize},
            );
            throw error;
          }
        } catch (e, stackTrace) {
          await LoggerService.instance.logApiError(
            apiName: 'getVideoByPartition',
            url: url.toString(),
            statusCode: 200,
            responseBody: response.body,
            error: e,
            stackTrace: stackTrace,
            requestParams: {'partitionId': partitionId, 'page': page, 'pageSize': pageSize},
          );
          rethrow;
        }
      } else {
        final error = Exception('HTTP错误: ${response.statusCode}');
        await LoggerService.instance.logApiError(
          apiName: 'getVideoByPartition',
          url: url.toString(),
          statusCode: response.statusCode,
          responseBody: response.body,
          error: error,
          requestParams: {'partitionId': partitionId, 'page': page, 'pageSize': pageSize},
        );
        throw error;
      }
    } catch (e, stackTrace) {
      await LoggerService.instance.logApiError(
        apiName: 'getVideoByPartition',
        url: url.toString(),
        error: e,
        stackTrace: stackTrace,
        requestParams: {'partitionId': partitionId, 'page': page, 'pageSize': pageSize},
      );
      rethrow;
    }
  }

  // 搜索视频
  static Future<List<VideoApiModel>> searchVideo({
    required String keywords,
    int page = 1,
    int pageSize = 30,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/video/searchVideo');

    try {
      LoggerService.instance.logDebug('🔍 搜索视频: $keywords (page: $page)');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'page': page,
          'pageSize': pageSize > 30 ? 30 : pageSize, // 最大30
          'keyWords': keywords,
        }),
      );

      LoggerService.instance.logDebug('📡 搜索响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          LoggerService.instance.logDebug('✅ 搜索JSON解析成功，code: ${jsonData['code']}');

          final apiResponse = ApiResponse.fromJson(jsonData);

          if (apiResponse.isSuccess && apiResponse.data != null) {
            LoggerService.instance.logDebug('🎬 搜索到 ${apiResponse.data!.videos.length} 个视频');
            return apiResponse.data!.videos;
          } else {
            final error = Exception('搜索API返回错误: ${apiResponse.msg}');
            await LoggerService.instance.logApiError(
              apiName: 'searchVideo',
              url: url.toString(),
              statusCode: 200,
              responseBody: response.body,
              error: error,
              requestParams: {'keywords': keywords, 'page': page, 'pageSize': pageSize},
            );
            throw error;
          }
        } catch (e, stackTrace) {
          await LoggerService.instance.logApiError(
            apiName: 'searchVideo',
            url: url.toString(),
            statusCode: 200,
            responseBody: response.body,
            error: e,
            stackTrace: stackTrace,
            requestParams: {'keywords': keywords, 'page': page, 'pageSize': pageSize},
          );
          rethrow;
        }
      } else {
        final error = Exception('搜索HTTP错误: ${response.statusCode}');
        await LoggerService.instance.logApiError(
          apiName: 'searchVideo',
          url: url.toString(),
          statusCode: response.statusCode,
          responseBody: response.body,
          error: error,
          requestParams: {'keywords': keywords, 'page': page, 'pageSize': pageSize},
        );
        throw error;
      }
    } catch (e, stackTrace) {
      await LoggerService.instance.logApiError(
        apiName: 'searchVideo',
        url: url.toString(),
        error: e,
        stackTrace: stackTrace,
        requestParams: {'keywords': keywords, 'page': page, 'pageSize': pageSize},
      );
      rethrow;
    }
  }
}
