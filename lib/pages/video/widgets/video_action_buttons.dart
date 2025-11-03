import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../models/video_detail.dart';
import '../../../services/video_service.dart';

/// 视频操作按钮（点赞、收藏、分享）
class VideoActionButtons extends StatefulWidget {
  final int vid;
  final VideoStat initialStat;
  final bool initialHasLiked;
  final bool initialHasCollected;

  const VideoActionButtons({
    super.key,
    required this.vid,
    required this.initialStat,
    required this.initialHasLiked,
    required this.initialHasCollected,
  });

  @override
  State<VideoActionButtons> createState() => _VideoActionButtonsState();
}

class _VideoActionButtonsState extends State<VideoActionButtons>
    with SingleTickerProviderStateMixin {
  late VideoStat _stat;
  late bool _hasLiked;
  late bool _hasCollected;
  bool _isLiking = false;
  bool _isCollecting = false;

  final VideoService _videoService = VideoService();
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

    setState(() {
      _isLiking = true;
    });

    // 乐观更新 UI
    final previousLikeState = _hasLiked;
    final previousCount = _stat.like;

    setState(() {
      _hasLiked = !_hasLiked;
      _stat = _stat.copyWith(like: _hasLiked ? _stat.like + 1 : _stat.like - 1);
    });

    if (_hasLiked) {
      _likeAnimationController.forward().then((_) {
        _likeAnimationController.reverse();
      });
    }

    // 调用 API
    bool success;
    if (_hasLiked) {
      success = await _videoService.likeVideo(widget.vid);
    } else {
      success = await _videoService.unlikeVideo(widget.vid);
    }

    if (!success) {
      // 回滚
      setState(() {
        _hasLiked = previousLikeState;
        _stat = _stat.copyWith(like: previousCount);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
        );
      }
    }

    setState(() {
      _isLiking = false;
    });
  }

  /// 显示收藏对话框
  Future<void> _showCollectDialog() async {
    if (_isCollecting) return;

    // TODO: 实现收藏夹选择对话框
    // 这里简化为直接切换收藏状态
    setState(() {
      _isCollecting = true;
    });

    final previousCollectState = _hasCollected;
    final previousCount = _stat.collect;

    setState(() {
      _hasCollected = !_hasCollected;
      _stat = _stat.copyWith(collect: _hasCollected ? _stat.collect + 1 : _stat.collect - 1);
    });

    // 调用 API（简化版）
    bool success = await _videoService.collectVideo(
      widget.vid,
      _hasCollected ? [1] : [], // 添加到默认收藏夹
      _hasCollected ? [] : [1], // 从默认收藏夹移除
    );

    if (!success) {
      // 回滚
      setState(() {
        _hasCollected = previousCollectState;
        _stat = _stat.copyWith(collect: previousCount);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_hasCollected ? '收藏成功' : '已取消收藏')),
        );
      }
    }

    setState(() {
      _isCollecting = false;
    });
  }

  /// 显示分享选项
  Future<void> _showShareOptions() async {
    // 生成分享链接（这里需要根据实际的 URL scheme）
    final shareUrl = 'https://your-domain.com/video/${widget.vid}';

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
                '分享视频',
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
                Share.share(
                  shareUrl,
                  subject: '分享一个有趣的视频',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('生成二维码'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 实现二维码生成
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('二维码功能开发中')),
                );
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? (activeColor ?? Theme.of(context).primaryColor).withOpacity(0.1)
              : Colors.grey[100],
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
                  : Colors.grey[700],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive
                    ? (activeColor ?? Theme.of(context).primaryColor)
                    : Colors.grey[700],
              ),
            ),
            if (count.isNotEmpty)
              Text(
                count,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
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
              onTap: _showCollectDialog,
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
