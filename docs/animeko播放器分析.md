# Animeko 项目播放器分析报告

## 项目概述

**Animeko** 是一个 Kotlin Multiplatform (KMP) 项目，使用 Compose Multiplatform 构建跨平台应用。

## 播放器架构

### 统一抽象层：MediaMP

Animeko 使用了一个统一的媒体播放器抽象层 `MediaMP` (`org.openani.mediamp`)，它封装了不同平台的播放器实现，提供统一的 API 接口。

**包结构**: `org.openani.mediamp`

### 平台特定实现

#### 1. **Android 平台** ✅
- **播放器库**: Media3 ExoPlayer
- **版本**: `androidx-media3 = "1.6.1"`
- **具体实现**: `ExoPlayerMediampPlayer`
- **UI组件**: `ExoPlayerMediampPlayerSurface`
- **依赖库**:
  ```kotlin
  androidx-media3-ui
  androidx-media3-exoplayer
  androidx-media3-exoplayer-dash      // DASH 流媒体支持
  androidx-media3-exoplayer-hls       // HLS 流媒体支持
  ```

**代码位置**:
- `app/shared/video-player/src/androidMain/kotlin/ui/VideoPlayer.android.kt`

**特点**:
- 支持 DASH、HLS 等流媒体协议
- 自定义字幕样式（CaptionStyleCompat）
- 隐藏默认控制器，使用自定义控制UI

---

#### 2. **Desktop 平台** (Windows/macOS/Linux) ✅
- **播放器库**: VLCJ (VLC for Java)
- **版本**: `vlcj = "4.8.2"`
- **具体实现**: `VlcMediampPlayer`
- **UI组件**: `VlcMediampPlayerSurface`
- **底层**: VLC Media Player 3.0.18
- **依赖库**:
  ```kotlin
  vlcj                                 // VLC Java 绑定
  jna = "5.13.0"                       // Java Native Access（注意版本固定）
  ```

**代码位置**:
- `app/shared/video-player/src/desktopMain/kotlin/ui/VideoPlayer.desktop.kt`

**重要提示**: 
- ⚠️ **VLC版本固定为 3.0.18**
- ⚠️ **JNA 版本固定为 5.13.0**（版本更改可能导致兼容性问题）

**特点**:
- 支持几乎所有视频格式
- 强大的硬件解码支持
- 跨平台桌面应用播放器首选

---

#### 3. **iOS/macOS 平台** ✅
- **播放器库**: AVKit (Apple 原生框架)
- **具体实现**: `AVKitMediampPlayer`（推断）
- **UI组件**: `MediampPlayerSurface`
- **底层**: AVFoundation / AVKit

**代码位置**:
- `app/shared/video-player/src/iosMain/kotlin/ui/VideoPlayer.ios.kt`

**特点**:
- 使用 Apple 原生播放框架
- 良好的系统集成
- 硬件加速支持

---

## 核心功能实现

### 播放器控制器 (`PlayerControllerState`)
- 播放/暂停控制
- 进度控制
- 音量控制
- 播放速度控制
- 字幕切换
- 音频轨道切换
- 章节导航

### 手势控制 (`PlayerGestureHost`)
- **Android**: `PlayerGestureHost.android.kt`
- **通用**: `PlayerGestureHost.kt`
  - 滑动进度调节 (`SwipeSeekerState`)
  - 滑动音量控制 (`SwipeVolumeControl`)
  - 快速跳过 (`FastSkipState`)
  - 手势锁定 (`GestureLock`)
  - 键盘进度控制 (`KeyboardSeek`)

### UI组件
- **进度条**: `MediaProgressSlider`、`MediaProgressIndicatorText`
- **控制器栏**: `PlayerControllerBar`
- **顶部栏**: `PlayerTopBar`、`Indicators`
- **字幕切换器**: `SubtitleSwitcher`
- **音频切换器**: `AudioSwitcher`
- **垂直滑块**: `VerticalSlider`
- **浮动按钮**: `PlayerFloatingButtonBox`、`ScreenshotButton`

