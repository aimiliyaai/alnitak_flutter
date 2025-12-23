import 'package:intl/intl.dart';

/// 时间格式化工具类
class TimeUtils {
  /// 格式化时间为友好显示
  /// - 1分钟内：刚刚
  /// - 1小时内：xx分钟前
  /// - 24小时内：xx小时前
  /// - 今年内：MM-dd
  /// - 跨年：yyyy-MM-dd
  static String formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) {
      return '';
    }

    try {
      final dateTime = DateTime.parse(timeStr);
      final now = DateTime.now();
      final diff = now.difference(dateTime);

      if (diff.inMinutes < 1) {
        return '刚刚';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes}分钟前';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}小时前';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}天前';
      } else if (dateTime.year == now.year) {
        return DateFormat('MM-dd').format(dateTime);
      } else {
        return DateFormat('yyyy-MM-dd').format(dateTime);
      }
    } catch (e) {
      return timeStr;
    }
  }

  /// 格式化时间为完整日期时间
  static String formatDateTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) {
      return '';
    }

    try {
      final dateTime = DateTime.parse(timeStr);
      return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
    } catch (e) {
      return timeStr;
    }
  }

  /// 格式化时间为日期
  static String formatDate(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) {
      return '';
    }

    try {
      final dateTime = DateTime.parse(timeStr);
      return DateFormat('yyyy-MM-dd').format(dateTime);
    } catch (e) {
      return timeStr;
    }
  }

  /// 格式化秒数为时分秒
  static String formatDuration(int seconds) {
    if (seconds <= 0) return '00:00';

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }
}
