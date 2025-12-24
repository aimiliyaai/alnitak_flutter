import 'package:flutter/material.dart';
import '../../utils/login_guard.dart';
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

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final loggedIn = await LoginGuard.isLoggedIn();
    if (mounted) {
      setState(() {
        _isLoggedIn = loggedIn;
        _isLoading = false;
      });
    }
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
                  onTap: () => _navigateTo(const AnnouncePage()),
                ),
                _buildDivider(),
                _buildMessageItem(
                  icon: Icons.favorite_outline,
                  iconColor: Colors.red,
                  title: '收到的赞',
                  subtitle: '别人对你内容的点赞',
                  onTap: () => _navigateTo(const LikeMessagePage()),
                ),
                _buildDivider(),
                _buildMessageItem(
                  icon: Icons.chat_bubble_outline,
                  iconColor: Colors.blue,
                  title: '回复我的',
                  subtitle: '评论和回复消息',
                  onTap: () => _navigateTo(const ReplyMessagePage()),
                ),
                _buildDivider(),
                _buildMessageItem(
                  icon: Icons.alternate_email,
                  iconColor: Colors.green,
                  title: '@我的',
                  subtitle: '被提及的消息',
                  onTap: () => _navigateTo(const AtMessagePage()),
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

  void _navigateTo(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  Widget _buildMessageItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
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
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
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
