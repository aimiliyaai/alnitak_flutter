import 'package:flutter/material.dart';
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('消息'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 消息分类卡片
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 74),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey[100],
      ),
    );
  }
}
