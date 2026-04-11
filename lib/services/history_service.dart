import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/http_client.dart';
import '../utils/token_manager.dart';
import '../models/history_models.dart';
import 'logger_service.dart';

/// 历史记录服务
///
/// Token 刷新逻辑已移至 HttpClient 统一处理
/// 本地缓存+重试机制，确保网络不好时也能恢复进度
class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  /// 测试用构造器，跳过 Dio/TokenManager 初始化
  @visibleForTesting
  HistoryService.forTest();

  final Dio _dio = HttpClient().dio;
  final TokenManager _tokenManager = TokenManager();

  // 用于保证进度上报顺序的序列号
  int _progressSequence = 0;
  // 最后成功上报的进度（用于去重）
  double? _lastSuccessfulProgress;
  int? _lastSuccessfulVid;
  int? _lastSuccessfulPart;
  final Map<String, double> _lastSubmittedProgress = {};

  String _historyKey(int vid, int part) => '${vid}_$part';

  @visibleForTesting
  static bool isProgressRegression({
    required double newProgress,
    required double? lastProgress,
    double toleranceSeconds = 0.5,
  }) {
    if (newProgress < 0) return false;
    if (lastProgress == null || lastProgress < 0) return false;
    return newProgress + toleranceSeconds < lastProgress;
  }

  /// 获取本地缓存的进度
  Future<PlayProgressData?> _getLocalProgress(int vid, int? part) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = part != null ? 'progress_${vid}_$part' : 'progress_${vid}_latest';
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        return PlayProgressData.fromJson({'vid': vid, 'part': part ?? 1, 'progress': double.parse(jsonStr)});
      }
    } catch (e) {
      LoggerService.instance.logWarning('本地进度读取失败: $e', tag: 'HistoryService');
    }
    return null;
  }

  /// 保存进度到本地缓存
  Future<void> _saveLocalProgress(int vid, int part, double progress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'progress_${vid}_$part';
      await prefs.setString(key, progress.toStringAsFixed(1));
    } catch (e) {
      LoggerService.instance.logWarning('本地进度保存失败: $e', tag: 'HistoryService');
    }
  }

  /// 带重试的获取进度请求
  Future<PlayProgressData?> _fetchProgressWithRetry({
    required int vid,
    int? part,
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      attempt++;
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
          return PlayProgressData.fromJson(response.data['data']);
        } else if (code == 404) {
          return null;
        }
      } catch (e) {
        LoggerService.instance.logWarning('获取播放进度异常 (#$attempt/$maxRetries): $e', tag: 'HistoryService');
      }

      if (attempt < maxRetries) {
        await Future.delayed(delay);
        delay *= 2;
      }
    }

    return null;
  }

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
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return false;
    }

    final currentSequence = ++_progressSequence;
    final key = _historyKey(vid, part);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 单调保护：同一视频分P不允许回退写入（-1 完播标记除外）
    final lastSubmitted = _lastSubmittedProgress[key];
    if (isProgressRegression(newProgress: time, lastProgress: lastSubmitted)) {
      return true;
    }

    if (time >= 0) {
      _lastSubmittedProgress[key] = lastSubmitted == null
          ? time
          : (time > lastSubmitted ? time : lastSubmitted);
    } else {
      _lastSubmittedProgress[key] = time;
    }

    // 去重：跳过完全相同的上报
    if (_lastSuccessfulVid == vid &&
        _lastSuccessfulPart == part &&
        _lastSuccessfulProgress == time) {
      return true;
    }

    try {
      final response = await _dio.post(
        '/api/v1/history/video/addHistory',
        data: AddHistoryRequest(
          vid: vid,
          part: part,
          time: time,
          duration: duration,
          clientSequence: currentSequence,
          clientTimestampMs: nowMs,
        ).toJson(),
      );

      final code = response.data['code'];

      // 检查是否有更新的请求已经发出（当前请求已过期）
      if (currentSequence < _progressSequence) {
        return true;
      }

      if (code == 200) {
        _lastSuccessfulVid = vid;
        _lastSuccessfulPart = part;
        _lastSuccessfulProgress = time;
        // 同步写入本地缓存，断网时可作为 fallback
        _saveLocalProgress(vid, part, time);
        return true;
      }

      LoggerService.instance.logWarning('保存历史记录失败: code=$code', tag: 'HistoryService');
      return false;
    } catch (e) {
      LoggerService.instance.logWarning('保存历史记录异常: $e', tag: 'HistoryService');
      return false;
    }
  }

  /// 重置进度上报状态（切换视频时调用）
  void resetProgressState() {
    _lastSuccessfulVid = null;
    _lastSuccessfulPart = null;
    _lastSuccessfulProgress = null;
    _lastSubmittedProgress.clear();
  }

  /// 获取播放进度
  Future<PlayProgressData?> getProgress({
    required int vid,
    int? part,
    bool useCache = true,
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return null;
    }

    // 先读取本地缓存（后续可作为降级方案）
    PlayProgressData? localProgress;
    if (useCache) {
      localProgress = await _getLocalProgress(vid, part);
    }

    // 发起带重试的网络请求
    final serverProgress = await _fetchProgressWithRetry(vid: vid, part: part);

    // 服务端成功则更新本地缓存并返回
    if (serverProgress != null) {
      await _saveLocalProgress(vid, serverProgress.part, serverProgress.progress);
      return serverProgress;
    }

    // 网络失败时，返回之前已读取的本地缓存
    if (localProgress != null) {
      return localProgress;
    }

    return null;
  }

  /// 获取历史记录列表
  Future<HistoryListResponse?> getHistoryList({
    int page = 1,
    int pageSize = 20,
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return null;
    }

    try {
      final response = await _dio.get(
        '/api/v1/history/video/getHistory',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
        },
      );

      final code = response.data['code'];

      if (code == 200) {
        return HistoryListResponse.fromJson(response.data['data']);
      }

      return null;
    } catch (e) {
      LoggerService.instance.logWarning('获取历史记录异常: $e', tag: 'HistoryService');
      return null;
    }
  }
}
