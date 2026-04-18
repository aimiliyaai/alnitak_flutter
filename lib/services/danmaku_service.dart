import 'package:dio/dio.dart';
import '../models/danmaku.dart';
import '../utils/http_client.dart';
import 'logger_service.dart';

/// 弹幕API服务
class DanmakuService {
  static final DanmakuService _instance = DanmakuService._internal();
  factory DanmakuService() => _instance;
  DanmakuService._internal();

  final Dio _dio = HttpClient().dio;

  /// 获取视频弹幕列表
  /// [vid] 视频ID (支持 shortId)
  /// [rid] 资源 shortId（传入则优先按 rid 精准匹配）
  /// [part] 分P编号（从1开始），仅在 rid 为空时生效
  Future<List<Danmaku>> getDanmakuList({
    required String vid,
    String? rid,
    int part = 1,
  }) async {
    try {
      final query = <String, dynamic>{'vid': vid};
      if (rid != null && rid.isNotEmpty) {
        query['rid'] = rid;
      } else {
        query['part'] = part;
      }
      final response = await _dio.get(
        '/api/v1/danmaku/getDanmaku',
        queryParameters: query,
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
      LoggerService.instance.logWarning('获取弹幕列表失败: $e', tag: 'DanmakuService');
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
      LoggerService.instance.logWarning('发送弹幕失败: $e', tag: 'DanmakuService');
      return false;
    }
  }
}
