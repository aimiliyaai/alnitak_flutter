import 'package:flutter/material.dart';
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
        borderRadius: BorderRadius.circular(10),
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
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 封面图片
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
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
                    // 时长标签
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          video.duration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 内容区域
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 用户名（可点击跳转到UP主页面）
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
                      child: Row(
                        children: [
                          if (video.authorAvatar != null)
                            CachedCircleAvatar(
                              imageUrl: video.authorAvatar!,
                              radius: 8,
                              cacheKey: video.authorUid != null ? 'user_avatar_${video.authorUid}' : null,
                            ),
                          if (video.authorAvatar != null) const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              video.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    // 播放次数和弹幕数量
                    Row(
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          size: 12,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          video.formattedPlayCount,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 12,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          video.formattedDanmakuCount,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
