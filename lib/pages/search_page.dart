import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../services/video_api_service.dart';
import '../services/logger_service.dart';
import '../widgets/video_card.dart';
import '../theme/theme_extensions.dart';
import 'video/video_play_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();

  List<VideoItem> _videos = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _hasSearched = false;
  String? _errorMessage;
  String _currentKeywords = '';
  static const int _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 自动聚焦搜索框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoading &&
        _hasMore &&
        _hasSearched) {
      _loadMoreVideos();
    }
  }

  Future<void> _performSearch() async {
    final keywords = _searchController.text.trim();

    if (keywords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入搜索关键词')),
      );
      return;
    }

    // 隐藏键盘
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentPage = 1;
      _videos = [];
      _hasSearched = true;
      _currentKeywords = keywords;
    });

    try {
      final apiVideos = await VideoApiService.searchVideo(
        keywords: keywords,
        page: 1,
        pageSize: _pageSize,
      );

      final videos = apiVideos
          .map((apiVideo) => VideoItem.fromApiModel(apiVideo))
          .toList();

      setState(() {
        _videos = videos;
        _hasMore = videos.length >= _pageSize;
        _isLoading = false;
      });

      if (videos.isEmpty) {
        setState(() {
          _errorMessage = '未找到相关视频';
        });
      }
    } catch (e, stackTrace) {
      await LoggerService.instance.logDataLoadError(
        dataType: '搜索视频',
        operation: '搜索',
        error: e,
        stackTrace: stackTrace,
        context: {
          '关键词': keywords,
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
            content: Text('搜索失败: $e'),
            action: SnackBarAction(
              label: '重试',
              onPressed: _performSearch,
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadMoreVideos() async {
    if (_isLoading || !_hasMore || _currentKeywords.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final nextPage = _currentPage + 1;

    try {
      final apiVideos = await VideoApiService.searchVideo(
        keywords: _currentKeywords,
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
      await LoggerService.instance.logDataLoadError(
        dataType: '搜索视频',
        operation: '加载更多',
        error: e,
        stackTrace: stackTrace,
        context: {
          '关键词': _currentKeywords,
          '页码': nextPage,
          '每页数量': _pageSize,
          '当前视频数量': _videos.length,
        },
      );

      setState(() {
        _isLoading = false;
        _hasMore = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载更多失败: $e')),
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
              hintText: '搜索视频',
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
            onChanged: (_) {
              setState(() {}); // 更新清除按钮显示状态
            },
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
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    // 未搜索状态
    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Text(
              '输入关键词搜索视频',
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

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
              onPressed: _performSearch,
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

    // 搜索中
    if (_videos.isEmpty && _isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 搜索结果列表
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 搜索结果提示
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '找到 ${_videos.length} 个相关视频',
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
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
        // 底部占位
        const SliverToBoxAdapter(
          child: SizedBox(height: 16),
        ),
      ],
    );
  }

  void _showVideoDetail(BuildContext context, VideoItem video) {
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
