import 'package:flutter/material.dart';
import 'comment_manage_page.dart';
import 'video_manage_page.dart';
import 'playlist_manage_page.dart';
import '../upload/article_manuscript_page.dart';
import '../upload/video_upload_page.dart';
import '../upload/article_upload_page.dart';
import '../../utils/login_guard.dart';
import '../../theme/theme_extensions.dart';

/// 创作中心页面
class CreatorCenterPage extends StatefulWidget {
  const CreatorCenterPage({super.key});

  @override
  State<CreatorCenterPage> createState() => _CreatorCenterPageState();
}

class _CreatorCenterPageState extends State<CreatorCenterPage> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  /// 检查登录状态
  Future<void> _checkLogin() async {
    final isLoggedIn = await LoginGuard.isLoggedInAsync();

    if (!isLoggedIn && mounted) {
      // 未登录，显示提示并跳转登录
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final result = await LoginGuard.navigateToLogin(context);
        if (result != true && mounted) {
          // 用户没有登录成功，返回上一页
          Navigator.pop(context);
        }
      });
    }
  }

  /// 显示上传类型选择对话框
  void _showUploadTypeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择投稿类型'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_library, color: Colors.blue),
              title: const Text('视频投稿'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const VideoUploadPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.article, color: Colors.green),
              title: const Text('文章投稿'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ArticleUploadPage()),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('创作中心'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 菜单列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildMenuItem(
                  icon: Icons.video_library_outlined,
                  title: '视频管理',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const VideoManagePage()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.article_outlined,
                  title: '文章管理',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ArticleManuscriptPage()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.playlist_play_outlined,
                  title: '合集管理',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PlaylistManagePage()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.comment_outlined,
                  title: '评论管理',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CommentManagePage()),
                    );
                  },
                ),
              ],
            ),
          ),

          // 底部发布按钮
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _showUploadTypeDialog,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    '发布新稿件',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建菜单项
  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            // 图标
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 24,
                color: colors.iconPrimary,
              ),
            ),
            const SizedBox(width: 16),

            // 标题
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: colors.textPrimary,
                ),
              ),
            ),

            // 箭头
            Icon(
              Icons.chevron_right,
              size: 24,
              color: colors.iconSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
