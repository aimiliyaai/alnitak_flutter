/// 播放循环模式
enum LoopMode {
  /// 关闭循环
  off,

  /// 单集循环
  on,
}

extension LoopModeExtension on LoopMode {
  /// 获取显示名称
  String get displayName {
    switch (this) {
      case LoopMode.off:
        return '关闭循环';
      case LoopMode.on:
        return '单集循环';
    }
  }

  /// 获取图标
  String get icon {
    switch (this) {
      case LoopMode.off:
        return '🔀';
      case LoopMode.on:
        return '🔂';
    }
  }

  /// 从保存的值恢复（默认关闭循环）
  static LoopMode fromString(String? value) {
    switch (value) {
      case 'on':
      case 'single':
        return LoopMode.on;
      case 'off':
      default:
        return LoopMode.off; // 默认关闭循环
    }
  }

  /// 转换为保存的值
  String toSavedString() {
    switch (this) {
      case LoopMode.off:
        return 'off';
      case LoopMode.on:
        return 'on';
    }
  }

  /// 切换循环模式
  LoopMode toggle() {
    switch (this) {
      case LoopMode.off:
        return LoopMode.on;
      case LoopMode.on:
        return LoopMode.off;
    }
  }
}
