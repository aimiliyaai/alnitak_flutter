import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 自定义缓存管理器 - 使用稳定的缓存 key 避免重复缓存
///
/// 当 URL 包含时间戳等变化参数时，提取基础 URL 作为缓存 key
/// 这样即使 URL 变化，也会覆盖旧缓存而不是创建新缓存
class SmartCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'smartImageCache';

  static final SmartCacheManager _instance = SmartCacheManager._();
  factory SmartCacheManager() => _instance;

  SmartCacheManager._() : super(
    Config(
      key,
      stalePeriod: const Duration(days: 7), // 7天后过期
      maxNrOfCacheObjects: 200, // 最多缓存200个文件
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );

  /// 从 URL 提取稳定的缓存 key
  /// 移除时间戳、随机数等变化参数
  static String getStableCacheKey(String url) {
    try {
      final uri = Uri.parse(url);
      // 移除常见的缓存破坏参数
      final cleanParams = Map<String, String>.from(uri.queryParameters)
        ..remove('t')
        ..remove('time')
        ..remove('timestamp')
        ..remove('_t')
        ..remove('_')
        ..remove('random')
        ..remove('r')
        ..remove('v')
        ..remove('version');

      // 重建 URL（不含变化参数）
      final cleanUri = uri.replace(queryParameters: cleanParams.isEmpty ? null : cleanParams);
      return cleanUri.toString();
    } catch (e) {
      // 解析失败时使用原 URL
      return url;
    }
  }
}

/// 带缓存的网络图片组件
///
/// 自动处理图片加载、缓存、错误和占位符
/// 【优化】使用稳定的缓存 key，避免 URL 变化导致的重复缓存
class CachedImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;
  /// 自定义缓存 key（可选）
  /// 如果提供，将使用此 key 而不是从 URL 提取
  final String? cacheKey;

  const CachedImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.cacheKey,
  });

  @override
  Widget build(BuildContext context) {
    // 使用自定义 key 或从 URL 提取稳定 key
    final effectiveCacheKey = cacheKey ?? SmartCacheManager.getStableCacheKey(imageUrl);

    Widget imageWidget = CachedNetworkImage(
      imageUrl: imageUrl,
      cacheKey: effectiveCacheKey, // 【关键】使用稳定的缓存 key
      cacheManager: SmartCacheManager(), // 使用自定义缓存管理器
      fit: fit ?? BoxFit.cover,
      width: width,
      height: height,
      placeholder: placeholder != null
          ? (context, url) => placeholder!
          : (context, url) => Container(
                color: Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
      errorWidget: errorWidget != null
          ? (context, url, error) => errorWidget!
          : (context, url, error) => Container(
                color: Colors.grey[300],
                child: const Icon(
                  Icons.broken_image,
                  color: Colors.grey,
                ),
              ),
      // 优化缓存策略
      memCacheWidth: 800, // 限制内存缓存宽度
      maxHeightDiskCache: 1000, // 限制磁盘缓存高度
      maxWidthDiskCache: 1000, // 限制磁盘缓存宽度
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}

/// 圆形头像图片组件
/// 【优化】使用稳定的缓存 key，避免头像 URL 变化导致的重复缓存
class CachedCircleAvatar extends StatelessWidget {
  final String imageUrl;
  final double radius;
  final Widget? placeholder;
  final Widget? errorWidget;
  /// 自定义缓存 key（可选）
  /// 推荐使用用户 ID 作为缓存 key，这样头像更新时会自动覆盖旧缓存
  final String? cacheKey;

  const CachedCircleAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 20,
    this.placeholder,
    this.errorWidget,
    this.cacheKey,
  });

  @override
  Widget build(BuildContext context) {
    // 使用自定义 key 或从 URL 提取稳定 key
    final effectiveCacheKey = cacheKey ?? SmartCacheManager.getStableCacheKey(imageUrl);

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[200],
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          cacheKey: effectiveCacheKey, // 【关键】使用稳定的缓存 key
          cacheManager: SmartCacheManager(), // 使用自定义缓存管理器
          fit: BoxFit.cover,
          width: radius * 2,
          height: radius * 2,
          placeholder: placeholder != null
              ? (context, url) => placeholder!
              : (context, url) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          errorWidget: errorWidget != null
              ? (context, url, error) => errorWidget!
              : (context, url, error) => Icon(
                    Icons.person,
                    size: radius,
                    color: Colors.grey,
                  ),
          memCacheWidth: (radius * 2 * 2).toInt(), // 2x for retina
          maxHeightDiskCache: (radius * 2 * 2).toInt(),
          maxWidthDiskCache: (radius * 2 * 2).toInt(),
        ),
      ),
    );
  }
}
