import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/captcha_service.dart';
import '../widgets/slider_captcha_widget.dart';
import '../utils/error_handler.dart';
import '../theme/theme_extensions.dart';

/// 重置密码页面（忘记密码）
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final AuthService _authService = AuthService();
  final CaptchaService _captchaService = CaptchaService();

  // 当前步骤：1=填写邮箱, 2=重置密码, 3=成功
  int _currentStep = 1;

  // 验证码ID
  String? _captchaId;

  // 步骤1：邮箱
  final TextEditingController _emailController = TextEditingController();

  // 步骤2：新密码
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

  /// 脱敏邮箱显示
  String _desensitizeEmail(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 3) {
      return email.replaceRange(0, atIndex, '***');
    }
    return '${email.substring(0, 3)}***${email.substring(atIndex)}';
  }

  /// 显示人机验证对话框（使用服务端返回的 captchaId）
  Future<void> _showCaptchaDialog(String serverCaptchaId) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SliderCaptchaWidget(
        captchaId: serverCaptchaId,
        onSuccess: () {
          _captchaId = serverCaptchaId;
        },
        onCancel: () {
          _captchaId = null;
        },
      ),
    );
  }

  /// 步骤1：验证邮箱是否存在
  Future<void> _checkEmail() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showMessage('请输入邮箱');
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage('请输入有效的邮箱地址');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 验证邮箱是否存在（首次不带 captchaId）
      final success = await _authService.resetPasswordCheck(
        email: email,
        captchaId: _captchaId,
      );

      if (success) {
        setState(() => _currentStep = 2);
        _captchaId = null; // 成功后清除
      } else {
        _showMessage('该邮箱未注册');
      }
    } on ResetPasswordCaptchaRequiredException catch (e) {
      // 需要人机验证
      if (mounted) {
        setState(() => _isLoading = false);
        await _showCaptchaDialog(e.captchaId);
        if (_captchaId != null) {
          _checkEmail(); // 验证成功后重试
        }
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

  /// 发送邮箱验证码
  Future<void> _sendEmailCode() async {
    final email = _emailController.text.trim();

    if (_countdown > 0) return;

    setState(() => _isSendingCode = true);

    try {
      // 发送验证码（首次不带 captchaId）
      final success = await _captchaService.sendEmailCode(
        email: email,
        captchaId: _captchaId,
      );

      if (success) {
        _showMessage('验证码已发送，请查收邮箱');
        setState(() => _countdown = 60);
        _startCountdown();
        _captchaId = null; // 成功后清除
      } else {
        _showMessage('验证码发送失败，请重试');
      }
    } on SendCodeCaptchaRequiredException catch (e) {
      // 需要人机验证
      if (mounted) {
        setState(() => _isSendingCode = false);
        await _showCaptchaDialog(e.captchaId);
        if (_captchaId != null) {
          _sendEmailCode(); // 验证成功后重试
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

  /// 步骤2：提交新密码
  Future<void> _submitNewPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final code = _codeController.text.trim();

    // 验证输入
    if (password.isEmpty || confirmPassword.isEmpty || code.isEmpty) {
      _showMessage('请填写所有字段');
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
      final success = await _authService.modifyPassword(
        email: email,
        password: password,
        code: code,
        captchaId: _captchaId,
      );

      if (success) {
        setState(() => _currentStep = 3);
      } else {
        _showMessage('重置密码失败，请检查验证码是否正确');
      }
    } catch (e) {
      _showMessage(ErrorHandler.getErrorMessage(e));
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
        title: const Text('重置密码'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 步骤指示器
            _buildStepIndicator(),

            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildCurrentStep(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建步骤指示器
  Widget _buildStepIndicator() {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      color: colors.card,
      child: Row(
        children: [
          _buildStepItem(1, '填写账号'),
          _buildStepLine(1),
          _buildStepItem(2, '重置密码'),
          _buildStepLine(2),
          _buildStepItem(3, '操作成功'),
        ],
      ),
    );
  }

  Widget _buildStepItem(int step, String label) {
    final colors = context.colors;
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    final isCompleted = _currentStep > step;

    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? colors.accentColor : colors.surfaceVariant,
            border: isCurrent
                ? Border.all(color: colors.accentColor, width: 2)
                : null,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '$step',
                    style: TextStyle(
                      color: isActive ? Colors.white : colors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? colors.accentColor : colors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(int afterStep) {
    final colors = context.colors;
    final isActive = _currentStep > afterStep;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 20),
        color: isActive ? colors.accentColor : colors.surfaceVariant,
      ),
    );
  }

  /// 根据当前步骤构建内容
  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      default:
        return const SizedBox();
    }
  }

  /// 步骤1：填写邮箱
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),

        // 邮箱输入
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: '邮箱',
            hintText: '请输入绑定的邮箱',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 30),

        // 验证按钮
        ElevatedButton(
          onPressed: _isLoading ? null : _checkEmail,
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
              : const Text('验证', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  /// 步骤2：重置密码
  Widget _buildStep2() {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),

        // 显示脱敏邮箱
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.email_outlined, color: colors.iconSecondary),
              const SizedBox(width: 12),
              Text(
                _desensitizeEmail(_emailController.text.trim()),
                style: TextStyle(fontSize: 16, color: colors.textPrimary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 新密码
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: '新密码',
            hintText: '请输入新密码（至少 6 位）',
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

        // 确认密码
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          decoration: InputDecoration(
            labelText: '确认密码',
            hintText: '请再次输入新密码',
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

        // 验证码
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

        // 提交按钮
        ElevatedButton(
          onPressed: _isLoading ? null : _submitNewPassword,
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
              : const Text('保存', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  /// 步骤3：成功
  Widget _buildStep3() {
    final colors = context.colors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),

        // 成功图标
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.withValues(alpha: 0.1),
          ),
          child: Icon(
            Icons.check_circle,
            size: 60,
            color: Colors.green[600],
          ),
        ),
        const SizedBox(height: 24),

        Text(
          '重置成功',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        Text(
          '已成功重置密码',
          style: TextStyle(
            fontSize: 16,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 40),

        // 返回登录按钮
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('返回登录', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}
