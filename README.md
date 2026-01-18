# Alnitak Flutter - 视频播放应用

一个基于 Flutter 开发的视频播放应用,支持 HLS 流媒体播放、清晰度切换、全屏播放等功能。

## 📱 项目概述

- **项目名称**: Alnitak Flutter
- **版本**: 1.0.0+1
- **Flutter SDK**: 3.9.2
- **开发语言**: Dart
- **总代码行数**: 约 4,353 行

## ✨ 核心功能
## 功能特性

### ✅ 已实现
- 🏠 双列布局首页（参考哔哩哔哩国际版）
- 📱 底部导航栏（首页、动态、投稿、消息、我的）
- 🎬 热门视频列表展示
- 📄 分页加载（滚动到底部自动加载更多）
- 🖼️ 视频卡片展示（封面、标题、作者、播放数、时长等）
- 🌐 API 对接（热门视频接口）
- 🔐 **用户登录/注册**
  - 账号密码登录
  - 邮箱验证码注册
  - 图形验证码支持
  - Token 自动刷新机制
- 🎥 **视频播放页面**
  - 视频播放器（HLS 流媒体、多清晰度切换）
  - 作者信息卡片（头像、名字、粉丝数、关注按钮）
  - 视频信息展示（标题、播放量、弹幕数、上传时间、在线人数）
  - 三大操作按钮（点赞、收藏、分享）
  - 分集列表支持（列表/网格视图切换、自动连播）
  - 视频推荐区域（相关推荐、自动连播）
  - 播放进度记忆与上报
  - 响应式布局（宽屏左右两栏，窄屏单栏）
- 💬 **评论系统**
  - 评论列表展示（支持分页加载）
  - 发送评论/回复评论
  - 二级评论（楼中楼）
  - 评论点赞
  - 评论时间戳跳转（点击时间戳跳转到视频对应位置）
  - 表情包选择器（支持深色/浅色主题）
  - 评论预览卡片（YouTube 风格）
- 🎯 **弹幕功能**
  - 实时弹幕显示
  - 弹幕发送
  - 弹幕开关控制
- 📤 **视频投稿**
  - 视频上传（分片上传、断点续传、秒传）
  - 封面上传
  - 多分P支持
  - Token 自动刷新
- 👤 **个人中心**
  - 用户信息展示
  - 用户空间页面
  - 关注/粉丝列表

### 🚧 开发中
- 搜索功能
- 消息通知
- 动态功能

## 项目结构



### 🎬 视频播放
- ✅ HLS (M3U8) 流媒体播放
- ✅ 多清晰度切换(360P/480P/720P/1080P/4K 等)
- ✅ 友好的清晰度名称显示
- ✅ 播放进度保存和恢复
- ✅ 播放历史记录同步

### 📺 播放器功能
- ✅ 全屏/非全屏模式切换
- ✅ 横竖屏自动适配
- ✅ 手势控制(亮度、音量、进度)
- ✅ 双击暂停/播放
- ✅ 播放速度调节
- ✅ 画质自适应

### 🎨 界面特性
- ✅ Material Design 3 设计
- ✅ 自定义播放器控制栏
- ✅ 视频信息卡片展示
- ✅ 作者信息展示
- ✅ 分P选集列表
- ✅ 推荐视频列表
- ✅ 视频操作按钮(点赞、收藏、分享等)

## 🏗️ 技术架构

### 核心技术栈
- **UI 框架**: Flutter 3.35.7
- **视频播放**: media_kit (基于 AndroidX Media3)
  - `media_kit`: ^1.1.10 - 核心播放器
  - `media_kit_video`: ^1.2.4 - 视频 UI 组件
  - `media_kit_libs_video`: ^1.0.4 - 原生 libmpv 库
- **网络请求**:
  - `http`: ^1.2.0 - HTTP 客户端
  - `dio`: ^5.4.0 - 高级网络库（带重试机制）
- **图片缓存**: `cached_network_image`: ^3.3.1 - 网络图片缓存
- **本地存储**:
  - `shared_preferences`: ^2.2.0 - 轻量级键值存储
  - `path_provider`: ^2.1.1 - 路径获取
- **分享功能**: `share_plus`: ^7.2.0
- **国际化**: `intl`: ^0.18.1

