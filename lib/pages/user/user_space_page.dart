import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/login_guard.dart';
import '../../utils/image_utils.dart';
import '../video/video_play_page.dart';

/// UP主个人空间页面
class UserSpacePage extends StatefulWidget {
  final int userId;

  const UserSpacePage({
    super.key,
    required this.userId,
  });

  @override
  State<UserSpacePage> createState() => _UserSpacePageState();
}

class _UserSpacePageState extends State<UserSpacePage>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();

  late TabController _tabController;
  UserBaseInfo? _userInfo;
  FollowCount? _followCount;
  int _relationStatus = 0;
  bool _isLoading = true;
  bool _isFollowLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _userService.getUserBaseInfo(widget.userId),
        _userService.getFollowCount(widget.userId),
        _userService.getUserRelation(widget.userId),
      ]);

      setState(() {
        _userInfo = results[0] as UserBaseInfo?;
        _followCount = results[1] as FollowCount?;
        _relationStatus = results[2] as int;
        _isLoading = false;
      });
    } catch (e) {
      print('加载用户数据失败: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFollow() async {
    if (_isFollowLoading) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (!await LoginGuard.check(context, actionName: '关注')) return;

    final currentUserId = await LoginGuard.getCurrentUserId();
    if (currentUserId != null && currentUserId == widget.userId) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('不能关注自己'), duration: Duration(seconds: 1)),
      );
      return;
    }

    setState(() => _isFollowLoading = true);

    try {
      bool success;
      final previousStatus = _relationStatus;

      if (_relationStatus == 0) {
        success = await _userService.followUser(widget.userId);
      } else {
        success = await _userService.unfollowUser(widget.userId);
      }

      if (success) {
        final newRelation = await _userService.getUserRelation(widget.userId);
        final newFollowCount = await _userService.getFollowCount(widget.userId);
        setState(() {
          _relationStatus = newRelation;
          _followCount = newFollowCount;
        });

        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(previousStatus == 0 ? '关注成功' : '已取消关注'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } finally {
      setState(() => _isFollowLoading = false);
    }
  }

  String _getFollowButtonText() {
    switch (_relationStatus) {
      case 0:
        return '关注';
      case 1:
        return '已关注';
      case 2:
        return '互相关注';
      default:
        return '关注';
    }
  }

  IconData? _getGenderIcon(int gender) {
    switch (gender) {
      case 1:
        return Icons.male;
      case 2:
        return Icons.female;
      default:
        return null;
    }
  }

  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('个人空间'),
          backgroundColor: colors.card,
        ),
        backgroundColor: colors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_userInfo == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('个人空间'),
          backgroundColor: colors.card,
        ),
        backgroundColor: colors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colors.iconSecondary),
              const SizedBox(height: 16),
              Text('用户不存在', style: TextStyle(color: colors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // 顶部用户信息区域
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              backgroundColor: colors.card,
              flexibleSpace: FlexibleSpaceBar(
                background: _buildUserHeader(),
              ),
              title: innerBoxIsScrolled
                  ? Text(_userInfo!.name, style: TextStyle(color: colors.textPrimary))
                  : null,
            ),
            // Tab栏
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: colors.accentColor,
                  unselectedLabelColor: colors.textSecondary,
                  indicatorColor: colors.accentColor,
                  tabs: const [
                    Tab(text: '投稿'),
                    Tab(text: '关注'),
                    Tab(text: '粉丝'),
                  ],
                ),
                colors.card,
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _UserVideosTab(userId: widget.userId),
            _FollowListTab(userId: widget.userId, isFollowing: true),
            _FollowListTab(userId: widget.userId, isFollowing: false),
          ],
        ),
      ),
    );
  }

  Widget _buildUserHeader() {
    final colors = context.colors;
    final user = _userInfo!;

    return Stack(
      children: [
        // 封面背景
        Positioned.fill(
          child: user.spaceCover.isNotEmpty
              ? CachedImage(
                  imageUrl: ImageUtils.getFullImageUrl(user.spaceCover),
                  fit: BoxFit.cover,
                  cacheKey: 'user_space_cover_${user.uid}',
                )
              : Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.accentColor.withValues(alpha: 0.8),
                        colors.accentColor.withValues(alpha: 0.4),
                      ],
                    ),
                  ),
                ),
        ),
        // 遮罩
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
        ),
        // 用户信息
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 头像
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: user.avatar.isNotEmpty
                        ? CachedCircleAvatar(
                            imageUrl: ImageUtils.getFullImageUrl(user.avatar),
                            radius: 40,
                            cacheKey: 'user_avatar_${user.uid}',
                          )
                        : CircleAvatar(
                            radius: 40,
                            backgroundColor: colors.surfaceVariant,
                            child: Icon(Icons.person, size: 40, color: colors.iconSecondary),
                          ),
                  ),
                  const SizedBox(width: 16),
                  // 用户名和性别
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_getGenderIcon(user.gender) != null) ...[
                              const SizedBox(width: 8),
                              Icon(
                                _getGenderIcon(user.gender),
                                size: 20,
                                color: user.gender == 1 ? Colors.lightBlue : Colors.pink,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'UID: ${user.uid}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 关注按钮
                  ElevatedButton(
                    onPressed: _isFollowLoading ? null : _handleFollow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _relationStatus == 0
                          ? colors.accentColor
                          : Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: _isFollowLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(_getFollowButtonText()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 签名
              if (user.sign.isNotEmpty)
                Text(
                  user.sign,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 12),
              // 统计数据
              Row(
                children: [
                  _buildStatItem('关注', _formatCount(_followCount?.followingCount ?? 0)),
                  const SizedBox(width: 24),
                  _buildStatItem('粉丝', _formatCount(_followCount?.followerCount ?? 0)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// Tab栏代理
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _SliverAppBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

/// 用户视频列表Tab
class _UserVideosTab extends StatefulWidget {
  final int userId;

  const _UserVideosTab({required this.userId});

  @override
  State<_UserVideosTab> createState() => _UserVideosTabState();
}

class _UserVideosTabState extends State<_UserVideosTab>
    with AutomaticKeepAliveClientMixin {
  final UserService _userService = UserService();
  final ScrollController _scrollController = ScrollController();

  final List<UserVideo> _videos = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 12;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreVideos();
    }
  }

  Future<void> _loadVideos({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _currentPage = 1;
        _videos.clear();
        _hasMore = true;
      }
    });

    try {
      final response = await _userService.getVideoByUser(
        widget.userId,
        _currentPage,
        _pageSize,
      );

      if (response != null) {
        setState(() {
          // 只显示审核通过的视频 (status == 0 表示审核通过)
          final approvedVideos =
              response.videos.where((v) => v.status == 0).toList();
          _videos.addAll(approvedVideos);
          _hasMore = response.videos.length >= _pageSize;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('加载视频失败: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreVideos() async {
    if (!_hasMore || _isLoading) return;
    _currentPage++;
    await _loadVideos();
  }

  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.colors;

    if (_videos.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, size: 64, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Text('暂无投稿', style: TextStyle(color: colors.textSecondary)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadVideos(refresh: true),
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _videos.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _videos.length) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildVideoCard(_videos[index]);
        },
      ),
    );
  }

  Widget _buildVideoCard(UserVideo video) {
    final colors = context.colors;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayPage(vid: video.vid),
          ),
        );
      },
      child: Card(
        elevation: 2,
        color: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  video.cover.isNotEmpty
                      ? CachedImage(
                          imageUrl: ImageUtils.getFullImageUrl(video.cover),
                          fit: BoxFit.cover,
                          cacheKey: 'video_cover_${video.vid}',
                        )
                      : Container(
                          color: colors.surfaceVariant,
                          child: Icon(
                            Icons.video_library,
                            size: 40,
                            color: colors.iconSecondary,
                          ),
                        ),
                  // 播放量
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow, size: 12, color: Colors.white),
                          const SizedBox(width: 2),
                          Text(
                            _formatCount(video.clicks),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                video.title,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 关注/粉丝列表Tab
class _FollowListTab extends StatefulWidget {
  final int userId;
  final bool isFollowing; // true为关注列表，false为粉丝列表

  const _FollowListTab({
    required this.userId,
    required this.isFollowing,
  });

  @override
  State<_FollowListTab> createState() => _FollowListTabState();
}

class _FollowListTabState extends State<_FollowListTab>
    with AutomaticKeepAliveClientMixin {
  final UserService _userService = UserService();
  final ScrollController _scrollController = ScrollController();

  final List<FollowUser> _users = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 20;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreUsers();
    }
  }

  Future<void> _loadUsers({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _currentPage = 1;
        _users.clear();
        _hasMore = true;
      }
    });

    try {
      final response = widget.isFollowing
          ? await _userService.getFollowings(widget.userId, _currentPage, _pageSize)
          : await _userService.getFollowers(widget.userId, _currentPage, _pageSize);

      if (response != null) {
        setState(() {
          _users.addAll(response.list);
          _hasMore = response.list.length >= _pageSize;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('加载用户列表失败: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreUsers() async {
    if (!_hasMore || _isLoading) return;
    _currentPage++;
    await _loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.colors;

    if (_users.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.isFollowing ? Icons.person_add_outlined : Icons.people_outline,
              size: 64,
              color: colors.iconSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              widget.isFollowing ? '暂无关注' : '暂无粉丝',
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadUsers(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _users.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _users.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _buildUserItem(_users[index]);
        },
      ),
    );
  }

  Widget _buildUserItem(FollowUser followUser) {
    final colors = context.colors;
    final user = followUser.user;

    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserSpacePage(userId: user.uid),
          ),
        );
      },
      leading: user.avatar.isNotEmpty
          ? CachedCircleAvatar(
              imageUrl: ImageUtils.getFullImageUrl(user.avatar),
              radius: 24,
              cacheKey: 'user_avatar_${user.uid}',
            )
          : CircleAvatar(
              radius: 24,
              backgroundColor: colors.surfaceVariant,
              child: Icon(Icons.person, color: colors.iconSecondary),
            ),
      title: Text(
        user.name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
      subtitle: user.sign.isNotEmpty
          ? Text(
              user.sign,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: _buildRelationBadge(followUser.relation),
    );
  }

  Widget? _buildRelationBadge(int relation) {
    final colors = context.colors;

    if (relation == 0) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: relation == 2
            ? colors.accentColor.withValues(alpha: 0.1)
            : colors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        relation == 2 ? '互相关注' : '已关注',
        style: TextStyle(
          fontSize: 11,
          color: relation == 2 ? colors.accentColor : colors.textSecondary,
        ),
      ),
    );
  }
}
