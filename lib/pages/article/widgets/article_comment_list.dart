import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/gestures.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../../models/article_detail_model.dart';
import '../../../services/article_api_service.dart';
import '../../../services/user_service.dart';
import '../../../widgets/cached_image_widget.dart';
import '../../../utils/login_guard.dart';
import '../../../utils/auth_state_manager.dart';
import '../../../utils/timestamp_parser.dart';
import '../../../theme/theme_extensions.dart';
import '../../../utils/image_utils.dart';
import '../../../utils/time_utils.dart';
import '../../user/user_space_page.dart';

/// 文章评论列表组件
class ArticleCommentList extends StatefulWidget {
  final int aid;
  final ScrollController? scrollController;
  final VoidCallback? onCommentPosted;
  final void Function(int count)? onTotalCommentsChanged;

  const ArticleCommentList({
    super.key,
    required this.aid,
    this.scrollController,
    this.onCommentPosted,
    this.onTotalCommentsChanged,
  });

  @override
  State<ArticleCommentList> createState() => _ArticleCommentListState();
}

class _ArticleCommentListState extends State<ArticleCommentList> {
  final UserService _userService = UserService();
  final AuthStateManager _authStateManager = AuthStateManager();
  late final ScrollController _scrollController;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  bool _showEmojiPicker = false;
  final List<ArticleComment> _comments = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _totalComments = 0;

  int? _currentUserId;
  String? _currentUserAvatar;

  final Set<int> _expandedReplies = {};
  final Map<int, List<ArticleComment>> _loadedReplies = {};
  final Map<int, bool> _loadingReplies = {};

