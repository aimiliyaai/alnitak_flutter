import 'package:flutter/material.dart';
import '../../models/upload_article.dart';
import '../../services/article_submit_api_service.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/image_utils.dart';
import '../../widgets/loading_more_indicator.dart';
import 'article_upload_page.dart';

class ArticleManuscriptPage extends StatefulWidget {
  const ArticleManuscriptPage({super.key});

  @override
  State<ArticleManuscriptPage> createState() => _ArticleManuscriptPageState();
}

/// 文章筛选分类
enum ArticleFilter { all, published, pendingReview, rejected }

class _ArticleManuscriptPageState extends State<ArticleManuscriptPage> {
  final ScrollController _scrollController = ScrollController();

  List<ManuscriptArticle> _articles = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _errorMessage;
  static const int _pageSize = 20;
  ArticleFilter _currentFilter = ArticleFilter.all;

  static String _categoryFromFilter(ArticleFilter f) {
    switch (f) {
      case ArticleFilter.all:
        return 'all';
      case ArticleFilter.published:
        return 'published';
      case ArticleFilter.pendingReview:
        return 'pending';
      case ArticleFilter.rejected:
        return 'rejected';
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadArticles();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreArticles();
    }
  }

  Future<void> _loadArticles({bool forceReload = false}) async {
    if (!forceReload && _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentPage = 1;
      if (forceReload) {
        _articles = [];
        _hasMore = true;
      }
    });

    final category = _categoryFromFilter(_currentFilter);

    try {
      final articles = await ArticleSubmitApiService.getManuscriptArticles(
        page: 1,
        pageSize: _pageSize,
        category: category,
      );

      if (mounted) {
        setState(() {
          _articles = articles;
          _hasMore = articles.length >= _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreArticles() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    final nextPage = _currentPage + 1;
    final category = _categoryFromFilter(_currentFilter);

    try {
      final newArticles = await ArticleSubmitApiService.getManuscriptArticles(
        page: nextPage,
        pageSize: _pageSize,
        category: category,
      );

      if (mounted) {
        setState(() {
          _articles.addAll(newArticles);
          _currentPage = nextPage;
          _hasMore = newArticles.length >= _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载更多失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteArticle(ManuscriptArticle article) async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('确认删除', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          '确定要删除文章"${article.title}"吗?',
          style: TextStyle(color: colors.textSecondary),
        ),
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
      await ArticleSubmitApiService.deleteArticle(article.aid);

      if (mounted) {
        setState(() {
          _articles.removeWhere((a) => a.aid == article.aid);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _editArticle(ManuscriptArticle article) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArticleUploadPage(aid: article.aid),
      ),
    );

    if (result == true) {
      _loadArticles(forceReload: true);
    }
  }

  void _onFilterChanged(ArticleFilter filter) {
    if (_currentFilter == filter) return;
    setState(() {
      _currentFilter = filter;
    });
    _loadArticles(forceReload: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文章管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ArticleUploadPage(),
                ),
              );
              if (result == true) {
                _loadArticles(); // 刷新列表
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final colors = context.colors;
    const filters = [
      (ArticleFilter.all, '全部'),
      (ArticleFilter.published, '已发布'),
      (ArticleFilter.pendingReview, '待审核'),
      (ArticleFilter.rejected, '不通过'),
    ];

    return Container(
      height: 44,
      color: colors.card,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final (filter, label) = filters[index];
          final isSelected = _currentFilter == filter;
          return Center(
            child: GestureDetector(
              onTap: () => _onFilterChanged(filter),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? colors.accentColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? Colors.white : colors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    // 显示错误信息
    if (_errorMessage != null && _articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadArticles,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 初始加载中
    if (_articles.isEmpty && _isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 空状态（无任何稿件）
    if (_articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 80, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Text(
              '还没有投稿文章',
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ArticleUploadPage(),
                  ),
                );
                if (result == true) {
                  _loadArticles();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('投稿文章'),
            ),
          ],
        ),
      );
    }

    // 筛选后无结果
    if (_articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_list_off, size: 64, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Text(
              '该分类下暂无文章',
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    // 文章列表
    return RefreshIndicator(
      onRefresh: _loadArticles,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _articles.length + (_hasMore || _isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _articles.length) {
            return const LoadingMoreIndicator();
          }

          final article = _articles[index];
          return _buildArticleItem(article);
        },
      ),
    );
  }

  Widget _buildArticleItem(ManuscriptArticle article) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => _editArticle(article),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面：统一用完整 URL + 全局缓存（同图只缓存一份）
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 120,
                  height: 68,
                  child: article.cover.isNotEmpty
                      ? CachedImage(
                          imageUrl: ImageUtils.getFullImageUrl(article.cover),
                          width: 120,
                          height: 68,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.article_outlined, color: Colors.grey),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      article.getStatusText(),
                      style: TextStyle(
                        fontSize: 13,
                        color: _getStatusColor(article.status),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.visibility, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${article.clicks}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            article.createdAt,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 操作按钮
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _editArticle(article);
                  } else if (value == 'delete') {
                    _deleteArticle(article);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 8),
                        Text('编辑'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('删除', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1: // 待审核
        return Colors.blue;
      case 2: // 审核不通过
        return Colors.red;
      case 3: // 已发布
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
