import 'package:dio/dio.dart';

/// HTTP 客户端单例
class HttpClient {
  static final HttpClient _instance = HttpClient._internal();
  factory HttpClient() => _instance;

  late final Dio dio;

  HttpClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: 'http://anime.ayypd.cn:3000',
        // 增加超时时间,适应弱网环境
        connectTimeout: const Duration(seconds: 15),  // 连接超时 15秒
        receiveTimeout: const Duration(seconds: 30),  // 接收超时 30秒
        sendTimeout: const Duration(seconds: 15),     // 发送超时 15秒
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );

    // 添加重试拦截器(在请求拦截器之前)
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        logPrint: print,
        retries: 3,  // 最多重试 3 次
        retryDelays: const [
          Duration(seconds: 1),   // 第一次重试等待 1 秒
          Duration(seconds: 2),   // 第二次重试等待 2 秒
          Duration(seconds: 3),   // 第三次重试等待 3 秒
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
