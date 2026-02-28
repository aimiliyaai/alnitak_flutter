import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/video_item.dart';
import '../theme/theme_extensions.dart';
import '../pages/user/user_space_page.dart';
import 'cached_image_widget.dart';

/// 视频卡片（参考 pili_plus VideoCardV）
///
/// 配合 SliverGridDelegateWithExtentAndRatio 使用：
/// - 缩略图区域由 aspectRatio 控制高度
/// - 内容区由 mainAxisExtent 控制固定高度
/// - 标题用 Expanded 弹性占满，作者/统计行固定在底部
class VideoCard extends StatelessWidget {
  final VideoItem video;
  final VoidCallback? onTap;

  const VideoCard({
    super.key,
    required this.video,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 缩略图（由 grid 的 aspectRatio 控制高度）
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CachedImage(
                        imageUrl: video.coverUrl,
                        fit: BoxFit.cover,
                        cacheKey: 'video_cover_${video.id}',
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6.w,
                          vertical: 2.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text(
                          video.duration,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 内容区（参考 pili_plus: Expanded + 固定底部行）
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题（弹性高度，占满剩余空间）
                      Expanded(
                        child: Text(
                          "${video.title}\n",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            height: 1.38,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      // 统计行（播放量 + 弹幕数）
                      Row(
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            size: 12.sp,
                            color: colors.textTertiary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            video.formattedPlayCount,
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: colors.textTertiary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 12.sp,
                            color: colors.textTertiary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            video.formattedDanmakuCount,
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      // 作者行
                      Row(
                        children: [
                          if (video.authorAvatar != null)
                            GestureDetector(
                              onTap: video.authorUid != null
                                  ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              UserSpacePage(userId: video.authorUid!),
                                        ),
                                      )
                                  : null,
                              child: CachedCircleAvatar(
                                imageUrl: video.authorAvatar!,
                                radius: 8.r,
                                cacheKey: video.authorUid != null
                                    ? 'user_avatar_${video.authorUid}'
                                    : null,
                              ),
                            ),
                          if (video.authorAvatar != null)
                            const SizedBox(width: 4),
                          Expanded(
                            child: GestureDetector(
                              onTap: video.authorUid != null
                                  ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              UserSpacePage(userId: video.authorUid!),
                                        ),
                                      )
                                  : null,
                              child: Text(
                                video.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  height: 1.5,
                                  fontSize: 11.sp,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
