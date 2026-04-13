import '../utils/image_utils.dart';

/// 合集信息
class PlaylistInfo {
  final int id;
  final String title;
  final String desc;
  final String cover;
  final int uid;
  final String createdAt;
  final bool isOpen;

  PlaylistInfo({
    required this.id,
    required this.title,
    required this.desc,
    required this.cover,
    required this.uid,
    required this.createdAt,
    required this.isOpen,
  });

  factory PlaylistInfo.fromJson(Map<String, dynamic> json) {
    return PlaylistInfo(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      desc: json['desc'] ?? '',
      cover: ImageUtils.getFullImageUrl(json['cover']),
      uid: json['uid'] ?? 0,
      createdAt: json['createdAt'] ?? '',
      isOpen: json['isOpen'] ?? false,
    );
  }
}

/// 合集中的视频项
class PlaylistVideoItem {
  final int vid;
  final String? shortId;
  final String title;
  final String cover;
  final double duration;
  final int clicks;
  final String desc;
  final int? resourceId;  // 分P的资源ID
  final String? resourceShortId;  // 分P的资源ShortID
  final String? partTitle;  // 分P标题

  PlaylistVideoItem({
    required this.vid,
    this.shortId,
    required this.title,
    required this.cover,
    required this.duration,
    required this.clicks,
    required this.desc,
    this.resourceId,
    this.resourceShortId,
    this.partTitle,
  });

  factory PlaylistVideoItem.fromJson(Map<String, dynamic> json) {
    return PlaylistVideoItem(
      vid: json['vid'] ?? 0,
      shortId: json['shortId'],
      title: json['title'] ?? '',
      cover: ImageUtils.getFullImageUrl(json['cover']),
      duration: (json['duration'] ?? 0).toDouble(),
      clicks: json['clicks'] ?? 0,
      desc: json['desc'] ?? '',
      resourceId: json['resourceId'],
      resourceShortId: json['resourceShortId'],
      partTitle: json['partTitle'],
    );
  }
}
