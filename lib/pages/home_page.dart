import 'package:alnitak_flutter/models/partition.dart';
import 'package:alnitak_flutter/services/partition_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/video_item.dart';
import '../models/carousel_model.dart';
import '../models/article_list_model.dart';
import '../services/video_api_service.dart';
import '../services/article_api_service.dart';
import '../services/logger_service.dart';
import '../widgets/video_card.dart';
import '../widgets/carousel_widget.dart';
import '../theme/theme_extensions.dart';
import 'video/video_play_page.dart';
import 'search_page.dart';
import 'article/article_view_page.dart';
import '../widgets/cached_image_widget.dart';
import '../utils/grid_delegate.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  // ============ 视频数据 ============
  List<VideoItem> _videos = [];
  int _videoPage = 1;
  bool _isLoadingVideos = false;
  bool _hasMoreVideos = true;

  // ============ 文章数据 ============
  List<ArticleListItem> _articles = [];
  int _articlePage = 1;
  bool _isLoadingArticles = false;
  bool _hasMoreArticles = true;

  String? _errorMessage;
  static const int _pageSize = 10;

  // 防止并发加载的页码锁
  int? _loadingPage;
  int? _loadingArticlePage;

  // ============ 顶部导航状态 ============
  int _contentType = 0; // 0: 视频, 1: 专栏
  int _selectedPartitionId = 0; // 当前选中的分区ID，0表示推荐
  bool _isSearchCollapsed = false; // 搜索栏是否收缩

  // ============ 分区（分类）状态 ============
  List<Partition> _videoPartitions = [];
  List<Partition> _articlePartitions = [];
  bool _isFetchingPartitions = false;
  bool _isVideoTagsExpanded = false;
  bool _isArticleTagsExpanded = false;

  // ============ 动画控制器 ============
  late AnimationController _headerAnimController;
  late Animation<double> _headerAnimation;

  @override
  void initState() {
    super.initState();

    // 初始化动画控制器
    _headerAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _headerAnimation = CurvedAnimation(
      parent: _headerAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _scrollController.addListener(_onScroll);
    // 初始化日志服务
    LoggerService.instance.initialize();
    // 并发加载初始数据
    _loadInitialData();
  }

  // 并发加载初始视频和分区
  Future<void> _loadInitialData() async {
    // 同时开始视频加载和分区加载
    await Future.wait([
      _loadInitialVideos(),
      _fetchPartitions(),
    ]);
  }

  // 获取分区（分类）
  Future<void> _fetchPartitions() async {
    if (_isFetchingPartitions) return;
    setState(() {
      _isFetchingPartitions = true;
    });

    try {
      // 并发获取视频和文章分区
      final results = await Future.wait([
        PartitionApiService.getVideoPartitions(),
        PartitionApiService.getArticlePartitions(),
      ]);

      final videoPartitions = results[0];
      final articlePartitions = results[1];

      if (mounted) {
        setState(() {
          _videoPartitions = videoPartitions;
          _articlePartitions = articlePartitions;
        });
      }
    } catch (e) {
      // 静默失败，使用空列表
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingPartitions = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _headerAnimController.dispose();
    super.dispose();
  }

  // 监听滚动，到底部时加载更多 + 搜索栏收缩逻辑
  void _onScroll() {
    final currentOffset = _scrollController.position.pixels;

    // 搜索栏收缩逻辑：向下滑动超过100px时收缩，回到顶部时展开
    if (currentOffset > 100 && !_isSearchCollapsed) {
      setState(() => _isSearchCollapsed = true);
      _headerAnimController.forward(); // 播放收缩动画
    } else if (currentOffset <= 50 && _isSearchCollapsed) {
      setState(() => _isSearchCollapsed = false);
      _headerAnimController.reverse(); // 播放展开动画
    }

    // 加载更多
    final isLoading = _contentType == 0 ? _isLoadingVideos : _isLoadingArticles;
    final hasMore = _contentType == 0 ? _hasMoreVideos : _hasMoreArticles;

    if (currentOffset >= _scrollController.position.maxScrollExtent * 0.8 &&
        !isLoading &&
        hasMore) {
      if (_contentType == 0) {
        _loadMoreVideos();
      } else {
        _loadMoreArticles();
      }
    }
  }

  // 初始加载视频（根据分区）
  Future<void> _loadInitialVideos() async {
    if (_isLoadingVideos) return;

    setState(() {
      _isLoadingVideos = true;
      _errorMessage = null;
      _videoPage = 1;
    });

    try {
      final apiVideos = await VideoApiService.getVideoByPartition(
        partitionId: _selectedPartitionId,
        page: 1,
        pageSize: _pageSize,
      );

      final videos = apiVideos
          .map((apiVideo) => VideoItem.fromApiModel(apiVideo))
          .toList();

      _preloadImages(videos);

      setState(() {
        _videos = videos;
        _hasMoreVideos = videos.length >= _pageSize;
        _isLoadingVideos = false;
      });
    } catch (e, stackTrace) {
      // 记录错误日志
      await LoggerService.instance.logDataLoadError(
        dataType: '视频',
        operation: '初始加载',
        error: e,
        stackTrace: stackTrace,
        context: {
          '页码': 1,
          '每页数量': _pageSize,
          '分区ID': _selectedPartitionId,
        },
      );

      setState(() {
        _errorMessage = e.toString();
        _isLoadingVideos = false;
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
  Future<void> _loadMoreVideos() async {
    if (_isLoadingVideos || !_hasMoreVideos) return;

    final nextPage = _videoPage + 1;

    // 检查是否已经在加载这一页
    if (_loadingPage == nextPage) {
      return;
    }

    setState(() {
      _isLoadingVideos = true;
    });

    _loadingPage = nextPage;

    try {
      final apiVideos = await VideoApiService.getVideoByPartition(
        partitionId: _selectedPartitionId,
        page: nextPage,
        pageSize: _pageSize,
      );

      // 检查是否仍然是当前请求的页（防止竞态）
      if (_loadingPage != nextPage) {
        return;
      }

      final newVideos = apiVideos
          .map((apiVideo) => VideoItem.fromApiModel(apiVideo))
          .toList();
      _preloadImages(newVideos);

      setState(() {
        _videos.addAll(newVideos);
        _videoPage = nextPage;
        _hasMoreVideos = newVideos.length >= _pageSize;
        _isLoadingVideos = false;
      });
    } catch (e, stackTrace) {
      // 记录错误日志
      await LoggerService.instance.logDataLoadError(
        dataType: '视频',
        operation: '加载更多',
        error: e,
        stackTrace: stackTrace,
        context: {
          '页码': nextPage,
          '每页数量': _pageSize,
          '当前视频数量': _videos.length,
          '分区ID': _selectedPartitionId,
        },
      );

      setState(() {
        _isLoadingVideos = false;
        _hasMoreVideos = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载更多失败: $e'),
          ),
        );
      }
    } finally {
      if (_loadingPage == nextPage) {
        _loadingPage = null;
      }
    }
  }

  // 初始加载文章（根据分区）
  Future<void> _loadInitialArticles() async {
    if (_isLoadingArticles) return;

    setState(() {
      _isLoadingArticles = true;
      _errorMessage = null;
      _articlePage = 1;
    });

    try {
      final articles = await ArticleApiService.getArticleByPartition(
        partitionId: _selectedPartitionId,
        page: 1,
        pageSize: _pageSize,
      );

      setState(() {
        _articles = articles;
        _hasMoreArticles = articles.length >= _pageSize;
        _isLoadingArticles = false;
      });
    } catch (e, stackTrace) {
      await LoggerService.instance.logDataLoadError(
        dataType: '文章',
        operation: '初始加载',
        error: e,
        stackTrace: stackTrace,
        context: {
          '页码': 1,
          '每页数量': _pageSize,
          '分区ID': _selectedPartitionId,
        },
      );

      setState(() {
        _errorMessage = e.toString();
        _isLoadingArticles = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载失败: $e'),
            action: SnackBarAction(
              label: '重试',
              onPressed: _loadInitialArticles,
            ),
          ),
        );
      }
    }
  }

  // 加载更多文章
  Future<void> _loadMoreArticles() async {
    if (_isLoadingArticles || !_hasMoreArticles) return;

    final nextPage = _articlePage + 1;

    // 检查是否已经在加载这一页
    if (_loadingArticlePage == nextPage) {
      return;
    }

    setState(() {
      _isLoadingArticles = true;
    });

    _loadingArticlePage = nextPage;

    try {
      final newArticles = await ArticleApiService.getArticleByPartition(
        partitionId: _selectedPartitionId,
        page: nextPage,
        pageSize: _pageSize,
      );

      // 检查是否仍然是当前请求的页（防止竞态）
      if (_loadingArticlePage != nextPage) {
        return;
      }

      setState(() {
        _articles.addAll(newArticles);
        _articlePage = nextPage;
        _hasMoreArticles = newArticles.length >= _pageSize;
        _isLoadingArticles = false;
      });
    } catch (e, stackTrace) {
      await LoggerService.instance.logDataLoadError(
        dataType: '文章',
        operation: '加载更多',
        error: e,
        stackTrace: stackTrace,
        context: {
          '页码': nextPage,
          '每页数量': _pageSize,
          '当前文章数量': _articles.length,
          '分区ID': _selectedPartitionId,
        },
      );

      setState(() {
        _isLoadingArticles = false;
        _hasMoreArticles = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载更多失败: $e'),
          ),
        );
      }
    } finally {
      if (_loadingArticlePage == nextPage) {
        _loadingArticlePage = null;
      }
    }
  }

  /// 重新加载当前内容（切换分区时调用）
  void _reloadContent() {
    if (_contentType == 0) {
      _videos.clear();
      _videoPage = 1;
      _hasMoreVideos = true;
      _loadInitialVideos();
    } else {
      _articles.clear();
      _articlePage = 1;
      _hasMoreArticles = true;
      _loadInitialArticles();
    }
  }

  /// 切换内容类型（视频/专栏）
  void _handleContentTypeChange(int index) {
    if (_contentType == index) return;
    setState(() {
      _contentType = index;
      _selectedPartitionId = 0;
    });
    if (index == 0 && _videos.isEmpty) {
      _loadInitialVideos();
    } else if (index == 1 && _articles.isEmpty) {
      _loadInitialArticles();
    }
  }

  void _preloadImages(List<VideoItem> videos) {
    for (final video in videos) {
      SmartCacheManager.preloadImage(video.coverUrl);
      if (video.authorAvatar != null && video.authorUid != null) {
        SmartCacheManager.preloadImage(video.authorAvatar!);
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

    // 获取当前内容类型的数据和状态
    final isEmpty = _contentType == 0 ? _videos.isEmpty : _articles.isEmpty;
    final isLoading = _contentType == 0 ? _isLoadingVideos : _isLoadingArticles;
    final hasMore = _contentType == 0 ? _hasMoreVideos : _hasMoreArticles;

    // 显示错误信息
    if (_errorMessage != null && isEmpty) {
      return SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64.sp, color: colors.iconSecondary),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 16.h),
              ElevatedButton(
                onPressed: _reloadContent,
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
    if (isEmpty && isLoading) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 内容列表 - 使用 Stack 实现固定顶部导航
    return Stack(
      children: [
        // 主内容区域
        RefreshIndicator(
          onRefresh: () async {
            if (_contentType == 0) {
              await _loadInitialVideos();
            } else {
              await _loadInitialArticles();
            }
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 顶部区域：搜索栏 + 视频/专栏切换 + 分类标签
              SliverToBoxAdapter(
                child: _buildHeader(statusBarHeight),
              ),
              // 轮播图（仅视频模式显示）
              if (_contentType == 0)
                SliverToBoxAdapter(
                  child: CarouselWidget(
                    onTap: _onCarouselTap,
                  ),
                ),
              // 内容区域
              if (_contentType == 0)
                // 视频网格（参考 pili_plus: SliverGrid + ExtentAndRatio）
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithExtentAndRatio(
                      maxCrossAxisExtent: 240,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 16 / 10,
                      mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
                    ),
                    itemCount: _videos.length,
                    itemBuilder: (context, index) {
                      return VideoCard(
                        video: _videos[index],
                        onTap: () => _showVideoDetail(context, _videos[index]),
                      );
                    },
                  ),
                )
              else if (_articles.isEmpty && !_isLoadingArticles)
                // 专栏列表为空时的友好提示
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 64.sp,
                          color: colors.iconSecondary,
                        ),
                        SizedBox(height: 16.h),
                        Text(
                          '暂无专栏内容',
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: colors.textSecondary,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          '快去发布第一篇专栏吧',
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // 文章列表
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return _buildArticleCard(_articles[index]);
                      },
                      childCount: _articles.length,
                    ),
                  ),
                ),
              // 加载更多指示器
              if (isLoading && !isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16.w),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              // 没有更多数据提示
              if (!hasMore && !isEmpty)
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
              SliverToBoxAdapter(
                child: SizedBox(height: 16.h),
              ),
            ],
          ),
        ),
        // 固定顶部导航栏（使用动画过渡）
        _buildFixedHeader(statusBarHeight),
      ],
    );
  }

  /// 构建文章卡片
  Widget _buildArticleCard(ArticleListItem article) {
    final colors = context.colors;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArticleViewPage(aid: article.aid),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8.r),
                bottomLeft: Radius.circular(8.r),
              ),
              child: CachedImage(
                imageUrl: article.cover,
                width: 120.w,
                height: 80.h,
                fit: BoxFit.cover,
              ),
            ),
            // 文章信息
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(10.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    // 作者信息
                    Row(
                      children: [
                        // 头像
                        ClipOval(
                          child: CachedImage(
                            imageUrl: article.author.avatar,
                            width: 20.w,
                            height: 20.h,
                            fit: BoxFit.cover,
                          ),
                        ),
                        SizedBox(width: 6.w),
                        // 作者名
                        Expanded(
                          child: Text(
                            article.author.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        // 点击量
                        Icon(
                          Icons.remove_red_eye_outlined,
                          size: 14.sp,
                          color: colors.textTertiary,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          _formatCount(article.clicks),
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 格式化数量
  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  /// 构建顶部区域：搜索栏 + 视频/专栏切换 + 分类标签
  Widget _buildHeader(double statusBarHeight) {
    return Container(
      padding: EdgeInsets.only(top: statusBarHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 搜索栏（使用动画过渡）
          AnimatedBuilder(
            animation: _headerAnimation,
            builder: (context, child) {
              // 动画值从0到1，搜索栏逐渐收起
              final opacity = 1 - _headerAnimation.value;

              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: 1 - _headerAnimation.value,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: _buildSearchBar(),
                  ),
                ),
              );
            },
          ),
          // 视频/专栏切换 + 分类标签展开
          _buildContentTypeSwitchWithTags(),
        ],
      ),
    );
  }

  /// 构建固定顶部导航（滚动后显示，带动画过渡）
  Widget _buildFixedHeader(double statusBarHeight) {
    final colors = context.colors;

    return AnimatedBuilder(
      animation: _headerAnimation,
      builder: (context, child) {
        // 动画值从0到1，固定导航栏从顶部滑入
        final slideOffset = -60 * (1 - _headerAnimation.value);
        final opacity = _headerAnimation.value;

        // 完全隐藏时不渲染
        if (opacity <= 0) {
          return const SizedBox.shrink();
        }

        return Positioned(
          top: slideOffset,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Container(
              padding: EdgeInsets.only(top: statusBarHeight),
              decoration: BoxDecoration(
                color: colors.background,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05 * opacity),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 视频/专栏切换
                  Expanded(child: _buildContentTypeSwitchCompact()),
                  // 搜索按钮（带缩放动画）
                  Transform.scale(
                    scale: 0.8 + 0.2 * opacity,
                    child: _buildCollapsedSearchButton(),
                  ),
                   SizedBox(width: 12.w),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建搜索栏
  Widget _buildSearchBar() {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
      child: GestureDetector(
        onTap: _navigateToSearch,
        child: Container(
          height: 36.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: colors.inputBackground,
            borderRadius: BorderRadius.circular(18.r),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 20.sp, color: colors.textTertiary),
              SizedBox(width: 8.w),
              Text(
                '搜索视频、UP主',
                style: TextStyle(color: colors.textTertiary, fontSize: 14.sp),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建视频/专栏切换 + 分类标签展开
  Widget _buildContentTypeSwitchWithTags() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 视频/专栏切换
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: Row(
            children: [
              _buildSwitchItemWithExpand('视频', 0, _isVideoTagsExpanded, () {
                setState(() => _isVideoTagsExpanded = !_isVideoTagsExpanded);
              }),
              SizedBox(width: 32.w),
              _buildSwitchItemWithExpand('专栏', 1, _isArticleTagsExpanded, () {
                setState(() => _isArticleTagsExpanded = !_isArticleTagsExpanded);
              }),
            ],
          ),
        ),
        // 视频分类标签（展开时显示）
        if (_contentType == 0 && _isVideoTagsExpanded)
          _buildExpandedTags(_videoPartitions),
        // 专栏分类标签（展开时显示）
        if (_contentType == 1 && _isArticleTagsExpanded)
          _buildExpandedTags(_articlePartitions),
      ],
    );
  }

  /// 构建带展开箭头的切换项
  Widget _buildSwitchItemWithExpand(
    String title,
    int index,
    bool isExpanded,
    VoidCallback onExpandTap,
  ) {
    final colors = context.colors;
    final isSelected = _contentType == index;

    return GestureDetector(
      onTap: () => _handleContentTypeChange(index),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: isSelected ? 18.sp : 15.sp,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? colors.textPrimary : colors.textSecondary,
                ),
              ),
              SizedBox(height: 4.h),
              Container(
                width: 20.w,
                height: 3.h,
                decoration: BoxDecoration(
                  color: isSelected ? colors.accentColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(1.5.r),
                ),
              ),
            ],
          ),
          // 展开/收起箭头（仅选中时显示）
          if (isSelected)
            GestureDetector(
              onTap: onExpandTap,
              child: Padding(
                padding: EdgeInsets.only(left: 4.w),
                child: AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20.sp,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建展开的分类标签
  Widget _buildExpandedTags(List<Partition> partitions) {
    // 只显示主分区（parentId 为 null 的）
    final mainPartitions = partitions.where((p) => p.parentId == null).toList();

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // 推荐标签（始终显示）
            _buildTagChip('推荐', 0, _selectedPartitionId == 0),
            // 动态分区标签（只显示主分区）
            ...mainPartitions.map((partition) {
              return _buildTagChip(
                partition.name,
                partition.id,
                _selectedPartitionId == partition.id,
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 构建标签 Chip
  Widget _buildTagChip(String name, int partitionId, bool isSelected) {
    final colors = context.colors;

    return GestureDetector(
      onTap: () {
        if (_selectedPartitionId != partitionId) {
          setState(() => _selectedPartitionId = partitionId);
          _reloadContent();
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: isSelected ? colors.accentColor : colors.inputBackground,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 13.sp,
            color: isSelected ? Colors.white : colors.textSecondary,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 构建紧凑版视频/专栏切换（固定顶栏用）
  Widget _buildContentTypeSwitchCompact() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      child: Row(
        children: [
          _buildCompactSwitchItem('视频', 0),
          SizedBox(width: 24.w),
          _buildCompactSwitchItem('专栏', 1),
        ],
      ),
    );
  }

  Widget _buildCompactSwitchItem(String title, int index) {
    final colors = context.colors;
    final isSelected = _contentType == index;

    return GestureDetector(
      onTap: () => _handleContentTypeChange(index),
      child: Text(
        title,
        style: TextStyle(
          fontSize: isSelected ? 16.sp : 14.sp,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colors.textPrimary : colors.textSecondary,
        ),
      ),
    );
  }

  /// 构建收缩后的搜索按钮
  Widget _buildCollapsedSearchButton() {
    final colors = context.colors;

    return GestureDetector(
      onTap: _navigateToSearch,
      child: Container(
        width: 36.w,
        height: 36.h,
        decoration: BoxDecoration(
          color: colors.inputBackground,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.search, size: 20.sp, color: colors.textSecondary),
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
          videoRef: video.playRef,
        ),
      ),
    );
  }

  /// 轮播图点击处理
  void _onCarouselTap(CarouselItem item) {
    // 如果有url，解析并跳转
    if (item.url != null && item.url!.isNotEmpty) {
      final rawUrl = item.url!;

      Uri? uri;
      try {
        uri = Uri.parse(rawUrl);
      } catch (_) {
        uri = null;
      }

      if (uri != null) {
        // 优先解析统一的播放页链接：/watch?v=<vid>&p=<part>
        final v = uri.queryParameters['v'];
        if (v != null && v.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayPage(videoRef: v),
            ),
          );
          return;
        }

        // 兼容路径：/video/<数字 id 或 shortId>
        final videoMatch = RegExp(r'/video/([^/?#]+)').firstMatch(uri.path);
        if (videoMatch != null) {
          final ref = Uri.decodeComponent(videoMatch.group(1)!);
          if (ref.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoPlayPage(videoRef: ref),
              ),
            );
            return;
          }
        }
      }
      // 其他链接暂不处理，后续可以添加 WebView 或外部浏览器打开
    }
  }
}