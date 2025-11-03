import 'package:flutter/material.dart';
import '../models/video_item.dart';
///import '../models/video_api_model.dart';
import '../services/video_api_service.dart';
import '../services/logger_service.dart';
import '../widgets/video_card.dart';
import 'video/video_play_page.dart';

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
  Future<void> _loadMoreVideos() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    final nextPage = _currentPage + 1;
    
    try {
      final apiVideos = await VideoApiService.getHotVideoAPI(
        page: nextPage,
        pageSize: _pageSize,
      );

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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        elevation: 0,
        centerTitle: false,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 显示错误信息
    if (_errorMessage != null && _videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialVideos,
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

    // 视频列表
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 双列网格布局
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              childAspectRatio: 0.88,
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
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  '没有更多了',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ),
        // 底部占位，防止最后一行被遮挡
        const SliverToBoxAdapter(
          child: SizedBox(height: 16),
        ),
      ],
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
}
