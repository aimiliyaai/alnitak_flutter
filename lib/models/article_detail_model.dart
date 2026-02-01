import '../utils/image_utils.dart';

/// 文章详情模型
class ArticleDetail {
  final int aid;
  final int uid;
  final String title;
  final String cover;
  final String content;
  final String createdAt;
  final bool copyright;
  final String tags;
  final int clicks;
  final int partitionId;
  final ArticleDetailAuthor author;

  ArticleDetail({
    required this.aid,
    required this.uid,
    required this.title,
    required this.cover,
    required this.content,
    required this.createdAt,
    required this.copyright,
    required this.tags,
    required this.clicks,
    required this.partitionId,
    required this.author,
  });

  factory ArticleDetail.fromJson(Map<String, dynamic> json) {
    return ArticleDetail(
      aid: json['aid'] ?? 0,
      uid: json['uid'] ?? 0,
      title: json['title'] ?? '',
      cover: ImageUtils.getFullImageUrl(json['cover'] ?? ''),
      content: json['content'] ?? '',
      createdAt: json['createdAt'] ?? '',
      copyright: json['copyright'] ?? false,
      tags: json['tags'] ?? '',
      clicks: json['clicks'] ?? 0,
      partitionId: json['partitionId'] ?? 0,
      author: ArticleDetailAuthor.fromJson(json['author'] ?? {}),
    );
  }

  /// 获取标签列表
  List<String> get tagList {
    if (tags.isEmpty) return [];
    return tags.split(',').where((t) => t.isNotEmpty).toList();
  }

  /// 格式化创建时间
  String get formattedDate {
    try {
      final date = DateTime.parse(createdAt);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return createdAt;
    }
  }
}

/// 文章详情作者模型
class ArticleDetailAuthor {
  final int uid;
  final String name;
  final String avatar;
  final String sign;

  ArticleDetailAuthor({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.sign,
  });

  factory ArticleDetailAuthor.fromJson(Map<String, dynamic> json) {
    return ArticleDetailAuthor(
      uid: json['uid'] ?? 0,
      name: json['name'] ?? '',
      avatar: ImageUtils.getFullImageUrl(json['avatar'] ?? ''),
      sign: json['sign'] ?? '',
    );
  }
}

/// 文章详情 API 响应
class ArticleDetailResponse {
  final int code;
  final String msg;
  final ArticleDetail? article;

  ArticleDetailResponse({
    required this.code,
    required this.msg,
    this.article,
  });

  bool get isSuccess => code == 200;

  factory ArticleDetailResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    final articleData = data?['article'] as Map<String, dynamic>?;

    return ArticleDetailResponse(
      code: json['code'] ?? 0,
      msg: json['msg'] ?? '',
      article: articleData != null ? ArticleDetail.fromJson(articleData) : null,
    );
  }
}

/// 文章统计信息
class ArticleStat {
  final int like;
  final int collect;
  final int share;

  ArticleStat({
    required this.like,
    required this.collect,
    required this.share,
  });

  factory ArticleStat.fromJson(Map<String, dynamic> json) {
    return ArticleStat(
      like: json['like'] ?? 0,
      collect: json['collect'] ?? 0,
      share: json['share'] ?? 0,
    );
  }

  ArticleStat copyWith({int? like, int? collect, int? share}) {
    return ArticleStat(
      like: like ?? this.like,
      collect: collect ?? this.collect,
      share: share ?? this.share,
    );
  }
}

/// 文章评论模型
class ArticleComment {
  final int id;
  final int aid;
  final int uid;
  final String username;
  final String avatar;
  final String content;
  final int parentId;
  final int? replyUserId;
  final String? replyUserName;
  final String? replyContent;
  final int replyCount;
  final DateTime createdAt;
  final String? atUserIds; // @提及的用户ID列表（逗号分隔）
  final String? atUsernames; // @提及的用户名列表（逗号分隔）

  ArticleComment({
    required this.id,
    required this.aid,
    required this.uid,
    required this.username,
    required this.avatar,
    required this.content,
    required this.parentId,
    this.replyUserId,
    this.replyUserName,
    this.replyContent,
    required this.replyCount,
    required this.createdAt,
    this.atUserIds,
    this.atUsernames,
  });

  factory ArticleComment.fromJson(Map<String, dynamic> json) {
    return ArticleComment(
      id: json['id'] ?? 0,
      aid: json['aid'] ?? 0,
      uid: json['uid'] ?? 0,
      username: json['username'] ?? '',
      avatar: json['avatar'] ?? '',
      content: json['content'] ?? '',
      parentId: json['parentId'] ?? 0,
      replyUserId: json['replyUserId'],
      replyUserName: json['replyUserName'],
      replyContent: json['replyContent'],
      replyCount: json['replyCount'] ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      atUserIds: json['atUserIds'] as String?,
      atUsernames: json['atUsernames'] as String?,
    );
  }

  /// 解析 atUserIds 和 atUsernames 为 Map<用户名, 用户ID>
  Map<String, int> get atUserMap {
    if (atUserIds == null || atUsernames == null ||
        atUserIds!.isEmpty || atUsernames!.isEmpty) {
      return {};
    }
    final ids = atUserIds!.split(',');
    final names = atUsernames!.split(',');
    final map = <String, int>{};
    for (var i = 0; i < names.length && i < ids.length; i++) {
      final id = int.tryParse(ids[i]);
      if (id != null && names[i].isNotEmpty) {
        map[names[i]] = id;
      }
    }
    return map;
  }
}

/// 文章评论响应
class ArticleCommentResponse {
  final List<ArticleComment> comments;
  final int total;

  ArticleCommentResponse({
    required this.comments,
    required this.total,
  });

  factory ArticleCommentResponse.fromJson(Map<String, dynamic> json) {
    final commentList = json['comments'] as List<dynamic>? ?? [];
    return ArticleCommentResponse(
      comments: commentList.map((e) => ArticleComment.fromJson(e)).toList(),
      total: json['total'] ?? 0,
    );
  }

  bool get hasMore => comments.length < total;
}
