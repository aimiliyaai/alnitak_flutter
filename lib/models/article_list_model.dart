/// 文章列表项模型
class ArticleListItem {
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
  final ArticleAuthor author;

  ArticleListItem({
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

  factory ArticleListItem.fromJson(Map<String, dynamic> json) {
    return ArticleListItem(
      aid: json['aid'] ?? 0,
      uid: json['uid'] ?? 0,
      title: json['title'] ?? '',
      cover: json['cover'] ?? '',
      content: json['content'] ?? '',
      createdAt: json['createdAt'] ?? '',
      copyright: json['copyright'] ?? false,
      tags: json['tags'] ?? '',
      clicks: json['clicks'] ?? 0,
      partitionId: json['partitionId'] ?? 0,
      author: ArticleAuthor.fromJson(json['author'] ?? {}),
    );
  }

  /// 获取文章摘要（截取内容前100字符）
  String get summary {
    // 移除 HTML 标签和多余空白
    final plainText = content
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plainText.length <= 100) return plainText;
    return '${plainText.substring(0, 100)}...';
  }
}

/// 文章作者模型
class ArticleAuthor {
  final int uid;
  final String name;
  final String avatar;

  ArticleAuthor({
    required this.uid,
    required this.name,
    required this.avatar,
  });

  factory ArticleAuthor.fromJson(Map<String, dynamic> json) {
    return ArticleAuthor(
      uid: json['uid'] ?? 0,
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '',
    );
  }
}

/// 文章列表 API 响应
class ArticleListResponse {
  final int code;
  final String msg;
  final List<ArticleListItem> articles;

  ArticleListResponse({
    required this.code,
    required this.msg,
    required this.articles,
  });

  bool get isSuccess => code == 200;

  factory ArticleListResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    final articlesList = data?['articles'] as List<dynamic>? ?? [];

    return ArticleListResponse(
      code: json['code'] ?? 0,
      msg: json['msg'] ?? '',
      articles: articlesList
          .map((e) => ArticleListItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
