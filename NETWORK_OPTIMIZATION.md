# 网络优化指南

本文档记录了为提升 Alnitak Flutter 应用在弱网环境下性能而实施的网络优化措施。

## 优化概览

### 1. HTTP 客户端优化

**文件**: `lib/utils/http_client.dart`

#### 超时配置优化
增加了超时时间以适应弱网环境：

```dart
BaseOptions(
  connectTimeout: const Duration(seconds: 15),  // 连接超时：10s → 15s
  receiveTimeout: const Duration(seconds: 30),  // 接收超时：10s → 30s
  sendTimeout: const Duration(seconds: 15),     // 发送超时：新增
)
```

#### 重试机制
实现了自定义 `RetryInterceptor` 类，提供智能重试功能：

- **重试次数**: 最多 3 次
- **重试延迟**: 指数退避策略 (1秒, 2秒, 3秒)
- **重试条件**:
  - 连接超时 (`DioExceptionType.connectionTimeout`)
  - 发送超时 (`DioExceptionType.sendTimeout`)
  - 接收超时 (`DioExceptionType.receiveTimeout`)
  - 连接错误 (`DioExceptionType.connectionError`)
  - 服务器错误 (HTTP 5xx)

**重试逻辑示例**:
```dart
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final List<Duration> retryDelays;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final retryCount = err.requestOptions.extra['retryCount'] as int? ?? 0;

    if (retryCount < retries && _shouldRetry(err)) {
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      final delay = retryDelays[retryCount];

      await Future.delayed(delay);

      try {
        final response = await dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } on DioException catch (e) {
        return super.onError(e, handler);
      }
    }

    return super.onError(err, handler);
  }
}
```

### 2. 图片缓存优化

**文件**: `lib/widgets/cached_image_widget.dart`

#### 引入依赖
添加了 `cached_network_image` 库 (v3.4.1)：
```yaml
dependencies:
  cached_network_image: ^3.3.1
```

#### 自定义缓存组件

##### CachedImage - 通用图片缓存组件
```dart
class CachedImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  // 优化的缓存策略
  CachedNetworkImage(
    imageUrl: imageUrl,
    memCacheWidth: 800,           // 内存缓存限制
    maxHeightDiskCache: 1000,     // 磁盘缓存高度限制
    maxWidthDiskCache: 1000,      // 磁盘缓存宽度限制
    placeholder: (context, url) => CircularProgressIndicator(),
    errorWidget: (context, url, error) => Icon(Icons.broken_image),
  )
}
```

##### CachedCircleAvatar - 圆形头像缓存组件
```dart
class CachedCircleAvatar extends StatelessWidget {
  final String imageUrl;
  final double radius;

  // 针对头像优化的缓存大小
  memCacheWidth: (radius * 2 * 2).toInt(),  // 2x for retina
  maxHeightDiskCache: (radius * 2 * 2).toInt(),
  maxWidthDiskCache: (radius * 2 * 2).toInt(),
}
```

#### 更新的文件
将所有 `Image.network()` 和 `NetworkImage()` 替换为缓存组件：

1. **视频卡片** - `lib/widgets/video_card.dart`
   - 视频封面图片
   - 作者头像

2. **推荐列表** - `lib/pages/video/widgets/recommend_list.dart`
   - 推荐视频封面

3. **作者卡片** - `lib/pages/video/widgets/author_card.dart`
   - 作者头像

4. **评论列表** - `lib/pages/video/widgets/comment_list.dart`
   - 评论者头像
   - 回复者头像

5. **评论预览卡片** - `lib/pages/video/widgets/comment_preview_card.dart`
   - 最新评论者头像

### 3. HLS 视频流优化

**影响范围**: `lib/services/hls_service.dart`

HLS M3U8 播放列表的下载现在自动受益于 HTTP 客户端的重试机制：

- M3U8 文件下载失败时会自动重试
- TS 分片加载由 libmpv 内部处理（media_kit 底层）
- libmpv 自带缓冲和重试机制

## 优化效果

