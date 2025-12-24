import 'package:flutter/material.dart';

/// 应用颜色定义
/// 统一管理所有颜色，方便主题切换和维护
class AppColors {
  AppColors._();

  // ==================== 品牌色 ====================
  /// 主色调
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryLight = Color(0xFF64B5F6);
  static const Color primaryDark = Color(0xFF1976D2);

  /// 强调色
  static const Color accent = Color(0xFF03A9F4);

  // ==================== 浅色主题 ====================
  static const LightColors light = LightColors();

  // ==================== 深色主题 ====================
  static const DarkColors dark = DarkColors();
}

/// 浅色主题颜色
class LightColors {
  const LightColors();

  // 背景色
  Color get background => const Color(0xFFF5F5F5);
  Color get surface => Colors.white;
  Color get surfaceVariant => const Color(0xFFFAFAFA);
  Color get card => Colors.white;

  // 文字颜色
  Color get textPrimary => const Color(0xFF212121);
  Color get textSecondary => const Color(0xFF757575);
  Color get textTertiary => const Color(0xFF9E9E9E);
  Color get textDisabled => const Color(0xFFBDBDBD);

  // 图标颜色
  Color get iconPrimary => const Color(0xFF616161);
  Color get iconSecondary => const Color(0xFF9E9E9E);

  // 分割线
  Color get divider => const Color(0xFFE0E0E0);
  Color get dividerLight => const Color(0xFFF0F0F0);

  // 边框
  Color get border => const Color(0xFFE0E0E0);
  Color get borderLight => const Color(0xFFEEEEEE);

  // AppBar
  Color get appBarBackground => Colors.white;
  Color get appBarForeground => const Color(0xFF212121);

  // 底部导航栏
  Color get bottomNavBackground => Colors.white;
  Color get bottomNavSelected => AppColors.primary;
  Color get bottomNavUnselected => const Color(0xFF9E9E9E);

  // 输入框
  Color get inputBackground => const Color(0xFFF5F5F5);
  Color get inputBorder => const Color(0xFFE0E0E0);
  Color get inputFocusBorder => AppColors.primary;

  // 按钮
  Color get buttonDisabled => const Color(0xFFE0E0E0);
  Color get buttonTextDisabled => const Color(0xFF9E9E9E);

  // 列表项
  Color get listTileBackground => Colors.white;
  Color get listTileHover => const Color(0xFFF5F5F5);

  // 状态色
  Color get success => const Color(0xFF4CAF50);
  Color get warning => const Color(0xFFFF9800);
  Color get error => const Color(0xFFF44336);
  Color get info => const Color(0xFF2196F3);

  // 遮罩
  Color get overlay => Colors.black.withValues(alpha: 0.5);
  Color get overlayLight => Colors.black.withValues(alpha: 0.3);

  // 阴影
  Color get shadow => Colors.black.withValues(alpha: 0.1);

  // 标签/徽章
  Color get tagBackground => const Color(0xFFF0F0F0);
  Color get tagText => const Color(0xFF666666);

  // 进度条
  Color get progressBackground => const Color(0xFFE0E0E0);
  Color get progressForeground => AppColors.primary;

  // 开关
  Color get switchTrackActive => AppColors.primary.withValues(alpha: 0.5);
  Color get switchTrackInactive => const Color(0xFFE0E0E0);

  // 骨架屏
  Color get skeleton => const Color(0xFFE0E0E0);
  Color get skeletonHighlight => const Color(0xFFF5F5F5);
}

/// 深色主题颜色
class DarkColors {
  const DarkColors();

  // 背景色 - 采用分层设计，增加层次感
  Color get background => const Color(0xFF121212);
  Color get surface => const Color(0xFF1E1E1E);
  Color get surfaceVariant => const Color(0xFF2C2C2C);
  Color get card => const Color(0xFF1E1E1E);

  // 文字颜色 - 使用不同透明度的白色，增加可读性
  Color get textPrimary => const Color(0xFFE0E0E0);
  Color get textSecondary => const Color(0xFFB0B0B0);
  Color get textTertiary => const Color(0xFF808080);
  Color get textDisabled => const Color(0xFF606060);

  // 图标颜色
  Color get iconPrimary => const Color(0xFFB0B0B0);
  Color get iconSecondary => const Color(0xFF808080);

  // 分割线 - 深色模式下使用更深的分割线
  Color get divider => const Color(0xFF2C2C2C);
  Color get dividerLight => const Color(0xFF242424);

  // 边框
  Color get border => const Color(0xFF3C3C3C);
  Color get borderLight => const Color(0xFF2C2C2C);

  // AppBar - 深色模式下稍微提亮
  Color get appBarBackground => const Color(0xFF1E1E1E);
  Color get appBarForeground => const Color(0xFFE0E0E0);

  // 底部导航栏
  Color get bottomNavBackground => const Color(0xFF1E1E1E);
  Color get bottomNavSelected => AppColors.primaryLight;
  Color get bottomNavUnselected => const Color(0xFF808080);

  // 输入框
  Color get inputBackground => const Color(0xFF2C2C2C);
  Color get inputBorder => const Color(0xFF3C3C3C);
  Color get inputFocusBorder => AppColors.primaryLight;

  // 按钮
  Color get buttonDisabled => const Color(0xFF3C3C3C);
  Color get buttonTextDisabled => const Color(0xFF606060);

  // 列表项
  Color get listTileBackground => const Color(0xFF1E1E1E);
  Color get listTileHover => const Color(0xFF2C2C2C);

  // 状态色 - 深色模式下稍微降低饱和度
  Color get success => const Color(0xFF66BB6A);
  Color get warning => const Color(0xFFFFB74D);
  Color get error => const Color(0xFFEF5350);
  Color get info => const Color(0xFF42A5F5);

  // 遮罩
  Color get overlay => Colors.black.withValues(alpha: 0.7);
  Color get overlayLight => Colors.black.withValues(alpha: 0.5);

  // 阴影 - 深色模式下阴影效果弱化
  Color get shadow => Colors.black.withValues(alpha: 0.3);

  // 标签/徽章
  Color get tagBackground => const Color(0xFF2C2C2C);
  Color get tagText => const Color(0xFFB0B0B0);

  // 进度条
  Color get progressBackground => const Color(0xFF3C3C3C);
  Color get progressForeground => AppColors.primaryLight;

  // 开关
  Color get switchTrackActive => AppColors.primaryLight.withValues(alpha: 0.5);
  Color get switchTrackInactive => const Color(0xFF3C3C3C);

  // 骨架屏
  Color get skeleton => const Color(0xFF2C2C2C);
  Color get skeletonHighlight => const Color(0xFF3C3C3C);
}
