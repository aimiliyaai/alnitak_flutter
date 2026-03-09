import 'package:intl/intl.dart';

/// 时间格式化工具类（统一为 YouTube 风格相对时间：刚刚、1分钟前、昨天 等，随时间推移变化）
class TimeUtils {
  /// 相对时间展示（全项目统一，YouTube 风格）
  /// 刚刚 → 分钟前 → 小时前 → 昨天 → 天前 → 周前 → 个月前 → 年前
  static String _relative(DateTime dateTime, DateTime now) {
    final diff = now.difference(dateTime);
    if (diff.isNegative) return DateFormat('M/d').format(dateTime);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return m == 1 ? '1分钟前' : '$m分钟前';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return h == 1 ? '1小时前' : '$h小时前';
    }
    if (diff.inDays == 1) return '昨天';
    final d = diff.inDays;
    if (d < 7) return '$d天前';
    if (d < 30) {
      final w = (d / 7).floor();
      return w == 1 ? '1周前' : '$w周前';
    }
    if (d < 365) {
      final mo = (d / 30).floor();
      return mo == 1 ? '1个月前' : '$mo个月前';
    }
    final y = now.year - dateTime.year;
    return y == 1 ? '1年前' : '$y年前';
  }

  /// 字符串时间 → 相对时间（统一入口，用于稿件/消息/评论等展示）
  static String formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      return _relative(DateTime.parse(timeStr), DateTime.now());
    } catch (_) {
      return timeStr;
    }
  }

  /// DateTime → 相对时间（与 formatTime 同一规则）
  static String formatRelativeTime(DateTime dateTime) {
    return _relative(dateTime, DateTime.now());
  }

  /// 完整日期时间（仅用于需要精确时间的场景，如后台/导出）
  static String formatDateTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(timeStr));
    } catch (_) {
      return timeStr;
    }
  }

  /// 仅日期（如需要绝对日期时用）
  static String formatDate(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      return DateFormat('yyyy-MM-dd').format(DateTime.parse(timeStr));
    } catch (_) {
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
