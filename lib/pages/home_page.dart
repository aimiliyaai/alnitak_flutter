import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../models/carousel_model.dart';
import '../services/video_api_service.dart';
import '../services/logger_service.dart';
import '../widgets/video_card.dart';
import '../widgets/carousel_widget.dart';
import '../theme/theme_extensions.dart';
import 'video/video_play_page.dart';
import 'search_page.dart';

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

  // 监听滚动，到底部时加载更多
  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('首页'),
        elevation: 0,
        centerTitle: false,
        backgroundColor: colors.appBarBackground,
        foregroundColor: colors.appBarForeground,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SearchPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    // 显示错误信息
    if (_errorMessage != null && _videos.isEmpty) {
      return Center(
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
      );
    }

    // 初始加载中
    if (_videos.isEmpty && _isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 视频列表 - 添加下拉刷新
    return RefreshIndicator(
      onRefresh: _loadInitialVideos,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
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
                      // 后续添加视频详情页导航
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
