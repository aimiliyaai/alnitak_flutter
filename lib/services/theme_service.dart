import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'logger_service.dart';

/// 主题服务
/// 管理应用主题模式，支持持久化存储
class ThemeService extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  static final ThemeService _instance = ThemeService._internal();
  static final LoggerService _logger = LoggerService.instance;

  AppThemeMode _themeMode = AppThemeMode.system;

  AppThemeMode get themeMode => _themeMode;

  factory ThemeService() => _instance;

  ThemeService._internal();

  /// 初始化主题服务
  Future<void> init() async {
    await _loadThemeMode();
  }

  /// 从持久化存储加载主题模式
  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeIndex = prefs.getInt(_themeModeKey);
      if (modeIndex != null && modeIndex >= 0 && modeIndex < AppThemeMode.values.length) {
        _themeMode = AppThemeMode.values[modeIndex];
        notifyListeners();
      }
    } catch (e) {
      _logger.logWarning('[ThemeService] 加载主题模式失败: $e', tag: 'ThemeService');
    }
  }

  /// 设置主题模式
  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeModeKey, mode.index);
    } catch (e) {
      _logger.logWarning('[ThemeService] 保存主题模式失败: $e', tag: 'ThemeService');
    }
  }

  /// 获取当前应该使用的 ThemeMode
  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  /// 判断当前是否为深色模式
  bool isDarkMode(BuildContext context) {
    switch (_themeMode) {
      case AppThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
      case AppThemeMode.light:
        return false;
      case AppThemeMode.dark:
        return true;
    }
  }

  /// 获取主题模式的显示名称
  String getThemeModeName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return '跟随系统';
      case AppThemeMode.light:
        return '浅色模式';
      case AppThemeMode.dark:
        return '深色模式';
    }
  }

  /// 获取主题模式的图标
  IconData getThemeModeIcon(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return Icons.brightness_auto;
      case AppThemeMode.light:
        return Icons.light_mode;
      case AppThemeMode.dark:
        return Icons.dark_mode;
    }
  }
}
