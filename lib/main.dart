import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'pages/main_page.dart';
import 'pages/settings_page.dart';
import 'theme/app_theme.dart';
import 'services/theme_service.dart';
import 'config/api_config.dart';
import 'utils/http_client.dart';
import 'utils/token_manager.dart';
import 'utils/auth_state_manager.dart';
import 'utils/screen_adapter.dart';

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
  // 初始化屏幕适配器（在第一个 MaterialApp 构建时）
  print('🌐 API 基础地址: ${ApiConfig.baseUrl}');
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

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        // 初始化屏幕适配器
        ScreenAdapter().init(context);
        return MaterialApp(
          title: 'Alnitak Flutter',
          debugShowCheckedModeBanner: false,
          // 使用自定义主题
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: _themeService.flutterThemeMode,
          // 添加中文本地化支持
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh', 'CN'), // 简体中文
            Locale('en', 'US'), // 英文
          ],
          locale: const Locale('zh', 'CN'), // 默认使用简体中文
          home: const MainPage(),
          routes: {
            '/settings': (context) => const SettingsPage(),
          },
        );
      },
    );
  }
}
