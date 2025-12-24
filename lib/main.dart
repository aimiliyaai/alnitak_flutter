import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'pages/main_page.dart';
import 'pages/settings_page.dart';
import 'theme/app_theme.dart';
import 'services/theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 media_kit
  MediaKit.ensureInitialized();
  // 初始化主题服务
  await ThemeService().init();
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
  }
}
