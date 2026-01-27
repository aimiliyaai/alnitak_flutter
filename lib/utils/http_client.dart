import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'error_handler.dart';
import '../config/api_config.dart';
import 'token_manager.dart';

/// HTTP 客户端单例
class HttpClient {
  static final HttpClient _instance = HttpClient._internal();
  factory HttpClient() => _instance;

  late final Dio dio;

  HttpClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        // 大幅增加超时时间,确保HLS分片请求在弱网环境下也能成功
        connectTimeout: const Duration(seconds: 30),  // 连接超时 30秒（提高到30秒）
        receiveTimeout: const Duration(seconds: 60),  // 接收超时 60秒（提高到60秒）
        sendTimeout: const Duration(seconds: 30),     // 发送超时 30秒（提高到30秒）
        headers: {
          'Content-Type': 'application/json',
        },
        // 启用自动重定向支持（最多跟踪5次重定向）
        followRedirects: true,
        maxRedirects: 5,
      ),
    );

    // 添加认证拦截器（第一个添加，确保优先执行）
    dio.interceptors.add(
      AuthInterceptor(this),
    );

    // 添加重试拦截器
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        logPrint: _debugPrint,
        retries: 10,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 3),
          Duration(seconds: 3),
          Duration(seconds: 5),
          Duration(seconds: 5),
          Duration(seconds: 8),
          Duration(seconds: 8),
          Duration(seconds: 10),
          Duration(seconds: 10),
        ],
      ),
    );

    // 添加日志拦截器（仅调试模式）
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _debugPrint('🌐 请求: ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          _debugPrint('✅ 响应: ${response.statusCode} ${response.requestOptions.uri}');
          return handler.next(response);
        },
        onError: (error, handler) {
          final friendlyMessage = ErrorHandler.getErrorMessage(error);
          _debugPrint('❌ 请求失败: $friendlyMessage (${error.requestOptions.uri})');
          return handler.next(error);
        },
      ),
    );
  }

  /// 调试日志（Release 模式不输出）
  static void _debugPrint(Object message) {
    if (kDebugMode) {
      print(message);
    }
  }

  /// 初始化 HttpClient（应在 TokenManager.initialize() 之后调用）
  Future<void> init() async {
    // 更新 baseUrl
    dio.options.baseUrl = ApiConfig.baseUrl;
    _debugPrint('🌐 HttpClient baseUrl 已更新: ${ApiConfig.baseUrl}');
  }

  // ========== 兼容性 API（委托给 TokenManager）==========

  /// 获取缓存的 Token
  static String? get cachedToken => TokenManager().token;

  /// 获取缓存的 RefreshToken
  static String? get cachedRefreshToken => TokenManager().refreshToken;

  /// 更新 Token 缓存（登录成功后调用）
  static Future<void> updateCachedTokens({
    required String token,
    required String refreshToken,
  }) async {
    await TokenManager().saveTokens(token: token, refreshToken: refreshToken);
  }

  /// 更新单个 Token（刷新后调用）
  static Future<void> updateCachedToken(String token) async {
    await TokenManager().updateToken(token);
  }

  /// 清除 Token 缓存（登出时调用）
  static Future<void> clearCachedTokens() async {
    await TokenManager().clearTokens();
  }

  /// 刷新 Token（带锁机制，防止并发刷新）
  Future<String?> refreshToken() async {
    final tokenManager = TokenManager();

    // 【新增】检查是否刷新已失败（冷却期内不再尝试）
    if (tokenManager.isRefreshFailed) {
      _debugPrint('⏸️ Token 刷新已失败且在冷却期内，跳过刷新');
      return null;
    }

    // 检查是否正在刷新
    final existingCompleter = tokenManager.refreshCompleter;
    if (tokenManager.isRefreshing && existingCompleter != null) {
      _debugPrint('🔄 Token 正在刷新中，等待...');
      return existingCompleter.future;
    }

    // 开始刷新
    final completer = Completer<String?>();
    tokenManager.setRefreshing(true, completer);

    try {
      final refreshTokenValue = tokenManager.refreshToken;
      if (refreshTokenValue == null || refreshTokenValue.isEmpty) {
        _debugPrint('❌ RefreshToken 不存在，需要重新登录');
        tokenManager.markRefreshFailed(); // 【新增】标记刷新失败
        await tokenManager.handleTokenExpired();
        completer.complete(null);
        return null;
      }

      _debugPrint('🔄 开始刷新 Token...');

      // 使用新的 Dio 实例避免拦截器循环
      final refreshDio = Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      final response = await refreshDio.post(
        '/api/v1/auth/updateToken',
        data: {'refreshToken': refreshTokenValue},
      );

      if (response.data['code'] == 200) {
        final newToken = response.data['data']['token'] as String;
        await tokenManager.updateToken(newToken);
        _debugPrint('✅ Token 刷新成功');
        completer.complete(newToken);
        return newToken;
      } else if (response.data['code'] == 2000) {
        // RefreshToken 也失效了，触发自动退出
        _debugPrint('❌ RefreshToken 已失效，执行自动退出');
        tokenManager.markRefreshFailed(); // 【新增】标记刷新失败
        await tokenManager.handleTokenExpired();
        completer.complete(null);
        return null;
      } else {
        _debugPrint('⚠️ Token 刷新失败: ${response.data['msg']}');
        tokenManager.markRefreshFailed(); // 【新增】标记刷新失败
        completer.complete(null);
        return null;
      }
    } catch (e) {
      _debugPrint('❌ Token 刷新异常: $e');
      tokenManager.markRefreshFailed(); // 【新增】标记刷新失败
      completer.complete(null);
      return null;
    } finally {
      tokenManager.setRefreshing(false, null);
      // 延迟清除 Completer
      Future.delayed(const Duration(milliseconds: 100), () {
        if (tokenManager.refreshCompleter == completer) {
          tokenManager.setRefreshing(false, null);
        }
      });
    }
  }
}

