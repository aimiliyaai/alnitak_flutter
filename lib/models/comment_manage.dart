import '../utils/image_utils.dart';

/// 评论管理 - 视频/文章简要信息
class ContentBrief {
  final int id; // vid 或 aid
  final String title;
  final String cover;

  ContentBrief({
    required this.id,
    required this.title,
    required this.cover,
  });

  factory ContentBrief.fromVideoJson(Map<String, dynamic> json) {
    return ContentBrief(
      id: json['vid'] ?? 0,
      title: json['title'] ?? '',
      cover: ImageUtils.getFullImageUrl(json['cover'] ?? ''),
    );
  }

  factory ContentBrief.fromArticleJson(Map<String, dynamic> json) {
    return ContentBrief(
      id: json['aid'] ?? 0,
      title: json['title'] ?? '',
      cover: ImageUtils.getFullImageUrl(json['cover'] ?? ''),
    );
  }
}

/// 评论管理 - 用户信息
class CommentAuthor {
  final int uid;
  final String name;
  final String avatar;

  CommentAuthor({
    required this.uid,
    required this.name,
    required this.avatar,
  });

  factory CommentAuthor.fromJson(Map<String, dynamic> json) {
    return CommentAuthor(
      uid: json['uid'] ?? 0,
      name: json['name'] ?? '匿名用户',
      avatar: ImageUtils.getFullImageUrl(json['avatar'] ?? ''),
    );
  }
}

/// 评论管理 - 评论项
class ManageComment {
  final int id;
  final CommentAuthor author;
  final CommentAuthor? target; // 被回复的用户（可选）
  final String content;
  final String? rootContent; // 根评论内容（如果是回复）
  final String? targetReplyContent; // 被回复的评论内容（如果是回复的回复）
  final ContentBrief? video; // 所属视频
  final ContentBrief? article; // 所属文章
  final DateTime createdAt;

  ManageComment({
    required this.id,
    required this.author,
    this.target,
    required this.content,
    this.rootContent,
    this.targetReplyContent,
    this.video,
    this.article,
    required this.createdAt,
  });

  factory ManageComment.fromVideoJson(Map<String, dynamic> json) {
    return ManageComment(
      id: json['id'] ?? 0,
      author: CommentAuthor.fromJson(json['author'] ?? {}),
      target: json['target'] != null
          ? CommentAuthor.fromJson(json['target'])
          : null,
      content: json['content'] ?? '',
      rootContent: json['rootContent'],
      targetReplyContent: json['targetReplyContent'],
      video: json['video'] != null
          ? ContentBrief.fromVideoJson(json['video'])
          : null,
      article: null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  factory ManageComment.fromArticleJson(Map<String, dynamic> json) {
    return ManageComment(
      id: json['id'] ?? 0,
      author: CommentAuthor.fromJson(json['author'] ?? {}),
      target: json['target'] != null
          ? CommentAuthor.fromJson(json['target'])
          : null,
      content: json['content'] ?? '',
      rootContent: json['rootContent'],
      targetReplyContent: json['targetReplyContent'],
      video: null,
      article: json['article'] != null
          ? ContentBrief.fromArticleJson(json['article'])
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

/// 评论管理列表响应
class ManageCommentListResponse {
  final List<ManageComment> comments;
  final int total;

  ManageCommentListResponse({
    required this.comments,
    required this.total,
  });

  factory ManageCommentListResponse.fromVideoJson(Map<String, dynamic> json) {
    final commentsList = json['comments'] as List<dynamic>? ?? [];
    return ManageCommentListResponse(
      comments: commentsList
          .map((e) => ManageComment.fromVideoJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] ?? 0,
    );
  }

  factory ManageCommentListResponse.fromArticleJson(Map<String, dynamic> json) {
    final commentsList = json['comments'] as List<dynamic>? ?? [];
    return ManageCommentListResponse(
      comments: commentsList
          .map((e) => ManageComment.fromArticleJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] ?? 0,
    );
  }
}

/// 用户视频列表项（用于下拉选择）
class UserVideoItem {
  final int vid;
  final String title;

  UserVideoItem({
    required this.vid,
    required this.title,
  });

  factory UserVideoItem.fromJson(Map<String, dynamic> json) {
    return UserVideoItem(
      vid: json['vid'] ?? 0,
      title: json['title'] ?? '',
    );
  }
}

/// 用户文章列表项（用于下拉选择）
class UserArticleItem {
  final int aid;
  final String title;

  UserArticleItem({
    required this.aid,
    required this.title,
  });

  factory UserArticleItem.fromJson(Map<String, dynamic> json) {
    return UserArticleItem(
      aid: json['aid'] ?? 0,
      title: json['title'] ?? '',
    );
  }
}
