import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_response.dart';
import '../models/video_api_model.dart';
import '../config/api_config.dart';

class VideoApiService {
  static String get baseUrl => ApiConfig.baseUrl;
  static const int pageSize = 10;

  static Future<List<VideoApiModel>> asyncGetHotVideoAPI({
    int page = 1,
    int pageSize = VideoApiService.pageSize,
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/v1/video/getHotVideo?page=$page&pageSize=$pageSize',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final apiResponse = ApiResponse.fromJson(jsonData);

      if (apiResponse.isSuccess && apiResponse.data != null) {
        return apiResponse.data!.videos;
      } else {
        throw Exception('API返回错误: ${apiResponse.msg}');
      }
    } else {
      throw Exception('HTTP错误: ${response.statusCode}');
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

    final url = Uri.parse(
      '$baseUrl/api/v1/video/getVideoListByPartition?partitionId=$partitionId&size=$pageSize',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final apiResponse = ApiResponse.fromJson(jsonData);

      if (apiResponse.isSuccess && apiResponse.data != null) {
        return apiResponse.data!.videos;
      } else {
        throw Exception('API返回错误: ${apiResponse.msg}');
      }
    } else {
      throw Exception('HTTP错误: ${response.statusCode}');
    }
  }

  static Future<List<VideoApiModel>> searchVideo({
    required String keywords,
    int page = 1,
    int pageSize = 30,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/video/searchVideo');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'page': page,
        'pageSize': pageSize > 30 ? 30 : pageSize,
        'keyWords': keywords,
      }),
    );

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final apiResponse = ApiResponse.fromJson(jsonData);

      if (apiResponse.isSuccess && apiResponse.data != null) {
        return apiResponse.data!.videos;
      } else {
        throw Exception('搜索API返回错误: ${apiResponse.msg}');
      }
    } else {
      throw Exception('搜索HTTP错误: ${response.statusCode}');
    }
  }
}
