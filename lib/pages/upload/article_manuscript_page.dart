import 'package:flutter/material.dart';
import '../../models/upload_article.dart';
import '../../services/article_submit_api_service.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';
import 'article_upload_page.dart';

class ArticleManuscriptPage extends StatefulWidget {
  const ArticleManuscriptPage({super.key});

  @override
  State<ArticleManuscriptPage> createState() => _ArticleManuscriptPageState();
}

class _ArticleManuscriptPageState extends State<ArticleManuscriptPage> {
  final ScrollController _scrollController = ScrollController();

  List<ManuscriptArticle> _articles = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _errorMessage;
  static const int _pageSize = 20;

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

  Future<void> _loadArticles() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentPage = 1;
    });

    try {
      final articles = await ArticleSubmitApiService.getManuscriptArticles(
        page: 1,
        pageSize: _pageSize,
      );

      setState(() {
        _articles = articles;
        _hasMore = articles.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreArticles() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    final nextPage = _currentPage + 1;

    try {
      final newArticles = await ArticleSubmitApiService.getManuscriptArticles(
        page: nextPage,
        pageSize: _pageSize,
      );

      setState(() {
        _articles.addAll(newArticles);
        _currentPage = nextPage;
        _hasMore = newArticles.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载更多失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteArticle(ManuscriptArticle article) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除文章"${article.title}"吗?'),
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

      setState(() {
        _articles.removeWhere((a) => a.aid == article.aid);
      });

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
      _loadArticles(); // 刷新列表
    }
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
      body: _buildBody(),
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

    // 空状态
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

    // 文章列表
    return RefreshIndicator(
      onRefresh: _loadArticles,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _articles.length + (_hasMore || _isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _articles.length) {
            // 加载更多指示器
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
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
              // 封面
              CachedImage(
                imageUrl: article.cover,
                width: 120,
                height: 68,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(4),
                cacheKey: 'article_cover_${article.aid}', // 使用文章ID作为缓存key
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
