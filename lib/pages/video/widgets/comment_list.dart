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
  final Map<int, TextEditingController> _replyControllers = {}; // 每个评论的回复输入框

  List<Comment> _comments = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _totalComments = 0;

  // 当前登录用户ID（TODO: 从用户服务获取）
  int? _currentUserId;

  // 展开回复的评论ID集合
  final Set<int> _expandedReplies = {};
  // 显示回复输入框的评论ID集合
  final Set<int> _showReplyInputs = {};
  final Map<int, List<Comment>> _loadedReplies = {};
  final Map<int, bool> _loadingReplies = {};

  @override
  void initState() {
    super.initState();
    // 使用外部提供的 ScrollController 或创建新的
    _scrollController = widget.scrollController ?? ScrollController();
    _loadCurrentUserId(); // 加载当前用户ID
    _loadComments();
    _scrollController.addListener(_onScroll);
  }

  /// 加载当前登录用户ID（TODO: 从用户服务或SharedPreferences获取）
  Future<void> _loadCurrentUserId() async {
    // TODO: 从用户服务获取当前登录用户ID
    // 暂时使用占位值，实际应该从认证服务获取
    setState(() {
      _currentUserId = null; // 未登录时为null
    });
  }

  @override
  void dispose() {
    // 只销毁我们自己创建的 ScrollController
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _commentController.dispose();
    // 销毁所有回复输入框
    for (var controller in _replyControllers.values) {
      controller.dispose();
    }
    _replyControllers.clear();
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
      cid: widget.vid,
      content: content,
    );

    if (success) {
      _commentController.clear();
      // 刷新评论列表
      _currentPage = 1;
      _comments.clear();
      await _loadComments();
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

  /// 提交回复
  Future<void> _submitReply(int commentId, Comment parentComment) async {
    final controller = _replyControllers[commentId];
    if (controller == null) return;

    final content = controller.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _loadingReplies[commentId] = true;
    });

    try {
      final success = await _videoService.postComment(
        cid: widget.vid,
        content: content,
        parentID: commentId,
        replyUserID: parentComment.uid,
        replyUserName: parentComment.username,
        replyContent: parentComment.content,
      );

      if (success) {
        controller.clear();
        // 隐藏回复输入框
        setState(() {
          _showReplyInputs.remove(commentId);
          _loadingReplies[commentId] = false;
        });
        // 重新加载评论以获取最新回复
        _currentPage = 1;
        _comments.clear();
        await _loadComments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('回复发表成功')),
          );
        }
      } else {
        setState(() {
          _loadingReplies[commentId] = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('回复发表失败')),
          );
        }
      }
    } catch (e) {
      print('发表回复失败: $e');
      setState(() {
        _loadingReplies[commentId] = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发表回复失败: $e')),
        );
      }
    }
  }

  /// 删除评论或回复
  Future<void> _deleteComment(int commentId) async {
    // 确认删除对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条评论吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _videoService.deleteComment(commentId);

      if (success) {
        // 重新加载评论
        _currentPage = 1;
        _comments.clear();
        await _loadComments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除成功')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除失败')),
          );
        }
      }
    } catch (e) {
      print('删除评论失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除评论失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 删除回复
  Future<void> _deleteReply(int replyId) async {
    // 确认删除对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条回复吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _videoService.deleteComment(replyId);

      if (success) {
        // 重新加载评论
        _currentPage = 1;
        _comments.clear();
        await _loadComments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除成功')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除失败')),
          );
        }
      }
    } catch (e) {
      print('删除回复失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除回复失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 显示回复输入框（只能激活一个）
  void _showReplyInput(int commentId) {
    setState(() {
      // 如果点击的是已激活的评论，则关闭回复输入框
      if (_showReplyInputs.contains(commentId)) {
        _showReplyInputs.remove(commentId);
        // 可选：同时关闭回复列表
        // _expandedReplies.remove(commentId);
      } else {
        // 如果点击的是其他评论，先关闭之前的回复输入框
        _showReplyInputs.clear();
        // 激活新的回复输入框
        _showReplyInputs.add(commentId);
        
        // 确保有对应的输入框控制器
        if (!_replyControllers.containsKey(commentId)) {
          _replyControllers[commentId] = TextEditingController();
        }
        
        // 同时展开回复列表以便查看
        _expandedReplies.add(commentId);
        // 如果还没有加载回复，则加载
        if (!_loadedReplies.containsKey(commentId)) {
          _loadReplies(commentId);
        }
      }
    });
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
                       onReply: () => _showReplyInput(comment.id),
                       onDelete: () => _deleteComment(comment.id),
                       onDeleteReply: _deleteReply,
                       showReplies: _expandedReplies.contains(comment.id),
                       replies: _loadedReplies[comment.id],
                       isLoadingReplies: _loadingReplies[comment.id] ?? false,
                       formatTime: _formatTime,
                       currentUserId: _currentUserId,
                       replyController: _replyControllers[comment.id],
                       showReplyInput: _showReplyInputs.contains(comment.id),
                       onSubmitReply: () => _submitReply(comment.id, comment),
                       isSubmittingReply: _loadingReplies[comment.id] ?? false,
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
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final Function(int) onDeleteReply; // 删除回复回调
  final bool showReplies;
  final List<Comment>? replies;
  final bool isLoadingReplies;
  final String Function(DateTime) formatTime;
  final int? currentUserId; // 当前登录用户ID
  final TextEditingController? replyController; // 回复输入框控制器
  final bool showReplyInput; // 是否显示回复输入框
  final VoidCallback? onSubmitReply; // 提交回复回调
  final bool isSubmittingReply; // 是否正在提交回复

  const _CommentItem({
    required this.comment,
    required this.onToggleReplies,
    required this.onReply,
    required this.onDelete,
    required this.onDeleteReply,
    required this.showReplies,
    this.replies,
    required this.isLoadingReplies,
    required this.formatTime,
    this.currentUserId,
    this.replyController,
    this.showReplyInput = false,
    this.onSubmitReply,
    this.isSubmittingReply = false,
  });

  /// 判断是否为当前用户的评论
  bool get isOwnComment => currentUserId != null && comment.uid == currentUserId;


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
                        InkWell(
                          onTap: onReply,
                          child: Row(
                            children: [
                              Icon(
                                Icons.reply,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '回复',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 查看回复按钮（如果有回复）
                        if (comment.replyCount > 0)
                          InkWell(
                            onTap: onToggleReplies,
                            child: Row(
                              children: [
                                Icon(
                                  showReplies ? Icons.expand_less : Icons.expand_more,
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
                        const Spacer(),
                        // 删除按钮（仅当前用户的评论显示）
                        if (isOwnComment)
                          InkWell(
                            onTap: onDelete,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: Colors.red[400],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '删除',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red[400],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    // 回复输入框（当点击回复按钮时显示）
                    if (showReplyInput && replyController != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: replyController,
                              decoration: InputDecoration(
                                hintText: '回复 ${comment.username}...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.grey[200],
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              maxLines: null,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => onSubmitReply?.call(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: isSubmittingReply
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            onPressed: isSubmittingReply ? null : onSubmitReply,
                            color: Theme.of(context).primaryColor,
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
                                          const SizedBox(height: 4),
                                          // 回复的操作按钮
                                          Row(
                                            children: [
                                              InkWell(
                                                onTap: () {
                                                  // 回复回复：使用父评论的ID作为parentID
                                                  // TODO: 可以添加回复回复的输入框
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('回复回复功能待实现')),
                                                  );
                                                },
                                                child: Text(
                                                  '回复',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ),
                                              const Spacer(),
                                              // 删除按钮（仅当前用户的回复显示）
                                              if (currentUserId != null && reply.uid == currentUserId)
                                                InkWell(
                                                  onTap: () => onDeleteReply(reply.id),
                                                  child: Text(
                                                    '删除',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.red[400],
                                                    ),
                                                  ),
                                                ),
                                            ],
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

