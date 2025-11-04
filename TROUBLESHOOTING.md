# 问题排查指南

本文档汇总了项目开发过程中遇到的常见问题及解决方案。

## 🔧 编译构建问题

### ❌ Kotlin 编译错误: "different roots"

**错误信息**:
```
IllegalArgumentException: this and base files have different roots: 
C:\Users\...\Pub\Cache\... and E:\alnitak_flutter\android
```

**原因**: 
Kotlin 增量编译在跨盘符(如 C: 和 E:)环境下无法正确计算相对路径。

**解决方案**:
在 `android/gradle.properties` 中禁用 Kotlin 增量编译:
```properties
kotlin.incremental=false
kotlin.incremental.java=false
kotlin.caching.enabled=false
org.gradle.caching=false
```

然后清理并重新编译:
```bash
cd android && ./gradlew --stop
cd .. && flutter clean
flutter build apk --release --split-per-abi
```

**影响**: 编译速度会稍慢,但可以保证编译成功。

---

### ❌ CMake 文件锁定错误

**错误信息**:
```
FileSystemException: E:\...\CMakeFiles\...: 另一个程序正在使用此文件...
```

**原因**: 
有其他进程(如 Android Studio、Gradle daemon)正在占用 CMake 缓存文件。

**解决方案**:
```bash
# 1. 停止所有 Gradle daemon
cd android && ./gradlew --stop

# 2. 删除 CMake 缓存
rm -rf build/.cxx

# 3. 完全清理
flutter clean

# 4. 重新编译
flutter build apk --release --split-per-abi
```

---

### ❌ Gradle 下载超时

**错误信息**:
```
Could not download gradle-8.12-all.zip
```

**解决方案 1** - 使用国内镜像:

编辑 `android/gradle/wrapper/gradle-wrapper.properties`:
```properties
distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-8.12-all.zip
```

**解决方案 2** - 手动下载:
1. 手动下载 Gradle 到本地
2. 修改为本地路径:
```properties
distributionUrl=file\:///D:/gradle/gradle-8.12-all.zip
```

---

## 🎬 视频播放问题

### ❌ libmpv.so 找不到

**错误信息**:
```
Exception: Cannot find libmpv.so. Please ensure it's presence in the APK.
```

**原因**: 
`media_kit_libs_video` 依赖未正确添加或被误删除。

**解决方案**:
1. 检查 `pubspec.yaml`:
```yaml
dependencies:
  media_kit: ^1.1.10
  media_kit_video: ^1.2.4
  media_kit_libs_video: ^1.0.4  # 必须保留!
```

2. 重新安装依赖:
```bash
flutter pub get
flutter clean
flutter build apk --release --split-per-abi
```

**验证**: 查看日志中是否有:
```
Downloading file from: https://github.com/media-kit/libmpv-android-video-build/.../default-arm64-v8a.jar
```

---

### ❌ 视频播放黑屏

**可能原因**:

#### 1. M3U8 URL 无效或网络问题
```dart
// 添加调试日志
print('📹 视频URL: $videoUrl');
print('📹 网络状态: ${await _testNetworkConnectivity()}');
```

检查日志中是否有 HTTP 错误。

#### 2. HLS 流处理失败
```dart
// 检查 HlsService 日志
print('✅ M3U8 临时文件已创建: $localPath');
```

如果看不到此日志,说明 M3U8 下载或处理失败。

#### 3. Widget 生命周期问题
```dart
@override
void dispose() {
  print('📹 [dispose] 销毁播放器');
  _player.dispose();
  super.dispose();
}
```

确保播放器在 Widget dispose 时正确销毁。

#### 4. 全屏状态下 Widget 未重建
```dart
// 在 initState 中初始化播放器
@override
void initState() {
  super.initState();
  print('📹 [initState] 初始化 - resourceId: ${widget.resourceId}');
  _initPlayer();
}
```

---

### ❌ 全屏切换后画面丢失

**原因**: 
全屏切换触发 Widget 重建,但播放器实例被销毁。

**解决方案**:

方案 1 - 使用 `AutomaticKeepAliveClientMixin`:
```dart
class _MediaPlayerWidgetState extends State<MediaPlayerWidget> 
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用!
    // ...
  }
}
```

方案 2 - 在 `didUpdateWidget` 中恢复播放:
```dart
@override
void didUpdateWidget(MediaPlayerWidget oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (widget.resourceId != oldWidget.resourceId) {
    _loadVideo();
  }
}
```

---

### ❌ 清晰度切换卡顿

**问题**: 切换清晰度时视频重新从头播放或卡顿严重。

**优化方案**:
```dart
Future<void> _changeQuality(String newQuality) async {
  // 1. 保存当前播放位置
  final currentPosition = _player.state.position;
  print('📹 当前位置: ${currentPosition.inSeconds}秒');
  
  // 2. 暂停播放
  await _player.pause();
  
  // 3. 获取新清晰度的 URL
  final newUrl = await _getQualityUrl(newQuality);
  
  // 4. 打开新视频但不立即播放
  await _player.open(Media(newUrl), play: false);
  
  // 5. 跳转到之前的位置
  await _player.seek(currentPosition);
  
  // 6. 继续播放
  await _player.play();
  
  print('📹 清晰度切换完成: $newQuality');
}
```

