// 消息相关数据模型

/// 公告消息
class AnnounceMessage {
  final int id;
  final String title;
  final String content;
  final String createdAt;
  final String url;

  AnnounceMessage({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.url,
  });

  factory AnnounceMessage.fromJson(Map<String, dynamic> json) {
    return AnnounceMessage(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      createdAt: json['createdAt'] ?? '',
      url: json['url'] ?? '',
    );
  }
}

/// 基础用户信息（用于消息展示）
class MessageUserInfo {
  final int uid;
  final String name;
  final String avatar;

  MessageUserInfo({
    required this.uid,
    required this.name,
    required this.avatar,
  });

  factory MessageUserInfo.fromJson(Map<String, dynamic> json) {
    return MessageUserInfo(
      uid: json['uid'] ?? 0,
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '',
    );
  }
}

/// 基础视频信息（用于消息展示）
class MessageVideoInfo {
  final int vid;
  final String title;
  final String cover;

  MessageVideoInfo({
    required this.vid,
    required this.title,
    required this.cover,
  });

  factory MessageVideoInfo.fromJson(Map<String, dynamic> json) {
    return MessageVideoInfo(
      vid: json['vid'] ?? 0,
      title: json['title'] ?? '',
      cover: json['cover'] ?? '',
    );
  }
}

/// 基础文章信息（用于消息展示）
class MessageArticleInfo {
  final int aid;
  final String title;
  final String cover;

  MessageArticleInfo({
    required this.aid,
    required this.title,
    required this.cover,
  });

  factory MessageArticleInfo.fromJson(Map<String, dynamic> json) {
    return MessageArticleInfo(
      aid: json['aid'] ?? 0,
      title: json['title'] ?? '',
      cover: json['cover'] ?? '',
    );
  }
}

/// @消息
class AtMessage {
  final int id;
  final int type; // 0=视频, 1=文章
  final MessageVideoInfo? video;
  final MessageArticleInfo? article;
  final MessageUserInfo user;
  final String createdAt;

  AtMessage({
    required this.id,
    required this.type,
    this.video,
    this.article,
    required this.user,
    required this.createdAt,
  });

  factory AtMessage.fromJson(Map<String, dynamic> json) {
    return AtMessage(
      id: json['id'] ?? 0,
      type: json['type'] ?? 0,
      video: json['video'] != null ? MessageVideoInfo.fromJson(json['video']) : null,
      article: json['article'] != null ? MessageArticleInfo.fromJson(json['article']) : null,
      user: MessageUserInfo.fromJson(json['user'] ?? {}),
      createdAt: json['createdAt'] ?? '',
    );
  }
}

/// 点赞消息
class LikeMessage {
  final int id;
  final int type; // 0=视频, 1=文章
  final MessageVideoInfo? video;
  final MessageArticleInfo? article;
  final MessageUserInfo user;
  final String createdAt;

  LikeMessage({
    required this.id,
    required this.type,
    this.video,
    this.article,
    required this.user,
    required this.createdAt,
  });

  factory LikeMessage.fromJson(Map<String, dynamic> json) {
    return LikeMessage(
      id: json['id'] ?? 0,
      type: json['type'] ?? 0,
      video: json['video'] != null ? MessageVideoInfo.fromJson(json['video']) : null,
      article: json['article'] != null ? MessageArticleInfo.fromJson(json['article']) : null,
      user: MessageUserInfo.fromJson(json['user'] ?? {}),
      createdAt: json['createdAt'] ?? '',
    );
  }
}

/// 回复消息
class ReplyMessage {
  final int id;
  final int type; // 0=视频, 1=文章
  final MessageVideoInfo? video;
  final MessageArticleInfo? article;
  final MessageUserInfo user;
  final String createdAt;
  final String content; // 回复内容
  final String targetReplyContent; // 被回复的内容
  final String rootContent; // 根评论内容
  final String commentId; // 评论ID

  ReplyMessage({
    required this.id,
    required this.type,
    this.video,
    this.article,
    required this.user,
    required this.createdAt,
    required this.content,
    required this.targetReplyContent,
    required this.rootContent,
    required this.commentId,
  });

  factory ReplyMessage.fromJson(Map<String, dynamic> json) {
    return ReplyMessage(
      id: json['id'] ?? 0,
      type: json['type'] ?? 0,
      video: json['video'] != null ? MessageVideoInfo.fromJson(json['video']) : null,
      article: json['article'] != null ? MessageArticleInfo.fromJson(json['article']) : null,
      user: MessageUserInfo.fromJson(json['user'] ?? {}),
      createdAt: json['createdAt'] ?? '',
      content: json['content'] ?? '',
      targetReplyContent: json['targetReplyContent'] ?? '',
      rootContent: json['rootContent'] ?? '',
      commentId: json['commentId']?.toString() ?? '',
    );
  }
}

/// 私信列表项
class WhisperListItem {
  final MessageUserInfo user;
  final String createdAt;
  final bool status; // 是否已读

  WhisperListItem({
    required this.user,
    required this.createdAt,
    required this.status,
  });

  factory WhisperListItem.fromJson(Map<String, dynamic> json) {
    print('解析私信列表项JSON: $json');
    final userJson = json['user'] ?? {};
    print('用户信息JSON: $userJson');
    return WhisperListItem(
      user: MessageUserInfo.fromJson(userJson),
      createdAt: json['createdAt'] ?? json['created_at'] ?? '',
      status: json['status'] ?? false,
    );
  }
}

/// 私信详情
class WhisperDetail {
  final int fid;
  final int fromId;
  final String content;
  final String createdAt;

  WhisperDetail({
    required this.fid,
    required this.fromId,
    required this.content,
    required this.createdAt,
  });

  factory WhisperDetail.fromJson(Map<String, dynamic> json) {
    print('解析私信详情JSON: $json');
    return WhisperDetail(
      fid: json['fid'] ?? 0,
      fromId: json['fromId'] ?? json['from_id'] ?? 0,
      content: json['content'] ?? '',
      createdAt: json['createdAt'] ?? json['created_at'] ?? '',
    );
  }
}
