import 'package:flutter/foundation.dart';

import '../models/message_models.dart';
import '../utils/login_guard.dart';
import '../utils/message_read_status.dart';
import 'logger_service.dart';
import 'message_api_service.dart';

/// 未读消息状态（供「我的」Tab 与个人页「消息」入口展示角标/数量）
class UnreadMessageService extends ChangeNotifier {
  UnreadMessageService._();
  static final UnreadMessageService instance = UnreadMessageService._();

  final MessageApiService _apiService = MessageApiService();

  /// 未读条数（公告/赞/回复/@ 各算 0 或 1，私信按未读会话数累加，用于角标展示）
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  /// 是否存在任意类型未读
  bool get hasUnread => _unreadCount > 0;

  /// 刷新未读状态（与消息中心逻辑一致：拉取各分类最新一条 + 已读进度，计算未读）
  Future<void> refresh() async {
    final loggedIn = await LoginGuard.isLoggedInAsync();
    if (!loggedIn) {
      if (_unreadCount != 0) {
        _unreadCount = 0;
        notifyListeners();
      }
      return;
    }

    try {
      final results = await Future.wait([
        _apiService.getAnnounceList(page: 1, pageSize: 1),
        _apiService.getLikeMessageList(page: 1, pageSize: 1),
        _apiService.getReplyMessageList(page: 1, pageSize: 1),
        _apiService.getAtMessageList(page: 1, pageSize: 1),
        _apiService.getWhisperList(),
      ]);

      final announceList = results[0] as List;
      final likeList = results[1] as List;
      final replyList = results[2] as List;
      final atList = results[3] as List;
      final whisperList = results[4] as List<WhisperListItem>;

      final announceLatestId = announceList.isNotEmpty ? announceList.first.id as int : 0;
      final likeLatestId = likeList.isNotEmpty ? likeList.first.id as int : 0;
      final replyLatestId = replyList.isNotEmpty ? replyList.first.id as int : 0;
      final atLatestId = atList.isNotEmpty ? atList.first.id as int : 0;

      final serverRead = await _apiService.getReadStatus();
      for (final category in [MessageReadStatus.announce, MessageReadStatus.like, MessageReadStatus.reply, MessageReadStatus.at]) {
        final local = await MessageReadStatus.getLastReadId(category);
        final server = serverRead[category] ?? 0;
        if (server > local) await MessageReadStatus.markAsRead(category, server);
      }

      final unreadResults = await Future.wait([
        MessageReadStatus.hasUnread(MessageReadStatus.announce, announceLatestId),
        MessageReadStatus.hasUnread(MessageReadStatus.like, likeLatestId),
        MessageReadStatus.hasUnread(MessageReadStatus.reply, replyLatestId),
        MessageReadStatus.hasUnread(MessageReadStatus.at, atLatestId),
      ]);

      int count = 0;
      if (unreadResults[0]) count += 1;
      if (unreadResults[1]) count += 1;
      if (unreadResults[2]) count += 1;
      if (unreadResults[3]) count += 1;
      final whisperUnreadCount = whisperList.where((e) => !e.status).length;
      count += whisperUnreadCount;

      if (count != _unreadCount) {
        _unreadCount = count;
        notifyListeners();
      }
    } catch (e) {
      LoggerService.instance.logWarning('刷新未读消息失败: $e', tag: 'UnreadMessageService');
    }
  }
}
