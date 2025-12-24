import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/captcha_service.dart';
import '../widgets/slider_captcha_widget.dart';
import '../utils/auth_state_manager.dart';
import '../utils/error_handler.dart';
import 'register_page.dart';
import 'reset_password_page.dart';

/// 登录页面
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final CaptchaService _captchaService = CaptchaService();

  // Tab 控制器
  late TabController _tabController;

  // 验证码ID
  String? _captchaId;

  // 密码登录
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // 验证码登录
  final TextEditingController _emailCodeController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSendingCode = false;
  int _countdown = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailCodeController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// 密码登录
  Future<void> _handlePasswordLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('请输入邮箱和密码');
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage('请输入有效的邮箱地址');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _authService.login(
        email: email,
        password: password,
        captchaId: _captchaId,
      );

      if (response != null) {
        // 通知全局登录状态变化
        AuthStateManager().onLoginSuccess();
        if (mounted) {
          _showMessage('登录成功');
          Navigator.of(context).pop(true); // 返回 true 表示登录成功
        }
      } else {
        _showMessage('登录失败，请检查邮箱和密码');
      }
    } on CaptchaRequiredException catch (e) {
      // 捕获需要人机验证异常，使用服务端返回的 captchaId
      if (mounted) {
        setState(() => _isLoading = false);
        await _showCaptchaDialog(e.captchaId);
        // 验证成功后重试登录
        _handlePasswordLogin();
      }
      return;
    } catch (e) {
      _showMessage(ErrorHandler.getErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 显示人机验证对话框
  /// [serverCaptchaId] 服务端返回的验证码ID
  Future<void> _showCaptchaDialog(String serverCaptchaId) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SliderCaptchaWidget(
        captchaId: serverCaptchaId,
        onSuccess: () {
          // 验证成功，保存captchaId
          setState(() => _captchaId = serverCaptchaId);
        },
        onCancel: () {
          // 取消验证
          setState(() => _captchaId = null);
        },
      ),
    );
  }

  /// 验证码登录
  Future<void> _handleEmailLogin() async {
    final email = _emailCodeController.text.trim();
    final code = _codeController.text.trim();

    if (email.isEmpty || code.isEmpty) {
      _showMessage('请输入邮箱和验证码');
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage('请输入有效的邮箱地址');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _authService.loginWithEmail(
        email: email,
        code: code,
      );

      if (response != null) {
        // 通知全局登录状态变化
        AuthStateManager().onLoginSuccess();
        if (mounted) {
          _showMessage('登录成功');
          Navigator.of(context).pop(true);
        }
      } else {
        _showMessage('登录失败，请检查邮箱和验证码');
      }
    } catch (e) {
      _showMessage(ErrorHandler.getErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 验证码登录用的 captchaId
  String? _emailCodeCaptchaId;

  /// 发送邮箱验证码（验证码登录用）
  Future<void> _sendEmailCode() async {
    final email = _emailCodeController.text.trim();

    if (email.isEmpty) {
      _showMessage('请先输入邮箱');
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage('请输入有效的邮箱地址');
      return;
    }

    if (_countdown > 0) return;

    setState(() => _isSendingCode = true);

    try {
      // 发送验证码（首次不带 captchaId，服务端决定是否需要验证）
      final success = await _captchaService.sendEmailCode(
        email: email,
        captchaId: _emailCodeCaptchaId,
      );

      if (success) {
        _showMessage('验证码已发送，请查收邮箱');
        setState(() => _countdown = 60);
        _startCountdown();
        // 成功后清除 captchaId
        _emailCodeCaptchaId = null;
      } else {
        _showMessage('验证码发送失败，请重试');
      }
    } on SendCodeCaptchaRequiredException catch (e) {
      // 需要人机验证，使用服务端返回的 captchaId
      if (mounted) {
        setState(() => _isSendingCode = false);
        await _showCaptchaDialogForCode(e.captchaId);
        // 验证成功后重试发送
        if (_emailCodeCaptchaId != null) {
          _sendEmailCode();
        }
      }
      return;
    } catch (e) {
      _showMessage(ErrorHandler.getErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isSendingCode = false);
      }
    }
  }

  /// 显示人机验证对话框（发送验证码用）
  /// [serverCaptchaId] 服务端返回的验证码ID
  Future<void> _showCaptchaDialogForCode(String serverCaptchaId) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SliderCaptchaWidget(
        captchaId: serverCaptchaId,
        onSuccess: () {
          // 验证成功，保存 captchaId
          _emailCodeCaptchaId = serverCaptchaId;
        },
        onCancel: () {
          // 取消验证
          _emailCodeCaptchaId = null;
        },
      ),
    );
  }

  /// 开始倒计时
  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;

      if (_countdown > 0) {
        setState(() => _countdown--);
        _startCountdown();
      }
    });
  }

  /// 验证邮箱格式
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  /// 显示消息
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Tab 切换
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: TabBar(
                controller: _tabController,
                labelColor: Theme.of(context).primaryColor,
                unselectedLabelColor: Theme.of(context).textTheme.bodyMedium?.color,
                indicatorColor: Theme.of(context).primaryColor,
                tabs: const [
                  Tab(text: '密码登录'),
                  Tab(text: '验证码登录'),
                ],
              ),
            ),

            // Tab 内容
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 密码登录
                  _buildPasswordLoginTab(),
                  // 验证码登录
                  _buildEmailLoginTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 密码登录 Tab
  Widget _buildPasswordLoginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),

          // 邮箱输入
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: '邮箱',
              hintText: '请输入邮箱',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 密码输入
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: '密码',
              hintText: '请输入密码',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 忘记密码链接
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ResetPasswordPage()),
                );
              },
              child: Text(
                '忘记密码？',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 登录按钮
          ElevatedButton(
            onPressed: _isLoading ? null : _handlePasswordLogin,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登录', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 20),

          // 注册链接
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('还没有账号？', style: TextStyle(color: Colors.grey[600])),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RegisterPage()),
                  );
                },
                child: const Text('立即注册'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 验证码登录 Tab
  Widget _buildEmailLoginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),

          // 邮箱输入
          TextField(
            controller: _emailCodeController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: '邮箱',
              hintText: '请输入邮箱',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 验证码输入
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '验证码',
              hintText: '请输入验证码',
              prefixIcon: const Icon(Icons.verified_user_outlined),
              suffixIcon: TextButton(
                onPressed: (_isSendingCode || _countdown > 0) ? null : _sendEmailCode,
                child: _isSendingCode
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _countdown > 0 ? '${_countdown}s' : '获取验证码',
                        style: TextStyle(
                          color: (_isSendingCode || _countdown > 0) ? Colors.grey : null,
                        ),
                      ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 30),

          // 登录按钮
          ElevatedButton(
            onPressed: _isLoading ? null : _handleEmailLogin,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登录', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 20),

          // 注册链接
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('还没有账号？', style: TextStyle(color: Colors.grey[600])),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RegisterPage()),
                  );
                },
                child: const Text('立即注册'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
