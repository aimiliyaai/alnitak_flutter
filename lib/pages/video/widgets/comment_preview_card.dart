import 'package:flutter/material.dart';
import '../../../models/comment.dart';
import '../../../widgets/cached_image_widget.dart';
import '../../../utils/timestamp_parser.dart';
import '../../../utils/image_utils.dart';
import '../../../theme/theme_extensions.dart';
import 'comment_list.dart';

/// 评论预览卡片 - 参考 YouTube 设计
/// 显示最新一条评论预览和总评论数，点击可展开完整评论区
class CommentPreviewCard extends StatelessWidget {
  final int totalComments;
  final Comment? latestComment; // 最新评论
  final int vid; // 视频ID，用于打开评论面板时传递
  final void Function(int seconds)? onSeek; // 点击时间戳跳转回调
  final VoidCallback? onCommentPosted; // 评论发送成功后的回调

  const CommentPreviewCard({
    super.key,
    required this.totalComments,
    this.latestComment,
    required this.vid,
    this.onSeek,
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
                        // 评论内容（最多显示2行，支持时间戳点击）
                        RichText(
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            children: TimestampParser.buildTextSpans(
                              text: latestComment!.content,
                              defaultStyle: TextStyle(
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                              timestampStyle: TextStyle(
                                fontSize: 13,
                                color: colors.accentColor,
                                fontWeight: FontWeight.w500,
                              ),
                              onTimestampTap: onSeek,
                            ),
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
      builder: (context) => CommentPanel(
        totalComments: totalComments,
        latestComment: latestComment,
        vid: vid,
        onSeek: onSeek,
        onCommentPosted: onCommentPosted,
      ),
    );
  }
}

/// 评论面板 - 底部弹出的完整评论区
class CommentPanel extends StatefulWidget {
  final int totalComments;
  final Comment? latestComment;
  final int vid;
  final void Function(int seconds)? onSeek; // 点击时间戳跳转回调
  final VoidCallback? onCommentPosted; // 评论发送成功后的回调

  const CommentPanel({
    super.key,
    required this.totalComments,
    this.latestComment,
    required this.vid,
    this.onSeek,
    this.onCommentPosted,
  });

  @override
  State<CommentPanel> createState() => _CommentPanelState();
}

class _CommentPanelState extends State<CommentPanel> {
  late int _currentTotalComments;

  @override
  void initState() {
    super.initState();
    _currentTotalComments = widget.totalComments;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // 计算面板高度，确保不挡住播放器
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final playerHeight = screenWidth * 9 / 16; // 播放器高度（16:9）
    final availableHeight = screenHeight - playerHeight; // 可用高度

    // 计算初始大小和最大大小（基于可用高度）
    final initialSize = (availableHeight * 0.7) / screenHeight; // 初始占用屏幕的70%
    final minSize = (availableHeight * 0.4) / screenHeight; // 最小40%
    final maxSize = (availableHeight * 0.95) / screenHeight; // 最大95%，但不超过播放器下方

    return DraggableScrollableSheet(
      initialChildSize: initialSize.clamp(0.4, 0.85),
      minChildSize: minSize.clamp(0.3, 0.6),
      maxChildSize: maxSize.clamp(0.5, 0.9),
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
                child: CommentListContent(
                  vid: widget.vid,
                  scrollController: scrollController,
                  onSeek: (seconds) {
                    // 先关闭评论面板，再触发 seek
                    Navigator.pop(context);
                    widget.onSeek?.call(seconds);
                  },
                  onCommentPosted: widget.onCommentPosted,
                  onTotalCommentsChanged: (count) {
                    if (mounted && count != _currentTotalComments) {
                      setState(() {
                        _currentTotalComments = count;
                      });
                    }
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
