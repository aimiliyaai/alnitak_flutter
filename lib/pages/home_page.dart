import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/video_item.dart';
import '../models/carousel_model.dart';
import '../services/video_api_service.dart';
import '../services/logger_service.dart';
import '../widgets/video_card.dart';
import '../widgets/carousel_widget.dart';
import '../theme/theme_extensions.dart';
import 'video/video_play_page.dart';
import 'search_page.dart';
import '../widgets/cached_image_widget.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _scrollController = ScrollController();

  List<VideoItem> _videos = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _errorMessage;
  static const int _pageSize = 10;

  // 【新增】用于防止并发加载的页码锁
  int? _loadingPage;

  // ============ 顶部导航状态 ============
  int _contentType = 0; // 0: 视频, 1: 专栏
  int _selectedCategory = 0; // 当前选中的分类
  bool _isSearchCollapsed = false; // 搜索栏是否收缩

  // 分类标签
  static const List<String> _categories = ['推荐', '生活', '影视', '游戏', '科技', '音乐', '舞蹈', '美食'];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 初始化日志服务
    LoggerService.instance.initialize();
    // 初始加载使用 asyncGetHotVideoAPI
    _loadInitialVideos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // 监听滚动，到底部时加载更多 + 搜索栏收缩逻辑
  void _onScroll() {
    final currentOffset = _scrollController.position.pixels;

    // 搜索栏收缩逻辑：向下滑动超过100px时收缩，回到顶部时展开
    if (currentOffset > 100 && !_isSearchCollapsed) {
      setState(() => _isSearchCollapsed = true);
    } else if (currentOffset <= 50 && _isSearchCollapsed) {
      setState(() => _isSearchCollapsed = false);
    }

    // 加载更多
    if (currentOffset >= _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreVideos();
    }
  }

  // 初始加载热门视频
  Future<void> _loadInitialVideos() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentPage = 1;
    });

    try {
      final apiVideos = await VideoApiService.asyncGetHotVideoAPI(
        page: 1,
        pageSize: _pageSize,
      );

      final videos = apiVideos
          .map((apiVideo) => VideoItem.fromApiModel(apiVideo))
          .toList();

      if (videos.isNotEmpty) {
        ///print('🖼️ 转换后的封面URL: ${videos[0].coverUrl}');
      }
      _preloadImages(videos);

      setState(() {
        _videos = videos;
        _hasMore = videos.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      // 记录错误日志
      await LoggerService.instance.logDataLoadError(
        dataType: '热门视频',
        operation: '初始加载',
        error: e,
        stackTrace: stackTrace,
        context: {
          '页码': 1,
          '每页数量': _pageSize,
        },
      );

      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载失败: $e'),
            action: SnackBarAction(
              label: '重试',
              onPressed: _loadInitialVideos,
            ),
          ),
        );
      }
    }
  }

  // 加载更多视频
  /// 【修复】使用页码锁防止并发加载同一页
  Future<void> _loadMoreVideos() async {
    if (_isLoading || !_hasMore) return;

    final nextPage = _currentPage + 1;

    // 【修复】检查是否已经在加载这一页
    if (_loadingPage == nextPage) {
      print('⏭️ 页面 $nextPage 正在加载中，跳过重复请求');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    _loadingPage = nextPage;

    try {
      final apiVideos = await VideoApiService.getHotVideoAPI(
        page: nextPage,
        pageSize: _pageSize,
      );

      // 【修复】检查是否仍然是当前请求的页（防止竞态）
      if (_loadingPage != nextPage) {
        print('⏭️ 页面 $nextPage 加载完成但已过期，丢弃数据');
        return;
      }

      final newVideos = apiVideos
          .map((apiVideo) => VideoItem.fromApiModel(apiVideo))
          .toList();
      _preloadImages(newVideos);

      setState(() {
        _videos.addAll(newVideos);
        _currentPage = nextPage;
        _hasMore = newVideos.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      // 记录错误日志
      await LoggerService.instance.logDataLoadError(
        dataType: '热门视频',
        operation: '加载更多',
        error: e,
        stackTrace: stackTrace,
        context: {
          '页码': nextPage,
          '每页数量': _pageSize,
          '当前视频数量': _videos.length,
        },
      );

      setState(() {
        _isLoading = false;
        _hasMore = false; // 出错时停止加载更多
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载更多失败: $e'),
          ),
        );
      }
    } finally {
      // 【修复】清除加载锁
      if (_loadingPage == nextPage) {
        _loadingPage = null;
      }
    }
  }

  void _preloadImages(List<VideoItem> videos) {
    for (final video in videos) {
      SmartCacheManager.preloadImage(
        video.coverUrl,
        cacheKey: 'video_cover_${video.id}',
      );
      if (video.authorAvatar != null && video.authorUid != null) {
        SmartCacheManager.preloadImage(
          video.authorAvatar!,
          cacheKey: 'user_avatar_${video.authorUid}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 设置沉浸式状态栏
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: colors.background,
        // 去掉 AppBar，让内容延伸到状态栏下方
        extendBodyBehindAppBar: true,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    // 显示错误信息
    if (_errorMessage != null && _videos.isEmpty) {
      return SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colors.iconSecondary),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadInitialVideos,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    // 初始加载中
    if (_videos.isEmpty && _isLoading) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 视频列表 - 使用 Stack 实现固定搜索图标
    return Stack(
      children: [
        // 主内容区域
        RefreshIndicator(
          onRefresh: _loadInitialVideos,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 顶部区域：搜索栏 + 视频/专栏切换 + 分类标签
              SliverToBoxAdapter(
                child: _buildHeader(statusBarHeight),
              ),
              // 轮播图
              SliverToBoxAdapter(
                child: CarouselWidget(
                  onTap: _onCarouselTap,
                ),
              ),
              // 双列网格布局
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return VideoCard(
                        video: _videos[index],
                        onTap: () {
                          _showVideoDetail(context, _videos[index]);
                        },
                      );
                    },
                    childCount: _videos.length,
                  ),
                ),
              ),
              // 加载更多指示器
              if (_isLoading && _videos.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              // 没有更多数据提示
              if (!_hasMore && _videos.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        '没有更多了',
                        style: TextStyle(color: colors.textTertiary),
                      ),
                    ),
                  ),
                ),
              // 底部占位，防止最后一行被遮挡
              const SliverToBoxAdapter(
                child: SizedBox(height: 16),
              ),
            ],
          ),
        ),
        // 右上角固定搜索图标（滚动时显示）
        if (_isSearchCollapsed)
          Positioned(
            top: statusBarHeight + 8,
            right: 12,
            child: _buildCollapsedSearchButton(),
          ),
      ],
    );
  }

  /// 构建顶部区域：搜索栏 + 视频/专栏切换 + 分类标签
  Widget _buildHeader(double statusBarHeight) {
    return Container(
      padding: EdgeInsets.only(top: statusBarHeight),
      child: Column(
        children: [
          // 搜索栏（未收缩时显示）
          if (!_isSearchCollapsed) _buildSearchBar(),
          // 视频/专栏切换
          _buildContentTypeSwitch(),
          // 分类标签
          _buildCategoryTabs(),
        ],
      ),
    );
  }

  /// 构建搜索栏
  Widget _buildSearchBar() {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GestureDetector(
        onTap: _navigateToSearch,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.inputBackground,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 20, color: colors.textTertiary),
              const SizedBox(width: 8),
              Text(
                '搜索视频、UP主',
                style: TextStyle(color: colors.textTertiary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建视频/专栏切换
  Widget _buildContentTypeSwitch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildSwitchItem('视频', 0),
          const SizedBox(width: 24),
          _buildSwitchItem('专栏', 1),
        ],
      ),
    );
  }

  Widget _buildSwitchItem(String title, int index) {
    final colors = context.colors;
    final isSelected = _contentType == index;

    return GestureDetector(
      onTap: () {
        if (_contentType != index) {
          setState(() => _contentType = index);
          // TODO: 切换内容类型时重新加载数据
        }
      },
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: isSelected ? 18 : 15,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 20,
            height: 3,
            decoration: BoxDecoration(
              color: isSelected ? colors.accentColor : Colors.transparent,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建分类标签
  Widget _buildCategoryTabs() {
    final colors = context.colors;

    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedCategory == index;
          return GestureDetector(
            onTap: () {
              if (_selectedCategory != index) {
                setState(() => _selectedCategory = index);
                // TODO: 切换分类时重新加载数据
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(
                _categories[index],
                style: TextStyle(
                  fontSize: 14,
                  color: isSelected ? colors.accentColor : colors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建收缩后的搜索按钮
  Widget _buildCollapsedSearchButton() {
    final colors = context.colors;

    return GestureDetector(
      onTap: _navigateToSearch,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(Icons.search, size: 22, color: colors.textSecondary),
      ),
    );
  }

  /// 导航到搜索页
  void _navigateToSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchPage()),
    );
  }

  void _showVideoDetail(BuildContext context, VideoItem video) {
    // 跳转到视频播放页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayPage(
          vid: int.parse(video.id),
        ),
      ),
    );
  }

  /// 轮播图点击处理
  void _onCarouselTap(CarouselItem item) {
    // 如果有url，解析并跳转
    if (item.url != null && item.url!.isNotEmpty) {
      // 尝试解析视频ID（格式如：/video/123）
      final videoMatch = RegExp(r'/video/(\d+)').firstMatch(item.url!);
      if (videoMatch != null) {
        final vid = int.tryParse(videoMatch.group(1)!);
        if (vid != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayPage(vid: vid),
            ),
          );
          return;
        }
      }
      // 其他链接暂不处理，后续可以添加WebView或外部浏览器打开
    }
  }
}