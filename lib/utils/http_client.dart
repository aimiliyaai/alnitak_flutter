import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'error_handler.dart';
import '../config/api_config.dart';

/// HTTP 客户端单例
class HttpClient {
  static final HttpClient _instance = HttpClient._internal();
  factory HttpClient() => _instance;

  late final Dio dio;

  // 【关键修复】Token 内存缓存，避免频繁读取 SharedPreferences
  static String? _cachedToken;
  static String? _cachedRefreshToken;
  static bool _isRefreshingToken = false;
  static Completer<String?>? _refreshCompleter;

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

    // 添加重试拦截器(在请求拦截器之前)
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        logPrint: print,
        retries: 10,  // 最多重试 10 次（提高重试次数，确保HLS分片请求成功）
        retryDelays: const [
          Duration(seconds: 1),   // 第1次重试等待 1 秒
          Duration(seconds: 2),   // 第2次重试等待 2 秒
          Duration(seconds: 3),   // 第3次重试等待 3 秒
          Duration(seconds: 3),   // 第4次重试等待 3 秒
          Duration(seconds: 5),   // 第5次重试等待 5 秒
          Duration(seconds: 5),   // 第6次重试等待 5 秒
          Duration(seconds: 8),   // 第7次重试等待 8 秒
          Duration(seconds: 8),   // 第8次重试等待 8 秒
          Duration(seconds: 10),  // 第9次重试等待 10 秒
          Duration(seconds: 10),  // 第10次重试等待 10 秒
        ],
      ),
    );

    // 添加日志拦截器
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          print('🌐 请求: ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          print('✅ 响应: ${response.statusCode} ${response.requestOptions.uri}');
          return handler.next(response);
        },
        onError: (error, handler) {
          final friendlyMessage = ErrorHandler.getErrorMessage(error);
          print('❌ 请求失败: $friendlyMessage (${error.requestOptions.uri})');
          return handler.next(error);
        },
      ),
    );

    // 【关键修复】初始化时预加载 Token 到内存
    _preloadTokens();
  }

  /// 初始化 HttpClient（应在 ApiConfig.init() 之后调用）
  /// 用于更新 baseUrl 并预加载 Token
  Future<void> init() async {
    // 更新 baseUrl（确保使用最新的 ApiConfig 配置）
    dio.options.baseUrl = ApiConfig.baseUrl;
    print('🌐 HttpClient baseUrl 已更新: ${ApiConfig.baseUrl}');

    // 预加载 Token
    await _preloadTokens();
  }

  /// 预加载 Token 到内存缓存
  Future<void> _preloadTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedToken = prefs.getString('auth_token');
      _cachedRefreshToken = prefs.getString('refresh_token');
      print('🔐 Token 已预加载到内存: ${_cachedToken != null ? "有效" : "无"}');
    } catch (e) {
      print('⚠️ 预加载 Token 失败: $e');
    }
  }

  /// 获取缓存的 Token（同步方法，避免异步竞争）
  static String? get cachedToken => _cachedToken;

  /// 获取缓存的 RefreshToken
  static String? get cachedRefreshToken => _cachedRefreshToken;

  /// 更新 Token 缓存（登录成功后调用）
  static Future<void> updateCachedTokens({
    required String token,
    required String refreshToken,
  }) async {
    _cachedToken = token;
    _cachedRefreshToken = refreshToken;
    print('🔐 Token 缓存已更新');

    // 同时保存到 SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('refresh_token', refreshToken);
  }

  /// 更新单个 Token（刷新后调用）
  static Future<void> updateCachedToken(String token) async {
    _cachedToken = token;
    print('🔐 Token 已刷新');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  /// 清除 Token 缓存（登出时调用）
  static Future<void> clearCachedTokens() async {
    _cachedToken = null;
    _cachedRefreshToken = null;
    print('🔐 Token 缓存已清除');

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');
  }

  /// 刷新 Token（带锁机制，防止并发刷新）
  Future<String?> refreshToken() async {
    // 如果已经在刷新中，等待结果
    if (_isRefreshingToken && _refreshCompleter != null) {
      print('🔄 Token 正在刷新中，等待...');
      return _refreshCompleter!.future;
    }

    // 开始刷新
    _isRefreshingToken = true;
    _refreshCompleter = Completer<String?>();

    try {
      final refreshToken = _cachedRefreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        print('❌ RefreshToken 不存在，需要重新登录');
        _refreshCompleter!.complete(null);
        return null;
      }

      print('🔄 开始刷新 Token...');

      // 使用新的 Dio 实例避免拦截器循环
      final refreshDio = Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      final response = await refreshDio.post(
        '/api/v1/auth/updateToken',
        data: {'refreshToken': refreshToken},
      );

      if (response.data['code'] == 200) {
        final newToken = response.data['data']['token'] as String;
        await updateCachedToken(newToken);
        print('✅ Token 刷新成功');
        _refreshCompleter!.complete(newToken);
        return newToken;
      } else if (response.data['code'] == 2000) {
        // RefreshToken 也失效了
        print('❌ RefreshToken 已失效，需要重新登录');
        await clearCachedTokens();
        _refreshCompleter!.complete(null);
        return null;
      } else {
        print('⚠️ Token 刷新失败: ${response.data['msg']}');
        _refreshCompleter!.complete(null);
        return null;
      }
    } catch (e) {
      print('❌ Token 刷新异常: $e');
      _refreshCompleter!.complete(null);
      return null;
    } finally {
      _isRefreshingToken = false;
      _refreshCompleter = null;
    }
  }
}

/// 认证拦截器 - 自动添加 Authorization header + 自动刷新 Token
class AuthInterceptor extends Interceptor {
  final HttpClient _httpClient;

  AuthInterceptor(this._httpClient);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 如果请求已经包含 Authorization header，不覆盖
    if (options.headers.containsKey('Authorization')) {
      return handler.next(options);
    }

    // 【关键修复】直接从内存缓存获取 Token（同步，无竞争）
    final token = HttpClient.cachedToken;

    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = token;
      print('🔑 添加 Authorization: $token');
    }

    return handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    // 【关键修复】检测 Token 失效响应，自动刷新
    if (response.data is Map && response.data['code'] == 3000) {
      print('🔄 检测到 Token 失效 (code=3000)，尝试自动刷新...');

      final newToken = await _httpClient.refreshToken();
      if (newToken != null) {
        // Token 刷新成功，重试原请求
        print('🔄 Token 刷新成功，重试原请求...');
        try {
          final options = response.requestOptions;
          options.headers['Authorization'] = newToken;
          final retryResponse = await _httpClient.dio.fetch(options);
          return handler.next(retryResponse);
        } catch (e) {
          print('❌ 重试请求失败: $e');
          return handler.next(response);
        }
      } else {
        print('❌ Token 刷新失败，返回原响应');
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
        '⏳ $friendlyMessage，${delay.inSeconds}秒后进行第 ${retryCount + 1} 次重试'
      );

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
        (err.response?.statusCode != null && 
         err.response!.statusCode! >= 500);
  }
}
