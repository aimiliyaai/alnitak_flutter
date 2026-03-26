import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../models/article_list_model.dart';
import '../models/user_model.dart';
import '../services/video_api_service.dart';
import '../services/article_api_service.dart';
import '../services/user_service.dart';
import '../services/logger_service.dart';
import '../widgets/video_card.dart';
import '../theme/theme_extensions.dart';
import '../utils/image_utils.dart';
import 'video/video_play_page.dart';
import 'article/article_view_page.dart';
import 'user/user_space_page.dart';

/// 综合搜索：视频 / 专栏 / UP主
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late TabController _tabController;

  final ScrollController _videoScroll = ScrollController();
  final ScrollController _articleScroll = ScrollController();
  final ScrollController _userScroll = ScrollController();

  final UserService _userService = UserService();

  static const int _pageSize = 30;

  List<VideoItem> _videos = [];
  int _videoPage = 1;
  bool _videoLoading = false;
  bool _videoHasMore = true;

  List<ArticleListItem> _articles = [];
  int _articlePage = 1;
  bool _articleLoading = false;
  bool _articleHasMore = true;

  List<UserBaseInfo> _users = [];
  int _userPage = 1;
  bool _userLoading = false;
  bool _userHasMore = true;

  bool _hasSearched = false;
  String _keywords = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _videoScroll.addListener(() => _onScroll(0));
    _articleScroll.addListener(() => _onScroll(1));
    _userScroll.addListener(() => _onScroll(2));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_keywords.isEmpty) return;
    _ensureTabLoaded(_tabController.index);
  }

  void _onScroll(int tabIndex) {
    if (_tabController.index != tabIndex) return;
    final c = tabIndex == 0
        ? _videoScroll
        : tabIndex == 1
            ? _articleScroll
            : _userScroll;
    if (!c.hasClients) return;
    if (c.position.pixels < c.position.maxScrollExtent * 0.85) return;
    _loadMoreForTab(tabIndex);
  }

  Future<void> _ensureTabLoaded(int index) async {
    if (index == 0 && _videos.isEmpty && !_videoLoading) {
      await _loadVideos(reset: true);
    } else if (index == 1 && _articles.isEmpty && !_articleLoading) {
      await _loadArticles(reset: true);
    } else if (index == 2 && _users.isEmpty && !_userLoading) {
      await _loadUsers(reset: true);
    }
  }

  Future<void> _loadMoreForTab(int index) async {
    if (index == 0) {
      if (!_videoHasMore || _videoLoading) return;
      await _loadVideos(reset: false);
    } else if (index == 1) {
      if (!_articleHasMore || _articleLoading) return;
      await _loadArticles(reset: false);
    } else {
      if (!_userHasMore || _userLoading) return;
      await _loadUsers(reset: false);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _videoScroll.dispose();
    _articleScroll.dispose();
    _userScroll.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final keywords = _searchController.text.trim();
    if (keywords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入搜索关键词')),
      );
      return;
    }
    FocusScope.of(context).unfocus();

    setState(() {
      _keywords = keywords;
      _hasSearched = true;
      _errorMessage = null;
      _videos = [];
      _videoPage = 1;
      _videoHasMore = true;
      _articles = [];
      _articlePage = 1;
      _articleHasMore = true;
      _users = [];
      _userPage = 1;
      _userHasMore = true;
    });

    await _loadCurrentTab(reset: true);
  }

  Future<void> _loadCurrentTab({required bool reset}) async {
    final i = _tabController.index;
    if (i == 0) await _loadVideos(reset: reset);
    if (i == 1) await _loadArticles(reset: reset);
    if (i == 2) await _loadUsers(reset: reset);
  }

  Future<void> _loadVideos({required bool reset}) async {
    if (_videoLoading) return;
    setState(() => _videoLoading = true);
    if (reset) {
      _videoPage = 1;
      _videos = [];
      _videoHasMore = true;
    }
    try {
      final list = await VideoApiService.searchVideo(
        keywords: _keywords,
        page: _videoPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _videos.addAll(list.map((e) => VideoItem.fromApiModel(e)));
        if (list.length < _pageSize) {
          _videoHasMore = false;
        } else {
          _videoPage++;
        }
        _videoLoading = false;
        if (_videos.isEmpty) {
          _errorMessage = '未找到相关视频';
        } else {
          _errorMessage = null;
        }
      });
    } catch (e, st) {
      await LoggerService.instance.logDataLoadError(
        dataType: '搜索视频',
        operation: '搜索',
        error: e,
        stackTrace: st,
        context: {'关键词': _keywords},
      );
      if (!mounted) return;
      setState(() {
        _videoLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadArticles({required bool reset}) async {
    if (_articleLoading) return;
    setState(() => _articleLoading = true);
    if (reset) {
      _articlePage = 1;
      _articles = [];
      _articleHasMore = true;
    }
    try {
      final list = await ArticleApiService.searchArticles(
        keywords: _keywords,
        page: _articlePage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _articles.addAll(list);
        if (list.length < _pageSize) {
          _articleHasMore = false;
        } else {
          _articlePage++;
        }
        _articleLoading = false;
      });
    } catch (e, st) {
      await LoggerService.instance.logDataLoadError(
        dataType: '搜索专栏',
        operation: '搜索',
        error: e,
        stackTrace: st,
        context: {'关键词': _keywords},
      );
      if (!mounted) return;
      setState(() {
        _articleLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('专栏搜索失败: $e')),
        );
      }
    }
  }

  Future<void> _loadUsers({required bool reset}) async {
    if (_userLoading) return;
    setState(() => _userLoading = true);
    if (reset) {
      _userPage = 1;
      _users = [];
      _userHasMore = true;
    }
    try {
      final list = await _userService.searchUsers(
        keywords: _keywords,
        page: _userPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _users.addAll(list);
        if (list.length < _pageSize) {
          _userHasMore = false;
        } else {
          _userPage++;
        }
        _userLoading = false;
      });
    } catch (e, st) {
      await LoggerService.instance.logDataLoadError(
        dataType: '搜索用户',
        operation: '搜索',
        error: e,
        stackTrace: st,
        context: {'关键词': _keywords},
      );
      if (!mounted) return;
      setState(() {
        _userLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('用户搜索失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: colors.inputBackground,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: '搜索视频、专栏、UP主',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              hintStyle: TextStyle(
                color: colors.textTertiary,
                fontSize: 15,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: colors.iconSecondary,
                size: 20,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: colors.iconSecondary,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                        });
                      },
                    )
                  : null,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _performSearch(),
            onChanged: (_) => setState(() {}),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _performSearch,
            child: Text(
              '搜索',
              style: TextStyle(fontSize: 15, color: colors.accentColor),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colors.accentColor,
          unselectedLabelColor: colors.textSecondary,
          tabs: const [
            Tab(text: '视频'),
            Tab(text: '专栏'),
            Tab(text: 'UP主'),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Text(
              '输入关键词搜索',
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildVideoTab(colors),
        _buildArticleTab(colors),
        _buildUserTab(colors),
      ],
    );
  }

  Widget _buildVideoTab(dynamic colors) {
    if (_errorMessage != null &&
        _videos.isEmpty &&
        !_videoLoading &&
        _tabController.index == 0) {
      return _buildError(colors, _errorMessage!, _performSearch);
    }
    if (_videos.isEmpty && _videoLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_videos.isEmpty) {
      return Center(
        child: Text('暂无相关视频', style: TextStyle(color: colors.textSecondary)),
      );
    }
    return CustomScrollView(
      controller: _videoScroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.05,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final v = _videos[index];
                return VideoCard(
                  video: v,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            VideoPlayPage(vid: int.parse(v.id)),
                      ),
                    );
                  },
                );
              },
              childCount: _videos.length,
            ),
          ),
        ),
        if (_videoLoading && _videos.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        if (!_videoHasMore && _videos.isNotEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('没有更多了', style: TextStyle(color: colors.textTertiary)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildArticleTab(dynamic colors) {
    if (_articles.isEmpty && _articleLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_articles.isEmpty) {
      return Center(
        child: Text('暂无相关专栏', style: TextStyle(color: colors.textSecondary)),
      );
    }
    return ListView.builder(
      controller: _articleScroll,
      padding: const EdgeInsets.all(12),
      itemCount: _articles.length + 1,
      itemBuilder: (context, index) {
        if (index >= _articles.length) {
          if (_articleLoading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (_articles.isNotEmpty && !_articleHasMore) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('没有更多了', style: TextStyle(color: colors.textTertiary)),
              ),
            );
          }
          return const SizedBox.shrink();
        }
        final a = _articles[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                a.cover,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72),
              ),
            ),
            title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              a.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ArticleViewPage(aid: a.aid),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildUserTab(dynamic colors) {
    if (_users.isEmpty && _userLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_users.isEmpty) {
      return Center(
        child: Text('暂无相关用户', style: TextStyle(color: colors.textSecondary)),
      );
    }
    return ListView.builder(
      controller: _userScroll,
      padding: const EdgeInsets.all(12),
      itemCount: _users.length + 1,
      itemBuilder: (context, index) {
        if (index >= _users.length) {
          if (_userLoading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (_users.isNotEmpty && !_userHasMore) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('没有更多了', style: TextStyle(color: colors.textTertiary)),
              ),
            );
          }
          return const SizedBox.shrink();
        }
        final u = _users[index];
        final avatarUrl = ImageUtils.getFullImageUrl(u.avatar);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            ),
            title: Text(u.name),
            subtitle: Text(
              u.sign.isEmpty ? '暂无签名' : u.sign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: u.fans != null
                ? Text('粉丝 ${u.fans}', style: TextStyle(fontSize: 12, color: colors.textTertiary))
                : null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserSpacePage(userId: u.uid),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildError(
    dynamic colors,
    String msg,
    VoidCallback onRetry,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: colors.iconSecondary),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
