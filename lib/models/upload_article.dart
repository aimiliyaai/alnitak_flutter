/// 上传文章模型
class UploadArticle {
  final String title;
  final String cover;
  final String content;
  final String tags;
  final bool copyright;
  final int partitionId;

  UploadArticle({
    required this.title,
    required this.cover,
    required this.content,
    required this.tags,
    required this.copyright,
    required this.partitionId,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'cover': cover,
      'content': content,
      'tags': tags,
      'copyright': copyright,
      'partitionId': partitionId,
    };
  }
}

/// 编辑文章模型
class EditArticle {
  final int aid;
  final String title;
  final String cover;
  final String content;
  final String tags;

  EditArticle({
    required this.aid,
    required this.title,
    required this.cover,
    required this.content,
    required this.tags,
  });

  Map<String, dynamic> toJson() {
    return {
      'aid': aid,
      'title': title,
      'cover': cover,
      'content': content,
      'tags': tags,
    };
  }
}

/// 文章状态模型
class ArticleStatus {
  final int aid;
  final String title;
  final String cover;
  final String content;
  final String tags;
  final int status;
  final bool copyright;
  final int partitionId;
  final String createdAt;

  ArticleStatus({
    required this.aid,
    required this.title,
    required this.cover,
    required this.content,
    required this.tags,
    required this.status,
    required this.copyright,
    required this.partitionId,
    required this.createdAt,
  });

  factory ArticleStatus.fromJson(Map<String, dynamic> json) {
    return ArticleStatus(
      aid: json['aid'] as int,
      title: json['title'] as String,
      cover: json['cover'] as String,
      content: json['content'] as String,
      tags: json['tags'] as String,
      status: json['status'] as int,
      copyright: json['copyright'] as bool,
      partitionId: json['partitionId'] as int,
      createdAt: json['createdAt'] as String,
    );
  }
}

/// 用户投稿文章列表项
class ManuscriptArticle {
  final int aid;
  final String title;
  final String cover;
  final int status;
  final int clicks;
  final String createdAt;

  ManuscriptArticle({
    required this.aid,
    required this.title,
    required this.cover,
    required this.status,
    required this.clicks,
    required this.createdAt,
  });

  factory ManuscriptArticle.fromJson(Map<String, dynamic> json) {
    return ManuscriptArticle(
      aid: json['aid'] as int,
      title: json['title'] as String,
      cover: json['cover'] as String,
      status: json['status'] as int,
      clicks: json['clicks'] as int,
      createdAt: json['createdAt'] as String,
    );
  }

  /// 获取状态文本
  String getStatusText() {
    switch (status) {
      case 1:
        return '待审核';
      case 2:
        return '审核不通过';
      case 3:
        return '已发布';
      default:
        return '未知状态';
    }
  }
}
