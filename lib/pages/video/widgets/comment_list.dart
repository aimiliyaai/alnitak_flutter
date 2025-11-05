import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/comment.dart';
import '../../../services/video_service.dart';

/// 评论列表组件 - 参考 YouTube 设计
class CommentList extends StatefulWidget {
  final int vid; // 视频ID

  const CommentList({
    super.key,
    required this.vid,
  });

  @override
  State<CommentList> createState() => _CommentListState();
}

/// 评论列表内容（可复用，支持外部 ScrollController）
class CommentListContent extends StatefulWidget {
  final int vid;
  final ScrollController? scrollController; // 可选的 ScrollController

  const CommentListContent({
    super.key,
    required this.vid,
    this.scrollController,
  });

  @override
  State<CommentListContent> createState() => _CommentListContentState();
}

class _CommentListState extends State<CommentList> {
  @override
  Widget build(BuildContext context) {
    return CommentListContent(vid: widget.vid);
  }
}

class _CommentListContentState extends State<CommentListContent> {
  final VideoService _videoService = VideoService();
  late final ScrollController _scrollController;
  final TextEditingController _commentController = TextEditingController();

  List<Comment> _comments = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _totalComments = 0;

  // 展开回复的评论ID集合
  final Set<int> _expandedReplies = {};
  final Map<int, List<Comment>> _loadedReplies = {};
  final Map<int, bool> _loadingReplies = {};

  @override
  void initState() {
    super.initState();
    // 使用外部提供的 ScrollController 或创建新的
    _scrollController = widget.scrollController ?? ScrollController();
    _loadComments();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    // 只销毁我们自己创建的 ScrollController
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _commentController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreComments();
    }
  }

  Future<void> _loadComments({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _currentPage = 1;
        _comments.clear();
        _hasMore = true;
      }
    });

    try {
      final response = await _videoService.getComments(
        vid: widget.vid,
        page: _currentPage,
        pageSize: 20,
      );

      if (response != null) {
        setState(() {
          _comments.addAll(response.comments);
          _totalComments = response.total;
          _hasMore = response.hasMore;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('加载评论失败: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载评论失败: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreComments() async {
    if (!_hasMore || _isLoading) return;

    setState(() {
      _currentPage++;
    });

    await _loadComments();
  }

  Future<void> _loadReplies(int commentId) async {
    if (_loadingReplies[commentId] == true) return;

    setState(() {
      _loadingReplies[commentId] = true;
    });

    try {
      final replies = await _videoService.getCommentReplies(commentId: commentId);
      if (replies != null) {
        setState(() {
          _loadedReplies[commentId] = replies;
          _loadingReplies[commentId] = false;
        });
      } else {
        setState(() {
          _loadingReplies[commentId] = false;
        });
      }
    } catch (e) {
      print('加载回复失败: $e');
      setState(() {
        _loadingReplies[commentId] = false;
      });
    }
  }

  void _toggleReplies(int commentId) {
    setState(() {
      if (_expandedReplies.contains(commentId)) {
        _expandedReplies.remove(commentId);
      } else {
        _expandedReplies.add(commentId);
        // 如果还没有加载回复，则加载
        if (!_loadedReplies.containsKey(commentId)) {
          _loadReplies(commentId);
        }
      }
    });
  }

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    // 显示加载状态
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('正在发表评论...'),
        duration: Duration(seconds: 2),
      ),
    );

    final success = await _videoService.postComment(
      vid: widget.vid,
      content: content,
    );

    if (success) {
      _commentController.clear();
      // 刷新评论列表
      await _loadComments(refresh: true);
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('评论发表成功')),
        );
      }
    } else {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('评论发表失败，请重试')),
        );
      }
    }
  }


  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}年前';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}个月前';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 判断是否在面板中使用（通过是否有外部 ScrollController）
    final isInPanel = widget.scrollController != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 评论头部：标题（仅在独立使用时显示）
        if (!isInPanel) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              '评论 $_totalComments',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
        ],

        // 评论列表（可滚动区域）
        Expanded(
          child: _comments.isEmpty && !_isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.comment_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        '暂无评论',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.only(
                    bottom: isInPanel ? 80 : 0, // 在面板中为底部输入框留出空间
                  ),
                  itemCount: _comments.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _comments.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final comment = _comments[index];
                    return _CommentItem(
                      comment: comment,
                      onToggleReplies: () => _toggleReplies(comment.id),
                      showReplies: _expandedReplies.contains(comment.id),
                      replies: _loadedReplies[comment.id],
                      isLoadingReplies: _loadingReplies[comment.id] ?? false,
                      formatTime: _formatTime,
                    );
                  },
                ),
        ),

        // 评论输入框（固定在底部）
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              top: BorderSide(color: Colors.grey[300]!, width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 当前登录用户头像（占位，实际应该从用户服务获取）
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey[300],
                  child: const Icon(Icons.person, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                // 输入框
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: '添加公开评论...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitComment(),
                  ),
                ),
                const SizedBox(width: 8),
                // 发送按钮
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _submitComment,
                  color: Theme.of(context).primaryColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 评论项组件
class _CommentItem extends StatelessWidget {
  final Comment comment;
  final VoidCallback onToggleReplies;
  final bool showReplies;
  final List<Comment>? replies;
  final bool isLoadingReplies;
  final String Function(DateTime) formatTime;

  const _CommentItem({
    required this.comment,
    required this.onToggleReplies,
    required this.showReplies,
    this.replies,
    required this.isLoadingReplies,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 用户头像
              CircleAvatar(
                radius: 20,
                backgroundImage: comment.avatar.isNotEmpty
                    ? NetworkImage(comment.avatar)
                    : null,
                child: comment.avatar.isEmpty
                    ? const Icon(Icons.person, size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              // 评论内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 用户名和时间
                    Row(
                      children: [
                        Text(
                          comment.username,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatTime(comment.createdAt),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 评论正文（如果有回复用户名，显示回复格式）
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                        children: [
                          if (comment.replyUserName != null && comment.replyUserName!.isNotEmpty)
                            TextSpan(
                              text: '@${comment.replyUserName} ',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          TextSpan(text: comment.content),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 操作按钮
                    Row(
                      children: [
                        // 回复按钮
                        if (comment.replyCount > 0)
                          InkWell(
                            onTap: onToggleReplies,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.reply,
                                  size: 16,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${comment.replyCount} 条回复',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 回复列表
        if (showReplies && (replies != null || isLoadingReplies))
          Padding(
            padding: const EdgeInsets.only(left: 52, right: 16),
            child: isLoadingReplies
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : replies != null && replies!.isNotEmpty
                    ? Column(
                        children: [
                          ...replies!.map((reply) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundImage:
                                          reply.avatar.isNotEmpty
                                              ? NetworkImage(reply.avatar)
                                              : null,
                                      child: reply.avatar.isEmpty
                                          ? const Icon(Icons.person, size: 16)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                reply.username,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                formatTime(reply.createdAt),
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          // 回复内容（如果有回复用户名，显示回复格式）
                                          RichText(
                                            text: TextSpan(
                                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                                              children: [
                                                if (reply.replyUserName != null && reply.replyUserName!.isNotEmpty)
                                                  TextSpan(
                                                    text: '@${reply.replyUserName} ',
                                                    style: TextStyle(
                                                      color: Theme.of(context).primaryColor,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                TextSpan(text: reply.content),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          InkWell(
                            onTap: onToggleReplies,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 12),
                              child: Text(
                                '收起回复',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '暂无回复',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ),
          ),

        const Divider(height: 1),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}

