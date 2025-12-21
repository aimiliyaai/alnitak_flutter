import 'package:dio/dio.dart';

/// 统一错误处理工具类
class ErrorHandler {
  /// 根据错误类型返回友好的错误提示
  static String getErrorMessage(dynamic error) {
    // 处理 DioException
    if (error is DioException) {
      return _getDioErrorMessage(error);
    }

    final errorStr = error.toString().toLowerCase();

    // 网络相关错误
    if (_isNetworkError(errorStr)) {
      return '网络连接失败，请检查网络后重试';
    }

    // 超时错误
    if (_isTimeoutError(errorStr)) {
      return '请求超时，请检查网络后重试';
    }

    // 服务器错误
    if (_isServerError(errorStr)) {
      return '服务器繁忙，请稍后重试';
    }

    // 资源不存在
    if (errorStr.contains('404') || errorStr.contains('not found')) {
      return '请求的资源不存在';
    }

    // 权限错误
    if (_isAuthError(errorStr)) {
      return '暂无访问权限，请重新登录';
    }

    // 默认错误提示
    return '操作失败，请稍后重试';
  }

  /// 处理 Dio 异常
  static String _getDioErrorMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查网络后重试';
      case DioExceptionType.sendTimeout:
        return '发送超时，请检查网络后重试';
      case DioExceptionType.receiveTimeout:
        return '接收超时，请检查网络后重试';
      case DioExceptionType.badCertificate:
        return '证书验证失败';
      case DioExceptionType.badResponse:
        return _getHttpStatusMessage(error.response?.statusCode);
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络设置';
      case DioExceptionType.unknown:
        // 检查内部错误
        final message = error.message?.toLowerCase() ?? '';
        if (_isNetworkError(message)) {
          return '网络连接失败，请检查网络后重试';
        }
        return '网络异常，请稍后重试';
    }
  }

  /// 根据 HTTP 状态码返回错误信息
  static String _getHttpStatusMessage(int? statusCode) {
    if (statusCode == null) {
      return '服务器响应异常';
    }

    switch (statusCode) {
      case 400:
        return '请求参数错误';
      case 401:
        return '登录已过期，请重新登录';
      case 403:
        return '暂无访问权限';
      case 404:
        return '请求的资源不存在';
      case 405:
        return '请求方式不支持';
      case 408:
        return '请求超时';
      case 429:
        return '请求过于频繁，请稍后再试';
      case 500:
        return '服务器内部错误';
      case 501:
        return '服务未实现';
      case 502:
        return '网关错误';
      case 503:
        return '服务暂时不可用';
      case 504:
        return '网关超时';
      default:
        if (statusCode >= 500) {
          return '服务器繁忙，请稍后重试';
        }
        return '请求失败 ($statusCode)';
    }
  }

  /// 检查是否是网络错误
  static bool _isNetworkError(String errorStr) {
    return errorStr.contains('socketexception') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('connection reset') ||
        errorStr.contains('connection closed') ||
        errorStr.contains('network is unreachable') ||
        errorStr.contains('no address associated') ||
        errorStr.contains('host lookup') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('no internet') ||
        errorStr.contains('no route to host') ||
        errorStr.contains('network unreachable') ||
        errorStr.contains('enetunreach') ||
        errorStr.contains('econnrefused') ||
        errorStr.contains('econnreset');
  }

  /// 检查是否是超时错误
  static bool _isTimeoutError(String errorStr) {
    return errorStr.contains('timeout') ||
        errorStr.contains('timed out') ||
        errorStr.contains('etimedout');
  }

  /// 检查是否是服务器错误
  static bool _isServerError(String errorStr) {
    return errorStr.contains('500') ||
        errorStr.contains('502') ||
        errorStr.contains('503') ||
        errorStr.contains('504') ||
        errorStr.contains('internal server error');
  }

  /// 检查是否是认证错误
  static bool _isAuthError(String errorStr) {
    return errorStr.contains('401') ||
        errorStr.contains('403') ||
        errorStr.contains('unauthorized') ||
        errorStr.contains('forbidden');
  }

  /// 判断是否是网络相关的错误（用于决定是否显示重试按钮）
  static bool isNetworkRelatedError(dynamic error) {
    if (error is DioException) {
      return error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError ||
          (error.type == DioExceptionType.unknown &&
              _isNetworkError(error.message?.toLowerCase() ?? ''));
    }

    final errorStr = error.toString().toLowerCase();
    return _isNetworkError(errorStr) || _isTimeoutError(errorStr);
  }
}
