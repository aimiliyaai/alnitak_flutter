import 'package:flutter/material.dart';
import '../../models/message_models.dart';
import '../../services/message_api_service.dart';
import '../../utils/time_utils.dart';
import '../../utils/image_utils.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';
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
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('回复我的'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Text(
              '暂无回复消息',
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
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
    final colors = context.colors;
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
        color: colors.card,
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
                      backgroundColor: colors.surfaceVariant,
                      child: Icon(Icons.person, size: 24, color: colors.iconSecondary),
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
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          TimeUtils.formatTime(message.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 回复内容
                    Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textPrimary,
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
                          color: colors.surfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 30,
                              decoration: BoxDecoration(
                                color: colors.iconSecondary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                message.targetReplyContent,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
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
                                color: colors.textSecondary,
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
