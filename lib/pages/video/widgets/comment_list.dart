import 'package:flutter/material.dart';
import '../../../models/comment.dart';
///import '../../../models/user_model.dart';
import '../../../services/video_service.dart';
import '../../../services/user_service.dart';
import '../../../widgets/cached_image_widget.dart';
import '../../../utils/login_guard.dart';
import '../../../utils/timestamp_parser.dart';
import '../../../utils/auth_state_manager.dart';
import '../../../theme/theme_extensions.dart';
import '../../../utils/image_utils.dart';
import '../../user/user_space_page.dart';

/// 评论列表组件 - 优化输入体验
class CommentList extends StatefulWidget {
  final int vid; // 视频ID
  final void Function(int seconds)? onSeek; // 点击时间戳跳转回调

  const CommentList({
    super.key,
    required this.vid,
    this.onSeek,
  });

  @override
  State<CommentList> createState() => _CommentListState();
}

/// 评论列表内容（可复用，支持外部 ScrollController）
class CommentListContent extends StatefulWidget {
  final int vid;
  final ScrollController? scrollController; // 可选的 ScrollController
  final void Function(int seconds)? onSeek; // 点击时间戳跳转回调
  final VoidCallback? onCommentPosted; // 评论发送或删除成功后的回调
  final void Function(int count)? onTotalCommentsChanged; // 评论总数变化回调

  const CommentListContent({
    super.key,
    required this.vid,
    this.scrollController,
    this.onSeek,
    this.onCommentPosted,
    this.onTotalCommentsChanged,
  });

  @override
  State<CommentListContent> createState() => _CommentListContentState();
}

class _CommentListState extends State<CommentList> {
  @override
  Widget build(BuildContext context) {
    return CommentListContent(vid: widget.vid, onSeek: widget.onSeek);
  }
}

class _CommentListContentState extends State<CommentListContent> {
  final VideoService _videoService = VideoService();
  final UserService _userService = UserService();
  final AuthStateManager _authStateManager = AuthStateManager();
  late final ScrollController _scrollController;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  final List<Comment> _comments = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _totalComments = 0;

  // 当前登录用户信息
  int? _currentUserId;
  String? _currentUserAvatar;

  // 展开回复的评论ID集合
  final Set<int> _expandedReplies = {};
  final Map<int, List<Comment>> _loadedReplies = {};
  final Map<int, bool> _loadingReplies = {};

  // 回复上下文
  Comment? _replyToComment; // 当前回复的评论（一级或二级）
  Comment? _replyToParentComment; // 当前回复的父评论（仅用于二级回复）

  @override
  void initState() {
    super.initState();
    // 使用外部提供的 ScrollController 或创建新的
    _scrollController = widget.scrollController ?? ScrollController();
    _loadCurrentUserInfo();
    _loadComments();
    _scrollController.addListener(_onScroll);
    _authStateManager.addListener(_onAuthStateChanged);

    // 监听焦点变化
    _commentFocusNode.addListener(_onFocusChange);
  }

