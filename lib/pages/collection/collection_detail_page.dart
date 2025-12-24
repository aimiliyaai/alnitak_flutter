import 'package:flutter/material.dart';
import '../../models/collection_models.dart';
import '../../services/collection_api_service.dart';
import '../../utils/image_utils.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';
import '../video/video_play_page.dart';

/// 收藏夹详情页面
class CollectionDetailPage extends StatefulWidget {
  final int collectionId;
  final String collectionName;

  const CollectionDetailPage({
    super.key,
    required this.collectionId,
    required this.collectionName,
  });

  @override
  State<CollectionDetailPage> createState() => _CollectionDetailPageState();
}

class _CollectionDetailPageState extends State<CollectionDetailPage> {
  final CollectionApiService _apiService = CollectionApiService();
  final ScrollController _scrollController = ScrollController();

  CollectionInfo? _collectionInfo;
  List<CollectionVideo> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _total = 0;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _page = 1;
    });

    // 并行加载收藏夹信息和视频列表
    final results = await Future.wait([
      _apiService.getCollectionInfo(widget.collectionId),
      _apiService.getCollectionVideos(
        collectionId: widget.collectionId,
        page: _page,
        pageSize: _pageSize,
      ),
    ]);

    if (mounted) {
      final info = results[0] as CollectionInfo?;
      final videoResult = results[1] as ({List<CollectionVideo> videos, int total});

      setState(() {
        _collectionInfo = info;
        _videos = videoResult.videos;
        _total = videoResult.total;
        _isLoading = false;
        _hasMore = videoResult.videos.length >= _pageSize;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    _page++;

    final result = await _apiService.getCollectionVideos(
      collectionId: widget.collectionId,
      page: _page,
      pageSize: _pageSize,
    );

    if (mounted) {
      setState(() {
        _videos.addAll(result.videos);
        _isLoadingMore = false;
        _hasMore = result.videos.length >= _pageSize;
      });
    }
  }

  /// 从收藏夹移除视频
  Future<void> _removeVideo(CollectionVideo video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认移除'),
        content: Text('确定要从收藏夹中移除"${video.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 调用取消收藏API
    final success = await _apiService.collectVideo(
      CollectVideoParams(
        vid: video.vid,
        addList: [],
        cancelList: [widget.collectionId],
      ),
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _videos.removeWhere((v) => v.vid == video.vid);
        _total--;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已移除')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('移除失败')),
      );
    }
  }

  void _navigateToVideo(CollectionVideo video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayPage(vid: video.vid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(widget.collectionName),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // 收藏夹信息卡片
          if (_collectionInfo != null)
            SliverToBoxAdapter(
              child: _buildInfoCard(),
            ),

          // 视频列表
          if (_videos.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.video_library_outlined,
                        size: 64, color: colors.iconSecondary),
                    const SizedBox(height: 16),
                    Text(
                      '收藏夹里还没有视频',
                      style: TextStyle(fontSize: 16, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _videos.length) {
                      return _buildLoadingMore();
                    }
                    return _buildVideoItem(_videos[index]);
                  },
                  childCount: _videos.length + (_hasMore ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final colors = context.colors;
    final info = _collectionInfo!;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: info.cover.isNotEmpty
                ? CachedImage(
                    imageUrl: ImageUtils.getFullImageUrl(info.cover),
                    width: 100,
                    height: 70,
                    fit: BoxFit.cover,
                    cacheKey: 'collection_cover_${info.id}',
                  )
                : Container(
                    width: 100,
                    height: 70,
                    color: colors.surfaceVariant,
                    child: Icon(Icons.folder, size: 35, color: colors.iconSecondary),
                  ),
          ),
          const SizedBox(width: 16),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        info.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: info.open
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        info.open ? '公开' : '私密',
                        style: TextStyle(
                          fontSize: 11,
                          color: info.open ? Colors.green : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
                if (info.desc.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    info.desc,
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '共 $_total 个视频',
                  style: TextStyle(fontSize: 12, color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoItem(CollectionVideo video) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _navigateToVideo(video),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedImage(
                      imageUrl: ImageUtils.getFullImageUrl(video.cover),
                      width: 140,
                      height: 80,
                      fit: BoxFit.cover,
                      cacheKey: 'video_cover_${video.vid}',
                    ),
                  ),
                  // 时长标签
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        video.formattedDuration,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // 视频信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        video.author.avatar.isNotEmpty
                            ? CachedCircleAvatar(
                                imageUrl: ImageUtils.getFullImageUrl(video.author.avatar),
                                radius: 10,
                                cacheKey: 'author_avatar_${video.author.uid}',
                              )
                            : CircleAvatar(
                                radius: 10,
                                backgroundColor: colors.surfaceVariant,
                                child: Icon(Icons.person, size: 12, color: colors.iconSecondary),
                              ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            video.author.name,
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.play_arrow_outlined, size: 14, color: colors.iconSecondary),
                        const SizedBox(width: 2),
                        Text(
                          video.formattedClicks,
                          style: TextStyle(fontSize: 12, color: colors.textTertiary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 删除按钮
              IconButton(
                icon: Icon(Icons.close, size: 20, color: colors.iconSecondary),
                onPressed: () => _removeVideo(video),
                tooltip: '移除',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingMore() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: _isLoadingMore
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const SizedBox.shrink(),
    );
  }
}
