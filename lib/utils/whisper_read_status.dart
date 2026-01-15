import 'package:shared_preferences/shared_preferences.dart';

/// 私信已读状态管理（本地存储）
///
/// 使用 SharedPreferences 存储每个会话的最后阅读时间
/// 通过比较最后阅读时间和消息时间来判断是否有未读消息
class WhisperReadStatus {
  static const String _keyPrefix = 'whisper_read_';

  /// 标记与某用户的私信为已读
  /// [userId] 对方用户ID
  static Future<void> markAsRead(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String();
    await prefs.setString('$_keyPrefix$userId', now);
    print('📬 标记私信已读: userId=$userId, time=$now');
  }

  /// 获取最后阅读时间
  /// [userId] 对方用户ID
  /// 返回最后阅读时间，如果从未阅读过则返回 null
  static Future<DateTime?> getLastReadTime(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString('$_keyPrefix$userId');
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// 检查是否有未读消息
  /// [userId] 对方用户ID
  /// [messageTime] 最新消息时间字符串
  static Future<bool> hasUnread(int userId, String messageTime) async {
    final lastReadTime = await getLastReadTime(userId);
    if (lastReadTime == null) {
      // 从未阅读过，有未读消息
      return true;
    }

    // 解析消息时间
    final msgTime = DateTime.tryParse(messageTime);
    if (msgTime == null) {
      return false;
    }

    // 如果消息时间晚于最后阅读时间，则有未读
    return msgTime.isAfter(lastReadTime);
  }

  /// 清除某用户的已读记录
  static Future<void> clearReadStatus(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$userId');
  }

  /// 清除所有已读记录
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
