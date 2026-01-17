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

  /// 构建包含可点击时间戳的 TextSpan 列表
  /// [text] 原始文本
  /// [defaultStyle] 默认文本样式
  /// [timestampStyle] 时间戳文本样式
  /// [onTimestampTap] 点击时间戳的回调，参数为秒数
  static List<InlineSpan> buildTextSpans({
    required String text,
    required TextStyle defaultStyle,
    TextStyle? timestampStyle,
    void Function(int seconds)? onTimestampTap,
  }) {
    final spans = <InlineSpan>[];
    final effectiveTimestampStyle = timestampStyle ?? defaultStyle.copyWith(
      color: Colors.blue,
      fontWeight: FontWeight.w500,
    );

    int lastEnd = 0;
    final matches = _timestampRegex.allMatches(text);

    for (final match in matches) {
      // 添加匹配前的普通文本
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: defaultStyle,
        ));
      }

      // 添加时间戳（可点击）
      final timestampText = match.group(0)!;
      final seconds = parseToSeconds(timestampText);

      if (seconds != null && onTimestampTap != null) {
        spans.add(TextSpan(
          text: timestampText,
          style: effectiveTimestampStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => onTimestampTap(seconds),
        ));
      } else {
        // 无效时间戳或无回调，显示为普通文本
        spans.add(TextSpan(
          text: timestampText,
          style: defaultStyle,
        ));
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
}
