import 'dart:async';
import 'package:flutter/material.dart';

/// 播放器控制器可见性状态
enum ControllerVisibility {
  visible,        // 完全可见
  invisible,      // 完全隐藏
  progressOnly,   // 仅显示进度条
}

/// 播放器控制器状态管理
/// 管理控制器的显示/隐藏逻辑，包括自动隐藏、手势控制等
class PlayerControllerState extends ChangeNotifier {
  ControllerVisibility _visibility = ControllerVisibility.visible;
  Timer? _autoHideTimer;
  bool _alwaysOn = false; // 是否始终显示（如打开菜单时）

  /// 自动隐藏延迟时间（秒）
  static const int autoHideDuration = 3;

  ControllerVisibility get visibility => _visibility;
  bool get isVisible => _visibility == ControllerVisibility.visible;
  bool get isInvisible => _visibility == ControllerVisibility.invisible;
  bool get isProgressOnly => _visibility == ControllerVisibility.progressOnly;
  bool get alwaysOn => _alwaysOn;

  /// 切换控制器显示状态
  void toggleVisibility() {
    if (_visibility == ControllerVisibility.visible) {
      hide();
    } else {
      show();
    }
  }

  /// 显示控制器（并启动自动隐藏计时器）
  void show({bool startAutoHide = true}) {
    _visibility = ControllerVisibility.visible;
    notifyListeners();

    if (startAutoHide && !_alwaysOn) {
      _resetAutoHideTimer();
    }
  }

  /// 隐藏控制器
  void hide() {
    if (_alwaysOn) return;

    _visibility = ControllerVisibility.invisible;
    _cancelAutoHideTimer();
    notifyListeners();
  }

  /// 仅显示进度条
  void showProgressOnly() {
    if (_alwaysOn) return;

    _visibility = ControllerVisibility.progressOnly;
    _cancelAutoHideTimer();
    notifyListeners();
  }

  /// 设置始终显示（如打开侧边栏时）
  void setAlwaysOn(bool value) {
    _alwaysOn = value;
    if (value) {
      _cancelAutoHideTimer();
      if (!isVisible) {
        show(startAutoHide: false);
      }
    } else {
      _resetAutoHideTimer();
    }
  }

  /// 重置自动隐藏计时器
  void _resetAutoHideTimer() {
    _cancelAutoHideTimer();
    if (!_alwaysOn) {
      _autoHideTimer = Timer(
        const Duration(seconds: autoHideDuration),
        () {
          if (!_alwaysOn) {
            hide();
          }
        },
      );
    }
  }

  /// 取消自动隐藏计时器
  void _cancelAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  /// 用户交互时调用（重置计时器）
  void onUserInteraction() {
    if (isVisible && !_alwaysOn) {
      _resetAutoHideTimer();
    }
  }

  @override
  void dispose() {
    _cancelAutoHideTimer();
    super.dispose();
  }
}