### 项目结构
```
lib/
├── main.dart                      # 应用入口
├── models/                        # 数据模型
│   ├── api_response.dart         # API 响应封装
│   ├── video_api_model.dart      # 视频 API 模型
│   ├── video_detail.dart         # 视频详情模型
│   └── video_item.dart           # 视频列表项模型
├── pages/                         # 页面
│   ├── main_page.dart            # 主页面(底部导航)
│   ├── home_page.dart            # 首页(视频列表)
│   ├── profile_page.dart         # 个人中心
│   └── video/                    # 视频播放相关
│       ├── video_play_page.dart  # 视频播放页面
│       └── widgets/              # 视频页面组件
│           ├── media_player_widget.dart    # 视频播放器组件(706行)
│           ├── author_card.dart           # 作者信息卡片
│           ├── part_list.dart             # 分P列表
│           ├── recommend_list.dart        # 推荐列表
│           ├── video_action_buttons.dart  # 视频操作按钮
│           └── video_info_card.dart       # 视频信息卡片
├── services/                      # 业务服务
│   ├── hls_service.dart          # HLS 流处理服务
│   ├── logger_service.dart       # 日志服务
│   ├── video_api_service.dart    # 视频 API 服务
│   └── video_service.dart        # 视频业务服务
├── utils/                         # 工具类
│   ├── http_client.dart          # HTTP 客户端封装
│   └── image_utils.dart          # 图片工具类
└── widgets/                       # 通用组件
    └── video_card.dart           # 视频卡片组件
```

## 🎯 核心组件说明

### MediaPlayerWidget (视频播放器)
位置: `lib/pages/video/widgets/media_player_widget.dart`

核心功能:
- **HLS 流处理**: 自动下载并解析 M3U8 文件,转换为本地可访问的播放地址
- **清晰度切换**: 支持多种清晰度无缝切换,保持播放进度
- **全屏管理**: 自动处理横竖屏切换和系统 UI 显示/隐藏
- **播放状态管理**: 完整的播放器生命周期管理(初始化、播放、暂停、销毁)
- **进度同步**: 定期向服务器同步播放进度

关键配置:
```dart
MaterialVideoControlsTheme(
  seekBarMargin: EdgeInsets.only(bottom: 44),        // 进度条位置
  bottomButtonBarMargin: EdgeInsets.only(bottom: 0), // 控制按钮位置
  displaySeekBar: true,                              // 显示进度条
  automaticallyImplySkipNextButton: false,           // 隐藏下一集按钮
  automaticallyImplySkipPreviousButton: false,       // 隐藏上一集按钮
)
```

### HlsService (HLS 流处理)
位置: `lib/services/hls_service.dart`

功能:
- 下载 M3U8 文件并解析
- 转换相对路径为绝对 URL
- 缓存处理的 M3U8 文件到本地
- 提供本地文件路径供播放器使用

### VideoService (视频业务服务)
位置: `lib/services/video_service.dart`

功能:
- 获取视频详情信息
- 获取视频资源和清晰度列表（指的是播放器）
- 播放进度管理（指的是播放器）
- 历史记录管理（指的是播放器）

## 🛠️ 构建说明

### 环境要求
- Flutter SDK: 3.35.7
- Dart SDK: 3.9.2
- Android: 
  - minSdk: 21
  - targetSdk: 34
  - Java: 11+
  - Kotlin: 1.9.0+

### 编译命令

#### Debug 版本
```bash
flutter run -d <device_id>
```

#### Release 版本 (推荐 - 分架构编译)
```bash
flutter build apk --release --split-per-abi
```

生成的 APK 文件:
- `app-armeabi-v7a-release.apk` (25.7MB) - 32位 ARM 设备
- `app-arm64-v8a-release.apk` (28.9MB) - 64位 ARM 设备(推荐)
- `app-x86_64-release.apk` (33.3MB) - x86_64 设备/模拟器

#### Release 版本 (通用包)
```bash
flutter build apk --release
```

### 重要配置说明

#### Gradle 配置 (`android/gradle.properties`)
```properties
# 禁用 Kotlin 增量编译(解决跨盘符路径问题)
kotlin.incremental=false
kotlin.incremental.java=false
kotlin.caching.enabled=false
org.gradle.caching=false

# JVM 内存配置
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G -XX:+HeapDumpOnOutOfMemoryError

# AndroidX 支持
android.useAndroidX=true
android.enableJetifier=true
```

> ⚠️ **注意**: 如果项目和 Flutter SDK/Pub Cache 在不同盘符,必须禁用 Kotlin 增量编译,否则会出现编译错误。

## 📡 API 接口

后端 API 地址: `http://anime.ayypd.cn:3000`

主要接口:
- `GET /api/v1/video/getHotVideo` - 获取热门视频列表
- `GET /api/v1/video/getVideoById` - 获取视频详情
- `GET /api/v1/video/getResourceQuality` - 获取视频清晰度列表
- `GET /api/v1/video/getVideoFile` - 获取视频播放地址
- `GET /api/v1/video/getRelatedVideoList` - 获取相关推荐
- `POST /api/v1/history/video/addHistory` - 添加播放历史
- `GET /api/v1/history/video/getProgress` - 获取播放进度

