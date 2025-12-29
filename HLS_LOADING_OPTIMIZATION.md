# HLS 视频加载优化方案

## 当前配置分析

当前代码中已配置：
- `cache-secs`: 120秒（预缓冲未来120秒）
- `demuxer-max-bytes`: 300MB（最大缓冲）
- `bufferSize`: 32MB（PlayerConfiguration）

## 优化方案

### 方案1：激进预缓冲（推荐用于快速启动）

**目标**：打开视频时立即加载更多内容，减少卡顿

```dart
// 在 _configurePlayerProperties() 中修改：

// 1. 增加初始缓冲大小（从32MB提升到64MB）
PlayerConfiguration(
  bufferSize: 64 * 1024 * 1024, // 64MB
)

// 2. 增加预缓冲时长（从120秒提升到180秒）
await nativePlayer.setProperty('cache-secs', '180');

// 3. 增加最大缓冲大小（从300MB提升到500MB）
await nativePlayer.setProperty('demuxer-max-bytes', '500M');

// 4. 【关键】设置最小缓冲时长（强制加载到指定秒数才开始播放）
await nativePlayer.setProperty('cache-secs-min', '30'); // 至少缓冲30秒才开始播放

// 5. 启用快速预加载
await nativePlayer.setProperty('demuxer-readahead-secs', '60'); // 预读60秒
```

**优点**：
- 启动时加载更多内容，减少后续卡顿
- 适合网络较好的环境

**缺点**：
- 消耗更多流量和内存
- 启动时间可能稍长

---

### 方案2：并发下载优化（提升下载速度）

**目标**：同时下载多个TS分片，加快加载速度

```dart
// 在 _configurePlayerProperties() 中添加：

// 1. 增加HTTP连接数（同时下载多个分片）
await nativePlayer.setProperty('stream-lavf-o',
  'timeout=10000000,reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,reconnect_delay_max=5,http_persistent=1,multiple_requests=1'
);

// 2. 设置HTTP并发连接数（需要MPV支持）
// 注意：MPV可能不支持直接设置并发数，但可以通过以下方式优化：
await nativePlayer.setProperty('http-header-fields', 
  'Connection: keep-alive\r\nAccept-Encoding: identity'
);

// 3. 启用HTTP/2（如果服务器支持）
await nativePlayer.setProperty('stream-lavf-o',
  'timeout=10000000,http_version=2.0'
);
```

**优点**：
- 充分利用带宽
- 下载速度更快

**缺点**：
- 需要服务器支持HTTP/2
- 可能增加服务器负载

---

### 方案3：智能预加载策略（平衡方案）

**目标**：根据网络状况动态调整缓冲策略

```dart
// 新增方法：根据网络速度动态配置
Future<void> _configurePlayerPropertiesByNetwork() async {
  if (kIsWeb) return;
  
  try {
    final nativePlayer = player.platform as NativePlayer?;
    if (nativePlayer == null) return;

    // 检测网络速度（可以通过下载测试或使用网络状态）
    // 这里假设有网络速度检测，实际需要实现网络测速
    
    // 快速网络（WiFi/5G）
    await nativePlayer.setProperty('cache-secs', '180');
    await nativePlayer.setProperty('demuxer-max-bytes', '500M');
    await nativePlayer.setProperty('cache-secs-min', '30');
    
    // 慢速网络（4G/3G）
    // await nativePlayer.setProperty('cache-secs', '60');
    // await nativePlayer.setProperty('demuxer-max-bytes', '200M');
    // await nativePlayer.setProperty('cache-secs-min', '10');
    
  } catch (e) {
    print('⚠️ 网络自适应配置失败: $e');
  }
}
```

---

### 方案4：TS分片预下载（最激进）

**目标**：在播放器加载前，提前下载前N个TS分片

