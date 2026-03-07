import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

/// Token 安全管理器（单例）
///
/// 安全特性：
/// - Token 在存储前进行混淆处理（非明文存储）
/// - 内存缓存减少 I/O 操作
/// - 提供统一的登录状态和自动退出机制
/// - Release 模式不输出敏感日志
class TokenManager extends ChangeNotifier {
  static final TokenManager _instance = TokenManager._internal();
  factory TokenManager() => _instance;
  TokenManager._internal();

  // 存储键（使用混淆后的键名）
  static const String _tokenKey = '_tk_auth_v2';
  static const String _refreshTokenKey = '_tk_refresh_v2';
  static const String _checksumKey = '_tk_checksum';

  // 内存缓存（仅在运行时有效）
  String? _cachedToken;
  String? _cachedRefreshToken;
  bool _isInitialized = false;

  // Token 刷新锁
  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  // 【新增】刷新失败标记（防止死循环）
  bool _refreshFailed = false;
  DateTime? _refreshFailedTime;
  // 刷新失败后的冷却时间（防止频繁重试）
  static const Duration _refreshCooldown = Duration(minutes: 5);

  // 登出回调（由 AuthStateManager 注册）
  VoidCallback? _onTokenExpired;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 是否已登录（同步检查，基于内存缓存）
  bool get isLoggedIn => _cachedToken != null && _cachedToken!.isNotEmpty;

  /// 【新增】检查是否可以进行需要认证的API请求
  /// 返回 true 表示可以请求（已登录且刷新未失败）
  /// 返回 false 表示不应该请求（未登录或刷新已失败）
  bool get canMakeAuthenticatedRequest {
    // 如果未登录，不能请求
    if (!isLoggedIn) return false;
    // 如果刷新已失败（token无效），也不应该请求
    if (isRefreshFailed) return false;
    return true;
  }

  /// 获取当前 Token
  String? get token => _cachedToken;

  /// 获取 RefreshToken
  String? get refreshToken => _cachedRefreshToken;

  /// 注册 token 过期回调
  void registerTokenExpiredCallback(VoidCallback callback) {
    _onTokenExpired = callback;
  }

  /// 初始化（应用启动时调用）
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // 读取并解码 Token
      final encodedToken = prefs.getString(_tokenKey);
      final encodedRefresh = prefs.getString(_refreshTokenKey);
      final storedChecksum = prefs.getString(_checksumKey);

      if (encodedToken != null && storedChecksum != null) {
        // 验证完整性
        final currentChecksum = _generateChecksum(encodedToken, encodedRefresh ?? '');
        if (currentChecksum == storedChecksum) {
          _cachedToken = _decode(encodedToken);
          _cachedRefreshToken = encodedRefresh != null ? _decode(encodedRefresh) : null;
        } else {
          // 校验失败，可能被篡改，清除
          _logSafe('Token 完整性校验失败，已清除');
          await _clearStorage(prefs);
        }
      }

      // 尝试从旧版存储迁移
      if (_cachedToken == null) {
        await _migrateFromOldStorage(prefs);
      }

