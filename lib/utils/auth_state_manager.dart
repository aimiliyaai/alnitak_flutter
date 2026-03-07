import 'package:flutter/foundation.dart';
import 'token_manager.dart';
import 'login_guard.dart';

/// 全局登录状态管理器
///
/// 监听 TokenManager 的状态变化，自动更新登录状态
/// 当 Token 过期时，自动触发退出登录流程
class AuthStateManager extends ChangeNotifier {
  static final AuthStateManager _instance = AuthStateManager._internal();
  factory AuthStateManager() => _instance;
  AuthStateManager._internal() {
    // 监听 TokenManager 状态变化
    _tokenManager.addListener(_onTokenManagerChanged);
    // 注册 Token 过期回调
    _tokenManager.registerTokenExpiredCallback(_onTokenExpired);
  }

  final TokenManager _tokenManager = TokenManager();

  bool _isInitialized = false;

  /// 是否已登录（直接从 TokenManager 获取）
  bool get isLoggedIn => _tokenManager.isLoggedIn;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化登录状态（应用启动时调用）
  Future<void> initialize() async {
    if (_isInitialized) return;

    // 先初始化 TokenManager
    await _tokenManager.initialize();
    _isInitialized = true;
    notifyListeners();
  }

  /// TokenManager 状态变化回调
  void _onTokenManagerChanged() {
    notifyListeners();
  }

  /// Token 过期回调（自动退出登录）
  void _onTokenExpired() {
    if (kDebugMode) {
    }
    // 清除 LoginGuard 的用户ID缓存
    LoginGuard.clearCache();
    notifyListeners();
  }

  /// 登录成功后调用（通知监听者）
  void onLoginSuccess() {
    notifyListeners();
  }

  /// 退出登录后调用
  void onLogout() {
    // 清除 LoginGuard 的用户ID缓存
    LoginGuard.clearCache();
    notifyListeners();
  }

  /// 刷新登录状态（强制从 TokenManager 同步）
  Future<void> refresh() async {
    if (!_tokenManager.isInitialized) {
      await _tokenManager.initialize();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _tokenManager.removeListener(_onTokenManagerChanged);
    super.dispose();
  }
}