/// 认证拦截器 - 自动添加 Authorization header + 自动刷新 Token
class AuthInterceptor extends Interceptor {
  final HttpClient _httpClient;

  AuthInterceptor(this._httpClient);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final tokenManager = TokenManager();

    // 如果请求已经包含 Authorization header，不覆盖
    if (options.headers.containsKey('Authorization')) {
      return handler.next(options);
    }

    // 【新增】如果刷新已失败（用户未登录或token无效），不添加无效的token
    if (tokenManager.isRefreshFailed) {
      if (kDebugMode) {
        print('⏸️ 刷新已失败，跳过添加 Authorization');
      }
      return handler.next(options);
    }

    // 从 TokenManager 获取 Token
    final token = tokenManager.token;

    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = token;
      // 不打印完整 token，只打印脱敏版本
      if (kDebugMode) {
        print('🔑 已添加 Authorization');
      }
    }

    return handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final tokenManager = TokenManager();

    // 检测 Token 失效响应，自动刷新
    if (response.data is Map && response.data['code'] == 3000) {
      // 【新增】如果刷新已失败，不再尝试刷新，直接返回响应
      if (tokenManager.isRefreshFailed) {
        if (kDebugMode) {
          print('⏸️ Token 刷新已失败且在冷却期内，直接返回响应');
        }
        return handler.next(response);
      }

      if (kDebugMode) {
        print('🔄 检测到 Token 失效 (code=3000)，尝试自动刷新...');
      }

      final newToken = await _httpClient.refreshToken();
      if (newToken != null) {
        // Token 刷新成功，重试原请求
        if (kDebugMode) {
          print('🔄 Token 刷新成功，重试原请求...');
        }
        try {
          final options = response.requestOptions;
          options.headers['Authorization'] = newToken;
          final retryResponse = await _httpClient.dio.fetch(options);
          return handler.next(retryResponse);
        } catch (e) {
          if (kDebugMode) {
            print('❌ 重试请求失败: $e');
          }
          return handler.next(response);
        }
      } else {
        if (kDebugMode) {
          print('❌ Token 刷新失败，返回原响应（不再重试）');
        }
        // 刷新失败，直接返回原响应，不会再次触发刷新
      }
    }

    return handler.next(response);
  }
}

/// 自定义重试拦截器
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final List<Duration> retryDelays;
  final void Function(Object message)? logPrint;

  RetryInterceptor({
    required this.dio,
    this.retries = 3,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
    ],
    this.logPrint,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final retryCount = extra['retryCount'] as int? ?? 0;

    // 判断是否需要重试
    if (retryCount < retries && _shouldRetry(err)) {
      extra['retryCount'] = retryCount + 1;

      // 计算延迟时间
      final delay = retryCount < retryDelays.length
          ? retryDelays[retryCount]
          : retryDelays.last;

      final friendlyMessage = ErrorHandler.getErrorMessage(err);
      logPrint?.call(
          '⏳ $friendlyMessage，${delay.inSeconds}秒后进行第 ${retryCount + 1} 次重试');

      // 延迟后重试
      await Future.delayed(delay);

      try {
        // 重新发起请求
        final response = await dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } on DioException catch (e) {
        // 继续处理错误
        return super.onError(e, handler);
      }
    }

    // 不重试或已达到最大重试次数
    return super.onError(err, handler);
  }

  /// 判断是否应该重试
  bool _shouldRetry(DioException err) {
    // 网络连接错误、超时错误需要重试
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        // 服务器 5xx 错误也重试
        (err.response?.statusCode != null && err.response!.statusCode! >= 500);
  }
}