## 🐛 已知问题与解决方案

### 1. Kotlin 编译错误
**问题**: 跨盘符(C: 和 E:)编译时出现 `IllegalArgumentException: this and base files have different roots`

**解决方案**: 在 `android/gradle.properties` 中禁用 Kotlin 增量编译

### 2. libmpv.so 找不到
**问题**: 运行时报错 `Cannot find libmpv.so`

**解决方案**: 确保 `media_kit_libs_video` 依赖已正确添加到 `pubspec.yaml`

### 3. 全屏播放黑屏
**问题**: 切换全屏后画面不显示

**解决方案**: 已通过正确配置 `SystemChrome` 和 Widget 生命周期管理解决

### 4. 弱网环境播放卡顿
**问题**: 网络不稳定时视频加载失败或图片加载缓慢

**解决方案**: 已实施网络优化，详见 [NETWORK_OPTIMIZATION.md](NETWORK_OPTIMIZATION.md)
- ✅ HTTP 请求自动重试机制（最多3次）
- ✅ 超时时间优化（15s 连接，30s 接收）
- ✅ 图片智能缓存（内存+磁盘双层缓存）
- ✅ HLS 分片下载自动重试

## 📦 依赖说明

### 核心依赖
- **media_kit**: AndroidX Media3 的 Flutter 封装,提供强大的视频播放能力
  - 支持 HLS、MP4、WebM 等多种格式
  - 内置缓冲管理和自适应码率
  - 原生性能优化

### 清理的旧依赖
以下文件已从项目中移除(使用 media_kit 原生控件替代):
- ❌ `player_controller_state.dart` - 旧播放器状态管理
- ❌ `player_gesture_detector.dart` - 旧手势检测
- ❌ `player_top_bar.dart` - 旧顶部控制栏
- ❌ `player_bottom_bar.dart` - 旧底部控制栏
- ❌ `media_progress_slider.dart` - 旧进度条

## 🚀 开发指南

### 调试日志
项目使用 `logger_service.dart` 提供统一的日志输出:
```dart
LoggerService.debug('日志消息');
LoggerService.error('错误消息', error: e, stackTrace: st);
```

日志输出格式:
- 🔍 DEBUG - 调试信息
- ⚠️ WARNING - 警告信息
- ❌ ERROR - 错误信息
- 📹 - 视频播放相关日志

### 添加新视频源
1. 在 `VideoService` 中添加新的 API 调用
2. 更新 `VideoDetailModel` 以支持新字段
3. 修改 `HlsService` 以处理不同的流格式(如需要)
4. 更新 UI 组件以展示新数据

### 自定义播放器样式
修改 `media_player_widget.dart` 中的 `MaterialVideoControlsTheme`:
```dart
MaterialVideoControlsTheme(
  seekBarMargin: EdgeInsets.only(bottom: 44),  // 调整进度条位置
  bottomButtonBarMargin: EdgeInsets.only(bottom: 0),  // 调整按钮位置
  seekBarColor: Colors.blue,  // 进度条颜色
  // ... 更多配置项
)
```

## 📝 版本历史

### v1.1.0 (2025-01-18)
- ✅ 投稿功能 Token 刷新统一（使用 TokenManager）
- ✅ 修复评论区表情包 emoji_picker_flutter 3.x API 兼容问题
- ✅ 表情选择器深色/浅色主题适配
- ✅ 回复二级评论自动添加 @用户名 前缀
- ✅ 发送评论后自动关闭表情面板
- ✅ 评论预览卡片深色模式适配
- ✅ 修复合集（分P）自动连播功能
- ✅ 修复推荐列表自动连播功能

### v1.0.0 (2025-01-04)
- ✅ 初始版本发布
- ✅ 实现基础视频播放功能
- ✅ 支持 HLS 流媒体播放
- ✅ 清晰度切换功能
- ✅ 全屏播放支持
- ✅ 播放历史和进度同步
- ✅ 解决 Kotlin 编译跨盘符问题
- ✅ 优化播放器控件位置

## 🔗 相关链接

- [Flutter 官方文档](https://flutter.dev/docs)
- [media_kit GitHub](https://github.com/alexmercerind/media_kit)
- [Material Design 3](https://m3.material.io/)

## 📄 许可证

本项目仅供学习交流使用。

## 👥 贡献者

- 开发者: acgkiss
- 技术支持: Claude AI&acgkiss

---

**最后更新**: 2025-01-18
