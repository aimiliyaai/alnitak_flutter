import 'package:shared_preferences/shared_preferences.dart';

/// 消息已读状态管理（本地存储）
///
/// 使用 SharedPreferences 存储每个消息分类最后已读的消息 ID
/// 通过比较最新消息 ID 和已读 ID 来判断是否有未读消息
class MessageReadStatus {
  static const String _keyPrefix = 'msg_read_';

  // 消息分类 key
  static const String announce = 'announce';
  static const String like = 'like';
  static const String reply = 'reply';
  static const String at = 'at';

  /// 标记某分类为已读
  static Future<void> markAsRead(String category, int latestId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_keyPrefix$category', latestId);
  }

  /// 获取某分类最后已读的消息 ID
  static Future<int> getLastReadId(String category) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_keyPrefix$category') ?? 0;
  }

  /// 检查某分类是否有未读消息
  static Future<bool> hasUnread(String category, int latestId) async {
    if (latestId <= 0) return false;
    final lastReadId = await getLastReadId(category);
    return latestId > lastReadId;
  }
}
