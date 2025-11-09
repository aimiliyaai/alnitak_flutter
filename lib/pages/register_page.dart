import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/captcha_service.dart';
import '../widgets/slider_captcha_widget.dart';

/// 注册页面
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final AuthService _authService = AuthService();
  final CaptchaService _captchaService = CaptchaService();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _isLoading = false;
  bool _isSendingCode = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  int _countdown = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// 显示人机验证对话框
  Future<String?> _showCaptchaDialog() async {
    final captchaId = _captchaService.generateCaptchaId();
    String? result;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SliderCaptchaWidget(
        captchaId: captchaId,
        onSuccess: () {
          result = captchaId;
        },
      ),
    );

    return result;
  }

  /// 发送邮箱验证码
  Future<void> _sendEmailCode() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showMessage('请先输入邮箱');
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage('请输入有效的邮箱地址');
      return;
    }

    // 如果正在倒计时，不允许再次发送
    if (_countdown > 0) {
      return;
    }

    setState(() => _isSendingCode = true);

    try {
      // 显示人机验证
      final captchaId = await _showCaptchaDialog();

      if (captchaId == null) {
        setState(() => _isSendingCode = false);
        return;
      }

      // 发送验证码
      final success = await _captchaService.sendEmailCode(
        email: email,
        captchaId: captchaId,
      );

      if (success) {
        _showMessage('验证码已发送，请查收邮箱');
        // 开始倒计时
        setState(() => _countdown = 60);
        _startCountdown();
      } else {
        _showMessage('验证码发送失败，请重试');
      }
    } catch (e) {
      _showMessage('发送失败：${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isSendingCode = false);
      }
    }
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

  /// 处理注册
  Future<void> _handleRegister() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final code = _codeController.text.trim();

    // 验证输入
    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty || code.isEmpty) {
      _showMessage('请填写所有字段');
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage('请输入有效的邮箱地址');
      return;
    }

    if (password.length < 6) {
      _showMessage('密码长度至少为 6 位');
      return;
    }

    if (password != confirmPassword) {
      _showMessage('两次输入的密码不一致');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await _authService.register(
        email: email,
        password: password,
        code: code,
      );

      if (success) {
        if (mounted) {
          _showMessage('注册成功！请登录');
          Navigator.of(context).pop(); // 返回登录页面
        }
      } else {
        _showMessage('注册失败，请检查验证码是否正确');
      }
    } catch (e) {
      _showMessage('注册失败：${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
        title: const Text('注册'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
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
                  hintText: '请输入密码（至少 6 位）',
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
              const SizedBox(height: 20),

              // 确认密码输入
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: '确认密码',
                  hintText: '请再次输入密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                    },
                  ),
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
                  hintText: '请输入邮箱验证码',
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

              // 注册按钮
              ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
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
                    : const Text('注册', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 20),

              // 返回登录链接
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('已有账号？', style: TextStyle(color: Colors.grey[600])),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('返回登录'),
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
