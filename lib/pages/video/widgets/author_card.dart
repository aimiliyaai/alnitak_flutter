import 'package:flutter/material.dart';
import '../../../models/video_detail.dart';
import '../../../services/video_service.dart';

/// 作者信息卡片
class AuthorCard extends StatefulWidget {
  final UserInfo author;
  final int initialRelationStatus;
  final VoidCallback? onAvatarTap;

  const AuthorCard({
    super.key,
    required this.author,
    this.initialRelationStatus = 0,
    this.onAvatarTap,
  });

  @override
  State<AuthorCard> createState() => _AuthorCardState();
}

class _AuthorCardState extends State<AuthorCard> {
  late int _relationStatus;
  bool _isLoading = false;
  final VideoService _videoService = VideoService();

  @override
  void initState() {
    super.initState();
    _relationStatus = widget.initialRelationStatus;
  }

  /// 格式化粉丝数
  String _formatFansCount(int fans) {
    if (fans >= 10000) {
      return '${(fans / 10000).toStringAsFixed(1)}万';
    }
    return fans.toString();
  }

  /// 处理关注操作
  Future<void> _handleFollow() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    bool success;
    if (_relationStatus == 0) {
      // 未关注 -> 关注
      success = await _videoService.followUser(widget.author.uid);
      if (success) {
        setState(() {
          _relationStatus = 1;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('关注成功')),
          );
        }
      }
    } else {
      // 已关注/互粉 -> 取消关注
      success = await _videoService.unfollowUser(widget.author.uid);
      if (success) {
        setState(() {
          _relationStatus = 0;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已取消关注')),
          );
        }
      }
    }

    setState(() {
      _isLoading = false;
    });

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败，请重试')),
      );
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

  /// 获取关注按钮样式
  ButtonStyle _getFollowButtonStyle() {
    if (_relationStatus == 0) {
      // 未关注：主题色
      return ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
    } else {
      // 已关注/互粉：灰色
      return ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[200],
        foregroundColor: Colors.grey[700],
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头像
            GestureDetector(
              onTap: widget.onAvatarTap,
              child: CircleAvatar(
                radius: 28,
                backgroundImage: widget.author.avatar.isNotEmpty
                    ? NetworkImage(widget.author.avatar)
                    : null,
                child: widget.author.avatar.isEmpty
                    ? const Icon(Icons.person, size: 32)
                    : null,
              ),
            ),
            const SizedBox(width: 12),

            // 用户信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 用户名
                  Text(
                    widget.author.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // 粉丝数
                  Text(
                    '${_formatFansCount(widget.author.fans)} 粉丝',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),

                  // 签名
                  if (widget.author.sign.isNotEmpty)
                    Text(
                      widget.author.sign,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // 关注按钮
            ElevatedButton(
              onPressed: _isLoading ? null : _handleFollow,
              style: _getFollowButtonStyle(),
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_getFollowButtonText()),
            ),
          ],
        ),
      ),
    );
  }
}
