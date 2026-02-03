import 'package:flutter/material.dart';
import '../../utils/login_guard.dart';
import '../../utils/message_read_status.dart';
import '../../services/message_api_service.dart';
import '../../theme/theme_extensions.dart';
import 'announce_page.dart';
import 'like_message_page.dart';
import 'reply_message_page.dart';
import 'at_message_page.dart';
import 'whisper_page.dart';

/// 消息中心页面
class MessageCenterPage extends StatefulWidget {
  const MessageCenterPage({super.key});

  @override
  State<MessageCenterPage> createState() => _MessageCenterPageState();
}

class _MessageCenterPageState extends State<MessageCenterPage> {
  bool _isLoggedIn = false;
  bool _isLoading = true;

  final MessageApiService _apiService = MessageApiService();
  final Map<String, bool> _unreadStatus = {};
  final Map<String, int> _latestIds = {};

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final loggedIn = await LoginGuard.isLoggedInAsync();
    if (mounted) {
      setState(() {
        _isLoggedIn = loggedIn;
        _isLoading = false;
      });
      if (loggedIn) {
        _checkUnreadStatus();
      }
    }
  }

  Future<void> _checkUnreadStatus() async {
    try {
      // 并行请求4类消息的最新一条
      final results = await Future.wait([
        _apiService.getAnnounceList(page: 1, pageSize: 1),
        _apiService.getLikeMessageList(page: 1, pageSize: 1),
        _apiService.getReplyMessageList(page: 1, pageSize: 1),
        _apiService.getAtMessageList(page: 1, pageSize: 1),
      ]);

      final announceList = results[0] as List;
      final likeList = results[1] as List;
      final replyList = results[2] as List;
      final atList = results[3] as List;

      final announceLatestId = announceList.isNotEmpty ? announceList.first.id as int : 0;
      final likeLatestId = likeList.isNotEmpty ? likeList.first.id as int : 0;
      final replyLatestId = replyList.isNotEmpty ? replyList.first.id as int : 0;
      final atLatestId = atList.isNotEmpty ? atList.first.id as int : 0;

      print('📬 最新消息ID: announce=$announceLatestId, like=$likeLatestId, reply=$replyLatestId, at=$atLatestId');

      _latestIds[MessageReadStatus.announce] = announceLatestId;
      _latestIds[MessageReadStatus.like] = likeLatestId;
      _latestIds[MessageReadStatus.reply] = replyLatestId;
      _latestIds[MessageReadStatus.at] = atLatestId;

      final savedAnnounce = await MessageReadStatus.getLastReadId(MessageReadStatus.announce);
      final savedLike = await MessageReadStatus.getLastReadId(MessageReadStatus.like);
      final savedReply = await MessageReadStatus.getLastReadId(MessageReadStatus.reply);
      final savedAt = await MessageReadStatus.getLastReadId(MessageReadStatus.at);
      print('📬 已读ID: announce=$savedAnnounce, like=$savedLike, reply=$savedReply, at=$savedAt');

      final unreadResults = await Future.wait([
        MessageReadStatus.hasUnread(MessageReadStatus.announce, announceLatestId),
        MessageReadStatus.hasUnread(MessageReadStatus.like, likeLatestId),
        MessageReadStatus.hasUnread(MessageReadStatus.reply, replyLatestId),
        MessageReadStatus.hasUnread(MessageReadStatus.at, atLatestId),
      ]);

      print('📬 未读状态: announce=${unreadResults[0]}, like=${unreadResults[1]}, reply=${unreadResults[2]}, at=${unreadResults[3]}');

      if (mounted) {
        setState(() {
          _unreadStatus[MessageReadStatus.announce] = unreadResults[0];
          _unreadStatus[MessageReadStatus.like] = unreadResults[1];
          _unreadStatus[MessageReadStatus.reply] = unreadResults[2];
          _unreadStatus[MessageReadStatus.at] = unreadResults[3];
        });
      }
    } catch (e) {
      print('检查未读状态失败: $e');
    }
  }

  Future<void> _navigateToAndMarkRead(String category, Widget page) async {
    final navigator = Navigator.of(context);
    final latestId = _latestIds[category] ?? 0;
    print('📬 标记已读: category=$category, latestId=$latestId');
    if (latestId > 0) {
      await MessageReadStatus.markAsRead(category, latestId);
      final verify = await MessageReadStatus.getLastReadId(category);
      print('📬 验证写入: category=$category, savedId=$verify');
    }
    if (!mounted) return;
    setState(() => _unreadStatus[category] = false);
    await navigator.push(
      MaterialPageRoute(builder: (context) => page),
    );
    if (!mounted) return;
    _checkUnreadStatus();
  }

  void _navigateTo(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('消息'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isLoggedIn) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('消息'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mail_outline, size: 64, color: colors.iconSecondary),
              const SizedBox(height: 16),
              Text(
                '登录后查看消息',
                style: TextStyle(fontSize: 16, color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final result = await LoginGuard.navigateToLogin(context);
                  if (result == true) {
                    _checkLoginStatus();
                  }
                },
                child: const Text('去登录'),
              ),
            ],
          ),
        ),
      );
    }

    return _buildContent();
  }

  Widget _buildContent() {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('消息'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 消息分类卡片
          Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildMessageItem(
                  icon: Icons.campaign_outlined,
                  iconColor: Colors.orange,
                  title: '站内公告',
                  subtitle: '系统通知和公告',
                  showDot: _unreadStatus[MessageReadStatus.announce] ?? false,
                  onTap: () => _navigateToAndMarkRead(MessageReadStatus.announce, const AnnouncePage()),
                ),
                _buildDivider(),
                _buildMessageItem(
                  icon: Icons.favorite_outline,
                  iconColor: Colors.red,
                  title: '收到的赞',
                  subtitle: '别人对你内容的点赞',
                  showDot: _unreadStatus[MessageReadStatus.like] ?? false,
                  onTap: () => _navigateToAndMarkRead(MessageReadStatus.like, const LikeMessagePage()),
                ),
                _buildDivider(),
                _buildMessageItem(
                  icon: Icons.chat_bubble_outline,
                  iconColor: Colors.blue,
                  title: '回复我的',
                  subtitle: '评论和回复消息',
                  showDot: _unreadStatus[MessageReadStatus.reply] ?? false,
                  onTap: () => _navigateToAndMarkRead(MessageReadStatus.reply, const ReplyMessagePage()),
                ),
                _buildDivider(),
                _buildMessageItem(
                  icon: Icons.alternate_email,
                  iconColor: Colors.green,
                  title: '@我的',
                  subtitle: '被提及的消息',
                  showDot: _unreadStatus[MessageReadStatus.at] ?? false,
                  onTap: () => _navigateToAndMarkRead(MessageReadStatus.at, const AtMessagePage()),
                ),
                _buildDivider(),
                _buildMessageItem(
                  icon: Icons.mail_outline,
                  iconColor: Colors.purple,
                  title: '私信',
                  subtitle: '私人消息',
                  onTap: () => _navigateTo(const WhisperPage()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool showDot = false,
  }) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (showDot) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colors.iconSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 74),
      child: Divider(
        height: 1,
        thickness: 1,
        color: colors.divider,
      ),
    );
  }
}
