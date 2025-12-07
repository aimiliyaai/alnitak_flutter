# 后台播放 (Background Play) 跨平台实现文档

## 概述

本项目使用**原生平台 API** 实现后台播放功能,遵循各平台最佳实践。

## 架构设计

```
┌─────────────────────────────────────────────────────────┐
│  VideoPlayerController (Dart)                           │
│  ├─ 监听应用生命周期 (didChangeAppLifecycleState)        │
│  ├─ 启用后台播放: BackgroundPlayManager.enable()        │
│  └─ 禁用后台播放: BackgroundPlayManager.disable()       │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  BackgroundPlayManager (Dart)                           │
│  ├─ 检测当前平台                                         │
│  ├─ 通过 MethodChannel 调用原生代码                      │
│  └─ 监听播放控制回调 (播放/暂停/跳转)                    │
└─────────────────────────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
  ┌──────────┐    ┌───────────┐    ┌──────────┐
  │ Android  │    │    iOS    │    │ Windows  │
  │  Plugin  │    │  Plugin   │    │   N/A    │
  └──────────┘    └───────────┘    └──────────┘
```

## 各平台实现

### Android

**文件**: `android/app/src/main/kotlin/.../BackgroundPlayPlugin.kt`

**核心技术栈**:
1. **Foreground Service** - 前台服务保持应用运行
2. **MediaSession** - 媒体会话管理播放状态
3. **Notification** - 显示播放控制通知

```kotlin
// 1. 创建 MediaSession
mediaSession = MediaSessionCompat(context, "AlnitakVideoPlayer").apply {
    setCallback(object : MediaSessionCompat.Callback() {
        override fun onPlay() { /* 处理播放 */ }
        override fun onPause() { /* 处理暂停 */ }
        override fun onSeekTo(pos: Long) { /* 处理跳转 */ }
    })
    isActive = true
}

// 2. 启动前台服务
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
    context.startForegroundService(serviceIntent)
}

// 3. 显示通知
class VideoPlaybackService : Service() {
    override fun onStartCommand(...) {
        startForeground(NOTIFICATION_ID, createNotification(...))
    }
}
```

**权限配置** (AndroidManifest.xml):
```xml
<!-- 前台服务权限 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>

<!-- 通知权限 -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<!-- 注册前台服务 -->
<service
    android:name=".VideoPlaybackService"
    android:enabled="true"
    android:exported="false"
    android:foregroundServiceType="mediaPlayback" />
```

**特点**:
- ✅ Android 8.0+ 必须使用前台服务
- ✅ 通知栏显示播放控制
- ✅ 锁屏界面显示媒体控制
- ✅ 支持蓝牙耳机等外部控制

---

### iOS

**文件**: `ios/Runner/BackgroundPlayPlugin.swift`

**核心技术栈**:
1. **AVAudioSession** - 配置音频会话为播放模式
2. **MPNowPlayingInfoCenter** - 更新锁屏/控制中心播放信息
3. **MPRemoteCommandCenter** - 处理远程控制事件

```swift
// 1. 配置音频会话
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
try audioSession.setActive(true)

// 2. 更新 Now Playing Info
var nowPlayingInfo = [String: Any]()
nowPlayingInfo[MPMediaItemPropertyTitle] = title
nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

// 3. 设置远程控制
let commandCenter = MPRemoteCommandCenter.shared()
commandCenter.playCommand.addTarget { event in
    // 处理播放
    return .success
}
```

**权限配置** (Info.plist):
```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

**特点**:
- ✅ iOS 官方推荐方式
- ✅ 锁屏界面显示播放信息
- ✅ 控制中心显示播放控制
- ✅ 支持 AirPods/CarPlay 等外部控制
- ✅ 后台播放音频

---

### Windows

**无需特殊处理**

Windows 桌面应用默认允许后台运行,不会被系统自动暂停。

```dart
// Windows 平台直接返回,无需操作
if (Platform.isWindows) {
  debugPrint('🪟 [Windows] 后台播放无需特殊处理');
}
```

**特点**:
- ✅ 系统不会自动暂停后台应用
- ✅ 窗口最小化后继续播放
- ✅ 无需额外配置或权限

---

## 使用方法

### 在 VideoPlayerController 中使用

```dart
import '../utils/background_play_manager.dart';

void handleAppLifecycleState(bool isPaused) {
  if (isPaused) {
    // 进入后台
    if (backgroundPlayEnabled.value) {
      _enableBackgroundPlayback();
    } else {
      player.pause();
    }
  } else {
    // 返回前台
    BackgroundPlayManager.disable();
  }
}

