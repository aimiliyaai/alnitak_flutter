import 'video_api_model.dart';
import '../services/video_api_service.dart';

class VideoItem {
  final String id;
  final String title;
  final String coverUrl;
  final String authorName;
  final int playCount;
  final String duration; // 格式如 "10:25"
  final int danmakuCount;
  final String? authorAvatar;

  VideoItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.authorName,
    required this.playCount,
    required this.duration,
    required this.danmakuCount,
    this.authorAvatar,
  });

  // 从API模型转换为VideoItem
  factory VideoItem.fromApiModel(VideoApiModel apiModel) {
    // 拼接完整的图片URL
    String getFullImageUrl(String path) {
      if (path.isEmpty) return '';
      if (path.startsWith('http://') || path.startsWith('https://')) {
        return path; // 已经是完整URL
      }
      // API返回的是相对路径，需要拼接baseUrl
      // 例如: "/api/image/1887881468064043008.png"
      return '${VideoApiService.baseUrl}$path';
    }

    return VideoItem(
      id: apiModel.vid.toString(),
      title: apiModel.title,
      coverUrl: getFullImageUrl(apiModel.cover),
      authorName: apiModel.author.name,
      playCount: apiModel.clicks,
      duration: apiModel.formattedDuration,
      danmakuCount: 0, // API中没有弹幕数量字段，设为0
      authorAvatar: apiModel.author.avatar.isNotEmpty
          ? getFullImageUrl(apiModel.author.avatar)
          : null,
    );
  }

  // 格式化播放次数
  String get formattedPlayCount {
    if (playCount < 1000) {
      return playCount.toString();
    } else if (playCount < 10000) {
      return '${(playCount / 1000).toStringAsFixed(1)}k';
    } else if (playCount < 100000000) {
      return '${(playCount / 10000).toStringAsFixed(1)}万';
    } else {
      return '${(playCount / 100000000).toStringAsFixed(1)}亿';
    }
  }

  // 格式化弹幕数量
  String get formattedDanmakuCount {
    if (danmakuCount < 1000) {
      return danmakuCount.toString();
    } else if (danmakuCount < 10000) {
      return '${(danmakuCount / 1000).toStringAsFixed(1)}k';
    } else {
      return '${(danmakuCount / 10000).toStringAsFixed(1)}万';
    }
  }
}
