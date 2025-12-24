import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

/// 主题模式
enum AppThemeMode {
  system, // 跟随系统
  light,  // 浅色
  dark,   // 深色
}

/// 应用主题配置
class AppTheme {
  AppTheme._();

  /// 浅色主题
  static ThemeData get lightTheme {
    final colors = AppColors.light;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // 颜色方案
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryLight,
        secondary: AppColors.accent,
        surface: colors.surface,
        error: colors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: colors.textPrimary,
        onError: Colors.white,
      ),

      // 脚手架背景色
      scaffoldBackgroundColor: colors.background,

      // AppBar 主题
      appBarTheme: AppBarTheme(
        backgroundColor: colors.appBarBackground,
        foregroundColor: colors.appBarForeground,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: colors.appBarForeground,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: colors.appBarForeground,
          size: 24,
        ),
      ),

      // 底部导航栏主题
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.bottomNavBackground,
        selectedItemColor: colors.bottomNavSelected,
        unselectedItemColor: colors.bottomNavUnselected,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),

      // 卡片主题
      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),

      // 分割线主题
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 0.5,
        space: 0,
      ),

      // 列表项主题
      listTileTheme: ListTileThemeData(
        tileColor: colors.listTileBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 15,
        ),
        subtitleTextStyle: TextStyle(
          color: colors.textSecondary,
          fontSize: 13,
        ),
      ),

      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.inputFocusBorder, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(color: colors.textTertiary),
      ),

      // 按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          disabledBackgroundColor: colors.buttonDisabled,
          disabledForegroundColor: colors.buttonTextDisabled,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),

      // 开关主题
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.switchTrackActive;
          }
          return colors.switchTrackInactive;
        }),
      ),

      // 进度条主题
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: colors.progressBackground,
      ),

      // 对话框主题
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: colors.textSecondary,
          fontSize: 14,
        ),
      ),

      // BottomSheet 主题
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        elevation: 8,
      ),

      // SnackBar 主题
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.textPrimary,
        contentTextStyle: TextStyle(color: colors.surface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // 文字主题
      textTheme: TextTheme(
        displayLarge: TextStyle(color: colors.textPrimary),
        displayMedium: TextStyle(color: colors.textPrimary),
        displaySmall: TextStyle(color: colors.textPrimary),
        headlineLarge: TextStyle(color: colors.textPrimary),
        headlineMedium: TextStyle(color: colors.textPrimary),
        headlineSmall: TextStyle(color: colors.textPrimary),
        titleLarge: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: colors.textPrimary),
        bodyMedium: TextStyle(color: colors.textSecondary),
        bodySmall: TextStyle(color: colors.textTertiary),
        labelLarge: TextStyle(color: colors.textPrimary),
        labelMedium: TextStyle(color: colors.textSecondary),
        labelSmall: TextStyle(color: colors.textTertiary),
      ),

      // 图标主题
      iconTheme: IconThemeData(
        color: colors.iconPrimary,
        size: 24,
      ),

      // 芯片主题
      chipTheme: ChipThemeData(
        backgroundColor: colors.tagBackground,
        labelStyle: TextStyle(color: colors.tagText, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // TabBar 主题
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
      ),
    );
  }

  /// 深色主题
  static ThemeData get darkTheme {
    final colors = AppColors.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // 颜色方案
      colorScheme: ColorScheme.dark(
        primary: AppColors.primaryLight,
        primaryContainer: AppColors.primaryDark,
        secondary: AppColors.accent,
        surface: colors.surface,
        error: colors.error,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: colors.textPrimary,
        onError: Colors.white,
      ),

      // 脚手架背景色
      scaffoldBackgroundColor: colors.background,

      // AppBar 主题
      appBarTheme: AppBarTheme(
        backgroundColor: colors.appBarBackground,
        foregroundColor: colors.appBarForeground,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: colors.appBarForeground,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: colors.appBarForeground,
          size: 24,
        ),
      ),

      // 底部导航栏主题
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.bottomNavBackground,
        selectedItemColor: colors.bottomNavSelected,
        unselectedItemColor: colors.bottomNavUnselected,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),

      // 卡片主题
      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),

      // 分割线主题
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 0.5,
        space: 0,
      ),

      // 列表项主题
      listTileTheme: ListTileThemeData(
        tileColor: colors.listTileBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 15,
        ),
        subtitleTextStyle: TextStyle(
          color: colors.textSecondary,
          fontSize: 13,
        ),
      ),

      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.inputFocusBorder, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(color: colors.textTertiary),
      ),

      // 按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          disabledBackgroundColor: colors.buttonDisabled,
          disabledForegroundColor: colors.buttonTextDisabled,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          side: const BorderSide(color: AppColors.primaryLight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),

      // 开关主题
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryLight;
          }
          return colors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.switchTrackActive;
          }
          return colors.switchTrackInactive;
        }),
      ),

      // 进度条主题
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primaryLight,
        linearTrackColor: colors.progressBackground,
      ),

      // 对话框主题
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: colors.textSecondary,
          fontSize: 14,
        ),
      ),

      // BottomSheet 主题
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        elevation: 8,
      ),

      // SnackBar 主题
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surface,
        contentTextStyle: TextStyle(color: colors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // 文字主题
      textTheme: TextTheme(
        displayLarge: TextStyle(color: colors.textPrimary),
        displayMedium: TextStyle(color: colors.textPrimary),
        displaySmall: TextStyle(color: colors.textPrimary),
        headlineLarge: TextStyle(color: colors.textPrimary),
        headlineMedium: TextStyle(color: colors.textPrimary),
        headlineSmall: TextStyle(color: colors.textPrimary),
        titleLarge: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: colors.textPrimary),
        bodyMedium: TextStyle(color: colors.textSecondary),
        bodySmall: TextStyle(color: colors.textTertiary),
        labelLarge: TextStyle(color: colors.textPrimary),
        labelMedium: TextStyle(color: colors.textSecondary),
        labelSmall: TextStyle(color: colors.textTertiary),
      ),

      // 图标主题
      iconTheme: IconThemeData(
        color: colors.iconPrimary,
        size: 24,
      ),

      // 芯片主题
      chipTheme: ChipThemeData(
        backgroundColor: colors.tagBackground,
        labelStyle: TextStyle(color: colors.tagText, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // TabBar 主题
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primaryLight,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: AppColors.primaryLight,
        indicatorSize: TabBarIndicatorSize.label,
      ),
    );
  }
}
