import 'package:flutter/material.dart';
import '../../models/comment_manage.dart';
import '../../services/comment_manage_service.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/cached_image_widget.dart';
import '../../utils/time_utils.dart';
import '../../utils/login_guard.dart';
import '../video/video_play_page.dart';

/// 评论管理页面
class CommentManagePage extends StatefulWidget {
  const CommentManagePage({super.key});

  @override
  State<CommentManagePage> createState() => _CommentManagePageState();
}

class _CommentManagePageState extends State<CommentManagePage>
    with SingleTickerProviderStateMixin {
  final CommentManageService _commentService = CommentManageService();
  final ScrollController _videoScrollController = ScrollController();
  final ScrollController _articleScrollController = ScrollController();
  late TabController _tabController;

  // 视频评论数据
  List<ManageComment> _videoComments = [];
  bool _isLoadingVideo = false;
  bool _isLoadingMoreVideo = false;
  bool _hasMoreVideo = true;
  int _videoPage = 1;
  int _videoTotal = 0;

  // 文章评论数据
  List<ManageComment> _articleComments = [];
  bool _isLoadingArticle = false;
  bool _isLoadingMoreArticle = false;
  bool _hasMoreArticle = true;
  int _articlePage = 1;
  int _articleTotal = 0;

  static const int _pageSize = 10;

  // 视频/文章筛选
  List<UserVideoItem> _videoList = [];
  List<UserArticleItem> _articleList = [];
  int _selectedVideoId = 0; // 0表示全部
  int _selectedArticleId = 0; // 0表示全部

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _videoScrollController.addListener(_onVideoScroll);
    _articleScrollController.addListener(_onArticleScroll);
    _checkLoginAndLoad();
  }

  /// 检查登录状态
  Future<void> _checkLoginAndLoad() async {
    final isLoggedIn = await LoginGuard.isLoggedIn();
    if (!isLoggedIn && mounted) {
      final result = await LoginGuard.navigateToLogin(context);
      if (result != true && mounted) {
        Navigator.pop(context);
        return;
      }
    }
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _videoScrollController.dispose();
    _articleScrollController.dispose();
    super.dispose();
  }

  /// 加载初始数据
  Future<void> _loadInitialData() async {
    // 并发加载视频列表、文章列表
    await Future.wait([
      _loadVideoList(),
      _loadArticleList(),
    ]);
    // 加载当前Tab的评论
    _loadVideoComments();
  }

  /// 加载用户的视频列表
  Future<void> _loadVideoList() async {
    final videos = await _commentService.getAllVideoList();
    if (mounted) {
      setState(() {
        _videoList = videos;
      });
    }
  }

  /// 加载用户的文章列表
  Future<void> _loadArticleList() async {
    final articles = await _commentService.getAllArticleList();
    if (mounted) {
      setState(() {
        _articleList = articles;
      });
    }
  }

  /// 标签页切换
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {}); // 刷新筛选栏
    // 首次切换到文章Tab时加载数据
    if (_tabController.index == 1 && _articleComments.isEmpty && !_isLoadingArticle) {
      _loadArticleComments();
    }
  }

  /// 视频滚动监听
  void _onVideoScroll() {
    if (_videoScrollController.position.pixels >=
        _videoScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingVideo && !_isLoadingMoreVideo && _hasMoreVideo) {
        _loadMoreVideoComments();
      }
    }
  }

  /// 文章滚动监听
  void _onArticleScroll() {
    if (_articleScrollController.position.pixels >=
        _articleScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingArticle && !_isLoadingMoreArticle && _hasMoreArticle) {
        _loadMoreArticleComments();
      }
    }
  }

  /// 加载视频评论列表
  Future<void> _loadVideoComments() async {
    if (_isLoadingVideo) return;

    setState(() {
      _isLoadingVideo = true;
    });

    try {
      final response = await _commentService.getVideoCommentList(
        vid: _selectedVideoId,
        page: _videoPage,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          if (response != null) {
            _videoComments = response.comments;
            _videoTotal = response.total;
            _hasMoreVideo = response.comments.length >= _pageSize;
          } else {
            _videoComments = [];
            _videoTotal = 0;
            _hasMoreVideo = false;
          }
          _isLoadingVideo = false;
        });
      }
    } catch (e) {
      debugPrint('加载视频评论列表失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  /// 加载更多视频评论
  Future<void> _loadMoreVideoComments() async {
    if (_isLoadingMoreVideo || !_hasMoreVideo) return;

    setState(() {
      _isLoadingMoreVideo = true;
    });

    try {
      _videoPage++;

      final response = await _commentService.getVideoCommentList(
        vid: _selectedVideoId,
        page: _videoPage,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          if (response != null && response.comments.isNotEmpty) {
            _videoComments.addAll(response.comments);
            _hasMoreVideo = response.comments.length >= _pageSize;
          } else {
            _hasMoreVideo = false;
          }
          _isLoadingMoreVideo = false;
        });
      }
    } catch (e) {
      debugPrint('加载更多视频评论失败: $e');
      if (mounted) {
        setState(() {
          _videoPage--;
          _isLoadingMoreVideo = false;
        });
      }
    }
  }

  /// 加载文章评论列表
  Future<void> _loadArticleComments() async {
    if (_isLoadingArticle) return;

    setState(() {
      _isLoadingArticle = true;
    });

    try {
      final response = await _commentService.getArticleCommentList(
        aid: _selectedArticleId,
        page: _articlePage,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          if (response != null) {
            _articleComments = response.comments;
            _articleTotal = response.total;
            _hasMoreArticle = response.comments.length >= _pageSize;
          } else {
            _articleComments = [];
            _articleTotal = 0;
            _hasMoreArticle = false;
          }
          _isLoadingArticle = false;
        });
      }
    } catch (e) {
      debugPrint('加载文章评论列表失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingArticle = false;
        });
      }
    }
  }

  /// 加载更多文章评论
  Future<void> _loadMoreArticleComments() async {
    if (_isLoadingMoreArticle || !_hasMoreArticle) return;

    setState(() {
      _isLoadingMoreArticle = true;
    });

    try {
      _articlePage++;

      final response = await _commentService.getArticleCommentList(
        aid: _selectedArticleId,
        page: _articlePage,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          if (response != null && response.comments.isNotEmpty) {
            _articleComments.addAll(response.comments);
            _hasMoreArticle = response.comments.length >= _pageSize;
          } else {
            _hasMoreArticle = false;
          }
          _isLoadingMoreArticle = false;
        });
      }
    } catch (e) {
      debugPrint('加载更多文章评论失败: $e');
      if (mounted) {
        setState(() {
          _articlePage--;
          _isLoadingMoreArticle = false;
        });
      }
    }
  }

  /// 删除评论
  Future<void> _deleteComment(ManageComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条评论吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    bool success;
    if (_tabController.index == 0) {
      success = await _commentService.deleteVideoComment(comment.id);
    } else {
      success = await _commentService.deleteArticleComment(comment.id);
    }

    if (success) {
      setState(() {
        if (_tabController.index == 0) {
          _videoComments.removeWhere((c) => c.id == comment.id);
          _videoTotal--;
        } else {
          _articleComments.removeWhere((c) => c.id == comment.id);
          _articleTotal--;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('评论已删除')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败，请重试')),
        );
      }
    }
  }

  /// 跳转到视频
  void _navigateToVideo(int vid) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayPage(vid: vid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('评论管理'),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.iconPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: colors.card,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '视频评论'),
                Tab(text: '文章评论'),
              ],
              labelColor: colors.accentColor,
              unselectedLabelColor: colors.textSecondary,
              indicatorColor: colors.accentColor,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 筛选器
          _buildFilterBar(),

          // 评论列表
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildVideoCommentList(),
                _buildArticleCommentList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建筛选栏
  Widget _buildFilterBar() {
    final colors = context.colors;
    final isVideoTab = _tabController.index == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            '筛选：',
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: isVideoTab ? _selectedVideoId : _selectedArticleId,
                  isExpanded: true,
                  dropdownColor: colors.card,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                  icon: Icon(Icons.arrow_drop_down, color: colors.iconSecondary),
                  items: isVideoTab
                      ? [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('全部视频', style: TextStyle(color: colors.textPrimary)),
                          ),
                          ..._videoList.map((video) => DropdownMenuItem(
                                value: video.vid,
                                child: Text(
                                  video.title,
                                  style: TextStyle(color: colors.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )),
                        ]
                      : [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('全部文章', style: TextStyle(color: colors.textPrimary)),
                          ),
                          ..._articleList.map((article) => DropdownMenuItem(
                                value: article.aid,
                                child: Text(
                                  article.title,
                                  style: TextStyle(color: colors.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )),
                        ],
                  onChanged: (value) {
                    if (isVideoTab) {
                      setState(() {
                        _selectedVideoId = value ?? 0;
                        _videoComments = [];
                        _hasMoreVideo = true;
                        _videoPage = 1;
                      });
                      _loadVideoComments();
                    } else {
                      setState(() {
                        _selectedArticleId = value ?? 0;
                        _articleComments = [];
                        _hasMoreArticle = true;
                        _articlePage = 1;
                      });
                      _loadArticleComments();
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 显示总数
          Text(
            '共 ${isVideoTab ? _videoTotal : _articleTotal} 条',
            style: TextStyle(fontSize: 12, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// 构建视频评论列表
  Widget _buildVideoCommentList() {
    if (_isLoadingVideo && _videoComments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_videoComments.isEmpty) {
      return _buildEmptyState(isVideo: true);
    }

    return RefreshIndicator(
      onRefresh: () async {
        _videoPage = 1;
        await _loadVideoComments();
      },
      child: ListView.separated(
        controller: _videoScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _videoComments.length + (_isLoadingMoreVideo ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _videoComments.length) {
            return _buildLoadingIndicator();
          }
          return _buildCommentItem(_videoComments[index], isVideo: true);
        },
      ),
    );
  }

  /// 构建文章评论列表
  Widget _buildArticleCommentList() {
    if (_isLoadingArticle && _articleComments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_articleComments.isEmpty) {
      return _buildEmptyState(isVideo: false);
    }

    return RefreshIndicator(
      onRefresh: () async {
        _articlePage = 1;
        await _loadArticleComments();
      },
      child: ListView.separated(
        controller: _articleScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _articleComments.length + (_isLoadingMoreArticle ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _articleComments.length) {
            return _buildLoadingIndicator();
          }
          return _buildCommentItem(_articleComments[index], isVideo: false);
        },
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState({required bool isVideo}) {
    final colors = context.colors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.comment_outlined,
            size: 80,
            color: colors.iconSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无评论',
            style: TextStyle(
              fontSize: 16,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isVideo ? '你的视频还没有收到评论' : '你的文章还没有收到评论',
            style: TextStyle(
              fontSize: 14,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建加载指示器
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
    );
  }

  /// 构建评论项
  Widget _buildCommentItem(ManageComment comment, {required bool isVideo}) {
    final colors = context.colors;
    final content = isVideo ? comment.video : comment.article;

    // 获取被引用的内容（确保非空且有实际内容）
    final quotedContent = (comment.targetReplyContent?.isNotEmpty == true)
        ? comment.targetReplyContent
        : (comment.rootContent?.isNotEmpty == true ? comment.rootContent : null);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像
          ClipOval(
            child: CachedImage(
              imageUrl: comment.author.avatar,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorWidget: Container(
                width: 36,
                height: 36,
                color: colors.surfaceVariant,
                child: Icon(Icons.person, size: 20, color: colors.iconSecondary),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 中间评论内容区
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 用户名和时间行
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            comment.author.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                          if (comment.target != null) ...[
                            Text(
                              ' 回复 ',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textTertiary,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                comment.target!.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.accentColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      TimeUtils.formatRelativeTime(comment.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // 评论内容
                Text(
                  comment.content,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary, height: 1.4),
                ),

                // 被引用的原评论（仅当有内容时显示）
                if (quotedContent != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border(
                        left: BorderSide(color: colors.textTertiary.withOpacity(0.3), width: 2),
                      ),
                    ),
                    child: Text(
                      quotedContent,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],

                // 删除按钮行
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => _deleteComment(comment),
                    child: Text(
                      '删除',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 右侧视频/文章封面
          if (content != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                if (isVideo && comment.video != null) {
                  _navigateToVideo(comment.video!.id);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('文章详情页开发中')),
                  );
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedImage(
                  imageUrl: content.cover,
                  width: 72,
                  height: 45,
                  fit: BoxFit.cover,
                  errorWidget: Container(
                    width: 72,
                    height: 45,
                    color: colors.surfaceVariant,
                    child: Icon(
                      isVideo ? Icons.play_circle_outline : Icons.article_outlined,
                      size: 20,
                      color: colors.iconSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
