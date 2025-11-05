import '../utils/image_utils.dart';

/// 评论数据模型
class Comment {
  final int id; // 评论ID
  final int uid; // 用户ID
  final String username; // 用户名
  final String avatar; // 用户头像
  final String content; // 评论内容
  final DateTime createdAt; // 发布时间
  final int replyCount; // 回复数
  final List<Comment>? replies; // 回复列表（可选，用于展开回复时加载）
  final String? replyUserName; // 回复的用户名（仅回复时存在）
  final int? replyUserId; // 回复的用户ID（仅回复时存在）
  final int? parentId; // 所属评论ID（仅回复时存在）

  Comment({
    required this.id,
    required this.uid,
    required this.username,
    required this.avatar,
    required this.content,
    required this.createdAt,
    this.replyCount = 0,
    this.replies,
    this.replyUserName,
    this.replyUserId,
    this.parentId,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>? ?? {};
    
    // 处理回复数组（首层评论的 reply 字段）
    List<Comment>? replies;
    if (json['reply'] != null && (json['reply'] as List).isNotEmpty) {
      replies = (json['reply'] as List<dynamic>)
          .map((e) => Comment.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return Comment(
      id: json['id'] ?? 0,
      uid: json['uid'] ?? 0,
      username: author['name'] ?? '匿名用户',
      avatar: ImageUtils.getFullImageUrl(author['avatar'] ?? ''),
      content: json['content'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      replyCount: json['replyCount'] ?? 0,
      replies: replies,
      replyUserName: json['replyUserName'],
      replyUserId: json['replyUserId'] != null && json['replyUserId'].toString().isNotEmpty
          ? int.tryParse(json['replyUserId'].toString())
          : null,
      parentId: json['parentId'] != null && json['parentId'].toString().isNotEmpty
          ? int.tryParse(json['parentId'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uid': uid,
      'username': username,
      'avatar': avatar,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'replyCount': replyCount,
      'replies': replies?.map((e) => e.toJson()).toList(),
      'replyUserName': replyUserName,
      'replyUserId': replyUserId,
      'parentId': parentId,
    };
  }

  Comment copyWith({
    int? id,
    int? uid,
    String? username,
    String? avatar,
    String? content,
    DateTime? createdAt,
    int? replyCount,
    List<Comment>? replies,
    String? replyUserName,
    int? replyUserId,
    int? parentId,
  }) {
    return Comment(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      username: username ?? this.username,
      avatar: avatar ?? this.avatar,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      replyCount: replyCount ?? this.replyCount,
      replies: replies ?? this.replies,
      replyUserName: replyUserName ?? this.replyUserName,
      replyUserId: replyUserId ?? this.replyUserId,
      parentId: parentId ?? this.parentId,
    );
  }
}

/// 评论列表响应
class CommentListResponse {
  final List<Comment> comments;
  final int total;
  final bool hasMore;

  CommentListResponse({
    required this.comments,
    required this.total,
    required this.hasMore,
  });

  factory CommentListResponse.fromJson(Map<String, dynamic> json) {
    final commentsList = json['comments'] as List<dynamic>? ?? [];
    return CommentListResponse(
      comments: commentsList
          .map((e) => Comment.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] ?? 0,
      hasMore: commentsList.isNotEmpty, // 根据实际返回的数据判断是否还有更多
    );
  }
}

