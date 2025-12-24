import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 主题扩展工具
/// 方便在 Widget 中获取当前主题的颜色
extension ThemeExtensions on BuildContext {
  /// 判断当前是否为深色模式
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// 获取当前主题的颜色配置
  dynamic get colors => isDarkMode ? AppColors.dark : AppColors.light;

  /// 快捷访问浅色颜色
  LightColors get lightColors => AppColors.light;

  /// 快捷访问深色颜色
  DarkColors get darkColors => AppColors.dark;
}
