import 'package:flutter/material.dart';
import '../models/video_item.dart';
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 封面图片
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedImage(
                  imageUrl: video.coverUrl,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(8),
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
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    video.duration,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 标题
          Text(
            video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 3),
          // 用户名
          Row(
            children: [
              if (video.authorAvatar != null)
                CachedCircleAvatar(
                  imageUrl: video.authorAvatar!,
                  radius: 8,
                ),
              if (video.authorAvatar != null) const SizedBox(width: 4),
              Expanded(
                child: Text(
                  video.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // 播放次数和弹幕数量
          Row(
            children: [
              Icon(
                Icons.play_circle_outline,
                size: 12,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                video.formattedPlayCount,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chat_bubble_outline,
                size: 12,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                video.formattedDanmakuCount,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
