import 'package:flutter/material.dart';
import '../widgets/cached_image_widget.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import '../utils/image_utils.dart';
import '../utils/auth_state_manager.dart';
import 'login_page.dart';
import 'edit_profile_page.dart';
import 'creator/creator_center_page.dart';
import 'history_page.dart';

/// 个人中心页面 - 简洁列表式设计
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final AuthStateManager _authStateManager = AuthStateManager();

  // 用户数据
  UserBaseInfo? _userInfo;
  bool _isLoggedIn = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // 监听登录状态变化
    _authStateManager.addListener(_onAuthStateChanged);
    _loadUserData();
  }

  @override
  void dispose() {
    _authStateManager.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  /// 登录状态变化回调
  void _onAuthStateChanged() {
    // 当登录状态变化时，重新加载用户数据
    _loadUserData();
  }

  /// 加载用户数据
  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    // 检查是否登录
    final isLoggedIn = await _authService.isLoggedIn();
    setState(() => _isLoggedIn = isLoggedIn);

    if (isLoggedIn) {
      // 获取用户信息
      final userInfo = await _userService.getUserInfo();
      if (userInfo != null) {
        setState(() {
          _userInfo = userInfo.userInfo;
          _isLoading = false;
        });
      } else {
        // Token 可能过期，尝试刷新
        final newToken = await _authService.updateToken();
        if (newToken != null) {
          // 重试获取用户信息
          final retryUserInfo = await _userService.getUserInfo();
          setState(() {
            _userInfo = retryUserInfo?.userInfo;
            _isLoading = false;
          });
        } else {
          // Token 失效，清除登录状态
          setState(() {
            _isLoggedIn = false;
            _isLoading = false;
          });
        }
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  /// 退出登录
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _authService.logout();
      // 通知全局登录状态变化
      _authStateManager.onLogout();
      setState(() {
        _isLoggedIn = false;
        _userInfo = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已退出登录')),
        );
      }
    }
  }

  /// 跳转到登录页面
  Future<void> _navigateToLogin() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );

    // 如果登录成功，刷新用户数据
    if (result == true) {
      _loadUserData();
    }
  }

  /// 跳转到编辑个人资料页面
  Future<void> _navigateToEditProfile() async {
    if (_userInfo == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfilePage(userInfo: _userInfo!),
      ),
    );

    // 如果编辑成功，刷新用户数据
    if (result == true) {
      _loadUserData();
    }
  }

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
        if (_isLoggedIn)
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: _handleLogout,
          )
        else
          IconButton(
            icon: const Icon(Icons.login, color: Colors.black),
            onPressed: _navigateToLogin,
          ),
      ],
    );
  }

  /// 构建用户信息卡片
  Widget _buildUserInfoCard() {
    // 加载中状态
    if (_isLoading) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 未登录状态
    if (!_isLoggedIn || _userInfo == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // 默认头像
            CircleAvatar(
              radius: 50,
              backgroundColor: const Color(0xFFE8D5C4),
              child: const Icon(
                Icons.person,
                size: 60,
                color: Color(0xFF8B7355),
              ),
            ),
            const SizedBox(height: 16),

            // 未登录提示
            Text(
              '未登录',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            // 登录按钮
            ElevatedButton(
              onPressed: _navigateToLogin,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('立即登录'),
            ),
          ],
        ),
      );
    }

    // 已登录状态
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
          _userInfo!.avatar.isNotEmpty
              ? CachedCircleAvatar(
                  imageUrl: ImageUtils.getFullImageUrl(_userInfo!.avatar),
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
            _userInfo!.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),

          // UID
          Text(
            'UID: ${_userInfo!.uid}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),

          // 个性签名
          if (_userInfo!.sign.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _userInfo!.sign,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // 编辑按钮
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _navigateToEditProfile,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: const Text(
              '编辑资料',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryPage()),
              );
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
          _buildDivider(),
          _buildMenuItem(
            icon: Icons.settings_outlined,
            title: '设置',
            onTap: () {
              Navigator.pushNamed(context, '/settings');
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreatorCenterPage()),
              );
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
