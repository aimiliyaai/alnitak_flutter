import 'dart:async';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import 'token_manager.dart';

class HttpClient {
  static final HttpClient _instance = HttpClient._internal();
  factory HttpClient() => _instance;

  late final Dio dio;

  HttpClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
        },
        followRedirects: true,
        maxRedirects: 5,
      ),
    );

    dio.interceptors.add(
      AuthInterceptor(this),
    );

    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
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

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          return handler.next(options);
        },
        onResponse: (response, handler) {
          return handler.next(response);
        },
        onError: (error, handler) {
          return handler.next(error);
        },
      ),
    );
  }

  Future<void> init() async {
    dio.options.baseUrl = ApiConfig.baseUrl;
  }

  static String? get cachedToken => TokenManager().token;

  static String? get cachedRefreshToken => TokenManager().refreshToken;

  static Future<void> updateCachedTokens({
    required String token,
    required String refreshToken,
  }) async {
    await TokenManager().saveTokens(token: token, refreshToken: refreshToken);
  }

  static Future<void> updateCachedToken(String token) async {
    await TokenManager().updateToken(token);
  }

  static Future<void> clearCachedTokens() async {
    await TokenManager().clearTokens();
  }

  Future<String?> refreshToken() async {
    final tokenManager = TokenManager();

    if (tokenManager.isRefreshFailed) {
      return null;
    }

    final existingCompleter = tokenManager.refreshCompleter;
    if (tokenManager.isRefreshing && existingCompleter != null) {
      return existingCompleter.future;
    }

    final completer = Completer<String?>();
    tokenManager.setRefreshing(true, completer);

    try {
      final refreshTokenValue = tokenManager.refreshToken;
      if (refreshTokenValue == null || refreshTokenValue.isEmpty) {
        tokenManager.markRefreshFailed();
        await tokenManager.handleTokenExpired();
        completer.complete(null);
        return null;
      }

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
        completer.complete(newToken);
        return newToken;
      } else if (response.data['code'] == 2000) {
        tokenManager.markRefreshFailed();
        await tokenManager.handleTokenExpired();
        completer.complete(null);
        return null;
      } else {
        tokenManager.markRefreshFailed();
        completer.complete(null);
        return null;
      }
    } catch (e) {
      tokenManager.markRefreshFailed();
      completer.complete(null);
      return null;
    } finally {
      tokenManager.setRefreshing(false, null);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (tokenManager.refreshCompleter == completer) {
          tokenManager.setRefreshing(false, null);
        }
      });
    }
  }
}

class AuthInterceptor extends Interceptor {
  final HttpClient _httpClient;

  AuthInterceptor(this._httpClient);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final tokenManager = TokenManager();

    if (options.headers.containsKey('Authorization')) {
      return handler.next(options);
    }

    if (tokenManager.isRefreshFailed) {
      return handler.next(options);
    }

    final token = tokenManager.token;

    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = token;
    }

    return handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final tokenManager = TokenManager();

    if (response.data is Map && response.data['code'] == 3000) {
      if (tokenManager.isRefreshFailed) {
        return handler.next(response);
      }

      final newToken = await _httpClient.refreshToken();
      if (newToken != null) {
        try {
          final options = response.requestOptions;
          options.headers['Authorization'] = newToken;
          final retryResponse = await _httpClient.dio.fetch(options);
          return handler.next(retryResponse);
        } catch (e) {
          return handler.next(response);
        }
      } else {
      }
    }

    return handler.next(response);
  }
}

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final List<Duration> retryDelays;

  RetryInterceptor({
    required this.dio,
    this.retries = 3,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
    ],
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final retryCount = extra['retryCount'] as int? ?? 0;

    if (retryCount < retries && _shouldRetry(err)) {
      extra['retryCount'] = retryCount + 1;

      final delay = retryCount < retryDelays.length
          ? retryDelays[retryCount]
          : retryDelays.last;

      await Future.delayed(delay);

      try {
        final response = await dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } on DioException catch (e) {
        return super.onError(e, handler);
      }
    }

    return super.onError(err, handler);
  }

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.response?.statusCode != null && err.response!.statusCode! >= 500);
  }
}