  ArticleComment? _replyToComment;
  ArticleComment? _replyToParentComment;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _loadCurrentUserInfo();
    _loadComments();
    _scrollController.addListener(_onScroll);
    _authStateManager.addListener(_onAuthStateChanged);
    _commentFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_commentFocusNode.hasFocus) {
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
    } catch (_) {
      // 静默忽略获取当前用户失败
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
      final response = await ArticleApiService.getArticleComments(
        aid: widget.aid,
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
        widget.onTotalCommentsChanged?.call(response.total);
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
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
      final replies = await ArticleApiService.getCommentReplies(commentId: commentId);
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

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (!await LoginGuard.check(context, actionName: '发表评论')) return;

    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('正在发表评论...'),
        duration: Duration(seconds: 2),
      ),
    );

    bool success;
    if (_replyToComment != null) {
      success = await ArticleApiService.postArticleComment(
        aid: widget.aid,
        content: content,
        parentID: _replyToParentComment?.id ?? _replyToComment!.id,
        replyUserID: _replyToComment!.uid,
        replyUserName: _replyToComment!.username,
        replyContent: _replyToComment!.content,
      );
    } else {
      success = await ArticleApiService.postArticleComment(
        aid: widget.aid,
        content: content,
      );
    }

    if (success) {
      final parentCommentId = _replyToParentComment?.id ?? _replyToComment?.id;

      _commentController.clear();
      setState(() {
        _replyToComment = null;
        _replyToParentComment = null;
        _showEmojiPicker = false;
      });
      _commentFocusNode.unfocus();

      _currentPage = 1;
      _comments.clear();
      await _loadComments();

      if (parentCommentId != null) {
        _loadReplies(parentCommentId);
      }

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
      final success = await ArticleApiService.deleteArticleComment(commentId);

      if (success) {
        await _loadComments(refresh: true);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除评论失败: $e')),
        );
      }
    }
  }

  void _replyToUser(ArticleComment comment, {ArticleComment? parentComment}) {
    setState(() {
      _replyToComment = comment;
      _replyToParentComment = parentComment;
      if (parentComment != null) {
        _commentController.text = '@${comment.username} ';
        _commentController.selection = TextSelection.fromPosition(
          TextPosition(offset: _commentController.text.length),
        );
      }
    });
    _commentFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyToComment = null;
      _replyToParentComment = null;
    });
    _commentFocusNode.unfocus();
  }

  /// 点赞/取消点赞评论（与点踩互斥）
  Future<void> _likeComment(int commentId, bool like) async {
    final error = await ArticleApiService.likeArticleComment(commentId, like);
    if (error == null || _isIdempotent(error, like, isLike: true)) {
      setState(() {
        _applyLikeUpdate(commentId, like);
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${like ? '点赞' : '取消点赞'}失败: $error')),
      );
    }
  }

  /// 点踩/取消点踩评论（与点赞互斥）
  Future<void> _dislikeComment(int commentId, bool dislike) async {
    final error = await ArticleApiService.dislikeArticleComment(commentId, dislike);
    if (error == null || _isIdempotent(error, dislike, isLike: false)) {
      setState(() {
        _applyDislikeUpdate(commentId, dislike);
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${dislike ? '点踩' : '取消点踩'}失败: $error')),
      );
    }
  }

  /// 判断错误是否为幂等型（服务端已是目标状态）
  bool _isIdempotent(String error, bool toTrue, {required bool isLike}) {
    if (isLike) {
      return (toTrue && error.contains('已点赞')) ||
          (!toTrue && error.contains('未点赞'));
    } else {
      return (toTrue && error.contains('已点踩')) ||
          (!toTrue && error.contains('未点踩'));
    }
  }

  /// 在一级评论及所有已加载回复中查找并更新点赞状态
  void _applyLikeUpdate(int commentId, bool like) {
    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index != -1) {
      final c = _comments[index];
      _comments[index] = c.copyWith(
        liked: like,
        likes: like
            ? c.likes + 1
            : (c.likes > 0 ? c.likes - 1 : 0),
        disliked: like ? false : c.disliked,
      );
      return;
    }
    for (final entry in _loadedReplies.entries) {
      final list = entry.value;
      final i = list.indexWhere((r) => r.id == commentId);
      if (i != -1) {
        final r = list[i];
        list[i] = r.copyWith(
          liked: like,
          likes: like
              ? r.likes + 1
              : (r.likes > 0 ? r.likes - 1 : 0),
          disliked: like ? false : r.disliked,
        );
        return;
      }
    }
  }

  /// 在一级评论及所有已加载回复中查找并更新点踩状态
  void _applyDislikeUpdate(int commentId, bool dislike) {
    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index != -1) {
      final c = _comments[index];
      final wasLiked = c.liked;
      _comments[index] = c.copyWith(
        disliked: dislike,
        liked: dislike ? false : c.liked,
        likes: dislike && wasLiked
            ? (c.likes > 0 ? c.likes - 1 : 0)
            : c.likes,
      );
      return;
    }
    for (final entry in _loadedReplies.entries) {
      final list = entry.value;
      final i = list.indexWhere((r) => r.id == commentId);
      if (i != -1) {
        final r = list[i];
        final wasLiked = r.liked;
        list[i] = r.copyWith(
          disliked: dislike,
          liked: dislike ? false : r.liked,
          likes: dislike && wasLiked
              ? (r.likes > 0 ? r.likes - 1 : 0)
              : r.likes,
        );
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInPanel = widget.scrollController != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 1),
        _buildInputArea(),

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
                    return _ArticleCommentItem(
                      comment: comment,
                      onToggleReplies: () => _toggleReplies(comment.id),
                      onReply: () => _replyToUser(comment),
                      onReplyToReply: (reply) => _replyToUser(reply, parentComment: comment),
                      onDelete: () => _deleteComment(comment.id),
                      onDeleteReply: _deleteComment,
                      onLike: (like) => _likeComment(comment.id, like),
                      onDislike: (dislike) => _dislikeComment(comment.id, dislike),
                      onReplyLike: _likeComment,
                      onReplyDislike: _dislikeComment,
                      showReplies: _expandedReplies.contains(comment.id),
                      replies: _loadedReplies[comment.id],
                      isLoadingReplies: _loadingReplies[comment.id] ?? false,
                      formatTime: TimeUtils.formatRelativeTime,
                      currentUserId: _currentUserId,
                    );
                  },
                ),
        ),
      ],
    );
  }

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

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _currentUserAvatar != null && _currentUserAvatar!.isNotEmpty
                    ? CachedCircleAvatar(
                        imageUrl: ImageUtils.getFullImageUrl(_currentUserAvatar!),
                        radius: 20,
                      )
                    : CircleAvatar(
                        radius: 20,
                        backgroundColor: colors.surfaceVariant,
                        child: Icon(Icons.person, color: colors.iconSecondary),
                      ),
                const SizedBox(width: 12),

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

                IconButton(
                  onPressed: () {
                    setState(() {
                      _showEmojiPicker = !_showEmojiPicker;
                    });
                  },
                  icon: Icon(
                    Icons.emoji_emotions,
                    color: _showEmojiPicker ? colors.accentColor : colors.iconSecondary,
                  ),
                ),

                const SizedBox(width: 8),

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

            Offstage(
              offstage: !_showEmojiPicker,
              child: SizedBox(
                height: 250,
                child: EmojiPicker(
                  textEditingController: _commentController,
                  config: Config(
                    height: 250,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      columns: 8,
                      emojiSizeMax: 28 * (foundation.defaultTargetPlatform == foundation.TargetPlatform.iOS ? 1.2 : 1.0),
                      backgroundColor: colors.card,
                      noRecents: Text(
                        '暂无最近使用的表情',
                        style: TextStyle(
                          fontSize: 16,
                          color: colors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: colors.card,
                      indicatorColor: colors.accentColor,
                      iconColorSelected: colors.accentColor,
                      iconColor: colors.iconSecondary,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(
                      enabled: false,
                    ),
                    searchViewConfig: SearchViewConfig(
                      backgroundColor: colors.card,
                      buttonIconColor: colors.iconSecondary,
                      hintText: '搜索表情',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 文章评论项组件
class _ArticleCommentItem extends StatelessWidget {
  final ArticleComment comment;
  final VoidCallback onToggleReplies;
  final VoidCallback onReply;
  final Function(ArticleComment) onReplyToReply;
  final VoidCallback onDelete;
  final Function(int) onDeleteReply;
  final Function(bool) onLike;
  final Function(bool) onDislike;
  final Function(int, bool) onReplyLike;
  final Function(int, bool) onReplyDislike;
  final bool showReplies;
  final List<ArticleComment>? replies;
  final bool isLoadingReplies;
  final String Function(DateTime) formatTime;
  final int? currentUserId;

  const _ArticleCommentItem({
    required this.comment,
    required this.onToggleReplies,
    required this.onReply,
    required this.onReplyToReply,
    required this.onDelete,
    required this.onDeleteReply,
    required this.onLike,
    required this.onDislike,
    required this.onReplyLike,
    required this.onReplyDislike,
    required this.showReplies,
    this.replies,
    required this.isLoadingReplies,
    required this.formatTime,
    this.currentUserId,
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
              GestureDetector(
                onTap: () => _navigateToUserSpace(context, comment.uid),
                child: comment.avatar.isNotEmpty
                    ? CachedCircleAvatar(
                        imageUrl: ImageUtils.getFullImageUrl(comment.avatar),
                        radius: 20,
                      )
                    : CircleAvatar(
                        radius: 20,
                        backgroundColor: colors.surfaceVariant,
                        child: Icon(Icons.person, size: 20, color: colors.iconSecondary),
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

                    RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 14, color: colors.textPrimary),
                        children: [
                          if (comment.replyUserName != null && comment.replyUserName!.isNotEmpty)
                            TextSpan(
                              text: '@${comment.replyUserName} ',
                              style: TextStyle(
                                color: colors.accentColor,
                                fontWeight: FontWeight.w500,
                              ),
                              recognizer: comment.replyUserId != null
                                  ? (TapGestureRecognizer()
                                    ..onTap = () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => UserSpacePage(userId: comment.replyUserId!),
                                        ),
                                      );
                                    })
                                  : null,
                            ),
                          // 使用 TimestampParser 解析评论内容，支持 @用户名点击跳转
                          ...TimestampParser.buildTextSpans(
                            text: comment.content,
                            defaultStyle: TextStyle(fontSize: 14, color: colors.textPrimary),
                            mentionStyle: TextStyle(
                              fontSize: 14,
                              color: colors.accentColor,
                              fontWeight: FontWeight.w500,
                            ),
                            atUserMap: comment.atUserMap,
                            onMentionTapWithId: (userId) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserSpacePage(userId: userId),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
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

                        // 点赞按钮
                        InkWell(
                          onTap: () => onLike(!comment.liked),
                          child: Row(
                            children: [
                              Icon(
                                comment.liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                                size: 16,
                                color: comment.liked ? const Color(0xFFFB7299) : colors.iconSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                comment.likes > 0 ? '${comment.likes}' : '赞',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: comment.liked ? const Color(0xFFFB7299) : colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // 点踩按钮（数量前端隐藏）
                        InkWell(
                          onTap: () => onDislike(!comment.disliked),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Icon(
                              comment.disliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                              size: 16,
                              color: comment.disliked ? const Color(0xFF5EB6FF) : colors.iconSecondary,
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

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
                          ...replies!.map((reply) => _ArticleReplyItem(
                                reply: reply,
                                rootUid: comment.uid,
                                onReply: () => onReplyToReply(reply),
                                onDelete: () => onDeleteReply(reply.id),
                                onLike: (like) => onReplyLike(reply.id, like),
                                onDislike: (dislike) => onReplyDislike(reply.id, dislike),
                                formatTime: formatTime,
                                currentUserId: currentUserId,
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

/// 文章回复项组件
class _ArticleReplyItem extends StatelessWidget {
  final ArticleComment reply;
  final int rootUid;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final Function(bool) onLike;
  final Function(bool) onDislike;
  final String Function(DateTime) formatTime;
  final int? currentUserId;

  const _ArticleReplyItem({
    required this.reply,
    required this.rootUid,
    required this.onReply,
    required this.onDelete,
    required this.onLike,
    required this.onDislike,
    required this.formatTime,
    this.currentUserId,
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

                RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: colors.textPrimary),
                    children: [
                      if (reply.replyUserName != null &&
                          reply.replyUserName!.isNotEmpty &&
                          reply.replyUserId != rootUid)
                        TextSpan(
                          text: '@${reply.replyUserName} ',
                          style: TextStyle(
                            color: colors.accentColor,
                            fontWeight: FontWeight.w500,
                          ),
                          recognizer: reply.replyUserId != null
                              ? (TapGestureRecognizer()
                                ..onTap = () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => UserSpacePage(userId: reply.replyUserId!),
                                    ),
                                  );
                                })
                              : null,
                        ),
                      // 使用 TimestampParser 解析回复内容，支持 @用户名点击跳转
                      ...TimestampParser.buildTextSpans(
                        text: reply.content,
                        defaultStyle: TextStyle(fontSize: 13, color: colors.textPrimary),
                        mentionStyle: TextStyle(
                          fontSize: 13,
                          color: colors.accentColor,
                          fontWeight: FontWeight.w500,
                        ),
                        atUserMap: reply.atUserMap,
                        onMentionTapWithId: (userId) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserSpacePage(userId: userId),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

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
                    // 点赞按钮
                    InkWell(
                      onTap: () => onLike(!reply.liked),
                      child: Row(
                        children: [
                          Icon(
                            reply.liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                            size: 14,
                            color: reply.liked ? const Color(0xFFFB7299) : colors.iconSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            reply.likes > 0 ? '${reply.likes}' : '赞',
                            style: TextStyle(
                              fontSize: 11,
                              color: reply.liked ? const Color(0xFFFB7299) : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 点踩按钮（数量前端隐藏）
                    InkWell(
                      onTap: () => onDislike(!reply.disliked),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Icon(
                          reply.disliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                          size: 14,
                          color: reply.disliked ? const Color(0xFF5EB6FF) : colors.iconSecondary,
                        ),
                      ),
                    ),
                    if (isOwnReply) ...[
                      const SizedBox(width: 8),
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
