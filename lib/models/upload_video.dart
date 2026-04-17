List<String> _parseTags(dynamic v) {
  if (v == null) return [];
  if (v is List) {
    return v.map((e) => e.toString().trim()).where((t) => t.isNotEmpty).toList();
  }
  if (v is String) {
    return v.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }
  return [];
}

/// 上传视频模型
class UploadVideo {
  final String vid;
  final String title;
  final String cover;
  final String desc;
  final String tags;
  final bool copyright;
  final int partitionId;

  UploadVideo({
    required this.vid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.tags,
    required this.copyright,
    required this.partitionId,
  });

  Map<String, dynamic> toJson() {
    return {
      'vid': vid,
      'title': title,
      'cover': cover,
      'desc': desc,
      'tags': tags,
      'copyright': copyright,
      'partitionId': partitionId,
    };
  }
}

/// 编辑视频模型
/// 参考PC端：编辑时不允许修改分区（EditVideoType不包含partitionId字段）
class EditVideo {
  final String vid;
  final String title;
  final String cover;
  final String desc;
  final String tags;

  EditVideo({
    required this.vid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.tags,
  });

  Map<String, dynamic> toJson() {
    return {
      'vid': vid,
      'title': title,
      'cover': cover,
      'desc': desc,
      'tags': tags,
    };
  }
}

/// 视频资源模型
class VideoResource {
  final String id;
  final String title;
  final String? url;
  final double? duration;
  final int status;
  final int? quality; // 清晰度
  final String? createdAt;
  final String? vid; // 视频ID

  VideoResource({
    required this.id,
    required this.title,
    this.url,
    this.duration,
    required this.status,
    this.quality,
    this.createdAt,
    this.vid,
  });

  factory VideoResource.fromJson(Map<String, dynamic> json) {
    return VideoResource(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      url: json['url'] as String?,
      duration: (json['duration'] as num?)?.toDouble(),
      status: json['status'] as int? ?? 0,
      quality: json['quality'] as int?,
      createdAt: json['createdAt'] as String?,
      vid: json['vid']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      if (url != null) 'url': url,
      if (duration != null) 'duration': duration,
      'status': status,
      if (quality != null) 'quality': quality,
      if (createdAt != null) 'createdAt': createdAt,
      if (vid != null) 'vid': vid,
    };
  }
}

/// 视频状态模型
class VideoStatus {
  final String vid;
  final String title;
  final String cover;
  final String desc;
  final List<String> tags;
  final int status;
  final bool copyright;
  final int partitionId;
  final List<VideoResource> resources;
  final String createdAt;

  VideoStatus({
    required this.vid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.tags,
    required this.status,
    required this.copyright,
    required this.partitionId,
    required this.resources,
    required this.createdAt,
  });

  factory VideoStatus.fromJson(Map<String, dynamic> json) {
    return VideoStatus(
      vid: json['vid']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      cover: json['cover'] as String? ?? '',
      desc: json['desc'] as String? ?? '',
      tags: _parseTags(json['tags']),
      status: json['status'] as int? ?? 0,
      copyright: json['copyright'] as bool? ?? false,
      partitionId: json['partitionId'] as int? ?? 0,
      resources: (json['resources'] as List<dynamic>?)
              ?.map((item) =>
                  VideoResource.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['createdAt'] as String? ?? '',
    );
  }
}

/// 用户投稿视频列表项
class ManuscriptVideo {
  final String vid;
  final String? shortId;
  final String title;
  final String cover;
  final int status;
  final int clicks;
  final String createdAt;
  final double transcodingProgress;
  final List<TranscodingProgressItem> transcodingDetails;

  ManuscriptVideo({
    required this.vid,
    this.shortId,
    required this.title,
    required this.cover,
    required this.status,
    required this.clicks,
    required this.createdAt,
    this.transcodingProgress = 0,
    this.transcodingDetails = const [],
  });

  factory ManuscriptVideo.fromJson(Map<String, dynamic> json) {
    return ManuscriptVideo(
      vid: json['vid']?.toString() ?? '',
      shortId: json['shortId'] as String?,
      title: json['title'] as String,
      cover: json['cover'] as String,
      status: json['status'] as int,
      clicks: json['clicks'] as int,
      createdAt: json['createdAt'] as String,
      transcodingProgress:
          (json['transcodingProgress'] as num?)?.toDouble() ?? 0,
      transcodingDetails: (json['transcodingDetails'] as List<dynamic>?)
              ?.map((item) => TranscodingProgressItem.fromJson(
                  item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// 获取状态文本
  /// 视频状态码（参考后端 constant.go）：
  /// - 0: AUDIT_APPROVED 审核通过（已发布）
  /// - 100: CREATED_VIDEO 创建视频
  /// - 200: VIDEO_PROCESSING 视频转码中
  /// - 300: SUBMIT_REVIEW 提交审核中
  /// - 500: WAITING_REVIEW 等待审核
  /// - 2000: REVIEW_FAILED 审核不通过
  /// - 3000: PROCESSING_FAIL 处理失败
  String getStatusText() {
    switch (status) {
      case 100:
      case 200:
      case 300:
        return '转码中';
      case 500:
        return '待审核';
      case 2000:
        return '审核不通过';
      case 3000:
        return '处理失败';
      case 0:
      default:
        return '已发布'; // 正常状态
    }
  }
}

class TranscodingProgressItem {
  final int resourceId;
  final String resourceTitle;
  final String quality;
  final double progress;
  final String status;

  const TranscodingProgressItem({
    required this.resourceId,
    required this.resourceTitle,
    required this.quality,
    required this.progress,
    required this.status,
  });

  factory TranscodingProgressItem.fromJson(Map<String, dynamic> json) {
    return TranscodingProgressItem(
      resourceId: json['resourceId'] as int? ?? 0,
      resourceTitle: json['resourceTitle'] as String? ?? '',
      quality: json['quality'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'processing',
    );
  }
}
