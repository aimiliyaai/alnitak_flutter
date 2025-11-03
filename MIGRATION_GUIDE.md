# 从 better_player 迁移到 media_kit 指南

## 概述

本项目已从 `better_player` 迁移到 `media_kit`，以解决 Android 15 (API 35) 上的崩溃问题，并使用基于 AndroidX Media3 的现代视频播放器。

## 为什么迁移？

### 问题
- **better_player** 在 Android 15 上崩溃，错误信息：`SecurityException: One of RECEIVER_EXPORTED or RECEIVER_NOT_EXPORTED should be specified`
- better_player 基于旧版 ExoPlayer，不再维护
- 不兼容 Android 13+ 的新安全要求

### 解决方案
- **media_kit** 基于 AndroidX Media3（Android 上的最新 ExoPlayer）
- 跨平台支持：Android、iOS、Windows、Linux、macOS、Web
- GPU 硬件加速，性能更好
- 积极维护，持续更新

## 依赖变更

### 之前 (better_player)
```yaml
dependencies:
  better_player: ^0.0.84
```

### 现在 (media_kit)
```yaml
dependencies:
  media_kit: ^1.1.10              # 核心库
  media_kit_video: ^1.2.4         # 视频渲染
  media_kit_libs_video: ^1.0.4    # 原生视频依赖
```

## Android 配置变更

### build.gradle.kts
```kotlin
defaultConfig {
    minSdk = 23  // media_kit 推荐最低版本
    targetSdk = 34  // 设置为 34 以兼容 AndroidX Media3
}
```

## 代码变更

### 初始化

#### 之前
```dart
void main() {
  runApp(const MyApp());
}
```

#### 现在
```dart
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();  // 必须初始化
  runApp(const MyApp());
}
```

### 播放器使用

#### 之前 (BetterPlayer)
```dart
BetterPlayerController? _betterPlayerController;

_betterPlayerController = BetterPlayerController(
  betterPlayerConfiguration,
  betterPlayerDataSource: betterPlayerDataSource,
);

BetterPlayer(controller: _betterPlayerController!)
```

#### 现在 (media_kit)
```dart
late final Player _player;
late final VideoController _videoController;

@override
void initState() {
  super.initState();
  _player = Player();
  _videoController = VideoController(_player);
}

Video(
  controller: _videoController,
  controls: MaterialVideoControls,
)
```

### 事件监听

#### 之前 (BetterPlayer)
```dart
void _onPlayerEvent(BetterPlayerEvent event) {
  switch (event.betterPlayerEventType) {
    case BetterPlayerEventType.finished:
      // 处理播放结束
      break;
    case BetterPlayerEventType.progress:
      // 处理播放进度
      break;
  }
}
```

#### 现在 (media_kit)
```dart
void _setupPlayerListeners() {
  // 播放完成
  _player.stream.completed.listen((completed) {
    if (completed) {
      // 处理播放结束
    }
  });

  // 播放进度
  _player.stream.position.listen((position) {
    // 处理播放进度
  });

  // 播放/暂停状态
  _player.stream.playing.listen((playing) {
    // 处理状态变化
  });

  // 错误处理
  _player.stream.error.listen((error) {
    // 处理错误
  });
}
```

### 播放控制

#### 之前 (BetterPlayer)
```dart
_betterPlayerController?.play();
_betterPlayerController?.pause();
_betterPlayerController?.seekTo(position);
final pos = _betterPlayerController?.videoPlayerController?.value.position;
```

#### 现在 (media_kit)
```dart
_player.play();
_player.pause();
_player.seek(position);
final pos = _player.state.position;
```

### 加载视频

#### 之前 (BetterPlayer)
```dart
final dataSource = BetterPlayerDataSource(
  BetterPlayerDataSourceType.file,
  filePath,
);
_betterPlayerController = BetterPlayerController(
  configuration,
  betterPlayerDataSource: dataSource,
);
```

#### 现在 (media_kit)
```dart
await _player.open(
  Media(filePath),
  play: true,  // 自动播放
);
```

## API 对照表

| 功能 | better_player | media_kit |
|------|--------------|-----------|
| 初始化 | `BetterPlayerController()` | `Player()` + `VideoController()` |
| 播放 | `controller.play()` | `player.play()` |
| 暂停 | `controller.pause()` | `player.pause()` |
| 跳转 | `controller.seekTo(duration)` | `player.seek(duration)` |
| 加载视频 | `BetterPlayerDataSource` | `player.open(Media())` |
| 获取位置 | `controller.videoPlayerController?.value.position` | `player.state.position` |
| 播放完成事件 | `BetterPlayerEventType.finished` | `player.stream.completed` |
| 进度更新 | `BetterPlayerEventType.progress` | `player.stream.position` |
| 错误处理 | 事件监听 | `player.stream.error` |
| 销毁 | `controller.dispose()` | `player.dispose()` |

## HLS 支持

media_kit 完全支持 HLS (m3u8) 流媒体，无需额外配置：

```dart
await _player.open(Media('path/to/video.m3u8'));
```

## 清晰度切换

清晰度切换逻辑保持不变，只需更换底层播放器 API：

```dart
Future<void> changeQuality(String quality) async {
  // 记录当前位置
  final currentPosition = _player.state.position;

  // 加载新清晰度视频
  await _loadVideo(quality);

  // 恢复播放位置
  await _player.seek(currentPosition);
}
```

## 性能优化

### Release 模式
media_kit 在 Release 模式下性能显著优于 Debug 模式：

```bash
flutter run --release
```

### GPU 加速
media_kit 自动使用 GPU 硬件加速，无需额外配置。

## 测试步骤

1. **清理项目**
   ```bash
   flutter clean
   ```

2. **获取依赖**
   ```bash
   flutter pub get
   ```

3. **Android 测试**
   ```bash
   flutter run -d android
   ```

4. **其他平台测试**
   ```bash
   flutter run -d windows
   flutter run -d ios
   flutter run -d chrome
   ```

## 已知问题

### Android 15 兼容性
- 已通过设置 `targetSdk = 34` 解决
- AndroidX Media3 完全兼容 Android 15

### Web 平台
- media_kit 在 Web 上使用 HTML5 video
- 某些高级功能可能受限

## 故障排除

### 黑屏问题
如果遇到黑屏：
1. 检查视频文件路径是否正确
2. 确认在 `main()` 中调用了 `MediaKit.ensureInitialized()`
3. 使用 Release 模式测试

### 编译错误
如果遇到编译错误：
```bash
flutter clean
cd android && ./gradlew clean && cd ..
flutter pub get
flutter run
```

### 性能问题
- 确保使用 Release 模式
- 检查是否启用了硬件加速
- 查看 Android Studio Profiler

## 参考资源

- [media_kit GitHub](https://github.com/media-kit/media-kit)
- [media_kit 文档](https://pub.dev/packages/media_kit)
- [AndroidX Media3 文档](https://github.com/androidx/media)
- [Flutter 官方视频播放指南](https://docs.flutter.dev/cookbook/plugins/play-video)

## 技术支持

如果遇到问题：
1. 检查 [media_kit Issues](https://github.com/media-kit/media-kit/issues)
2. 查看本项目的崩溃日志
3. 确认 Android SDK 和 Flutter 版本是否兼容
