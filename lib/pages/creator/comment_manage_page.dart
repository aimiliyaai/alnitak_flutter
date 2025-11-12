import 'package:flutter/material.dart';

/// 评论管理页面
class CommentManagePage extends StatefulWidget {
  const CommentManagePage({super.key});

  @override
  State<CommentManagePage> createState() => _CommentManagePageState();
}

class _CommentManagePageState extends State<CommentManagePage>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _selectedVideoId = 0; // 0表示全部

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadComments();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 标签页切换
  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        _comments = [];
        _hasMore = true;
        _selectedVideoId = 0;
      });
      _loadComments();
    }
  }

  /// 滚动监听
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMoreComments();
      }
    }
  }

  /// 加载评论列表
  Future<void> _loadComments() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // TODO: 根据tab调用不同的API
      // if (_tabController.index == 0) {
      //   // 视频评论
      //   final response = await _videoService.getVideoCommentList(_selectedVideoId, _currentPage, _pageSize);
      // } else {
      //   // 文章评论
      //   final response = await _articleService.getArticleCommentList(_selectedVideoId, _currentPage, _pageSize);
      // }

      await Future.delayed(const Duration(seconds: 1));

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('评论列表功能开发中，请先实现API接口')),
        );
      }
    } catch (e) {
      // print('加载评论列表失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 加载更多评论
  Future<void> _loadMoreComments() async {
    if (_isLoading || !_hasMore) return;
    await _loadComments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('评论管理'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '视频评论'),
            Tab(text: '文章评论'),
          ],
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue,
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
                _buildCommentList(), // 视频评论
                _buildCommentList(), // 文章评论
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建筛选栏
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Text(
            '选择${_tabController.index == 0 ? "视频" : "文章"}：',
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<int>(
              value: _selectedVideoId,
              isExpanded: true,
              underline: Container(),
              items: const [
                DropdownMenuItem(
                  value: 0,
                  child: Text('全部'),
                ),
                // TODO: 添加用户的视频/文章列表
              ],
              onChanged: (value) {
                setState(() {
                  _selectedVideoId = value ?? 0;
                  _comments = [];
                  _hasMore = true;
                });
                _loadComments();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建评论列表
  Widget _buildCommentList() {
    if (_comments.isEmpty && !_isLoading) {
      return _buildEmptyState();
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _comments.length + (_hasMore ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == _comments.length) {
          return _buildLoadingIndicator();
        }
        return _buildCommentItem(_comments[index]);
      },
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.comment_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            '暂无评论',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
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
  Widget _buildCommentItem(Map<String, dynamic> comment) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧评论信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 评论者头像和名字
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.grey[300],
                        child: const Icon(Icons.person, size: 20),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        comment['authorName'] ?? '匿名用户',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 评论内容
                  Text(
                    comment['content'] ?? '',
                    style: const TextStyle(fontSize: 14),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // 被回复的内容（如果有）
                  if (comment['targetReplyContent'] != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '回复 @${comment['targetUserName']}:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            comment['targetReplyContent'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // 时间
                  Text(
                    comment['createdAt'] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),

            // 右侧视频/文章预览
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                // TODO: 跳转到对应的视频/文章页面
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('跳转功能开发中')),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 80,
                  height: 60,
                  color: Colors.grey[300],
                  child: comment['videoCover'] != null
                      ? Image.network(
                          comment['videoCover'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.video_library_outlined,
                              size: 30,
                              color: Colors.grey[400],
                            );
                          },
                        )
                      : Icon(
                          _tabController.index == 0
                              ? Icons.video_library_outlined
                              : Icons.article_outlined,
                          size: 30,
                          color: Colors.grey[400],
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
