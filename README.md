# Alnitak Flutter

基于 Flutter 构建的全功能视频平台客户端，支持 DASH (fMP4) / M3U8 流媒体播放、多清晰度切换、弹幕、后台播放等特性。

## 项目概述

- **Flutter SDK**: 3.35.7 / Dart 3.9.2
- **视频引擎**: media_kit (libmpv)
- **状态管理**: 原生 Flutter（ChangeNotifier / ValueNotifier / setState）
- **后端**: Alnitak Server（Go，配套 DASH 转码服务）

## 核心功能

### 视频播放
- DASH SegmentBase (fMP4) 流媒体播放，支持 HTTP Range seek
- M3U8 (HLS) 兼容回退
- 多清晰度切换（360P / 480P / 720P / 1080P / 1080P60 / 2K / 4K）
- 播放进度记忆与云端同步
- 循环播放模式
- 后台音视频播放（Android audio_service）
- 硬解码 / 软解码可切换

### 播放器
- 自定义播放器 UI（手势控制亮度、音量、进度）
- 全屏 / 非全屏模式，横竖屏自适应
- 双击暂停 / 播放，长按加速
- 播放速度调节
- 分P选集列表（列表 / 网格视图）
- 自动连播（分集 → 合集 → 推荐）
- 弹幕实时显示与发送

### 社区功能
- 评论系统（分页、楼中楼、点赞、时间戳跳转）
- 表情包选择器
- 视频点赞、收藏、分享
- 关注 / 粉丝
- 用户空间
- 在线人数实时显示（WebSocket）

### 内容管理
- 视频投稿（分片上传、断点续传、秒传、多分P）
- 文章投稿
- 搜索功能
- 消息通知 / 私信
- 播放历史

### 系统特性
- Material Design 3 + 深色 / 浅色 / 跟随系统主题
- 响应式布局（宽屏双栏，窄屏单栏）
- HTTPS 可选
- 电池优化引导（后台播放）
- 缓存管理（自动清理、退出即清、大小限制）

## 技术架构

### 核心依赖
| 组件 | 库 | 说明 |
|------|-----|------|
| 视频播放 | media_kit ^1.1.10 | 基于 libmpv 的跨平台播放器 |
| 网络请求 | dio ^5.4.0 | 带 AuthInterceptor + RetryInterceptor (10 retries) |
| 图片缓存 | cached_network_image ^3.3.1 | 内存 + 磁盘双层缓存 |
| 本地存储 | shared_preferences ^2.2.0 | 设置、进度等轻量数据 |
| 安全存储 | flutter_secure_storage | Token 安全存储 |
| 后台播放 | audio_service | Android 后台音视频服务 |

### 项目结构
```
lib/
├── main.dart                         # 应用入口
├── config/
│   └── api_config.dart               # API 地址、HTTPS 配置
├── controllers/
│   ├── video_player_controller.dart   # 播放器核心逻辑 (ChangeNotifier)
│   └── danmaku_controller.dart        # 弹幕系统控制器
├── models/                            # 数据模型
│   ├── dash_models.dart              # DASH MPD 解析模型
│   ├── video_detail.dart             # 视频详情
│   ├── comment.dart                  # 评论
│   └── ...
├── pages/
│   ├── main_page.dart                # 主页面（底部导航）
│   ├── home_page.dart                # 首页（双列视频列表）
│   ├── settings_page.dart            # 设置页面
│   ├── search_page.dart              # 搜索
│   ├── video/
│   │   ├── video_play_page.dart      # 视频播放页面（进度/生命周期）
│   │   └── widgets/
│   │       ├── media_player_widget.dart   # 播放器组件
│   │       ├── custom_player_ui.dart      # 自定义播放器控制 UI
│   │       ├── comment_preview_card.dart  # 评论预览（YouTube 风格）
│   │       ├── part_list.dart             # 分集列表
│   │       ├── collection_list.dart       # 合集列表
│   │       └── recommend_list.dart        # 推荐列表
│   ├── upload/                        # 投稿（视频/文章）
│   ├── message/                       # 消息/私信
│   └── user/                          # 用户空间
├── services/
│   ├── video_stream_service.dart      # DASH 清单加载 + M3U8 回退
│   ├── cache_service.dart             # 播放器缓存清理
│   ├── history_service.dart           # 进度保存/恢复（服务端+本地）
│   ├── video_service.dart             # 视频业务 API
│   ├── auth_service.dart              # 认证服务
│   ├── danmaku_service.dart           # 弹幕 API
│   ├── online_websocket_service.dart  # 在线人数 WebSocket
│   ├── audio_service_handler.dart     # 后台播放服务
│   └── ...
├── utils/
│   ├── quality_utils.dart             # 清晰度排序/标签/匹配
│   ├── http_client.dart               # Dio 单例 + 拦截器
│   ├── token_manager.dart             # Token 自动刷新
│   └── ...
├── widgets/                           # 通用组件
│   ├── danmaku_overlay.dart           # 弹幕浮层
│   ├── video_card.dart                # 视频卡片
│   └── ...
└── theme/                             # 主题系统
    ├── app_theme.dart
    ├── app_colors.dart
    └── theme_extensions.dart
```

### mpv 播放器配置

针对 DASH fMP4 双流（video.m4s + audio.m4s）优化：

```dart
'hr-seek'              = 'yes'           // 双独立流精确 seek
'demuxer-lavf-o'       = 'fflags=+discardcorrupt'  // 容错，丢弃损坏帧
'demuxer-max-back-bytes' = '0'           // 禁止 demuxer 回退读取 (修复 PTS 回溯)
'network-timeout'      = '10'
'hwdec'                = <用户选择>       // 硬解/软解
// Android: 'volume-max' = '100'
```

详细分析见 [docs/fmp4_pts_analysis.md](docs/fmp4_pts_analysis.md)。

## 构建说明

### 环境要求
- Flutter SDK: 3.35.7+
- Dart SDK: 3.9.2+
- Android: minSdk 21, targetSdk 34, Java 11+, Kotlin 1.9.0+

### 编译

```bash
# Debug
flutter run -d <device_id>

# Release（推荐分架构编译）
flutter build apk --release --split-per-abi

# Release（通用包）
flutter build apk --release
```

### 重要配置

如果项目和 Flutter SDK / Pub Cache 在不同盘符（如 C: 和 E:），需在 `android/gradle.properties` 中禁用 Kotlin 增量编译：

```properties
kotlin.incremental=false
kotlin.incremental.java=false
kotlin.caching.enabled=false
```

## 技术文档

| 文档 | 说明 |
|------|------|
| [fMP4 PTS 分析](docs/fmp4_pts_analysis.md) | 视频 PTS 回溯问题分析：nvenc 关键帧修复、demuxer 回退修复、B站/YouTube fMP4 结构对比 |
| [开发进度](docs/开发进度.md) | 功能开发进度跟踪 |

## 已知问题与解决方案

| 问题 | 解决方案 |
|------|----------|
| Kotlin 编译跨盘符报错 | 禁用 Kotlin 增量编译 |
| libmpv.so 找不到 | 确保 `media_kit_libs_video` 已添加到 pubspec.yaml |
| fMP4 播放 PTS 回溯 | 服务端：nvenc 用 `-no-scenecut 1 -forced-idr 1`；客户端：`demuxer-max-back-bytes=0` |
| 后台播放被系统杀死 | 引导用户关闭电池优化（设置页自动跳转） |

## 许可证

本项目仅供学习交流使用。

## 贡献者

- 开发者: acgkiss
- 技术支持: Claude AI & acgkiss

---

**最后更新**: 2026-03-06
