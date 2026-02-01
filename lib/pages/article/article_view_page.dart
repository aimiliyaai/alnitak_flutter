import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../../models/article_detail_model.dart';
import '../../models/video_detail.dart';
import '../../services/article_api_service.dart';
import '../../services/video_service.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/login_guard.dart';
import '../user/user_space_page.dart';
import 'widgets/article_action_buttons.dart';
import 'widgets/article_comment_preview_card.dart';

/// 专栏浏览页面
class ArticleViewPage extends StatefulWidget {
  final int aid;

  const ArticleViewPage({
    super.key,
    required this.aid,
  });

  @override
  State<ArticleViewPage> createState() => _ArticleViewPageState();
}

class _ArticleViewPageState extends State<ArticleViewPage> {
  ArticleDetail? _article;
  ArticleStat? _stat;
  bool _hasLiked = false;
  bool _hasCollected = false;
  bool _isLoading = true;
  String? _errorMessage;

  // 评论相关
  int _totalComments = 0;
  ArticleComment? _latestComment;

  // 关注状态：0=未关注，1=已关注，2=互相关注
  int _relationStatus = 0;
  bool _isFollowLoading = false;

  final VideoService _videoService = VideoService();

  @override
  void initState() {
    super.initState();
    _loadArticle();
  }

  Future<void> _loadArticle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 先加载文章详情
      final article = await ArticleApiService.getArticleById(widget.aid);

      // 并行加载统计信息、用户操作状态、关注状态和评论预览
      final results = await Future.wait([
        ArticleApiService.getArticleStat(widget.aid),
        ArticleApiService.hasLikedArticle(widget.aid),
        ArticleApiService.hasCollectedArticle(widget.aid),
        _videoService.getUserActionStatus(0, article.author.uid),
        ArticleApiService.getArticleComments(aid: widget.aid, page: 1, pageSize: 1),
      ]);