---

## 依赖版本总结

```toml
# Media3 (Android)
androidx-media3 = "1.6.1"

# VLC (Desktop)
vlcj = "4.8.2"
jna = "5.13.0"              # 固定版本，不可更改

# Compose
compose-multiplatform = "1.9.0"
```

---

## 对于 Flutter 项目的建议

### 如果要迁移到 Flutter

Animeko 使用的播放器架构对于 Flutter 项目有以下参考价值：

#### 1. **Flutter 推荐的播放器库**

**Android/iOS**:
- `video_player` (官方推荐，基于 AVPlayer/ExoPlayer)
- `better_player` (功能更丰富的 ExoPlayer 封装)
- `media_kit` (跨平台，基于 libmpv/VLC)
- `chewie` (video_player 的 UI 包装器)

**跨平台方案**:
- `media_kit` - 支持 Android/iOS/Desktop，使用 libmpv 或 VLC
- `flutter_vlc_player` - 直接使用 VLC（适用于桌面）

#### 2. **建议架构**

```
lib/
├── video_player/
│   ├── models/              # 播放器状态模型
│   ├── controllers/         # 播放器控制器
│   ├── widgets/             # UI组件
│   │   ├── video_player_widget.dart
│   │   ├── player_controls.dart
│   │   ├── progress_bar.dart
│   │   └── gesture_handler.dart
│   └── services/            # 平台特定实现
│       ├── video_player_service.dart
│       ├── android_video_player.dart
│       └── ios_video_player.dart
```

#### 3. **功能对标**

| Animeko (KMP) | Flutter 推荐方案 |
|--------------|----------------|
| MediaMP 抽象层 | 自定义播放器服务抽象类 |
| ExoPlayer (Android) | `better_player` 或 `video_player` |
| VLC (Desktop) | `media_kit` 或 `flutter_vlc_player` |
| AVKit (iOS) | `video_player` (原生支持) |

---

## 关键设计模式

### 1. **平台特定实现 (expect/actual)**
```kotlin
// 通用接口
expect fun VideoPlayer(player: MediampPlayer, modifier: Modifier)

// Android实现
actual fun VideoPlayer(...) {
    ExoPlayerMediampPlayerSurface(...)
}

// Desktop实现
actual fun VideoPlayer(...) {
    VlcMediampPlayerSurface(...)
}
```

**Flutter 等价**:
```dart
// 抽象服务
abstract class VideoPlayerService {
  Future<void> play(String url);
  // ...
}

// Android实现
class AndroidVideoPlayerService implements VideoPlayerService {
  // 使用 ExoPlayer
}

// iOS实现
class IOSVideoPlayerService implements VideoPlayerService {
  // 使用 AVPlayer
}
```

### 2. **状态管理**
- 使用 Kotlin 状态管理（StateFlow、Compose State）
- 分离播放器状态和控制逻辑

**Flutter 等价**: 使用 `Provider`、`Riverpod` 或 `Bloc`

### 3. **手势处理**
- 平台特定手势实现
- 统一的手势处理抽象

**Flutter 等价**: 使用 `GestureDetector` 和自定义手势识别

---

## 总结

### Animeko 播放器架构优势：
1. ✅ **跨平台统一API** - MediaMP 抽象层
2. ✅ **平台优化** - 每个平台使用最佳播放器
3. ✅ **功能完整** - 支持字幕、多音轨、章节等
4. ✅ **手势丰富** - 滑动调节、快速跳过等
5. ✅ **UI可定制** - 隐藏默认控制器，完全自定义

### Flutter 项目建议：
1. 使用 `better_player` 或 `media_kit` 作为主要播放器
2. 创建统一的播放器服务抽象层
3. 实现自定义控制UI和手势处理
4. 支持字幕、多音轨等高级功能

---

**分析日期**: 2024-XX-XX
**项目路径**: `E:\animeko-main\animeko-main`