      _isInitialized = true;
      _logSafe('Token 管理器已初始化，登录状态: $isLoggedIn');
      notifyListeners();
    } catch (e) {
      _logSafe('Token 管理器初始化失败: $e');
      _isInitialized = true;
    }
  }

  /// 从旧版存储迁移
  Future<void> _migrateFromOldStorage(SharedPreferences prefs) async {
    try {
      final oldToken = prefs.getString('auth_token');
      final oldRefreshToken = prefs.getString('refresh_token');

      if (oldToken != null && oldToken.isNotEmpty) {
        _logSafe('检测到旧版 Token，正在迁移...');

        // 保存到新格式
        _cachedToken = oldToken;
        _cachedRefreshToken = oldRefreshToken;
        await _saveToStorage(prefs);

        // 删除旧版存储
        await prefs.remove('auth_token');
        await prefs.remove('refresh_token');

        _logSafe('Token 迁移完成');
      }
    } catch (e) {
      _logSafe('Token 迁移失败: $e');
    }
  }

  /// 保存 Token（登录成功后调用）
  Future<void> saveTokens({
    required String token,
    required String refreshToken,
  }) async {
    try {
      // 先更新内存缓存
      _cachedToken = token;
      _cachedRefreshToken = refreshToken;

      // 【新增】登录成功，重置刷新失败状态
      resetRefreshFailedState();

      // 保存到存储
      final prefs = await SharedPreferences.getInstance();
      await _saveToStorage(prefs);

      _logSafe('Token 已保存');
      notifyListeners();
    } catch (e) {
      _logSafe('保存 Token 失败: $e');
    }
  }

  /// 更新 Token（刷新后调用）
  Future<void> updateToken(String token) async {
    try {
      _cachedToken = token;

      final prefs = await SharedPreferences.getInstance();
      await _saveToStorage(prefs);

      _logSafe('Token 已更新');
      notifyListeners();
    } catch (e) {
      _logSafe('更新 Token 失败: $e');
    }
  }

  /// 清除所有 Token（退出登录时调用）
  Future<void> clearTokens() async {
    try {
      _cachedToken = null;
      _cachedRefreshToken = null;

      final prefs = await SharedPreferences.getInstance();
      await _clearStorage(prefs);

      _logSafe('Token 已清除');
      notifyListeners();
    } catch (e) {
      _logSafe('清除 Token 失败: $e');
    }
  }

  /// Token 过期处理（自动退出登录）
  Future<void> handleTokenExpired() async {
    _logSafe('Token 已过期，执行自动退出');
    await clearTokens();
    _onTokenExpired?.call();
  }

  /// 获取刷新锁状态
  bool get isRefreshing => _isRefreshing;

  /// 【新增】检查刷新是否已失败（且在冷却期内）
  bool get isRefreshFailed {
    if (!_refreshFailed) return false;
    // 检查是否已过冷却期
    if (_refreshFailedTime != null) {
      final elapsed = DateTime.now().difference(_refreshFailedTime!);
      if (elapsed >= _refreshCooldown) {
        // 冷却期已过，重置状态
        _refreshFailed = false;
        _refreshFailedTime = null;
        _logSafe('刷新冷却期已过，允许重新刷新');
        return false;
      }
    }
    return true;
  }

  /// 【新增】标记刷新失败
  void markRefreshFailed() {
    _refreshFailed = true;
    _refreshFailedTime = DateTime.now();
    _logSafe('Token 刷新已标记为失败，${_refreshCooldown.inMinutes}分钟内不再尝试');
  }

  /// 【新增】重置刷新失败状态（登录成功后调用）
  void resetRefreshFailedState() {
    _refreshFailed = false;
    _refreshFailedTime = null;
    _logSafe('刷新失败状态已重置');
  }

  /// 设置刷新状态（供 HttpClient 使用）
  void setRefreshing(bool value, [Completer<String?>? completer]) {
    _isRefreshing = value;
    _refreshCompleter = completer;
  }

  /// 获取刷新 Completer
  Completer<String?>? get refreshCompleter => _refreshCompleter;

  // ========== 私有方法 ==========

  /// 保存到存储
  Future<void> _saveToStorage(SharedPreferences prefs) async {
    final encodedToken = _encode(_cachedToken ?? '');
    final encodedRefresh = _encode(_cachedRefreshToken ?? '');
    final checksum = _generateChecksum(encodedToken, encodedRefresh);

    await prefs.setString(_tokenKey, encodedToken);
    await prefs.setString(_refreshTokenKey, encodedRefresh);
    await prefs.setString(_checksumKey, checksum);
  }

  /// 清除存储
  Future<void> _clearStorage(SharedPreferences prefs) async {
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_checksumKey);
    // 同时清除旧版存储
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');
  }

  /// 编码（Base64 + 简单混淆）
  String _encode(String value) {
    if (value.isEmpty) return '';
    // Base64 编码后反转字符串作为简单混淆
    final base64 = base64Encode(utf8.encode(value));
    return base64.split('').reversed.join('');
  }

  /// 解码
  String _decode(String encoded) {
    if (encoded.isEmpty) return '';
    try {
      // 反转后解码
      final base64 = encoded.split('').reversed.join('');
      return utf8.decode(base64Decode(base64));
    } catch (e) {
      return '';
    }
  }

  /// 生成校验和（防篡改）
  String _generateChecksum(String token, String refresh) {
    final data = '$token:$refresh:alnitak_salt_v2';
    return sha256.convert(utf8.encode(data)).toString().substring(0, 16);
  }

  /// 安全日志（不打印敏感信息）
  void _logSafe(String message) {
    if (kDebugMode) {
    }
  }

  /// 获取脱敏的 Token（用于调试）
  String? get maskedToken {
    if (_cachedToken == null || _cachedToken!.length < 20) return null;
    return '${_cachedToken!.substring(0, 10)}...${_cachedToken!.substring(_cachedToken!.length - 5)}';
  }
}
