import 'package:flutter/material.dart';
import '../widgets/cached_image_widget.dart';

/// 个人中心页面 - 简洁列表式设计
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // 模拟用户数据（实际应从API获取）
  final String _userName = 'Ethan';
  final String _userId = 'UID:123456789';
  final int _fansCount = 500;
  final int _videoCount = 100;
  String? _avatarUrl; // 用户头像URL，null表示使用默认头像

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // AppBar
            _buildAppBar(),

            // 用户信息卡片
            SliverToBoxAdapter(
              child: _buildUserInfoCard(),
            ),

            // 功能菜单列表
            SliverToBoxAdapter(
              child: _buildMenuList(),
            ),

            // 特色区域
            SliverToBoxAdapter(
              child: _buildSpecialSection(),
            ),

            // 底部间距
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建 AppBar
  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.white,
      centerTitle: true,
      title: const Text(
        '我的',
        style: TextStyle(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.black),
          onPressed: () {
            // TODO: 打开设置页面
          },
        ),
      ],
    );
  }

  /// 构建用户信息卡片
  Widget _buildUserInfoCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 头像
          _avatarUrl != null && _avatarUrl!.isNotEmpty
              ? CachedCircleAvatar(
                  imageUrl: _avatarUrl!,
                  radius: 50,
                )
              : CircleAvatar(
                  radius: 50,
                  backgroundColor: const Color(0xFFE8D5C4),
                  child: const Icon(
                    Icons.person,
                    size: 60,
                    color: Color(0xFF8B7355),
                  ),
                ),
          const SizedBox(height: 16),

          // 用户名
          Text(
            _userName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),

          // UID
          Text(
            _userId,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),

          // 粉丝和视频数
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_fansCount粉丝',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                width: 1,
                height: 12,
                color: Colors.grey[300],
              ),
              Text(
                '$_videoCount个视频',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建功能菜单列表
  Widget _buildMenuList() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.notifications_outlined,
            title: '消息',
            onTap: () {
              // TODO: 打开消息页面
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            icon: Icons.history_outlined,
            title: '观看历史',
            onTap: () {
              // TODO: 打开观看历史
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            icon: Icons.bookmark_border,
            title: '收藏夹',
            onTap: () {
              // TODO: 打开收藏夹
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            icon: Icons.download_outlined,
            title: '离线缓存',
            onTap: () {
              // TODO: 打开离线缓存
            },
          ),
        ],
      ),
    );
  }

  /// 构建特色区域
  Widget _buildSpecialSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            '特色区域',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
        ),

        // 创作中心卡片
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _buildMenuItem(
            icon: Icons.video_library_outlined,
            title: '创作中心',
            onTap: () {
              // TODO: 打开创作中心
            },
          ),
        ),
      ],
    );
  }

  /// 构建菜单项
  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: Colors.grey[700],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.grey[400],
                ),
          ],
        ),
      ),
    );
  }

  /// 构建分割线
  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey[100],
      ),
    );
  }
}
