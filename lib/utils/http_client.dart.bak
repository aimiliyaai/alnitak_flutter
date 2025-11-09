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
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );

    // 添加拦截器
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
