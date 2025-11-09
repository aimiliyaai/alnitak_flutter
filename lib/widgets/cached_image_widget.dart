import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 带缓存的网络图片组件
///
/// 自动处理图片加载、缓存、错误和占位符
/// 在弱网环境下提供更好的用户体验
class CachedImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const CachedImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget = CachedNetworkImage(
      imageUrl: imageUrl,
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
class CachedCircleAvatar extends StatelessWidget {
  final String imageUrl;
  final double radius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedCircleAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 20,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[200],
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
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
