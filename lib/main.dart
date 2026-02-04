import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'pages/main_page.dart';
import 'pages/settings_page.dart';
import 'theme/app_theme.dart';
import 'services/theme_service.dart';
import 'services/logger_service.dart';
import 'config/api_config.dart';
import 'utils/http_client.dart';
import 'utils/token_manager.dart';
import 'utils/auth_state_manager.dart';
import 'widgets/error_boundary.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 media_kit
  MediaKit.ensureInitialized();
  // 初始化主题服务
  await ThemeService().init();
  // 初始化 API 配置（必须在 HttpClient 之前）
  await ApiConfig.init();
  // 初始化 Token 管理器（安全存储）
  await TokenManager().initialize();
  // 初始化 HTTP 客户端
  await HttpClient().init();
  // 初始化登录状态管理器
  await AuthStateManager().initialize();
  // 确保屏幕尺寸可用
  await ScreenUtil.ensureScreenSize();
  LoggerService.instance.logInfo('API 基础地址: ${ApiConfig.baseUrl}', tag: 'App');
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ThemeService _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    // 监听主题变化
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  Widget _defaultErrorWidget(BuildContext context, Object error) {
    return Material(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red[400],
              ),
              const SizedBox(height: 16),
              Text(
                '出了点问题',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const MainPage()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.home),
                label: const Text('返回首页'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812), // 设计稿尺寸（iPhone X 基准）
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'Alnitak Flutter',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: _themeService.flutterThemeMode,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          locale: const Locale('zh', 'CN'),
          home: ErrorBoundary(
            child: child!,
            errorBuilder: (context, error, stack) => _defaultErrorWidget(context, error),
          ),
          routes: {
            '/settings': (context) => const SettingsPage(),
          },
        );
      },
      child: const MainPage(),
    );
  }
}
