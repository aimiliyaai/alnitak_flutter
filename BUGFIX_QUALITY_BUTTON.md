# 修复：清晰度切换后按钮状态不更新

## 问题描述

播放器切换清晰度后，清晰度按钮上显示的清晰度文本不会立即更新，需要切换全屏才能看到更新后的清晰度。

## 问题原因

播放器使用了 `media_kit` 库提供的 `MaterialVideoControlsTheme` 和 `MaterialCustomButton` 组件。这些组件在 `build` 方法中被创建，清晰度按钮的显示文本直接使用了状态变量 `_currentQuality`。

虽然在 `changeQuality` 方法中通过 `setState` 更新了 `_currentQuality`，但由于 `MaterialCustomButton` 是静态创建的（在 `bottomButtonBar` 数组中），它不会自动响应父 widget 的状态变化而重新构建。

## 解决方案

使用 `ValueNotifier` + `ValueListenableBuilder` 模式来管理清晰度状态，确保清晰度按钮能够响应状态变化并重新构建。

### 实施步骤

#### 1. 添加 ValueNotifier

在 `_MediaPlayerWidgetState` 类中添加清晰度状态的 ValueNotifier：

```dart
// 使用 ValueNotifier 来管理清晰度状态，确保UI能够响应变化
final ValueNotifier<String?> _qualityNotifier = ValueNotifier<String?>(null);
```

#### 2. 同步状态更新

在所有更新 `_currentQuality` 的地方，同时更新 `_qualityNotifier`：

```dart
// 初始化时
_currentQuality = HlsService.getDefaultQuality(_availableQualities);
_qualityNotifier.value = _currentQuality; // 同步到 notifier

// 切换清晰度时
setState(() {
  _currentQuality = quality;
  _qualityNotifier.value = quality; // 同步到 notifier
  _isSwitchingQuality = false;
});
```

#### 3. 使用 ValueListenableBuilder 包装清晰度按钮

在 `MaterialVideoControlsTheme` 的 `bottomButtonBar` 中，使用 `ValueListenableBuilder` 监听清晰度变化：

```dart
// 清晰度切换按钮 - 使用 ValueListenableBuilder 监听状态变化
if (_availableQualities.length > 1)
  ValueListenableBuilder<String?>(
    valueListenable: _qualityNotifier,
    builder: (context, currentQuality, child) {
      return MaterialCustomButton(
        icon: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white60, width: 0.8),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            currentQuality != null
                ? getQualityDisplayName(currentQuality)
                : '画质',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
            ),
          ),
        ),
        onPressed: () => _showQualityMenu(context),
      );
    },
  ),
```

#### 4. 清理资源

在 `dispose` 方法中销毁 ValueNotifier：

```dart
@override
void dispose() {
  print('📹 [dispose] 销毁播放器');
  _player.dispose();
  _qualityNotifier.dispose(); // 销毁 ValueNotifier
  // ...
  super.dispose();
}
```

## 修改的文件

- `lib/pages/video/widgets/media_player_widget.dart`
  - 第 58 行：添加 `_qualityNotifier`
  - 第 141 行：初始化时同步状态
  - 第 322 行：切换清晰度时同步状态
  - 第 355 行：dispose 时销毁 notifier
  - 第 428-451 行：非全屏模式清晰度按钮使用 ValueListenableBuilder
  - 第 521-544 行：全屏模式清晰度按钮使用 ValueListenableBuilder

## 效果

✅ **修复前**：
- 切换清晰度后，按钮上的文字保持旧的清晰度
- 需要切换全屏/退出全屏才能看到更新后的清晰度

✅ **修复后**：
- 切换清晰度后，按钮文字立即更新
- 无需切换全屏，清晰度显示实时准确
- 普通模式和全屏模式下都正常工作

## 技术要点

### ValueNotifier vs setState

- **setState**：触发整个 widget 的重新构建
- **ValueNotifier**：只重建监听该值的局部 widget

在这个场景中，`setState` 虽然被调用了，但由于 `MaterialVideoControlsTheme` 的内部实现机制，其 `bottomButtonBar` 数组中的 widget 不会自动重新构建。

使用 `ValueNotifier` + `ValueListenableBuilder` 可以确保即使在 media_kit 库的内部状态管理机制下，清晰度按钮也能正确响应状态变化。

### 为什么切换全屏能触发更新？

因为全屏切换会导致整个播放器 widget 树重新构建（由于 `MaterialVideoControlsTheme` 有 `normal` 和 `fullscreen` 两套配置），此时会读取最新的 `_currentQuality` 值，所以按钮显示正确。

但这不是理想的解决方案，因为用户不应该依赖切换全屏来看到正确的清晰度。

## 相关链接

- [ValueNotifier 官方文档](https://api.flutter.dev/flutter/foundation/ValueNotifier-class.html)
- [ValueListenableBuilder 官方文档](https://api.flutter.dev/flutter/widgets/ValueListenableBuilder-class.html)
- [media_kit 库](https://github.com/alexmercerind/media_kit)

---

**修复日期**: 2025-01-09
**修复版本**: v1.0.1
