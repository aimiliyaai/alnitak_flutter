import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import 'login_guard.dart';

/// 全局登录状态管理器
/// 使用单例模式 + ChangeNotifier，让各页面可以监听登录状态变化
class AuthStateManager extends ChangeNotifier {
  static final AuthStateManager _instance = AuthStateManager._internal();
  factory AuthStateManager() => _instance;
  AuthStateManager._internal();

  final AuthService _authService = AuthService();

  bool _isLoggedIn = false;
  bool _isInitialized = false;

  /// 是否已登录
  bool get isLoggedIn => _isLoggedIn;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化登录状态（应用启动时调用）
  Future<void> initialize() async {
    if (_isInitialized) return;

    _isLoggedIn = await _authService.isLoggedIn();
    _isInitialized = true;
    notifyListeners();
  }

  /// 登录成功后调用
  void onLoginSuccess() {
    _isLoggedIn = true;
    notifyListeners();
  }

  /// 退出登录后调用
  void onLogout() {
    _isLoggedIn = false;
    // 清除 LoginGuard 的用户ID缓存
    LoginGuard.clearCache();
    notifyListeners();
  }

  /// 刷新登录状态
  Future<void> refresh() async {
    final wasLoggedIn = _isLoggedIn;
    _isLoggedIn = await _authService.isLoggedIn();

    if (wasLoggedIn != _isLoggedIn) {
      if (!_isLoggedIn) {
        // 如果从登录变为未登录，清除缓存
        LoginGuard.clearCache();
      }
      notifyListeners();
    }
  }
}
