# 开发文档

## 快速开始

### 1. 环境准备
```bash
# 检查 Flutter 环境
flutter doctor

# 安装依赖
flutter pub get
```

### 2. 运行项目
```bash
# 查看可用设备
flutter devices

# 运行到设备
flutter run -d <device_id>

# 热重载
按 r 键: 热重载
按 R 键: 完全重启
按 q 键: 退出
```

### 3. 构建发布版本
```bash
# 清理旧构建
flutter clean

# 停止 Gradle daemon
cd android && ./gradlew --stop

# 构建 APK (分架构 - 推荐)
flutter build apk --release --split-per-abi

# 构建通用 APK
flutter build apk --release
```

## 项目架构详解

### MVVM 架构
```
View (UI)
  ↓
ViewModel (State Management)
  ↓
Model (Data)
  ↓
Service (Business Logic)
  ↓
Repository/API (Data Source)
```

### 数据流
```
用户操作 → Widget → Service → API
                  ↓
                Model
                  ↓
             setState()
                  ↓
             UI 更新
```

## 核心模块开发指南

### 1. 添加新页面
```dart
// 1. 在 lib/pages/ 下创建新页面
class NewPage extends StatefulWidget {
  const NewPage({super.key});
  
  @override
  State<NewPage> createState() => _NewPageState();
}

// 2. 在 main_page.dart 中添加路由
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const NewPage()),
);
```

### 2. 添加新 API
```dart
// 在 lib/services/video_api_service.dart 中添加
class VideoApiService {
  static Future<ApiResponse<YourModel>> yourNewApi() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/your/endpoint'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ApiResponse.fromJson(
          data,
          (json) => YourModel.fromJson(json),
        );
      }
      throw Exception('请求失败');
    } catch (e) {
      LoggerService.error('API错误', error: e);
      rethrow;
    }
  }
}
```

### 3. 添加新数据模型
```dart
// 在 lib/models/ 下创建模型
class YourModel {
  final int id;
  final String name;
  
  YourModel({
    required this.id,
    required this.name,
  });
  
  factory YourModel.fromJson(Map<String, dynamic> json) {
    return YourModel(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}
```

## 播放器开发

### 自定义播放器控件
```dart
// 修改 media_player_widget.dart 中的配置
MaterialVideoControlsTheme(
  // 控件位置
  seekBarMargin: EdgeInsets.only(bottom: 44),
  bottomButtonBarMargin: EdgeInsets.only(bottom: 0),
  
  // 颜色主题
  seekBarColor: Colors.blue,
  seekBarThumbColor: Colors.blue,
  
  // 显示/隐藏控件
  displaySeekBar: true,
  automaticallyImplySkipNextButton: false,
  
  // 字体大小
  seekBarPositionTextStyle: TextStyle(fontSize: 12),
)
```

### 处理视频切换
```dart
// 1. 暂停当前播放
await _player.pause();

// 2. 获取当前播放位置
final position = _player.state.position;

// 3. 切换视频源
await _player.open(Media(newVideoUrl));

// 4. 跳转到之前位置
await _player.seek(position);

// 5. 开始播放
await _player.play();
```

### HLS 流处理
```dart
// 使用 HlsService 处理 M3U8
final localM3u8Path = await HlsService.processAndCacheM3u8(
  m3u8Url: 'https://example.com/video.m3u8',
  baseUrl: 'https://example.com',
  videoId: '123',
  quality: '1080p',
);

// 播放本地文件
await _player.open(Media('file://$localM3u8Path'));
```

## 调试技巧

### 1. 日志输出
```dart
// 使用 LoggerService
LoggerService.debug('调试信息: $variable');
LoggerService.error('错误', error: e, stackTrace: st);

// 视频相关日志(带 📹 标记)
print('📹 播放器状态: ${_player.state.playing}');
```

### 2. 真机调试
```bash
# 查看实时日志
adb logcat | grep -E "flutter|📹|MediaPlayer"

# 过滤视频相关日志
adb logcat | grep "📹"

# 清空日志缓冲区
adb logcat -c
```

### 3. 性能分析
```bash
# 启动性能分析
flutter run --profile

# 打开 DevTools
flutter pub global run devtools
```

## 常见问题排查

