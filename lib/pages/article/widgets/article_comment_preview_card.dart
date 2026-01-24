import 'package:flutter/material.dart';
import '../../../models/article_detail_model.dart';
import '../../../widgets/cached_image_widget.dart';
import '../../../utils/image_utils.dart';
import '../../../theme/theme_extensions.dart';
import 'article_comment_list.dart';

/// 文章评论预览卡片 - 参考视频播放页的 CommentPreviewCard 设计
/// 显示最新一条评论预览和总评论数，点击可展开完整评论区
class ArticleCommentPreviewCard extends StatelessWidget {
  final int totalComments;
  final ArticleComment? latestComment; // 最新评论
  final int aid; // 文章ID，用于打开评论面板时传递
  final VoidCallback? onCommentPosted; // 评论发送成功后的回调

  const ArticleCommentPreviewCard({
    super.key,
    required this.totalComments,
    this.latestComment,
    required this.aid,
    this.onCommentPosted,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: () => _showCommentPanel(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 评论数标题
            Row(
              children: [
                Text(
                  '评论 $totalComments',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: colors.iconSecondary,
                ),
              ],
            ),
            // 最新评论预览
            if (latestComment != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 评论者头像
                  latestComment!.avatar.isNotEmpty
                      ? CachedCircleAvatar(
                          imageUrl: ImageUtils.getFullImageUrl(latestComment!.avatar),
                          radius: 20,
                        )
                      : CircleAvatar(
                          radius: 20,
                          backgroundColor: colors.surfaceVariant,
                          child: Icon(Icons.person, size: 20, color: colors.iconSecondary),
                        ),
                  const SizedBox(width: 12),
                  // 评论内容
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 用户名
                        Text(
                          latestComment!.username,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 评论内容（最多显示2行）
                        Text(
                          latestComment!.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              // 没有评论时的占位
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.comment_outlined,
                    size: 20,
                    color: colors.iconSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '暂无评论，来抢个沙发吧',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCommentPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ArticleCommentPanel(
        totalComments: totalComments,
        latestComment: latestComment,
        aid: aid,
        onCommentPosted: onCommentPosted,
      ),
    );
  }
}

/// 评论面板 - 底部弹出的完整评论区
class ArticleCommentPanel extends StatefulWidget {
  final int totalComments;
  final ArticleComment? latestComment;
  final int aid;
  final VoidCallback? onCommentPosted; // 评论发送成功后的回调

  const ArticleCommentPanel({
    super.key,
    required this.totalComments,
    this.latestComment,
    required this.aid,
    this.onCommentPosted,
  });

  @override
  State<ArticleCommentPanel> createState() => _ArticleCommentPanelState();
}

class _ArticleCommentPanelState extends State<ArticleCommentPanel> {
  late int _currentTotalComments;

  @override
  void initState() {
    super.initState();
    _currentTotalComments = widget.totalComments;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Column(
            children: [
              // 顶部拖拽指示条、评论数标题和关闭按钮
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    // 拖拽指示条
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 评论数标题
                    Text(
                      '评论 $_currentTotalComments',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    // 关闭按钮
                    IconButton(
                      icon: Icon(Icons.close, color: colors.iconPrimary),
                      onPressed: () => Navigator.pop(context),
                      iconSize: 24,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.divider),
              // 评论列表内容（包含头部和输入框）
              Expanded(
                child: ArticleCommentList(
                  aid: widget.aid,
                  scrollController: scrollController,
                  onTotalCommentsChanged: (count) {
                    if (mounted && count != _currentTotalComments) {
                      setState(() {
                        _currentTotalComments = count;
                      });
                    }
                    // 通知父组件刷新
                    widget.onCommentPosted?.call();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
