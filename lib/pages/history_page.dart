import 'package:flutter/material.dart';
import '../services/history_service.dart';
import '../services/auth_service.dart';
import '../models/history_models.dart';
import '../widgets/cached_image_widget.dart';
import '../utils/image_utils.dart';
import 'video/video_play_page.dart';
import 'login_page.dart';

/// 历史记录页面
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryService _historyService = HistoryService();
  final AuthService _authService = AuthService();
  final ScrollController _scrollController = ScrollController();

  List<HistoryItem> _historyList = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isLoggedIn = false;
  int _currentPage = 1;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _checkLoginAndLoad();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动监听，加载更多
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreHistory();
    }
  }

  /// 检查登录状态并加载数据
  Future<void> _checkLoginAndLoad() async {
    final isLoggedIn = await _authService.isLoggedIn();
    if (mounted) {
      setState(() => _isLoggedIn = isLoggedIn);
      if (isLoggedIn) {
        _loadHistory();
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 跳转到登录页
  Future<void> _navigateToLogin() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
    if (result == true) {
      _checkLoginAndLoad();
    }
  }

  /// 加载历史记录
  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
    });

    final response = await _historyService.getHistoryList(
      page: _currentPage,
      pageSize: _pageSize,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (response != null) {
          _historyList = response.videos;
          _hasMore = response.videos.length >= _pageSize;
        }
      });
    }
  }

  /// 加载更多
  Future<void> _loadMoreHistory() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    final response = await _historyService.getHistoryList(
      page: _currentPage + 1,
      pageSize: _pageSize,
    );

    if (mounted) {
      setState(() {
        _isLoadingMore = false;
        if (response != null) {
          _historyList.addAll(response.videos);
          _currentPage++;
          _hasMore = response.videos.length >= _pageSize;
        }
      });
    }
  }

  /// 格式化播放进度（已观看 / 总时长）
  String _formatProgress(double watchedSeconds, double? durationSeconds) {
    // 已看完
    if (watchedSeconds < 0) {
      return '已看完';
    }

    String fmt(Duration d) =>
        '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

    final watched = Duration(seconds: watchedSeconds.toInt());

    // 总时长未知
    if (durationSeconds == null || durationSeconds <= 0) {
      return '${fmt(watched)} / --:--';
    }

    final total = Duration(seconds: durationSeconds.toInt());
    return '${fmt(watched)} / ${fmt(total)}';
  }
  /// 计算播放进度比例（0.0 - 1.0）

  double _calculateProgress(double watchedSeconds, double? durationSeconds) {
    // 已看完
    if (watchedSeconds < 0) {
      return 1.0;
    }

    // 防御：无效 / 未知时长
    if (durationSeconds == null || durationSeconds <= 0) {
      return 0.0;
    }

    return (watchedSeconds / durationSeconds).clamp(0.0, 1.0);
  }

  /// 格式化时间
  String _formatTime(String updatedAt) {
    try {
      final dateTime = DateTime.parse(updatedAt);
      final now = DateTime.now();
      final diff = now.difference(dateTime);

      if (diff.inDays == 0) {
        return '今天';
      } else if (diff.inDays == 1) {
        return '昨天';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}天前';
      } else if (diff.inDays < 30) {
        return '${(diff.inDays / 7).floor()}周前';
      } else if (diff.inDays < 365) {
        return '${(diff.inDays / 30).floor()}个月前';
      } else {
        return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return '';
    }
  }

  /// 跳转到视频播放页
  void _navigateToVideo(HistoryItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayPage(vid: item.vid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('观看历史'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 未登录状态
    if (!_isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '登录后查看观看历史',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
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

    // 空记录状态
    if (_historyList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '暂无观看记录',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '快去看看感兴趣的视频吧',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _historyList.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _historyList.length) {
            return _buildLoadingMore();
          }
          return _buildHistoryItem(_historyList[index]);
        },
      ),
    );
  }

  /// 构建历史记录项
  Widget _buildHistoryItem(HistoryItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => _navigateToVideo(item),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              SizedBox(
                width: 140,
                height: 80,
                child: Stack(
                  children: [
                    // 封面图片
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedImage(
                          imageUrl: ImageUtils.getFullImageUrl(item.cover),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    // 播放时间标签
                    Positioned(
                      bottom: 6,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatProgress(item.time, item.duration.toDouble()),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    // 底部进度条
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(6),
                          bottomRight: Radius.circular(6),
                        ),
                        child: SizedBox(
                          height: 3,
                          child: Stack(
                            children: [
                              // 背景
                              Container(
                                color: Colors.black.withValues(alpha: 0.3),
                              ),
                              // 已播放进度（蓝色）
                              FractionallySizedBox(
                                widthFactor: _calculateProgress(item.time, item.duration.toDouble()),
                                child: Container(
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: SizedBox(
                  height: 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      const Spacer(),
                      // 观看时间
                      Text(
                        _formatTime(item.updatedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建加载更多
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
          : Text(
              '上拉加载更多',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
              ),
            ),
    );
  }
}
