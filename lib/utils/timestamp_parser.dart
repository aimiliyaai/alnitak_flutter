import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 时间戳解析工具
/// 用于识别评论中的时间格式（如 3:00、03:00、1:23:45）并生成可点击的文本
class TimestampParser {
  /// 匹配时间戳的正则表达式
  /// 支持格式：
  /// - 3:00, 03:00 (分:秒)
  /// - 3：00, 03：00 (中文冒号)
  /// - 1:23:45, 01:23:45 (时:分:秒)
  /// - 1：23：45 (中文冒号)
  static final RegExp _timestampRegex = RegExp(
    r'(\d{1,2})[：:](\d{2})(?:[：:](\d{2}))?',
  );

  /// 匹配 @用户名 的正则表达式
  /// 支持中文、英文、数字，用户名长度 1-20
  static final RegExp _mentionRegex = RegExp(
    r'@([\u4e00-\u9fa5a-zA-Z0-9]{1,20})',
  );

  /// 解析时间戳字符串为秒数
  /// 返回 null 表示无效的时间戳
  static int? parseToSeconds(String timestamp) {
    final match = _timestampRegex.firstMatch(timestamp);
    if (match == null) return null;

    final part1 = int.tryParse(match.group(1) ?? '') ?? 0;
    final part2 = int.tryParse(match.group(2) ?? '') ?? 0;
    final part3 = match.group(3) != null ? int.tryParse(match.group(3)!) : null;

    if (part3 != null) {
      // 格式：时:分:秒
      return part1 * 3600 + part2 * 60 + part3;
    } else {
      // 格式：分:秒
      return part1 * 60 + part2;
    }
  }

  /// 构建包含可点击时间戳和@用户名的 TextSpan 列表
  /// [text] 原始文本
  /// [defaultStyle] 默认文本样式
  /// [timestampStyle] 时间戳文本样式
  /// [mentionStyle] @用户名文本样式
  /// [onTimestampTap] 点击时间戳的回调，参数为秒数
  /// [onMentionTap] 点击@用户名的回调，参数为用户名（不含@）
  /// [onMentionTapWithId] 点击@用户名的回调（带用户ID），参数为用户ID
  /// [atUserMap] @用户名到用户ID的映射，用于支持点击跳转到用户主页
  static List<InlineSpan> buildTextSpans({
    required String text,
    required TextStyle defaultStyle,
    TextStyle? timestampStyle,
    TextStyle? mentionStyle,
    void Function(int seconds)? onTimestampTap,
    void Function(String username)? onMentionTap,
    void Function(int userId)? onMentionTapWithId,
    Map<String, int>? atUserMap,
  }) {
    final spans = <InlineSpan>[];
    final effectiveTimestampStyle = timestampStyle ?? defaultStyle.copyWith(
      color: Colors.blue,
      fontWeight: FontWeight.w500,
    );
    final effectiveMentionStyle = mentionStyle ?? defaultStyle.copyWith(
      color: Colors.blue,
      fontWeight: FontWeight.w500,
    );

    // 收集所有匹配项并按位置排序
    final allMatches = <_MatchInfo>[];

    // 收集时间戳匹配
    for (final match in _timestampRegex.allMatches(text)) {
      allMatches.add(_MatchInfo(
        start: match.start,
        end: match.end,
        text: match.group(0)!,
        type: _MatchType.timestamp,
      ));
    }

    // 收集 @用户名 匹配
    for (final match in _mentionRegex.allMatches(text)) {
      allMatches.add(_MatchInfo(
        start: match.start,
        end: match.end,
        text: match.group(0)!,
        username: match.group(1),
        type: _MatchType.mention,
      ));
    }

    // 按起始位置排序
    allMatches.sort((a, b) => a.start.compareTo(b.start));

    // 移除重叠的匹配（保留先出现的）
    final filteredMatches = <_MatchInfo>[];
    int lastEnd = 0;
    for (final match in allMatches) {
      if (match.start >= lastEnd) {
        filteredMatches.add(match);
        lastEnd = match.end;
      }
    }

    // 构建 TextSpan
    lastEnd = 0;
    for (final match in filteredMatches) {
      // 添加匹配前的普通文本
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: defaultStyle,
        ));
      }

      // 根据匹配类型添加对应的 TextSpan
      if (match.type == _MatchType.timestamp) {
        final seconds = parseToSeconds(match.text);
        if (seconds != null && onTimestampTap != null) {
          spans.add(TextSpan(
            text: match.text,
            style: effectiveTimestampStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => onTimestampTap(seconds),
          ));
        } else {
          spans.add(TextSpan(
            text: match.text,
            style: defaultStyle,
          ));
        }
      } else if (match.type == _MatchType.mention) {
        final String? username = match.username;
        int? userId;
        if (username != null && atUserMap != null) {
          userId = atUserMap[username];
        }

        // 优先使用带用户ID的回调
        if (userId != null && onMentionTapWithId != null) {
          spans.add(TextSpan(
            text: match.text,
            style: effectiveMentionStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => onMentionTapWithId(userId!),
          ));
        } else if (onMentionTap != null && username != null) {
          spans.add(TextSpan(
            text: match.text,
            style: effectiveMentionStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => onMentionTap(username),
          ));
        } else {
          // 即使没有回调，@用户名也显示为蓝色高亮
          spans.add(TextSpan(
            text: match.text,
            style: effectiveMentionStyle,
          ));
        }
      }

      lastEnd = match.end;
    }

    // 添加剩余的普通文本
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: defaultStyle,
      ));
    }

    // 如果没有任何匹配，返回完整的普通文本
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: defaultStyle));
    }

    return spans;
  }

  /// 检查文本中是否包含时间戳
  static bool containsTimestamp(String text) {
    return _timestampRegex.hasMatch(text);
  }

  /// 检查文本中是否包含 @用户名
  static bool containsMention(String text) {
    return _mentionRegex.hasMatch(text);
  }
}

/// 匹配类型
enum _MatchType {
  timestamp,
  mention,
}

/// 匹配信息
class _MatchInfo {
  final int start;
  final int end;
  final String text;
  final String? username;
  final _MatchType type;

  _MatchInfo({
    required this.start,
    required this.end,
    required this.text,
    this.username,
    required this.type,
  });
}