### 问题 1: 视频播放黑屏
**排查步骤**:
1. 检查 M3U8 URL 是否有效
2. 查看日志中是否有网络错误
3. 确认 libmpv.so 已加载
4. 检查 Widget 生命周期

```dart
// 添加调试日志
print('📹 视频URL: $videoUrl');
print('📹 播放器状态: ${_player.state.buffering}');
```

### 问题 2: 全屏切换异常
**排查步骤**:
1. 检查 `SystemChrome.setEnabledSystemUIMode` 调用
2. 确认 `OrientationBuilder` 正确嵌套
3. 查看 Widget 是否被正确 dispose

### 问题 3: 清晰度切换卡顿
**优化方案**:
```dart
// 保存当前位置
final position = _player.state.position;

// 快速切换
await _player.pause();
await _player.open(Media(newQualityUrl), play: false);
await _player.seek(position);
await _player.play();
```

## 性能优化

### 1. 减少 Widget 重建
```dart
// 使用 const 构造函数
const Text('标题');

// 使用 ValueListenableBuilder
ValueListenableBuilder<bool>(
  valueListenable: _isPlayingNotifier,
  builder: (context, isPlaying, child) {
    return Icon(isPlaying ? Icons.pause : Icons.play);
  },
);
```

### 2. 图片缓存优化
```dart
// 使用 CachedNetworkImage
CachedNetworkImage(
  imageUrl: imageUrl,
  placeholder: (context, url) => CircularProgressIndicator(),
  errorWidget: (context, url, error) => Icon(Icons.error),
  memCacheWidth: 800, // 限制内存缓存大小
);
```

### 3. 列表性能优化
```dart
// 使用 ListView.builder 而不是 ListView
ListView.builder(
  itemCount: videos.length,
  itemBuilder: (context, index) {
    final video = videos[index];
    return VideoCard(video: video);
  },
);
```

## 代码规范

### 1. 命名规范
- 类名: `PascalCase` (如 `VideoPlayPage`)
- 变量/方法: `camelCase` (如 `isPlaying`, `loadVideo()`)
- 私有成员: `_camelCase` (如 `_player`, `_initPlayer()`)
- 常量: `lowerCamelCase` (如 `maxRetries`)
- 文件名: `snake_case` (如 `video_play_page.dart`)

### 2. 注释规范
```dart
/// 视频播放器组件
/// 
/// 支持 HLS 流媒体播放、清晰度切换、全屏播放等功能
class MediaPlayerWidget extends StatefulWidget {
  /// 视频资源 ID
  final int resourceId;
  
  /// 初始清晰度
  final String? initialQuality;
  
  const MediaPlayerWidget({
    super.key,
    required this.resourceId,
    this.initialQuality,
  });
}
```

### 3. 错误处理
```dart
try {
  // 业务逻辑
  await loadVideo();
} catch (e, stackTrace) {
  // 记录日志
  LoggerService.error('加载视频失败', error: e, stackTrace: stackTrace);
  
  // 显示用户友好的错误信息
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('视频加载失败,请重试')),
    );
  }
}
```

## Git 工作流

### 提交规范
```bash
# 功能开发
git commit -m "feat: 添加清晰度切换功能"

# Bug 修复
git commit -m "fix: 修复全屏播放黑屏问题"

# 文档更新
git commit -m "docs: 更新 README 文档"

# 代码重构
git commit -m "refactor: 重构播放器控制逻辑"

# 性能优化
git commit -m "perf: 优化视频列表加载性能"
```

## 测试

### 单元测试
```dart
// test/services/video_service_test.dart
void main() {
  group('VideoService', () {
    test('获取视频详情', () async {
      final detail = await VideoService.getVideoDetail(1);
      expect(detail.id, 1);
      expect(detail.title, isNotEmpty);
    });
  });
}
```

### Widget 测试
```dart
void main() {
  testWidgets('视频卡片显示', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VideoCard(video: testVideo),
      ),
    );
    
    expect(find.text(testVideo.title), findsOneWidget);
  });
}
```

## 发布清单

- [ ] 更新版本号 (pubspec.yaml)
- [ ] 更新 CHANGELOG
- [ ] 运行完整测试
- [ ] 构建 release APK
- [ ] 测试所有核心功能
- [ ] 检查内存泄漏
- [ ] 更新文档
- [ ] 打 Git 标签

---

**最后更新**: 2025-01-04
