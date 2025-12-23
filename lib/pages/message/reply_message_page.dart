import 'package:flutter/material.dart';
import '../../models/message_models.dart';
import '../../services/message_api_service.dart';
import '../../utils/time_utils.dart';
import '../../utils/image_utils.dart';
import '../../widgets/cached_image_widget.dart';
import '../video/video_play_page.dart';

/// 回复消息页面
class ReplyMessagePage extends StatefulWidget {
  const ReplyMessagePage({super.key});

  @override
  State<ReplyMessagePage> createState() => _ReplyMessagePageState();
}

class _ReplyMessagePageState extends State<ReplyMessagePage> {
  final MessageApiService _apiService = MessageApiService();
  final ScrollController _scrollController = ScrollController();

  List<ReplyMessage> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
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

    final data = await _apiService.getReplyMessageList(
      page: _page,
      pageSize: _pageSize,
    );

    if (mounted) {
      setState(() {
        _messages = data;
        _isLoading = false;
        _hasMore = data.length >= _pageSize;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    _page++;

    final data = await _apiService.getReplyMessageList(
      page: _page,
      pageSize: _pageSize,
    );

    if (mounted) {
      setState(() {
        _messages.addAll(data);
        _isLoadingMore = false;
        _hasMore = data.length >= _pageSize;
      });
    }
  }

  void _navigateToContent(ReplyMessage message) {
    if (message.type == 0 && message.video != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayPage(vid: message.video!.vid),
        ),
      );
    }
    // TODO: 文章跳转
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('回复我的'),
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

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '暂无回复消息',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _messages.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _messages.length) {
            return _buildLoadingMore();
          }
          return _buildMessageItem(_messages[index]);
        },
      ),
    );
  }

  Widget _buildMessageItem(ReplyMessage message) {
    final cover = message.type == 0
        ? message.video?.cover ?? ''
        : message.article?.cover ?? '';
    final title = message.type == 0
        ? message.video?.title ?? ''
        : message.article?.title ?? '';
    final contentId = message.type == 0
        ? message.video?.vid
        : message.article?.aid;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _navigateToContent(message),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 用户头像
              message.user.avatar.isNotEmpty
                  ? CachedCircleAvatar(
                      imageUrl: ImageUtils.getFullImageUrl(message.user.avatar),
                      radius: 20,
                      cacheKey: 'user_avatar_${message.user.uid}',
                    )
                  : CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[200],
                      child: const Icon(Icons.person, size: 24, color: Colors.grey),
                    ),
              const SizedBox(width: 12),
              // 消息内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 用户名和时间
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.user.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Text(
                          TimeUtils.formatTime(message.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 回复内容
                    Text(
                      message.content,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 被回复的内容
                    if (message.targetReplyContent.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.grey[400],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                message.targetReplyContent,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // 内容缩略图
                    if (cover.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: CachedImage(
                              imageUrl: ImageUtils.getFullImageUrl(cover),
                              width: 60,
                              height: 38,
                              fit: BoxFit.cover,
                              cacheKey: message.type == 0
                                  ? 'video_cover_$contentId'
                                  : 'article_cover_$contentId',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
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