  /// 焦点变化监听
  void _onFocusChange() {
    if (_commentFocusNode.hasFocus) {
      // 输入框获得焦点时，延迟滚动到顶部
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _onAuthStateChanged() {
    _loadCurrentUserInfo();
  }

  /// 加载当前登录用户信息
  Future<void> _loadCurrentUserInfo() async {
    final isLoggedIn = await LoginGuard.isLoggedInAsync();
    if (!isLoggedIn) {
      if (mounted) {
        setState(() {
          _currentUserId = null;
          _currentUserAvatar = null;
        });
      }
      return;
    }

    try {
      final userInfo = await _userService.getUserInfo();
      if (userInfo != null && mounted) {
        setState(() {
          _currentUserId = userInfo.userInfo.uid;
          _currentUserAvatar = userInfo.userInfo.avatar;
        });
      }
    } catch (e) {
      print('加载用户信息失败: $e');
    }
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _authStateManager.removeListener(_onAuthStateChanged);
    _commentController.dispose();
    _commentFocusNode.dispose();
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
        // 通知外部评论总数变化
        widget.onTotalCommentsChanged?.call(response.total);
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
        if (!_loadedReplies.containsKey(commentId)) {
          _loadReplies(commentId);
        }
      }
    });
  }

  /// 发表评论
  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    // 在 await 之前获取 ScaffoldMessenger，避免 use_build_context_synchronously 警告
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // 登录检测
    if (!await LoginGuard.check(context, actionName: '发表评论')) return;

    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('正在发表评论...'),
        duration: Duration(seconds: 2),
      ),
    );

    bool success;
    if (_replyToComment != null) {
      // 回复评论（一级或二级）
      success = await _videoService.postComment(
        cid: widget.vid,
        content: content,
        parentID: _replyToParentComment?.id ?? _replyToComment!.id,
        replyUserID: _replyToComment!.uid,
        replyUserName: _replyToComment!.username,
        replyContent: _replyToComment!.content,
      );
    } else {
      // 发表新评论
      success = await _videoService.postComment(
        cid: widget.vid,
        content: content,
      );
    }

    if (success) {
      _commentController.clear();
      setState(() {
        _replyToComment = null;
        _replyToParentComment = null;
      });
      _commentFocusNode.unfocus();

      // 刷新评论列表
      _currentPage = 1;
      _comments.clear();
      await _loadComments();

      // 通知外部评论已发送成功
      widget.onCommentPosted?.call();

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

  /// 删除评论
  Future<void> _deleteComment(int commentId) async {
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

    try {
      final success = await _videoService.deleteComment(commentId);

      if (success) {
        // 删除成功后刷新列表
        await _loadComments(refresh: true);
        // 通知外部刷新（复用 onCommentPosted 回调，用于更新预览区）
        widget.onCommentPosted?.call();
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
    }
  }

  /// 回复评论（一级或二级）
  void _replyToUser(Comment comment, {Comment? parentComment}) {
    setState(() {
      _replyToComment = comment;
      _replyToParentComment = parentComment;
    });
    _commentFocusNode.requestFocus();
  }

  /// 取消回复
  void _cancelReply() {
    setState(() {
      _replyToComment = null;
      _replyToParentComment = null;
    });
    _commentFocusNode.unfocus();
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
    final isInPanel = widget.scrollController != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 评论输入框（置顶）
        _buildInputArea(),

        // 评论头部：标题（仅在独立使用时显示）
        if (!isInPanel) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              '评论 $_totalComments',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
        ],

        // 评论列表（可滚动区域）
        Expanded(
          child: _comments.isEmpty && !_isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.comment_outlined,
                          size: 64, color: context.colors.iconSecondary),
                      const SizedBox(height: 16),
                      Text(
                        '暂无评论',
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 16),
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
                      onReply: () => _replyToUser(comment),
                      onReplyToReply: (reply) => _replyToUser(reply, parentComment: comment),
                      onDelete: () => _deleteComment(comment.id),
                      onDeleteReply: _deleteComment,
                      showReplies: _expandedReplies.contains(comment.id),
                      replies: _loadedReplies[comment.id],
                      isLoadingReplies: _loadingReplies[comment.id] ?? false,
                      formatTime: _formatTime,
                      currentUserId: _currentUserId,
                      onSeek: widget.onSeek,
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 构建输入区域（置顶）
  Widget _buildInputArea() {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(
          bottom: BorderSide(color: colors.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 回复提示条
            if (_replyToComment != null)
              Container(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '回复 @${_replyToComment!.username}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelReply,
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: colors.iconSecondary,
                      ),
                    ),
                  ],
                ),
              ),

            // 输入框行
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 当前登录用户头像
                _currentUserAvatar != null && _currentUserAvatar!.isNotEmpty
                    ? CachedCircleAvatar(
                        imageUrl: ImageUtils.getFullImageUrl(_currentUserAvatar!),
                        radius: 20,
                        cacheKey: 'current_user_avatar_$_currentUserId',
                      )
                    : CircleAvatar(
                        radius: 20,
                        backgroundColor: colors.surfaceVariant,
                        child: Icon(Icons.person, color: colors.iconSecondary),
                      ),
                const SizedBox(width: 12),

                // 输入框
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    focusNode: _commentFocusNode,
                    decoration: InputDecoration(
                      hintText: _replyToComment != null
                          ? '回复 @${_replyToComment!.username}'
                          : '添加公开评论...',
                      hintStyle: TextStyle(color: colors.textSecondary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colors.surfaceVariant,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: TextStyle(color: colors.textPrimary),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitComment(),
                  ),
                ),
                const SizedBox(width: 8),

                // 发送按钮
                Container(
                  decoration: BoxDecoration(
                    color: colors.accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, size: 20),
                    onPressed: _submitComment,
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 评论项组件
class _CommentItem extends StatelessWidget {
  final Comment comment;
  final VoidCallback onToggleReplies;
  final VoidCallback onReply;
  final Function(Comment) onReplyToReply; // 回复二级评论
  final VoidCallback onDelete;
  final Function(int) onDeleteReply;
  final bool showReplies;
  final List<Comment>? replies;
  final bool isLoadingReplies;
  final String Function(DateTime) formatTime;
  final int? currentUserId;
  final void Function(int seconds)? onSeek; // 点击时间戳跳转回调

  const _CommentItem({
    required this.comment,
    required this.onToggleReplies,
    required this.onReply,
    required this.onReplyToReply,
    required this.onDelete,
    required this.onDeleteReply,
    required this.showReplies,
    this.replies,
    required this.isLoadingReplies,
    required this.formatTime,
    this.currentUserId,
    this.onSeek,
  });

  bool get isOwnComment => currentUserId != null && comment.uid == currentUserId;

  void _navigateToUserSpace(BuildContext context, int uid) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserSpacePage(userId: uid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 用户头像（可点击跳转到UP主页面）
              GestureDetector(
                onTap: () => _navigateToUserSpace(context, comment.uid),
                child: comment.avatar.isNotEmpty
                    ? CachedCircleAvatar(
                        imageUrl: ImageUtils.getFullImageUrl(comment.avatar),
                        radius: 20,
                        cacheKey: 'user_avatar_${comment.uid}',
                      )
                    : CircleAvatar(
                        radius: 20,
                        backgroundColor: colors.surfaceVariant,
                        child: Icon(Icons.person, size: 20, color: colors.iconSecondary),
                      ),
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
                        GestureDetector(
                          onTap: () => _navigateToUserSpace(context, comment.uid),
                          child: Text(
                            comment.username,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatTime(comment.createdAt),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // 评论正文（支持时间戳点击跳转）
                    RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 14, color: colors.textPrimary),
                        children: [
                          if (comment.replyUserName != null && comment.replyUserName!.isNotEmpty)
                            TextSpan(
                              text: '@${comment.replyUserName} ',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          // 使用 TimestampParser 解析评论内容，支持时间戳点击
                          ...TimestampParser.buildTextSpans(
                            text: comment.content,
                            defaultStyle: TextStyle(fontSize: 14, color: colors.textPrimary),
                            timestampStyle: const TextStyle(
                              fontSize: 14,
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                            onTimestampTap: onSeek,
                          ),
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
                                color: colors.iconSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '回复',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),

                        // 查看回复按钮
                        if (comment.replyCount > 0)
                          InkWell(
                            onTap: onToggleReplies,
                            child: Row(
                              children: [
                                Icon(
                                  showReplies ? Icons.expand_less : Icons.expand_more,
                                  size: 16,
                                  color: colors.iconSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${comment.replyCount} 条回复',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Spacer(),

                        // 删除按钮
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
                          ...replies!.map((reply) => _ReplyItem(
                                reply: reply,
                                onReply: () => onReplyToReply(reply),
                                onDelete: () => onDeleteReply(reply.id),
                                formatTime: formatTime,
                                currentUserId: currentUserId,
                                onSeek: onSeek,
                              )),
                          InkWell(
                            onTap: onToggleReplies,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 12),
                              child: Text(
                                '收起回复',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
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
                          style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        ),
                      ),
          ),

        Divider(height: 1, color: colors.divider),
      ],
    );
  }
}

/// 回复项组件
class _ReplyItem extends StatelessWidget {
  final Comment reply;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final String Function(DateTime) formatTime;
  final int? currentUserId;
  final void Function(int seconds)? onSeek; // 点击时间戳跳转回调

  const _ReplyItem({
    required this.reply,
    required this.onReply,
    required this.onDelete,
    required this.formatTime,
    this.currentUserId,
    this.onSeek,
  });

  bool get isOwnReply => currentUserId != null && reply.uid == currentUserId;

  void _navigateToUserSpace(BuildContext context, int uid) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserSpacePage(userId: uid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _navigateToUserSpace(context, reply.uid),
            child: reply.avatar.isNotEmpty
                ? CachedCircleAvatar(
                    imageUrl: ImageUtils.getFullImageUrl(reply.avatar),
                    radius: 16,
                    cacheKey: 'user_avatar_${reply.uid}',
                  )
                : CircleAvatar(
                    radius: 16,
                    backgroundColor: colors.surfaceVariant,
                    child: Icon(Icons.person, size: 16, color: colors.iconSecondary),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _navigateToUserSpace(context, reply.uid),
                      child: Text(
                        reply.username,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatTime(reply.createdAt),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // 回复内容（支持时间戳点击跳转）
                RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: colors.textPrimary),
                    children: [
                      if (reply.replyUserName != null && reply.replyUserName!.isNotEmpty)
                        TextSpan(
                          text: '@${reply.replyUserName} ',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      // 使用 TimestampParser 解析回复内容，支持时间戳点击
                      ...TimestampParser.buildTextSpans(
                        text: reply.content,
                        defaultStyle: TextStyle(fontSize: 13, color: colors.textPrimary),
                        timestampStyle: const TextStyle(
                          fontSize: 13,
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                        onTimestampTap: onSeek,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // 操作按钮
                Row(
                  children: [
                    InkWell(
                      onTap: onReply,
                      child: Text(
                        '回复',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (isOwnReply)
                      InkWell(
                        onTap: onDelete,
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
    );
  }
}
