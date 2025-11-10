import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HTTP 客户端单例
class HttpClient {
  static final HttpClient _instance = HttpClient._internal();
  factory HttpClient() => _instance;

  late final Dio dio;

  HttpClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: 'http://anime.ayypd.cn:3000',
        // 大幅增加超时时间,确保HLS分片请求在弱网环境下也能成功
        connectTimeout: const Duration(seconds: 30),  // 连接超时 30秒（提高到30秒）
        receiveTimeout: const Duration(seconds: 60),  // 接收超时 60秒（提高到60秒）
        sendTimeout: const Duration(seconds: 30),     // 发送超时 30秒（提高到30秒）
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );

    // 添加认证拦截器（第一个添加，确保优先执行）
    dio.interceptors.add(
      AuthInterceptor(),
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
          print('❌ 错误: ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }
}

/// 认证拦截器 - 自动添加 Authorization header
class AuthInterceptor extends Interceptor {
  static const String _tokenKey = 'auth_token';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // 如果请求已经包含 Authorization header，不覆盖
    if (options.headers.containsKey('Authorization')) {
      return handler.next(options);
    }

    // 从 SharedPreferences 获取 token
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);

      if (token != null && token.isNotEmpty) {
        // 添加 Authorization header
        options.headers['Authorization'] = token;
        print('🔑 添加 Authorization: $token');
      }
    } catch (e) {
      print('⚠️ 获取 token 失败: $e');
    }

    return handler.next(options);
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
      
      logPrint?.call(
        '⏳ 请求失败,${delay.inSeconds}秒后进行第 ${retryCount + 1} 次重试: ${err.requestOptions.uri}'
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
