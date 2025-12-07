# 屏幕常亮 (Wakelock) 跨平台实现文档

## 概述

本项目使用**原生平台 API** 实现屏幕常亮功能,遵循各平台最佳实践,而不是使用第三方插件。

## 架构设计

```
┌─────────────────────────────────────────────────────────┐
│  VideoPlayerController (Dart)                           │
│  ├─ 监听播放状态变化                                     │
│  └─ 调用 WakelockManager.enable/disable()              │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  WakelockManager (Dart)                                 │
│  ├─ 检测当前平台                                         │
│  └─ 通过 MethodChannel 调用原生代码                      │
└─────────────────────────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
  ┌──────────┐    ┌───────────┐    ┌──────────┐
  │ Android  │    │    iOS    │    │ Windows  │
  │  Plugin  │    │  Plugin   │    │  Plugin  │
  └──────────┘    └───────────┘    └──────────┘
```

## 各平台实现

### Android

**文件**: `android/app/src/main/kotlin/.../WakelockPlugin.kt`

**API**: `WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON`

```kotlin
window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)  // 启用
window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) // 禁用
```

**特点**:
- ✅ 不需要额外权限
- ✅ Activity 失去焦点时自动释放
- ✅ 与 NextPlayer 等专业播放器一致
- ✅ Android 官方推荐方式

---

### iOS

**文件**: `ios/Runner/WakelockPlugin.swift`

**API**: `UIApplication.shared.isIdleTimerDisabled`

```swift
UIApplication.shared.isIdleTimerDisabled = true  // 启用
UIApplication.shared.isIdleTimerDisabled = false // 禁用
```

**特点**:
- ✅ iOS 官方推荐方式
- ✅ 防止设备进入休眠状态
- ✅ 适用于视频播放场景
- ✅ 必须在主线程调用

---

### Windows

**文件**: `windows/runner/wakelock_plugin.cpp`

**API**: `SetThreadExecutionState`

```cpp
SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED);
```

**特点**:
- ✅ Windows 官方 API
- ✅ ES_CONTINUOUS: 持续有效
- ✅ ES_DISPLAY_REQUIRED: 强制显示器保持开启
- ✅ ES_SYSTEM_REQUIRED: 防止系统自动睡眠

---

### macOS (待实现)

**API**: IOKit (IOPMAssertion)

```swift
IOPMAssertionCreateWithName(
    kIOPMAssertionTypeNoDisplaySleep,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    ...
)
```

---

### Linux (待实现)

**API**: D-Bus (org.freedesktop.ScreenSaver)

---

## 使用方法

### 在 VideoPlayerController 中使用

```dart
import '../utils/wakelock_manager.dart';

// 播放时启用
player.stream.playing.listen((playing) {
  if (playing) {
    WakelockManager.enable();
  } else {
    WakelockManager.disable();
  }
});

// 销毁时禁用
@override
void dispose() {
  WakelockManager.disable();
  super.dispose();
}
```

### 调试输出

```
🤖 [Android] Wakelock 已启用 (FLAG_KEEP_SCREEN_ON)
🍎 [iOS] Wakelock 已启用 (isIdleTimerDisabled)
🪟 [Windows] Wakelock 已启用 (ES_CONTINUOUS | ES_DISPLAY_REQUIRED)
```

---

## 对比: 原生 vs 插件

| 方案 | 优点 | 缺点 |
|------|------|------|
| **原生 API** | ✅ 更精确控制<br>✅ 遵循平台最佳实践<br>✅ 性能更好<br>✅ 无第三方依赖 | ❌ 需要编写平台代码<br>❌ 维护成本稍高 |
| **WakelockPlus** | ✅ 简单易用<br>✅ 跨平台统一<br>✅ 维护成本低 | ❌ 依赖第三方插件<br>❌ 可能不够精细 |

---

## 参考实现

### NextPlayer (Android)
```kotlin
// PlayerActivity.kt:1118
private fun updateKeepScreenOnFlag() {
    if (mediaController?.isPlaying == true) {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    } else {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
```

---

## 权限配置

### Android (AndroidManifest.xml)

```xml
<!-- 可选:WAKE_LOCK 权限 (FLAG_KEEP_SCREEN_ON 不需要) -->
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### iOS (Info.plist)

无需额外权限配置。

### Windows

无需额外权限配置。

---

## 注意事项

1. **调用时机**
   - 播放时立即调用 `enable()`
   - 暂停时调用 `disable()`
   - 切换清晰度时保持启用状态

2. **生命周期管理**
   - 在 Controller dispose 时确保禁用
   - Android Activity 失去焦点时会自动清除

3. **错误处理**
   - 所有平台调用都包含 try-catch
   - 失败时输出日志,不影响播放

---

## 未来扩展

- [ ] macOS 支持 (IOPMAssertion)
- [ ] Linux 支持 (D-Bus)
- [ ] Web 支持 (Screen Wake Lock API)
- [ ] 添加单元测试
- [ ] 性能监控

---

## 总结

本实现采用**原生平台 API**,确保每个平台使用最佳实践:

- **Android**: `FLAG_KEEP_SCREEN_ON` (与 NextPlayer 一致)
- **iOS**: `isIdleTimerDisabled`
- **Windows**: `SetThreadExecutionState`

这种方式比使用第三方插件更**精确、可控、高效**。
