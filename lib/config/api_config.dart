import 'package:shared_preferences/shared_preferences.dart';

/// API 配置
/// 统一管理 API 地址，方便切换 HTTP/HTTPS
class ApiConfig {
  ApiConfig._();

  /// SharedPreferences key
  static const String _httpsEnabledKey = 'https_enabled';

  /// 服务器域名
  static const String host = 'anime.ayypd.cn';

  /// 服务器端口
  static const int port = 9000;

  /// 是否启用 HTTPS（默认关闭）
  static bool _httpsEnabled = false;

  /// 获取当前 HTTPS 启用状态
  static bool get httpsEnabled => _httpsEnabled;

  /// 初始化配置（应在 app 启动时调用）
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _httpsEnabled = prefs.getBool(_httpsEnabledKey) ?? false;
  }

  /// 设置 HTTPS 启用状态
  static Future<void> setHttpsEnabled(bool enabled) async {
    _httpsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_httpsEnabledKey, enabled);
  }

  /// 获取当前使用的协议
  static String get _protocol => _httpsEnabled ? 'https' : 'http';

  /// API 基础地址
  static String get baseUrl {
    return '$_protocol://$host:$port';
  }

  /// HTTPS 基础地址
  static String get httpsBaseUrl {
    return 'https://$host:$port';
  }

  /// HTTP 基础地址
  static String get httpBaseUrl {
    return 'http://$host:$port';
  }

  /// Web 地址（用于分享等场景）
  static String get webUrl {
    return '$_protocol://$host';
  }
}
