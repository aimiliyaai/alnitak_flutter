import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/captcha_service.dart';
import '../widgets/slider_captcha_widget.dart';
import 'register_page.dart';

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
        if (mounted) {
          _showMessage('登录成功');
          Navigator.of(context).pop(true); // 返回 true 表示登录成功
        }
      } else {
        _showMessage('登录失败，请检查邮箱和密码');
      }
    } catch (e) {
      if (e.toString().contains('需要人机验证')) {
        // 显示人机验证对话框
        if (mounted) {
          setState(() => _isLoading = false);
          await _showCaptchaDialog();
          // 验证成功后重试登录
          _handlePasswordLogin();
        }
        return;
      } else {
        _showMessage('登录失败：${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 显示人机验证对话框
  Future<void> _showCaptchaDialog() async {
    // 生成验证码ID
    final captchaId = _captchaService.generateCaptchaId();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SliderCaptchaWidget(
        captchaId: captchaId,
        onSuccess: () {
          // 验证成功，保存captchaId
          setState(() => _captchaId = captchaId);
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
        if (mounted) {
          _showMessage('登录成功');
          Navigator.of(context).pop(true);
        }
      } else {
        _showMessage('登录失败，请检查邮箱和验证码');
      }
    } catch (e) {
      _showMessage('登录失败：${e.toString()}');
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
        title: const Text('登录'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Tab 切换
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: Theme.of(context).primaryColor,
                unselectedLabelColor: Colors.grey[600],
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
          const SizedBox(height: 30),

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
                onPressed: () {
                  // TODO: 发送验证码
                  _showMessage('验证码发送功能待实现');
                },
                child: const Text('获取验证码'),
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