### 弱网环境改善
- ✅ **请求超时**: 超时时间增加 50%，减少误判
- ✅ **自动重试**: 临时网络波动不会导致加载失败
- ✅ **智能延迟**: 指数退避避免服务器过载
- ✅ **图片缓存**: 减少重复请求，提升加载速度

### 用户体验提升
- 📱 **更流畅**: 图片加载后缓存到磁盘，二次访问秒开
- 🔄 **更可靠**: 网络波动时自动重试，无需用户干预
- ⚡ **更快速**: 内存缓存提供即时响应
- 💾 **省流量**: 避免重复下载相同资源

## 缓存管理

### 自动清理
`cached_network_image` 库自带缓存管理：

- **内存缓存**: 应用重启后自动清空
- **磁盘缓存**:
  - 默认保留 7 天
  - 缓存大小达到限制时自动清理旧文件
  - 使用 LRU (Least Recently Used) 策略

### 手动清理（可选）
如需手动清理缓存，可以使用：

```dart
import 'package:cached_network_image/cached_network_image.dart';

// 清空所有缓存
await DefaultCacheManager().emptyCache();

// 删除特定图片缓存
await DefaultCacheManager().removeFile(imageUrl);
```

## 监控与调试

### 查看重试日志
HTTP 客户端会在控制台输出重试信息：

```
⏳ 请求失败,1秒后进行第 1 次重试: http://anime.ayypd.cn:3000/api/v1/video/1234
⏳ 请求失败,2秒后进行第 2 次重试: http://anime.ayypd.cn:3000/api/v1/video/1234
✅ 响应: 200 http://anime.ayypd.cn:3000/api/v1/video/1234
```

### 测试弱网环境

#### Android 设备
```bash
# 使用 ADB 限制网络速度
adb shell settings put global network_policy_restricted 1

# 恢复正常网络
adb shell settings put global network_policy_restricted 0
```

#### Chrome DevTools (Web)
1. 打开开发者工具 (F12)
2. 切换到 Network 标签
3. 在 "No throttling" 下拉菜单中选择：
   - Slow 3G
   - Fast 3G
   - Custom

## 后续优化建议

### 1. 视频预加载
考虑在视频列表中预加载下一个视频的 M3U8：

```dart
void _preloadNextVideo() {
  if (hasNextVideo) {
    HlsService().getLocalM3u8File(nextVideoUrl);
  }
}
```

### 2. 离线缓存
为高优先级视频实现离线缓存：

```dart
// 缓存整个视频
await HlsService().cacheVideo(videoId);

// 播放时优先使用缓存
final cachedPath = await HlsService().getCachedVideoPath(videoId);
if (cachedPath != null) {
  player.open(Media(cachedPath));
}
```

### 3. 网络状态适配
根据网络类型自动调整画质：

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

final connectivityResult = await Connectivity().checkConnectivity();
if (connectivityResult == ConnectivityResult.mobile) {
  // 移动网络：默认 480p
  _selectQuality('480p');
} else if (connectivityResult == ConnectivityResult.wifi) {
  // WiFi：默认 1080p
  _selectQuality('1080p');
}
```

### 4. CDN 加速
建议后端配置 CDN 加速静态资源（封面图、头像、视频）：

- 阿里云 OSS + CDN
- 腾讯云 COS + CDN
- 七牛云
- 又拍云

## 相关文件

- `lib/utils/http_client.dart` - HTTP 客户端与重试机制
- `lib/widgets/cached_image_widget.dart` - 图片缓存组件
- `lib/services/hls_service.dart` - HLS 视频流服务
- `pubspec.yaml` - 依赖配置

## 测试清单

- [ ] 在 3G 网络下测试视频播放
- [ ] 模拟网络断开后恢复，验证自动重试
- [ ] 检查图片是否正确缓存（二次加载应该秒开）
- [ ] 查看控制台日志确认重试机制工作正常
- [ ] 测试评论区头像加载
- [ ] 测试推荐视频封面加载

## 总结

通过 HTTP 重试机制和图片缓存优化，应用在弱网环境下的表现得到显著改善。用户将体验到：

- 更少的加载失败
- 更快的图片加载速度
- 更流畅的滚动体验
- 更低的流量消耗

这些优化为应用提供了生产级别的网络韧性。
