import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../models/history_models.dart';

/// 历史记录服务
class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  final Dio _dio = HttpClient().dio;

  /// 添加历史记录
  /// [vid] 视频ID
  /// [part] 分P（默认为1）
  /// [time] 播放进度（秒）
  Future<bool> addHistory({
    required int vid,
    int part = 1,
    required double time,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/history/video/addHistory',
        data: AddHistoryRequest(
          vid: vid,
          part: part,
          time: time,
        ).toJson(),
      );

      if (response.data['code'] == 200) {
        print('✅ 历史记录已保存: vid=$vid, part=$part, time=${time.toStringAsFixed(1)}s');
        return true;
      } else {
        print('⚠️ 保存历史记录失败: code=${response.data['code']}, msg=${response.data['msg']}');
        return false;
      }
    } catch (e) {
      print('❌ 保存历史记录失败: $e');
      return false;
    }
  }

  /// 获取播放进度
  /// [vid] 视频ID
  /// [part] 分P（默认为1）
  /// 返回播放进度（秒），如果没有历史记录返回null
  Future<double?> getProgress({
    required int vid,
    int part = 1,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/history/video/getProgress',
        queryParameters: {
          'vid': vid,
          'part': part,
        },
      );

      if (response.data['code'] == 200) {
        final data = PlayProgressData.fromJson(response.data['data']);
        print('📍 获取播放进度: vid=$vid, part=$part, progress=${data.progress.toStringAsFixed(1)}s');
        return data.progress;
      } else if (response.data['code'] == 404) {
        // 没有历史记录
        print('ℹ️ 无历史记录: vid=$vid, part=$part');
        return null;
      } else {
        print('⚠️ 获取播放进度失败: code=${response.data['code']}, msg=${response.data['msg']}');
        return null;
      }
    } catch (e) {
      print('❌ 获取播放进度失败: $e');
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
      final response = await _dio.get(
        '/api/v1/history/video/getHistory',
        queryParameters: {
          'page': page,
          'page_size': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        return HistoryListResponse.fromJson(response.data['data']);
      } else {
        print('⚠️ 获取历史记录列表失败: code=${response.data['code']}, msg=${response.data['msg']}');
        return null;
      }
    } catch (e) {
      print('❌ 获取历史记录列表失败: $e');
      return null;
    }
  }
}
