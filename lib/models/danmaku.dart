/// 弹幕数据模型
///
/// 支持多种弹幕类型：滚动弹幕、顶部固定、底部固定
class Danmaku {
  final int id;
  /// 弹幕出现时间（秒）
  final double time;
  /// 弹幕类型：0-滚动, 1-顶部固定, 2-底部固定
  final int type;
  /// 弹幕颜色（十六进制字符串，如 "#ffffff"）
  final String color;
  /// 弹幕文本内容
  final String text;
  /// 视频分P
  final int? part;
  /// 资源短ID
  final String? resourceShortId;
  /// 创建时间
  final DateTime? createdAt;

  const Danmaku({
    required this.id,
    required this.time,
    required this.type,
    required this.color,
    required this.text,
    this.part,
    this.resourceShortId,
    this.createdAt,
  });

  factory Danmaku.fromJson(Map<String, dynamic> json) {
    return Danmaku(
      id: json['id'] as int,
      time: (json['time'] as num).toDouble(),
      type: json['type'] as int? ?? 0,
      color: json['color'] as String? ?? '#ffffff',
      text: json['text'] as String? ?? '',
      part: json['part'] as int?,
      resourceShortId: json['resourceShortId'] as String?,
      createdAt: json['createdAt'] != null 
          ? DateTime.tryParse(json['createdAt'].toString()) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': time,
      'type': type,
      'color': color,
      'text': text,
      if (part != null) 'part': part,
      if (resourceShortId != null) 'resourceShortId': resourceShortId,
    };
  }

  /// 获取弹幕类型枚举
  DanmakuType get danmakuType {
    switch (type) {
      case 1:
        return DanmakuType.top;
      case 2:
        return DanmakuType.bottom;
      default:
        return DanmakuType.scroll;
    }
  }
}

/// 弹幕类型枚举
enum DanmakuType {
  /// 滚动弹幕（从右向左）
  scroll,
  /// 顶部固定弹幕
  top,
  /// 底部固定弹幕
  bottom,
}

/// 发送弹幕请求模型
class SendDanmakuRequest {
  final String vid;
  final String? rid;  // 分P的shortId
  final int part;
  final double time;
  final int type;
  final String color;
  final String text;

  const SendDanmakuRequest({
    required this.vid,
    this.rid,
    required this.part,
    required this.time,
    this.type = 0,
    this.color = '#ffffff',
    required this.text,
  });

Map<String, dynamic> toJson() {
    return {
      'vid': vid,
      if (rid != null) 'rid': rid,
      'part': part,
      'time': time,
      'type': type,
      'color': color,
      'text': text,
    };
  }
}
