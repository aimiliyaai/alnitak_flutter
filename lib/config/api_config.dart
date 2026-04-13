import 'package:shared_preferences/shared_preferences.dart';

/// API 配置
///
/// 统一管理 API / 分享地址，支持默认值 + SharedPreferences 覆盖。
class ApiConfig {
  ApiConfig._();

  // ── 持久化键 ──

  static const String _httpsEnabledKey = 'https_enabled';
  static const String _hostOverrideKey = 'api_host_override';
  static const String _portOverrideKey = 'api_port_override';

  // ── 默认值 ──

  static const String defaultHost = 'anime.ayypd.cn';
  static const int defaultPortHttp = 9000;
  static const int defaultPortHttps = 9001;
  static const String defaultShareHost = 'anime.ayypd.cn';
  static const int defaultSharePort = 3000;
  static const bool defaultShareHttps = true;

  // ── 运行时状态 ──

  static bool _httpsEnabled = true;
  static String? _hostOverride;
  static int? _portOverride;

  // ── 公开 getter ──

  static String get host => _hostOverride ?? defaultHost;
  static int get port =>
      _portOverride ?? (_httpsEnabled ? defaultPortHttps : defaultPortHttp);
  static bool get httpsEnabled => _httpsEnabled;
  static String get shareHost => defaultShareHost;
  static int get sharePort => defaultSharePort;

  // ── 初始化 ──

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _httpsEnabled = prefs.getBool(_httpsEnabledKey) ?? true;
    final savedHost = prefs.getString(_hostOverrideKey);
    _hostOverride = (savedHost != null && savedHost.isNotEmpty) ? savedHost : null;
    final savedPort = prefs.getInt(_portOverrideKey);
    _portOverride = (savedPort != null && savedPort > 0) ? savedPort : null;
  }

  // ── 设置方法 ──

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

  static Future<void> setHttpsEnabled(bool enabled) async {
    _httpsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_httpsEnabledKey, enabled);
  }

  // ── URL 构造 ──

  static String get baseUrl => _buildUrl(
        https: _httpsEnabled,
        host: host,
        port: port,
      );

  static String getShareUrl(String path) {
    final base = _buildUrl(
      https: defaultShareHttps,
      host: shareHost,
      port: sharePort,
    );
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$base/$cleanPath';
  }

  /// 构造 URL，标准端口（http:80 / https:443）自动省略
  static String _buildUrl({
    required bool https,
    required String host,
    required int port,
  }) {
    final protocol = https ? 'https' : 'http';
    final isDefaultPort = (https && port == 443) || (!https && port == 80);
    return isDefaultPort ? '$protocol://$host' : '$protocol://$host:$port';
  }
}
