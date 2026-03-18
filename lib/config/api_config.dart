import 'package:shared_preferences/shared_preferences.dart';

/// API 配置
/// 统一管理 API 地址，支持默认值 + SharedPreferences 覆盖（便于环境/调试切换）
class ApiConfig {
  ApiConfig._();

  static const String _httpsEnabledKey = 'https_enabled';
  static const String _hostOverrideKey = 'api_host_override';
  static const String _portOverrideKey = 'api_port_override';

  /// 默认服务器域名（可被 override 覆盖）
  static const String defaultHost = 'anime.ayypd.cn';
  static const int defaultPortHttp = 9000;
  static const int defaultPortHttps = 9001;
  static const String defaultShareHost = 'anime.ayypd.cn';
  static const int defaultSharePort = 3000;

  static bool _httpsEnabled = true;
  static String? _hostOverride;
  static int? _portOverride;

  /// 当前生效的服务器域名
  static String get host => _hostOverride ?? defaultHost;
  /// 当前生效的 API 端口（HTTPS 9001，HTTP 9000）
  static int get port => _portOverride ?? (_httpsEnabled ? defaultPortHttps : defaultPortHttp);
  static String get shareHost => defaultShareHost;
  static int get sharePort => defaultSharePort;

  static bool get httpsEnabled => _httpsEnabled;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _httpsEnabled = prefs.getBool(_httpsEnabledKey) ?? true;
    final savedHost = prefs.getString(_hostOverrideKey);
    _hostOverride = (savedHost != null && savedHost.isNotEmpty) ? savedHost : null;
    final savedPort = prefs.getInt(_portOverrideKey);
    _portOverride = (savedPort != null && savedPort > 0) ? savedPort : null;
  }

  /// 设置 API 主机/端口覆盖（空字符串或 0 表示恢复默认）
  static Future<void> setHostPortOverride({String? host, int? port}) async {
    final prefs = await SharedPreferences.getInstance();
    if (host != null) {
      _hostOverride = host.isEmpty ? null : host;
      if (_hostOverride == null) {
        await prefs.remove(_hostOverrideKey);
      } else {
        await prefs.setString(_hostOverrideKey, _hostOverride!);
      }
    }
    if (port != null) {
      _portOverride = port <= 0 ? null : port;
      if (_portOverride == null) {
        await prefs.remove(_portOverrideKey);
      } else {
        await prefs.setInt(_portOverrideKey, _portOverride!);
      }
    }
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

  /// 分享地址（HTTPS 启用时自动用 https 前缀）
  /// 80/443 端口不带端口，其他端口带端口
  static String getShareUrl(String path) {
    final portStr = sharePort == 80 || sharePort == 443 ? '' : ':$sharePort';
    return '$_protocol://$shareHost$portStr/$path';
  }
}