```dart
// 在 HlsService 中新增方法
Future<void> preloadTsSegments({
  required int resourceId,
  required String quality,
  int segmentCount = 5, // 预加载前5个分片
}) async {
  try {
    // 1. 获取m3u8内容
    final m3u8Content = await getHlsStreamContent(resourceId, quality);
    
    // 2. 解析TS分片URL
    final lines = m3u8Content.split('\n');
    final tsUrls = <String>[];
    
    for (var line in lines) {
      if (line.trim().startsWith('http://') || line.trim().startsWith('https://')) {
        tsUrls.add(line.trim());
      }
    }
    
    // 3. 并发下载前N个分片
    final segmentsToPreload = tsUrls.take(segmentCount).toList();
    
    await Future.wait(
      segmentsToPreload.map((url) async {
        try {
          final response = await _dio.get(
            url,
            options: Options(
              responseType: ResponseType.bytes,
            ),
          );
          // 分片会被浏览器/系统缓存，播放器会自动使用缓存
          print('✅ 预加载分片: ${url.split('/').last}');
        } catch (e) {
          print('⚠️ 预加载分片失败: $e');
        }
      }),
    );
    
    print('✅ 预加载完成: ${segmentsToPreload.length} 个分片');
  } catch (e) {
    print('❌ 预加载失败: $e');
  }
}

// 在 VideoPlayerController 的 initialize 中调用
Future<void> initialize({...}) async {
  // ... 现有代码 ...
  
  // 【新增】在加载视频前预加载TS分片
  await _hlsService.preloadTsSegments(
    resourceId: resourceId,
    quality: currentQuality.value!,
    segmentCount: 5, // 预加载前5个分片
  );
  
  await _loadVideo(currentQuality.value!, ...);
}
```

**优点**：
- 启动速度最快
- 分片已缓存，播放流畅

**缺点**：
- 实现复杂
- 需要解析m3u8
- 可能浪费流量（如果用户不播放）

---

### 方案5：混合方案（推荐）

**结合方案1 + 方案4**，既配置播放器参数，又预加载分片：

```dart
// 1. 修改 PlayerConfiguration
PlayerConfiguration(
  bufferSize: 64 * 1024 * 1024, // 64MB
  // ... 其他配置
)

// 2. 修改 _configurePlayerProperties
await nativePlayer.setProperty('cache-secs', '180');
await nativePlayer.setProperty('demuxer-max-bytes', '500M');
await nativePlayer.setProperty('cache-secs-min', '30'); // 至少缓冲30秒
await nativePlayer.setProperty('demuxer-readahead-secs', '60');

// 3. 在 initialize 中预加载分片
await _hlsService.preloadTsSegments(
  resourceId: resourceId,
  quality: currentQuality.value!,
  segmentCount: 3, // 预加载前3个分片即可
);
```

---

## 实施建议

### 优先级排序：

1. **方案1（激进预缓冲）** - 最简单，效果明显
   - 修改 `bufferSize` 和 `cache-secs`
   - 立即见效

2. **方案4（TS分片预下载）** - 效果最好，但需要实现
   - 需要解析m3u8和并发下载
   - 启动速度提升最明显

3. **方案2（并发下载）** - 需要服务器支持
   - 如果服务器支持HTTP/2，效果很好

4. **方案3（智能预加载）** - 长期优化
   - 需要网络检测
   - 用户体验最好

### 推荐配置值：

```dart
// 快速启动配置
bufferSize: 64 * 1024 * 1024  // 64MB
cache-secs: 180                // 预缓冲180秒
demuxer-max-bytes: 500M        // 最大500MB
cache-secs-min: 30             // 至少缓冲30秒才开始播放
demuxer-readahead-secs: 60     // 预读60秒
```

---

## 注意事项

1. **流量消耗**：激进预缓冲会消耗更多流量，建议：
   - WiFi环境：使用激进配置
   - 移动网络：使用保守配置

2. **内存占用**：大缓冲会占用更多内存，注意：
   - 低端设备可能需要降低配置
   - 监控内存使用情况

3. **服务器压力**：并发下载会增加服务器负载，建议：
   - 限制并发数
   - 添加CDN支持

4. **用户体验**：平衡启动速度和流畅度：
   - 启动时间 vs 缓冲时间
   - 流量消耗 vs 播放流畅度


