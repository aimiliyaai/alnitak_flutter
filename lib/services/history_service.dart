import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../models/history_models.dart';

/// 历史记录服务
///
/// 【关键修复】Token 刷新逻辑已移至 HttpClient 统一处理
/// 当收到 code=3000 时，AuthInterceptor 会自动刷新 Token 并重试请求
class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  final Dio _dio = HttpClient().dio;

  /// 添加历史记录
  /// [vid] 视频ID
  /// [part] 分P（默认为1）
  /// [time] 播放进度（秒，-1 表示已看完）
  /// [duration] 视频总时长（秒）
  Future<bool> addHistory({
    required int vid,
    int part = 1,
    required double time,
    required int duration,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/history/video/addHistory',
        data: AddHistoryRequest(
          vid: vid,
          part: part,
          time: time,
          duration: duration,
        ).toJson(),
      );

      final code = response.data['code'];

      if (code == 200) {
        print(
          '✅ 历史记录已保存: '
          'vid=$vid, part=$part, time=${time.toStringAsFixed(1)}s, duration=${duration}s',
        );
        return true;
      }

      // 【注意】code=3000 的情况已由 AuthInterceptor 自动处理
      // 如果走到这里说明自动刷新也失败了
      print('⚠️ 保存历史记录失败: code=$code, msg=${response.data['msg']}');
      return false;
    } catch (e) {
      print('❌ 保存历史记录异常: $e');
      return false;
    }
  }

  /// 获取播放进度
  /// [vid] 视频ID
  /// [part] 分P（可选）
  Future<PlayProgressData?> getProgress({
    required int vid,
    int? part,
  }) async {
    try {
      final queryParams = <String, dynamic>{'vid': vid};
      if (part != null) {
        queryParams['part'] = part;
      }

      final response = await _dio.get(
        '/api/v1/history/video/getProgress',
        queryParameters: queryParams,
      );

      final code = response.data['code'];

      if (code == 200) {
        final data = PlayProgressData.fromJson(response.data['data']);
        print(
          '📍 获取播放进度: '
          'vid=$vid, part=${data.part}, progress=${data.progress.toStringAsFixed(1)}s',
        );
        return data;
      }

      if (code == 404) {
        print('ℹ️ 无历史记录: vid=$vid${part != null ? ", part=$part" : ""}');
        return null;
      }

      print('⚠️ 获取播放进度失败: code=$code, msg=${response.data['msg']}');
      return null;
    } catch (e) {
      print('❌ 获取播放进度异常: $e');
      return null;
    }
  }

  /// 获取历史记录列表
  /// [page] 页码（从1开始）
  /// [pageSize] 每页数量
  Future<HistoryListResponse?> getHistoryList({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      print('📜 [History] 请求历史记录: page=$page, pageSize=$pageSize');

      final response = await _dio.get(
        '/api/v1/history/video/getHistory',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
        },
      );

      final code = response.data['code'];

      if (code == 200) {
        final result = HistoryListResponse.fromJson(response.data['data']);
        print('📜 [History] 解析成功: ${result.videos.length} 条记录');
        return result;
      }

      print('⚠️ 获取历史记录失败: code=$code, msg=${response.data['msg']}');
      return null;
    } catch (e) {
      print('❌ 获取历史记录异常: $e');
      return null;
    }
  }
}
