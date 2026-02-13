import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../utils/redirect_http_service.dart';

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
      stalePeriod: const Duration(days: 30), // 【优化】30天后过期，减少重复下载
      maxNrOfCacheObjects: 2000, // 【优化】缓存2000个文件
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: RedirectAwareHttpFileService(), // 使用支持重定向的服务
    ),
  );

  /// 预加载图片到缓存
  /// 用于提前加载即将显示的图片
  static Future<void> preloadImage(String url, {String? cacheKey}) async {
    try {
      final effectiveKey = cacheKey ?? getStableCacheKey(url);
      await _instance.getSingleFile(url, key: effectiveKey);
    } catch (_) {}
  }

  /// 批量预加载图片
  static Future<void> preloadImages(List<String> urls) async {
    // 并发预加载，但限制并发数为5
    final futures = <Future>[];
    for (int i = 0; i < urls.length; i++) {
      futures.add(preloadImage(urls[i]));
      // 每5个并发一组
      if (futures.length >= 5) {
        await Future.wait(futures);
        futures.clear();
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

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

/// 安全地将 double 转换为 int，处理 Infinity 和 NaN
int? _safeToInt(double? value) {
  if (value == null || value.isNaN || value.isInfinite) {
    return null;
  }
  return value.toInt();
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
      // 【优化】极短的淡入时间，几乎立即显示
      fadeInDuration: const Duration(milliseconds: 50),
      fadeOutDuration: Duration.zero,
      // 加载中：带闪烁动画的骨架屏
      placeholder: placeholder != null
          ? (context, url) => placeholder!
          : (context, url) => _ShimmerPlaceholder(
                width: width,
                height: height,
              ),
      errorWidget: errorWidget != null
          ? (context, url, error) => errorWidget!
          : (context, url, error) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Container(
                color: isDark ? const Color(0xFF3C3C3C) : Colors.grey[300],
                child: Icon(
                  Icons.broken_image,
                  color: isDark ? const Color(0xFF808080) : Colors.grey,
                ),
              );
            },
      // 根据实际显示尺寸缓存（防止 Infinity/NaN 导致崩溃）
      memCacheWidth: _safeToInt(width),
      memCacheHeight: _safeToInt(height),
      maxHeightDiskCache: 800,
      maxWidthDiskCache: 800,
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

/// 静态骨架屏占位符（性能优化：移除动画，减少CPU消耗）
/// 多个图片同时加载时，静态占位符比闪烁动画性能更好
class _ShimmerPlaceholder extends StatelessWidget {
  final double? width;
  final double? height;

  const _ShimmerPlaceholder({this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[200],
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CircleAvatar(
      radius: radius,
      backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[200],
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          cacheKey: effectiveCacheKey, // 【关键】使用稳定的缓存 key
          cacheManager: SmartCacheManager(), // 使用自定义缓存管理器
          fit: BoxFit.cover,
          width: radius * 2,
          height: radius * 2,
          // 【优化】极短的淡入时间，几乎立即显示
          fadeInDuration: const Duration(milliseconds: 50),
          fadeOutDuration: Duration.zero,
          // 【性能优化】使用空容器占位，头像背景色已由 CircleAvatar 提供
          placeholder: placeholder != null
              ? (context, url) => placeholder!
              : (context, url) => const SizedBox(),
          errorWidget: errorWidget != null
              ? (context, url, error) => errorWidget!
              : (context, url, error) => Icon(
                    Icons.person,
                    size: radius,
                    color: isDark ? const Color(0xFF808080) : Colors.grey,
                  ),
          memCacheWidth: (radius * 2 * 2).toInt(), // 2x for retina
          memCacheHeight: (radius * 2 * 2).toInt(),
          maxHeightDiskCache: (radius * 2 * 2).toInt(),
          maxWidthDiskCache: (radius * 2 * 2).toInt(),
        ),
      ),
    );
  }
}