      if (mounted) {
        final commentResponse = results[4] as ArticleCommentResponse?;
        setState(() {
          _article = article;
          _stat = results[0] as ArticleStat?;
          _hasLiked = results[1] as bool;
          _hasCollected = results[2] as bool;
          final actionStatus = results[3] as UserActionStatus?;
          _relationStatus = actionStatus?.relationStatus ?? 0;
          // 评论预览数据
          _totalComments = commentResponse?.total ?? 0;
          _latestComment = commentResponse?.comments.isNotEmpty == true
              ? commentResponse!.comments.first
              : null;
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

  /// 处理关注操作
  Future<void> _handleFollow() async {
    if (_isFollowLoading || _article == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // 登录检测
    if (!await LoginGuard.check(context, actionName: '关注')) return;

    // 检查是否关注自己
    final currentUserId = await LoginGuard.getCurrentUserId();
    if (currentUserId != null && currentUserId == _article!.author.uid) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('不能关注自己'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() {
      _isFollowLoading = true;
    });

    try {
      bool success;
      final previousStatus = _relationStatus;

      if (_relationStatus == 0) {
        // 未关注 -> 关注
        success = await _videoService.followUser(_article!.author.uid);
      } else {
        // 已关注/互粉 -> 取消关注
        success = await _videoService.unfollowUser(_article!.author.uid);
      }

      if (success) {
        // 重新获取关系状态以更新按钮显示
        final response = await _videoService.getUserActionStatus(
          0,
          _article!.author.uid,
        );

        setState(() {
          _relationStatus = response?.relationStatus ?? (previousStatus == 0 ? 1 : 0);
        });

        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(previousStatus == 0 ? '关注成功' : '已取消关注'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('操作失败，请重试')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
        );
      }
    } finally {
      setState(() {
        _isFollowLoading = false;
      });
    }
  }

  /// 获取关注按钮文本
  String _getFollowButtonText() {
    switch (_relationStatus) {
      case 0:
        return '+ 关注';
      case 1:
        return '已关注';
      case 2:
        return '互相关注';
      default:
        return '+ 关注';
    }
  }

  /// 刷新评论预览（发表评论后调用）
  Future<void> _refreshCommentPreview() async {
    try {
      final commentResponse = await ArticleApiService.getArticleComments(
        aid: widget.aid,
        page: 1,
        pageSize: 1,
      );
      if (commentResponse != null && mounted) {
        setState(() {
          _totalComments = commentResponse.total;
          _latestComment = commentResponse.comments.isNotEmpty
              ? commentResponse.comments.first
              : null;
        });
      }
    } catch (e) {
      // 忽略刷新失败
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.iconPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '专栏',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadArticle,
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

    if (_article == null) {
      return Center(
        child: Text(
          '文章不存在',
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        // 文章内容区域（可滚动）
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面图
                if (_article!.cover.isNotEmpty)
                  CachedImage(
                    imageUrl: _article!.cover,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    cacheKey: 'article_cover_${_article!.aid}',
                  ),
                // 内容区域
                Container(
                  color: colors.surface,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        _article!.title,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 文章信息
                      Row(
                        children: [
                          Text(
                            _article!.formattedDate,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textTertiary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(
                            Icons.remove_red_eye_outlined,
                            size: 14,
                            color: colors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_article!.clicks}',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 作者卡片
                      _buildAuthorCard(),
                      const SizedBox(height: 16),
                      // 分割线
                      Divider(color: colors.divider, height: 1),
                      const SizedBox(height: 16),
                      // 标签
                      if (_article!.tagList.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _article!.tagList.map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.accentColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.accentColor,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // 文章内容（HTML渲染）
                      HtmlWidget(
                        _article!.content,
                        textStyle: TextStyle(
                          fontSize: 16,
                          color: colors.textPrimary,
                          height: 1.8,
                        ),
                        customStylesBuilder: (element) {
                          // 自定义样式
                          if (element.localName == 'img') {
                            return {
                              'max-width': '100%',
                              'height': 'auto',
                              'border-radius': '8px',
                              'margin': '8px 0',
                            };
                          }
                          if (element.localName == 'p') {
                            return {
                              'margin': '8px 0',
                            };
                          }
                          if (element.localName == 'h1' ||
                              element.localName == 'h2' ||
                              element.localName == 'h3') {
                            return {
                              'font-weight': 'bold',
                              'margin': '16px 0 8px',
                            };
                          }
                          if (element.localName == 'blockquote') {
                            return {
                              'border-left': '4px solid ${colors.accentColor.toHex()}',
                              'padding-left': '12px',
                              'margin': '12px 0',
                              'color': colors.textSecondary.toHex(),
                            };
                          }
                          if (element.localName == 'code') {
                            return {
                              'background-color': colors.inputBackground.toHex(),
                              'padding': '2px 6px',
                              'border-radius': '4px',
                              'font-family': 'monospace',
                            };
                          }
                          if (element.localName == 'pre') {
                            return {
                              'background-color': colors.inputBackground.toHex(),
                              'padding': '12px',
                              'border-radius': '8px',
                              'overflow': 'auto',
                            };
                          }
                          return null;
                        },
                        onTapUrl: (url) {
                          // 处理链接点击
                          return true;
                        },
                      ),
                    ],
                  ),
                ),
                // 版权信息
                Container(
                  color: colors.surface,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(
                        _article!.copyright ? Icons.copyright : Icons.share,
                        size: 16,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _article!.copyright ? '原创文章，转载请注明出处' : '转载文章',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 评论预览卡片（参考视频播放页）
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ArticleCommentPreviewCard(
                    aid: widget.aid,
                    totalComments: _totalComments,
                    latestComment: _latestComment,
                    onCommentPosted: _refreshCommentPreview,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),

        // 底部操作栏（点赞、收藏、分享）
        Container(
          color: colors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SafeArea(
            top: false,
            child: ArticleActionButtons(
              aid: widget.aid,
              initialStat: _stat ?? ArticleStat(like: 0, collect: 0, share: 0),
              initialHasLiked: _hasLiked,
              initialHasCollected: _hasCollected,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建作者卡片
  Widget _buildAuthorCard() {
    final colors = context.colors;
    final author = _article!.author;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.inputBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 头像（可点击跳转到UP主页面）
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserSpacePage(userId: author.uid),
                ),
              );
            },
            child: ClipOval(
              child: CachedImage(
                imageUrl: author.avatar,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                cacheKey: 'user_avatar_${author.uid}',
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 作者信息（可点击跳转到UP主页面）
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserSpacePage(userId: author.uid),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    author.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (author.sign.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      author.sign,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 关注按钮
          ElevatedButton(
            onPressed: _isFollowLoading ? null : _handleFollow,
            style: ElevatedButton.styleFrom(
              backgroundColor: _relationStatus == 0
                  ? colors.accentColor
                  : colors.surfaceVariant,
              foregroundColor: _relationStatus == 0
                  ? Colors.white
                  : colors.textPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              minimumSize: const Size(0, 32),
            ),
            child: _isFollowLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _getFollowButtonText(),
                    style: const TextStyle(fontSize: 13),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Color 扩展：转换为 CSS hex 格式
extension ColorToHex on Color {
  String toHex() {
    return '#${r.toInt().toRadixString(16).padLeft(2, '0')}'
        '${g.toInt().toRadixString(16).padLeft(2, '0')}'
        '${b.toInt().toRadixString(16).padLeft(2, '0')}';
  }
}