---

## 📱 设备运行问题

### ❌ ADB 设备连接断开

**错误信息**:
```
adb.exe: no devices/emulators found
```

**解决方案**:
```bash
# 1. 重启 ADB 服务
adb kill-server
adb start-server

# 2. 检查设备连接
adb devices

# 3. 如果设备显示 unauthorized
# 在手机上重新授权 USB 调试

# 4. 如果是 WiFi 调试
adb connect 192.168.1.x:5555
```

---

### ❌ 安装 APK 失败

**错误信息**:
```
INSTALL_FAILED_UPDATE_INCOMPATIBLE
```

**原因**: 
签名不一致(之前安装的是 release 签名,现在是 debug 签名)。

**解决方案**:
```bash
# 1. 卸载旧版本
adb uninstall com.example.alnitak_flutter

# 2. 重新安装
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

### ❌ 应用闪退

**排查步骤**:

1. **查看崩溃日志**:
```bash
adb logcat | grep -E "AndroidRuntime|FATAL"
```

2. **常见原因**:
   - 网络权限未配置
   - 文件访问权限问题
   - 内存溢出
   - 未捕获的异常

3. **检查权限** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
```

---

## 🌐 网络请求问题

### ❌ API 请求失败

**常见错误**:

#### 1. 网络连接超时
```dart
try {
  final response = await http.get(url).timeout(
    const Duration(seconds: 10),
  );
} on TimeoutException {
  print('❌ 请求超时');
}
```

#### 2. 跨域问题 (Web 平台)
在后端配置 CORS:
```
Access-Control-Allow-Origin: *
```

#### 3. HTTP 明文传输被阻止 (Android 9+)
编辑 `android/app/src/main/AndroidManifest.xml`:
```xml
<application
    android:usesCleartextTraffic="true"
    ...>
```

---

## 💾 存储问题

### ❌ 临时文件清理失败

**问题**: M3U8 临时文件未能正确删除。

**解决方案**:
```dart
try {
  final file = File(localM3u8Path);
  if (await file.exists()) {
    await file.delete();
    print('🗑️  已删除临时文件: $localM3u8Path');
  }
} catch (e) {
  print('⚠️ 删除临时文件失败: $e');
  // 不要因为清理失败而影响主流程
}
```

**最佳实践**: 在应用启动时清理所有旧的临时文件:
```dart
Future<void> clearOldCache() async {
  final cacheDir = await getTemporaryDirectory();
  final hlsCacheDir = Directory('${cacheDir.path}/hls_cache');
  
  if (await hlsCacheDir.exists()) {
    await hlsCacheDir.delete(recursive: true);
    print('🧹 已清理 HLS 缓存');
  }
}
```

---

## 🎨 UI 问题

### ❌ 播放器控件位置不正确

**问题**: 控件被状态栏或虚拟按键遮挡。

**解决方案**:
```dart
// 使用 SafeArea 包裹
SafeArea(
  child: MediaPlayerWidget(resourceId: videoId),
)

// 或手动设置 padding
Padding(
  padding: EdgeInsets.only(
    top: MediaQuery.of(context).padding.top,
    bottom: MediaQuery.of(context).padding.bottom,
  ),
  child: MediaPlayerWidget(resourceId: videoId),
)
```

---

### ❌ 横竖屏切换时 UI 错乱

**解决方案**:
```dart
OrientationBuilder(
  builder: (context, orientation) {
    final isLandscape = orientation == Orientation.landscape;
    
    return Container(
      width: isLandscape ? MediaQuery.of(context).size.width : null,
      height: isLandscape ? MediaQuery.of(context).size.height : 220,
      child: MediaPlayerWidget(resourceId: videoId),
    );
  },
)
```

---

## 🔍 调试技巧

### 查看详细日志

```bash
# Flutter 应用日志
flutter run --verbose

# Android 原生日志
adb logcat | grep -E "flutter|📹"

# 过滤视频相关
adb logcat | grep "MediaPlayer\|Video\|HLS"

# 过滤错误
adb logcat | grep -E "ERROR|FATAL|Exception"
```

### 性能分析

```bash
# 启动性能模式
flutter run --profile

# 查看 CPU/内存占用
flutter run --profile --trace-skia

# 检查卡顿
flutter run --profile --trace-systrace
```

### 网络抓包

使用 Charles 或 Fiddler:
1. 配置手机代理
2. 安装 CA 证书
3. 抓取 HTTP/HTTPS 请求

---

## 📞 获取帮助

如果以上方法都无法解决问题:

1. **查看日志**: 使用 `flutter run --verbose` 获取详细日志
2. **搜索 Issues**: 在 GitHub 相关项目中搜索类似问题
3. **官方文档**: 
   - [Flutter Troubleshooting](https://docs.flutter.dev/testing/debugging)
   - [media_kit Issues](https://github.com/alexmercerind/media_kit/issues)
4. **社区求助**: Flutter 中文社区、Stack Overflow

---

**最后更新**: 2025-01-04
