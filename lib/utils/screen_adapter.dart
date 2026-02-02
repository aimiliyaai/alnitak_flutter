import 'package:flutter/material.dart';

/// 屏幕尺寸适配工具
/// 
/// 提供统一的屏幕参数获取和响应式布局计算
/// 支持：
/// - 不同屏幕尺寸（手机、平板）
/// - 不同宽高比（普通屏、全面屏、超长屏）
/// - 异形屏幕（刘海屏、挖孔屏）
/// - 屏幕方向（竖屏、横屏）
/// - 折叠屏设备
class ScreenAdapter {
  static final ScreenAdapter _instance = ScreenAdapter._internal();
  factory ScreenAdapter() => _instance;
  ScreenAdapter._internal();

  /// 当前屏幕数据
  MediaQueryData? _screenData;

  /// 初始化（应在 app 启动时调用）
  void init(BuildContext context) {
    _screenData = MediaQuery.of(context);
  }

  /// 更新屏幕数据（用于方向变化等）
  void update(BuildContext context) {
    _screenData = MediaQuery.of(context);
  }

  /// 获取屏幕数据
  MediaQueryData get screenData {
    assert(_screenData != null, 'ScreenAdapter 尚未初始化，请先调用 init()');
    return _screenData!;
  }

  /// 屏幕宽度
  double get width => screenData.size.width;

  /// 屏幕高度
  double get height => screenData.size.height;

  /// 屏幕宽高比
  double get aspectRatio => width / height;

  /// 状态栏高度
  double get statusBarHeight => screenData.padding.top;

  /// 底部安全区高度
  double get bottomSafeArea => screenData.padding.bottom;

  /// 顶部安全区高度（包括刘海屏）
  double get topSafeArea => screenData.padding.top;

  /// 设备像素比
  double get pixelRatio => screenData.devicePixelRatio;

  /// 是否为竖屏
  bool get isPortrait => screenData.orientation == Orientation.portrait;

  /// 是否为横屏
  bool get isLandscape => screenData.orientation == Orientation.landscape;

  /// 是否为平板（宽度 > 600dp）
  bool get isTablet => width >= 600;

  /// 是否为桌面设备（宽度 > 900dp）
  bool get isDesktop => width >= 900;

  /// 是否为全面屏（宽高比 >= 1.78，即 16:9 或更高）
  bool get isFullscreen => aspectRatio >= 1.78;

  /// 是否为超长屏（宽高比 >= 1.9，即 18:9 或更高）
  bool get isUltraLongScreen => aspectRatio >= 1.9;

  /// 是否为折叠屏
  bool get isFoldable => isTablet && (height / width) < 1.3;

  /// 是否有刘海屏或挖孔屏
  bool get hasNotch => statusBarHeight > 24;

  /// 最小边（取宽高较小值）
  double get minSide => width < height ? width : height;

  /// 最大边（取宽高较大值）
  double get maxSide => width > height ? width : height;

  /// ========== 尺寸适配 ==========

  /// 根据设计稿宽度适配尺寸
  /// [designWidth] 设计稿宽度（默认 375）
  /// [scaleFactor] 缩放因子
  double adaptWidth(double value, [double designWidth = 375]) {
    return value * (width / designWidth);
  }

  /// 根据设计稿高度适配尺寸
  /// [designHeight] 设计稿高度（默认 812）
  double adaptHeight(double value, [double designHeight = 812]) {
    return value * (height / designHeight);
  }

  /// 适配字体大小
  double adaptFont(double value, [double designWidth = 375]) {
    final scaleFactor = width / designWidth;
    // 限制缩放范围，避免字体过大或过小
    final clampedScale = scaleFactor.clamp(0.8, 1.3);
    return value * clampedScale;
  }

  /// ========== 响应式断点 ==========

  /// 断点宽度
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  /// 当前设备类型
  DeviceType get deviceType {
    if (width >= desktopBreakpoint) return DeviceType.desktop;
    if (width >= tabletBreakpoint) return DeviceType.tablet;
    return DeviceType.mobile;
  }

  /// ========== 布局计算 ==========

  /// 计算 Grid 列数
  int gridColumnCount([int defaultCount = 2]) {
    if (isDesktop) return 5;
    if (isTablet) return 4;
    if (width >= 400) return 3;
    return defaultCount;
  }

  /// 计算卡片宽度
  double cardWidth([double defaultWidth = 160]) {
    final columns = gridColumnCount();
    final spacing = 16.0;
    final totalSpacing = spacing * (columns + 1);
    final availableWidth = width - totalSpacing;
    return (availableWidth / columns).floorToDouble();
  }

  /// 计算内容区域最大宽度
  double get maxContentWidth {
    if (isDesktop) return 1200;
    if (isTablet) return 800;
    return width;
  }

  /// 计算边距
  double get horizontalPadding {
    if (isDesktop) return 48;
    if (isTablet) return 32;
    if (width > 400) return 16;
    return 12;
  }

  /// 计算垂直边距
  double get verticalPadding {
    if (isTablet) return 24;
    return 16;
  }

  /// ========== 视频播放器适配 ==========

  /// 计算视频播放器宽度（考虑安全区）
  double get videoPlayerWidth => width;

  /// 计算视频播放器最大高度（考虑状态栏和底部安全区）
  double get videoPlayerMaxHeight => height - topSafeArea - bottomSafeArea;

  /// 根据宽高比计算视频高度
  double calculateVideoHeight(double videoAspectRatio) {
    final height = videoPlayerWidth / videoAspectRatio;
    return height > videoPlayerMaxHeight ? videoPlayerMaxHeight : height;
  }

  /// ========== 工具方法 ==========

  /// dp 转 px
  double dpToPx(double dp) => dp * pixelRatio;

  /// px 转 dp
  double pxToDp(double px) => px / pixelRatio;

  /// 格式化尺寸为可读字符串
  String formatSize(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }
}

/// 设备类型枚举
enum DeviceType {
  mobile,
  tablet,
  desktop,
}

/// 全局屏幕适配器实例
final ScreenAdapter screenAdapter = ScreenAdapter();
