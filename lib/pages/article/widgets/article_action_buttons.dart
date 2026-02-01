import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../models/article_detail_model.dart';
import '../../../services/article_api_service.dart';
import '../../../utils/login_guard.dart';
import '../../../utils/http_client.dart';
import '../../../theme/theme_extensions.dart';

/// 文章操作按钮（点赞、收藏、分享）
class ArticleActionButtons extends StatefulWidget {
  final int aid;
  final ArticleStat initialStat;
  final bool initialHasLiked;
  final bool initialHasCollected;

  const ArticleActionButtons({
    super.key,
    required this.aid,
    required this.initialStat,
    required this.initialHasLiked,
    required this.initialHasCollected,
  });

  @override
  State<ArticleActionButtons> createState() => _ArticleActionButtonsState();
}

class _ArticleActionButtonsState extends State<ArticleActionButtons>
    with SingleTickerProviderStateMixin {
  late ArticleStat _stat;
  late bool _hasLiked;
  late bool _hasCollected;
  bool _isLiking = false;
  bool _isCollecting = false;
  DateTime? _lastErrorTime;

  int _likeOperationId = 0;
  int _collectOperationId = 0;

  late AnimationController _likeAnimationController;

  @override
  void initState() {
    super.initState();
    _stat = widget.initialStat;
    _hasLiked = widget.initialHasLiked;
    _hasCollected = widget.initialHasCollected;

    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant ArticleActionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStat != widget.initialStat) {
      setState(() {
        _stat = widget.initialStat;
      });
    }
    if (oldWidget.initialHasLiked != widget.initialHasLiked) {
      setState(() {
        _hasLiked = widget.initialHasLiked;
      });
    }
    if (oldWidget.initialHasCollected != widget.initialHasCollected) {
      setState(() {
        _hasCollected = widget.initialHasCollected;
      });
    }
  }

  @override
  void dispose() {
    _likeAnimationController.dispose();
    super.dispose();
  }

  /// 格式化数字
  String _formatNumber(int number) {
    if (number >= 100000000) {
      return '${(number / 100000000).toStringAsFixed(1)}亿';
    } else if (number >= 10000) {
      return '${(number / 10000).toStringAsFixed(1)}万';
    }
    return number.toString();
  }

  /// 处理点赞
  Future<void> _handleLike() async {
    if (_isLiking) return;

    // 登录检测
    if (!await LoginGuard.check(context, actionName: '点赞')) return;

    final currentOperationId = ++_likeOperationId;

    setState(() {
      _isLiking = true;
    });

    final previousLikeState = _hasLiked;
    final previousCount = _stat.like;

    // 乐观更新
    setState(() {
      _hasLiked = !previousLikeState;
      _stat = _stat.copyWith(like: !previousLikeState ? previousCount + 1 : previousCount - 1);
    });

    // 点赞动画
    if (!previousLikeState) {
      _likeAnimationController.forward().then((_) {
        _likeAnimationController.reverse();
      });
    }

    // 调用API
    bool success;
    if (previousLikeState) {
      success = await ArticleApiService.cancelLikeArticle(widget.aid);
    } else {
      success = await ArticleApiService.likeArticle(widget.aid);
    }

    if (currentOperationId != _likeOperationId) {
      return;
    }

    if (!success) {
      // 回滚状态
      setState(() {
        _hasLiked = previousLikeState;
        _stat = _stat.copyWith(like: previousCount);
      });

      final now = DateTime.now();
      if (mounted && (_lastErrorTime == null || now.difference(_lastErrorTime!).inSeconds >= 2)) {
        _lastErrorTime = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('操作失败，请重试'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    setState(() {
      _isLiking = false;
    });
  }

  /// 处理收藏
  Future<void> _handleCollect() async {
    if (_isCollecting) return;

    // 登录检测
    if (!await LoginGuard.check(context, actionName: '收藏')) return;

    final currentOperationId = ++_collectOperationId;

    setState(() {
      _isCollecting = true;
    });

    final previousCollectState = _hasCollected;
    final previousCount = _stat.collect;

    // 乐观更新
    setState(() {
      _hasCollected = !previousCollectState;
      _stat = _stat.copyWith(collect: !previousCollectState ? previousCount + 1 : previousCount - 1);
    });

    // 调用API
    bool success;
    if (previousCollectState) {
      success = await ArticleApiService.cancelCollectArticle(widget.aid);
    } else {
      success = await ArticleApiService.collectArticle(widget.aid);
    }

    if (currentOperationId != _collectOperationId) {
      return;
    }

    if (!success) {
      // 回滚状态
      setState(() {
        _hasCollected = previousCollectState;
        _stat = _stat.copyWith(collect: previousCount);
      });

      final now = DateTime.now();
      if (mounted && (_lastErrorTime == null || now.difference(_lastErrorTime!).inSeconds >= 2)) {
        _lastErrorTime = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('操作失败，请重试'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    setState(() {
      _isCollecting = false;
    });
  }

  /// 获取分享URL
  String _getShareUrl() {
    final baseUrl = HttpClient().dio.options.baseUrl;
    final domain = baseUrl.replaceAll('/api', '').replaceAll(RegExp(r'/$'), '');
    return '$domain/article/${widget.aid}';
  }

  /// 显示二维码对话框
  void _showQrCodeDialog(String shareUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫码分享'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: shareUrl,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '扫描二维码查看文章',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                shareUrl,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: shareUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('链接已复制到剪贴板')),
              );
            },
            child: const Text('复制链接'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 记录分享计数
  void _recordShare() {
    ArticleApiService.shareArticle(widget.aid);
    setState(() {
      _stat = _stat.copyWith(share: _stat.share + 1);
    });
  }

  /// 显示分享选项
  Future<void> _showShareOptions() async {
    final shareUrl = _getShareUrl();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '分享文章',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制链接'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: shareUrl));
                Navigator.pop(context);
                _recordShare();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('链接已复制到剪贴板')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('分享到其他应用'),
              onTap: () {
                Navigator.pop(context);
                _recordShare();
                Share.share(
                  shareUrl,
                  subject: '分享一篇好文章',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('生成二维码'),
              onTap: () {
                Navigator.pop(context);
                _recordShare();
                _showQrCodeDialog(shareUrl);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String count,
    required VoidCallback onTap,
    required bool isActive,
    Color? activeColor,
  }) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? (activeColor ?? Theme.of(context).primaryColor).withValues(alpha: 0.1)
              : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isActive
                  ? (activeColor ?? Theme.of(context).primaryColor)
                  : colors.iconPrimary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive
                    ? (activeColor ?? Theme.of(context).primaryColor)
                    : colors.textPrimary,
              ),
            ),
            if (count.isNotEmpty)
              Text(
                count,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.transparent,
      child: Row(
        children: [
          // 点赞按钮
          Expanded(
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.2).animate(
                CurvedAnimation(
                  parent: _likeAnimationController,
                  curve: Curves.easeInOut,
                ),
              ),
              child: _buildActionButton(
                icon: _hasLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                label: '点赞',
                count: _formatNumber(_stat.like),
                onTap: _handleLike,
                isActive: _hasLiked,
                activeColor: Colors.pink,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 收藏按钮
          Expanded(
            child: _buildActionButton(
              icon: _hasCollected ? Icons.star : Icons.star_border,
              label: '收藏',
              count: _formatNumber(_stat.collect),
              onTap: _handleCollect,
              isActive: _hasCollected,
              activeColor: Colors.orange,
            ),
          ),
          const SizedBox(width: 12),

          // 分享按钮
          Expanded(
            child: _buildActionButton(
              icon: Icons.share,
              label: '分享',
              count: _formatNumber(_stat.share),
              onTap: _showShareOptions,
              isActive: false,
            ),
          ),
        ],
      ),
    );
  }
}
