import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/http_client.dart';
import '../utils/token_manager.dart';
import '../models/history_models.dart';

/// 历史记录服务
///
/// 【关键修复】Token 刷新逻辑已移至 HttpClient 统一处理
/// 【新增】本地缓存+重试机制，确保网络不好时也能恢复进度
class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  final Dio _dio = HttpClient().dio;
  final TokenManager _tokenManager = TokenManager();

  // 【新增】用于保证进度上报顺序的序列号
  int _progressSequence = 0;
  // 【新增】最后成功上报的进度（用于去重）
  double? _lastSuccessfulProgress;
  int? _lastSuccessfulVid;
  int? _lastSuccessfulPart;

  /// 【新增】获取本地缓存的进度
  Future<PlayProgressData?> _getLocalProgress(int vid, int? part) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = part != null ? 'progress_${vid}_$part' : 'progress_${vid}_latest';
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        return PlayProgressData.fromJson({'vid': vid, 'part': part ?? 1, 'progress': double.parse(jsonStr)});
      }
    } catch (e) {
      print('❌ 读取本地进度缓存失败: $e');
    }
    return null;
  }

  /// 【新增】保存进度到本地缓存
  Future<void> _saveLocalProgress(int vid, int part, double progress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'progress_${vid}_$part';
      await prefs.setString(key, progress.toStringAsFixed(1));
    } catch (e) {
      print('❌ 保存本地进度缓存失败: $e');
    }
  }

  /// 【新增】带重试的获取进度请求
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
          final progress = PlayProgressData.fromJson(response.data['data']);
          print('✅ 获取服务端进度成功 (#$attempt): vid=$vid, part=${progress.part}');
          return progress;
        } else if (code == 404) {
          print('ℹ️ 服务端无历史记录: vid=$vid');
          return null;
        } else {
          print('⚠️ 获取播放进度失败: code=$code, msg=${response.data['msg']}');
        }
      } catch (e) {
        print('❌ 获取播放进度异常 (#$attempt/$maxRetries): $e');
      }

      if (attempt < maxRetries) {
        print('⏳ 等待 ${delay.inMilliseconds}ms 后重试...');
        await Future.delayed(delay);
        delay *= 2; // 指数退避
      }
    }

    print('⚠️ 获取进度失败，已重试 $maxRetries 次');
    return null;
  }

  /// 添加历史记录
  /// [vid] 视频ID
  /// [part] 分P（默认为1）
  /// [time] 播放进度（秒，-1 表示已看完）
  /// [duration] 视频总时长（秒）
  ///
  /// 【修复】使用序列号机制防止乱序上报
  Future<bool> addHistory({
    required int vid,
    int part = 1,
    required double time,
    required int duration,
  }) async {
    // 【新增】检查是否可以进行认证请求（防止死循环）
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      print('⏭️ 跳过历史记录上报：未登录或token已失效');
      return false;
    }

    // 【修复】获取当前序列号
    final currentSequence = ++_progressSequence;

    // 【修复】检查是否是重复上报（相同视频、分P、进度）
    if (_lastSuccessfulVid == vid &&
        _lastSuccessfulPart == part &&
        _lastSuccessfulProgress == time) {
      print('⏭️ 跳过重复上报: vid=$vid, part=$part, time=${time.toStringAsFixed(1)}s');
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
        ).toJson(),
      );

      final code = response.data['code'];

      // 【修复】检查是否有更新的请求已经发出
      if (currentSequence < _progressSequence) {
        print('⏭️ 进度上报 #$currentSequence 已过期（当前最新 #$_progressSequence），忽略结果');
        return true; // 返回 true 因为更新的请求会处理
      }

      if (code == 200) {
        // 【修复】记录成功上报的进度，用于去重
        _lastSuccessfulVid = vid;
        _lastSuccessfulPart = part;
        _lastSuccessfulProgress = time;

        print(
          '✅ 历史记录已保存 #$currentSequence: '
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

  /// 重置进度上报状态（切换视频时调用）
  void resetProgressState() {
    _lastSuccessfulVid = null;
    _lastSuccessfulPart = null;
    _lastSuccessfulProgress = null;
    print('🔄 进度上报状态已重置');
  }

  /// 获取播放进度
  /// [vid] 视频ID
  /// [part] 分P（可选）
  /// 【优化】添加重试机制和本地缓存降级，确保网络不好时也能恢复
  Future<PlayProgressData?> getProgress({
    required int vid,
    int? part,
    bool useCache = true,
  }) async {
    // 【新增】检查是否可以进行认证请求
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      print('⏭️ 跳过获取进度：未登录或token已失效');
      return null;
    }

    // 【新增】优先尝试本地缓存（立即返回，不阻塞）
    if (useCache) {
      final localProgress = await _getLocalProgress(vid, part);
      if (localProgress != null) {
        print('📍 [缓存] 获取本地进度: vid=$vid, part=${localProgress.part}, progress=${localProgress.progress.toStringAsFixed(1)}s');
      }
    }

    // 【优化】发起带重试的网络请求
    final serverProgress = await _fetchProgressWithRetry(vid: vid, part: part);

    // 【优化】服务端成功则更新本地缓存
    if (serverProgress != null) {
      await _saveLocalProgress(vid, serverProgress.part, serverProgress.progress);
      return serverProgress;
    }

    // 【降级】网络失败时，返回本地缓存
    if (useCache) {
      final localProgress = await _getLocalProgress(vid, part);
      if (localProgress != null) {
        print('📍 [降级] 网络失败，使用本地缓存: vid=$vid, progress=${localProgress.progress.toStringAsFixed(1)}s');
        return localProgress;
      }
    }

    print('⚠️ 获取进度失败，无可用缓存');
    return null;
  }

  /// 获取历史记录列表
  /// [page] 页码（从1开始）
  /// [pageSize] 每页数量
  Future<HistoryListResponse?> getHistoryList({
    int page = 1,
    int pageSize = 20,
  }) async {
    // 【新增】检查是否可以进行认证请求
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      print('⏭️ 跳过获取历史记录：未登录或token已失效');
      return null;
    }

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
