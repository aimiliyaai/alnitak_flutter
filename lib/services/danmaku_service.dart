import 'package:dio/dio.dart';
import '../models/danmaku.dart';
import '../utils/http_client.dart';

/// 弹幕API服务
class DanmakuService {
  static final DanmakuService _instance = DanmakuService._internal();
  factory DanmakuService() => _instance;
  DanmakuService._internal();

  final Dio _dio = HttpClient().dio;

  /// 获取视频弹幕列表
  /// [vid] 视频ID
  /// [part] 分P编号（从1开始）
  Future<List<Danmaku>> getDanmakuList({
    required int vid,
    int part = 1,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/danmaku/getDanmaku',
        queryParameters: {
          'vid': vid,
          'part': part,
        },
      );

      if (response.data['code'] == 200) {
        final danmakuList = response.data['data']['danmaku'] as List<dynamic>?;
        if (danmakuList == null || danmakuList.isEmpty) {
          return [];
        }
        return danmakuList
            .map((item) => Danmaku.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  /// 发送弹幕
  /// [request] 发送弹幕请求
  Future<bool> sendDanmaku(SendDanmakuRequest request) async {
    try {
      final response = await _dio.post(
        '/api/v1/danmaku/sendDanmaku',
        data: request.toJson(),
      );

      if (response.data['code'] == 200) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
}
