import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/video_item.dart';
import '../theme/theme_extensions.dart';
import '../pages/user/user_space_page.dart';
import 'cached_image_widget.dart';

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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 13.sp * 1.2 * 2,
                        child: Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          if (video.authorAvatar != null)
                            GestureDetector(
                              onTap: video.authorUid != null
                                  ? () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => UserSpacePage(userId: video.authorUid!),
                                        ),
                                      );
                                    }
                                  : null,
                              child: CachedCircleAvatar(
                                imageUrl: video.authorAvatar!,
                                radius: 8.r,
                                cacheKey: video.authorUid != null ? 'user_avatar_${video.authorUid}' : null,
                              ),
                            ),
                          SizedBox(width: 4.w),
                          Expanded(
                            child: GestureDetector(
                              onTap: video.authorUid != null
                                  ? () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => UserSpacePage(userId: video.authorUid!),
                                        ),
                                      );
                                    }
                                  : null,
                              child: Text(
                                video.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2.h),
                      Row(
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            size: 11.sp,
                            color: colors.textTertiary,
                          ),
                          SizedBox(width: 2.w),
                          Text(
                            video.formattedPlayCount,
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: colors.textTertiary,
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 11.sp,
                            color: colors.textTertiary,
                          ),
                          SizedBox(width: 2.w),
                          Text(
                            video.formattedDanmakuCount,
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: colors.textTertiary,
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
