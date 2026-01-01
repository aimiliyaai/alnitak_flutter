import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../models/video_detail.dart';
import '../../../models/collection.dart';
import '../../../services/video_service.dart';
import '../../../services/collection_service.dart';
import '../../../utils/login_guard.dart';
import '../../../utils/http_client.dart';
import '../../../theme/theme_extensions.dart';

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
  DateTime? _lastErrorTime; // 上次显示错误提示的时间

  // 【新增】用于防止并发点击的操作ID
  int _likeOperationId = 0;

  final VideoService _videoService = VideoService();
  final CollectionService _collectionService = CollectionService();
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
  void didUpdateWidget(covariant VideoActionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 【关键修复】当父组件传入新的状态时，更新本地状态
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
  /// 【修复】使用操作ID防止并发点击导致的状态混乱
  Future<void> _handleLike() async {
    if (_isLiking) return;

    // 登录检测
    if (!await LoginGuard.check(context, actionName: '点赞')) return;

    // 【修复】递增操作ID，用于识别当前操作
    final currentOperationId = ++_likeOperationId;

    setState(() {
      _isLiking = true;
    });

    final previousLikeState = _hasLiked;
    final previousCount = _stat.like;

    print('👍 点赞操作 #$currentOperationId: ${_hasLiked ? "取消点赞" : "点赞"} (当前状态: $previousLikeState)');

    // 【修复】立即更新UI（乐观更新），提升用户体验
    setState(() {
      _hasLiked = !previousLikeState;
      _stat = _stat.copyWith(like: !previousLikeState ? previousCount + 1 : previousCount - 1);
    });

    // 如果是点赞，立即播放动画
    if (!previousLikeState) {
      _likeAnimationController.forward().then((_) {
        _likeAnimationController.reverse();
      });
    }

    // 根据操作前的状态调用API
    bool success;
    if (previousLikeState) {
      // 之前是已点赞状态，调用取消点赞API
      success = await _videoService.unlikeVideo(widget.vid);
    } else {
      // 之前是未点赞状态，调用点赞API
      success = await _videoService.likeVideo(widget.vid);
    }

    // 【修复】检查操作ID是否仍然是最新的
    if (currentOperationId != _likeOperationId) {
      print('👍 操作 #$currentOperationId 已被新操作覆盖，忽略结果');
      return;
    }

    if (!success) {
      // API调用失败，回滚状态
      print('👍 API调用失败，回滚状态');
      setState(() {
        _hasLiked = previousLikeState;
        _stat = _stat.copyWith(like: previousCount);
      });

      // 防抖：只有距离上次错误提示超过2秒才显示新的错误提示
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
    } else {
      print('👍 操作 #$currentOperationId 成功');
    }

    setState(() {
      _isLiking = false;
    });
  }

  /// 显示收藏对话框（参考PC端实现）
  Future<void> _showCollectDialog() async {
    if (_isCollecting) return;

    // 登录检测
    if (!await LoginGuard.check(context, actionName: '收藏')) return;

    setState(() {
      _isCollecting = true;
    });

    try {
      // 并发获取收藏夹列表和当前视频的收藏信息
      final results = await Future.wait([
        _collectionService.getCollectionList(),
        _videoService.getCollectInfo(widget.vid),
      ]);

      final collectionList = results[0] as List<Collection>? ?? [];
      final currentCollectionIds = results[1] as List<int>;

      // 标记已收藏的收藏夹
      for (var collection in collectionList) {
        if (currentCollectionIds.contains(collection.id)) {
          collection.checked = true;
        }
      }

      if (!mounted) return;

      // 显示收藏对话框（参考PC端：即使列表为空也显示，让用户创建收藏夹）
      final result = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => _CollectionListDialog(
          vid: widget.vid,
          collectionList: collectionList,
          defaultCheckedIds: currentCollectionIds,
        ),
      );

      // 根据返回值更新UI
      if (result != null) {
        setState(() {
          if (result == 1) {
            // 新增收藏
            _hasCollected = true;
            _stat = _stat.copyWith(collect: _stat.collect + 1);
          } else if (result == -1) {
            // 取消收藏
            _hasCollected = false;
            _stat = _stat.copyWith(collect: _stat.collect - 1);
          }
          // result == 0 表示只是切换收藏夹，不改变总收藏状态
        });
      }
    } catch (e) {
      print('显示收藏对话框失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
        );
      }
    } finally {
      setState(() {
        _isCollecting = false;
      });
    }
  }

  /// 获取分享URL
  String _getShareUrl() {
    // 使用实际的API域名构建分享链接
    final baseUrl = HttpClient().dio.options.baseUrl;
    // 将 API baseUrl (http://anime.ayypd.cn:3000) 转换为 Web 链接
    // 移除 /api 路径部分，直接使用视频路径
    final domain = baseUrl.replaceAll('/api', '').replaceAll(RegExp(r'/$'), '');
    return '$domain/video/${widget.vid}';
  }

 /// 显示二维码对话框
  void _showQrCodeDialog(String shareUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫码分享'),
        // 【修改点】套一个 SizedBox 并给 maxFinite 宽度
        // 这告诉 AlertDialog："不要去算子组件要多宽了，直接给我撑满允许的最大宽度"
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
                '扫描二维码观看视频',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              // SelectableText 有时也需要明确的宽度约束
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
  /// 显示分享选项
  Future<void> _showShareOptions() async {
    // 生成分享链接
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

/// 收藏对话框组件（参考PC端实现）
class _CollectionListDialog extends StatefulWidget {
  final int vid;
  final List<Collection> collectionList;
  final List<int> defaultCheckedIds;

  const _CollectionListDialog({
    required this.vid,
    required this.collectionList,
    required this.defaultCheckedIds,
  });

  @override
  State<_CollectionListDialog> createState() => _CollectionListDialogState();
}

class _CollectionListDialogState extends State<_CollectionListDialog> {
  final VideoService _videoService = VideoService();
  final CollectionService _collectionService = CollectionService();
  final TextEditingController _nameController = TextEditingController();

  late List<Collection> _collections;
  late List<int> _defaultCheckedIds;
  bool _isSubmitting = false;
  bool _showCreateInput = false;

  @override
  void initState() {
    super.initState();
    _collections = List.from(widget.collectionList);
    _defaultCheckedIds = List.from(widget.defaultCheckedIds);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 创建收藏夹
  Future<void> _createCollection() async {
    print('📁 开始创建收藏夹');
    final name = _nameController.text.trim();
    print('📁 输入的收藏夹名称: "$name"');

    if (name.isEmpty) {
      print('📁 收藏夹名称为空');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入收藏夹名称')),
        );
      }
      return;
    }

    if (name.length > 20) {
      print('📁 收藏夹名称过长: ${name.length}字');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('收藏夹名称不能超过20个字符')),
        );
      }
      return;
    }

    print('📁 调用API创建收藏夹: $name');
    final success = await _collectionService.addCollection(name);
    print('📁 API返回结果: ${success != null ? "成功(ID=$success)" : "失败"}');

    // 如果API返回成功（无论是否有ID），都重新获取收藏夹列表
    if (success != null) {
      print('📁 创建成功，重新获取收藏夹列表');
      final updatedList = await _collectionService.getCollectionList();
      if (updatedList != null) {
        setState(() {
          _collections = updatedList;
          // 保持之前选中的收藏夹状态
          for (var collection in _collections) {
            if (_defaultCheckedIds.contains(collection.id)) {
              collection.checked = true;
            }
          }
          _nameController.clear();
          _showCreateInput = false;
        });
        print('📁 收藏夹列表已更新，共${_collections.length}个');
      } else {
        // 如果重新获取失败，使用返回的ID手动添加
        setState(() {
          _collections.add(Collection(
            id: success,
            name: name,
            checked: false,
          ));
          _nameController.clear();
          _showCreateInput = false;
        });
        print('📁 使用返回的ID添加到列表');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('创建成功'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else {
      print('📁 创建失败');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败，请重试')),
        );
      }
    }
  }

  /// 提交收藏（参考PC端逻辑）
  Future<void> _submitCollect() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    // 获取用户最终选中的收藏夹ID
    final checkedIds = _collections.where((c) => c.checked).map((c) => c.id).toList();

    // 计算差异：addList = 新增的，cancelList = 移除的
    final addList = checkedIds.where((id) => !_defaultCheckedIds.contains(id)).toList();
    final cancelList = _defaultCheckedIds.where((id) => !checkedIds.contains(id)).toList();

    print('📋 收藏操作: 添加到$addList，从$cancelList移除');

    final success = await _videoService.collectVideo(widget.vid, addList, cancelList);

    if (success) {
      // 计算收藏数变化（参考PC端逻辑）
      int countChange = 0;
      if (_defaultCheckedIds.isEmpty && checkedIds.isNotEmpty) {
        countChange = 1; // 从未收藏变为收藏
      } else if (_defaultCheckedIds.isNotEmpty && checkedIds.isEmpty) {
        countChange = -1; // 从收藏变为未收藏
      }
      // 否则 countChange = 0，只是切换收藏夹

      if (mounted) {
        Navigator.pop(context, countChange);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
        );
      }
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '收藏到',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      setState(() {
                        _showCreateInput = !_showCreateInput;
                      });
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // 创建收藏夹输入框
            if (_showCreateInput)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: '输入收藏夹名称（最多20字）',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          counterText: '', // 隐藏字符计数器
                        ),
                        maxLength: 20,
                        onSubmitted: (_) => _createCollection(), // 支持回车提交
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _createCollection,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: const Text('创建'),
                    ),
                  ],
                ),
              ),

            // 收藏夹列表（参考PC端：只有在列表不为空时才显示）
            if (_collections.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _collections.length,
                  itemBuilder: (context, index) {
                    final collection = _collections[index];
                    return CheckboxListTile(
                      title: Text(collection.name),
                      subtitle: collection.desc != null ? Text(collection.desc!) : null,
                      value: collection.checked,
                      onChanged: (value) {
                        setState(() {
                          collection.checked = value ?? false;
                        });
                      },
                    );
                  },
                ),
              ),

            // 空状态提示（PC端不显示列表时的占位）
            if (_collections.isEmpty && !_showCreateInput)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    '点击上方 + 按钮创建收藏夹',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitCollect,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('确定'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
