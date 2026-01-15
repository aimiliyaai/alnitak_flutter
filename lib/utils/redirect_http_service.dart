import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 自定义 HTTP 文件服务 - 支持多次301重定向
///
/// 默认的 HttpFileService 可能不支持跨域重定向，
/// 这个实现手动处理重定向以确保资源能正确加载
class RedirectAwareHttpFileService extends FileService {
  // 【性能优化】使用单例 http.Client 复用 TCP 连接
  // 配置更高的并发连接数以加速图片加载
  static final http.Client _sharedClient = _createOptimizedClient();
  final http.Client _httpClient;

  /// 创建优化的 HTTP 客户端
  /// 增加并发连接数，减少等待时间
  static http.Client _createOptimizedClient() {
    final httpClient = HttpClient()
      ..maxConnectionsPerHost = 10 // 【优化】每个主机最多10个并发连接（默认6个）
      ..connectionTimeout = const Duration(seconds: 15) // 连接超时
      ..idleTimeout = const Duration(seconds: 60); // 空闲连接保持60秒
    return IOClient(httpClient);
  }

  RedirectAwareHttpFileService({http.Client? httpClient})
      : _httpClient = httpClient ?? _sharedClient;

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    // 手动处理重定向，最多跟踪5次
    String currentUrl = url;
    http.StreamedResponse? response;

    for (int i = 0; i < 5; i++) {
      final request = http.Request('GET', Uri.parse(currentUrl));
      if (headers != null) {
        request.headers.addAll(headers);
      }
      // 不自动跟随重定向，手动处理
      request.followRedirects = false;

      response = await _httpClient.send(request);

      // 检查是否是重定向响应
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          // 处理相对路径重定向
          final redirectUri = Uri.parse(currentUrl).resolve(location);
          currentUrl = redirectUri.toString();
          // 消费掉当前响应体，避免资源泄漏
          await response.stream.drain();
          continue;
        }
      }

      // 非重定向响应，跳出循环
      break;
    }

    if (response == null) {
      throw Exception('Failed to get response for $url');
    }

    return HttpGetResponse(response);
  }
}
