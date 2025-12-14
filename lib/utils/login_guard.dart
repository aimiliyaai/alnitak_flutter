import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../pages/login_page.dart';

/// 登录守卫工具类
/// 用于统一处理需要登录才能执行的操作
class LoginGuard {
  static final AuthService _authService = AuthService();
  static final UserService _userService = UserService();

  // 缓存当前用户ID，避免频繁请求
  static int? _cachedUserId;

  /// 检查是否已登录
  static Future<bool> isLoggedIn() async {
    return await _authService.isLoggedIn();
  }

  /// 获取当前登录用户的ID
  /// 返回 null 表示未登录或获取失败
  static Future<int?> getCurrentUserId() async {
    // 如果已有缓存，直接返回
    if (_cachedUserId != null) {
      return _cachedUserId;
    }

    final isLogged = await isLoggedIn();
    if (!isLogged) {
      return null;
    }

    final userInfo = await _userService.getUserInfo();
    if (userInfo != null) {
      // UserInfo 包含 userInfo 字段（UserBaseInfo 类型），uid 在 UserBaseInfo 中
      _cachedUserId = userInfo.userInfo.uid;
      return userInfo.userInfo.uid;
    }
    return null;
  }

  /// 清除用户缓存（登出时调用）
  static void clearCache() {
    _cachedUserId = null;
  }

  /// 执行需要登录的操作
  /// 如果未登录，显示登录提示弹窗
  ///
  /// [context] BuildContext
  /// [action] 登录后要执行的操作
  /// [actionName] 操作名称，用于提示（如"点赞"、"评论"）
  ///
  /// 返回 true 表示已登录并可以执行操作，false 表示未登录
  static Future<bool> check(
    BuildContext context, {
    String actionName = '此功能',
  }) async {
    final loggedIn = await isLoggedIn();

    if (!loggedIn && context.mounted) {
      _showLoginPrompt(context, actionName);
      return false;
    }

    return true;
  }

  /// 执行需要登录的操作（带回调）
  /// 如果已登录，直接执行回调；否则显示登录提示
  static Future<void> run(
    BuildContext context, {
    required Future<void> Function() onLoggedIn,
    String actionName = '此功能',
  }) async {
    final canProceed = await check(context, actionName: actionName);
    if (canProceed) {
      await onLoggedIn();
    }
  }

  /// 显示登录提示弹窗
  static void _showLoginPrompt(BuildContext context, String actionName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _LoginPromptSheet(actionName: actionName),
    );
  }

  /// 跳转到登录页面
  static Future<bool?> navigateToLogin(BuildContext context) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginPage(),
      ),
    );
  }
}

/// 登录提示底部弹窗
class _LoginPromptSheet extends StatelessWidget {
  final String actionName;

  const _LoginPromptSheet({required this.actionName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖动条
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // 图标
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_outline,
                  size: 32,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(height: 16),

              // 标题
              Text(
                '登录后体验更多功能',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),

              // 描述
              Text(
                '$actionName需要登录账号',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),

              // 按钮
              Row(
                children: [
                  // 取消按钮
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('稍后再说'),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 登录按钮
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        final result = await LoginGuard.navigateToLogin(context);

                        // 如果登录成功，可以通过返回值通知调用方
                        if (result == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('登录成功'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('去登录'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