void _enableBackgroundPlayback() {
  BackgroundPlayManager.enable(
    title: '视频标题',
    artist: '作者',
    duration: player.state.duration,
    position: player.state.position,
  );

  // 设置播放控制回调
  BackgroundPlayManager.setPlaybackCallback(
    onPlay: () => player.play(),
    onPause: () => player.pause(),
    onSeekTo: (pos) => player.seek(pos),
  );
}
```

### 更新播放信息

```dart
// 播放状态改变时更新
BackgroundPlayManager.updatePlaybackInfo(
  position: player.state.position,
  isPlaying: player.state.playing,
);
```

### 调试输出

```
🤖 [Android] 后台播放已启用 (Foreground Service + MediaSession)
🍎 [iOS] 后台播放已启用 (AVAudioSession + MPNowPlayingInfoCenter)
🪟 [Windows] 后台播放无需特殊处理
```

---

## 功能对比

| 平台 | 技术方案 | 通知栏控制 | 锁屏控制 | 外部设备控制 |
|------|---------|-----------|----------|-------------|
| **Android** | Foreground Service + MediaSession | ✅ | ✅ | ✅ |
| **iOS** | AVAudioSession + MPNowPlayingInfoCenter | ❌ | ✅ | ✅ |
| **Windows** | 无需特殊处理 | ❌ | ❌ | ❌ |

---

## 播放控制回调

### Android & iOS 支持的控制事件

```dart
BackgroundPlayManager.setPlaybackCallback(
  onPlay: () {}, // 播放
  onPause: () {}, // 暂停
  onStop: () {}, // 停止
  onNext: () {}, // 下一首
  onPrevious: () {}, // 上一首
  onSeekTo: (Duration position) {}, // 跳转到指定位置
);
```

---

## Android 通知栏

### 通知样式

```
┌────────────────────────────────┐
│  🎬 视频播放                    │
│  作者名称                       │
│                                │
│  [◀] [⏸] [▶]                  │
└────────────────────────────────┘
```

### 自定义通知

可以在 `VideoPlaybackService.createNotification()` 中自定义:
- 通知图标
- 播放控制按钮
- 进度条
- 专辑封面

---

## iOS 锁屏界面

### 锁屏样式

```
┌────────────────────────────────┐
│                                │
│        [专辑封面]              │
│                                │
│      视频标题                   │
│      作者名称                   │
│                                │
│   ────────●───────             │
│   0:00        3:45             │
│                                │
│  [◀◀]  [⏸]  [▶▶]              │
└────────────────────────────────┘
```

### 自定义锁屏信息

```dart
BackgroundPlayManager.enable(
  title: '视频标题',
  artist: '作者',
  album: '专辑',
  duration: Duration(minutes: 3, seconds: 45),
  position: Duration(seconds: 30),
);
```

---

## 生命周期管理

### 启用时机

```dart
// 应用进入后台时
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    if (backgroundPlayEnabled.value) {
      BackgroundPlayManager.enable(...);
    }
  }
}
```

### 禁用时机

```dart
// 1. 返回前台时
if (state == AppLifecycleState.resumed) {
  BackgroundPlayManager.disable();
}

// 2. 播放器销毁时
@override
void dispose() {
  BackgroundPlayManager.disable();
  super.dispose();
}
```

---

## 注意事项

### Android

1. **Android 13+** 需要用户授予通知权限
2. **前台服务** 必须显示通知,不能隐藏
3. **省电模式** 可能限制后台播放
4. **服务类型** 必须设置为 `mediaPlayback`

### iOS

1. **音频会话** 必须设置为 `.playback` 类别
2. **Info.plist** 必须声明 `audio` 后台模式
3. **视频播放** 只能播放音频,视频帧不会渲染
4. **AirPlay** 自动支持

### Windows

1. **无需特殊处理** - 系统不限制后台运行
2. **窗口最小化** 后继续播放
3. **性能考虑** - 后台播放仍占用资源

---

## 测试步骤

### Android

1. 启动应用并播放视频
2. 按 Home 键将应用切换到后台
3. 检查通知栏是否显示播放控制
4. 点击通知栏的播放/暂停按钮
5. 检查视频是否继续播放(音频)

### iOS

1. 启动应用并播放视频
2. 按 Home 键将应用切换到后台
3. 从底部上滑打开控制中心
4. 检查是否显示播放信息和控制按钮
5. 锁屏后查看锁屏界面播放控制

### Windows

1. 启动应用并播放视频
2. 最小化窗口
3. 检查视频是否继续播放

---

## 常见问题

### Q: Android 通知不显示?
A: 检查:
1. 是否授予了通知权限
2. 前台服务是否正确启动
3. 通知渠道是否正确创建

### Q: iOS 锁屏不显示播放信息?
A: 检查:
1. Info.plist 是否添加了 `audio` 后台模式
2. AVAudioSession 是否正确激活
3. MPNowPlayingInfoCenter 是否设置了信息

### Q: 后台播放突然停止?
A: 可能原因:
1. 系统省电模式限制
2. 内存不足被系统杀掉
3. 音频会话被其他应用抢占 (iOS)

---

## 未来扩展

- [ ] macOS 支持 (MPNowPlayingInfoCenter)
- [ ] Linux 支持 (MPRIS D-Bus Interface)
- [ ] 自定义通知布局
- [ ] 专辑封面显示
- [ ] 进度条同步更新
- [ ] 播放列表支持

---

## 总结

本实现采用**原生平台 API**,确保每个平台使用最佳实践:

- **Android**: Foreground Service + MediaSession + Notification
- **iOS**: AVAudioSession + MPNowPlayingInfoCenter + MPRemoteCommandCenter
- **Windows**: 无需特殊处理

这种方式比使用第三方插件更**精确、可控、符合平台规范**。
