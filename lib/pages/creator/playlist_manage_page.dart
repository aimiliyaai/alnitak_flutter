import 'package:flutter/material.dart';
import '../../services/playlist_api_service.dart';
import '../../utils/image_utils.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';
import 'playlist_edit_page.dart';
import 'playlist_video_page.dart';

/// 合集管理页面
class PlaylistManagePage extends StatefulWidget {
  const PlaylistManagePage({super.key});

  @override
  State<PlaylistManagePage> createState() => _PlaylistManagePageState();
}

class _PlaylistManagePageState extends State<PlaylistManagePage> {
  final PlaylistApiService _api = PlaylistApiService();
  List<Map<String, dynamic>> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _isLoading = true);
    final list = await _api.getMyPlaylists();
    if (mounted) {
      setState(() {
        _playlists = list;
        _isLoading = false;
      });
    }
  }

  /// 删除合集
  Future<void> _deletePlaylist(Map<String, dynamic> playlist, int index) async {
    final title = playlist['title'] ?? '';
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final colors = ctx.colors;
            return AlertDialog(
              backgroundColor: colors.card,
              title: Text('删除合集', style: TextStyle(color: colors.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 14, color: colors.textPrimary),
                      children: [
                        const TextSpan(text: '请输入 '),
                        TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const TextSpan(text: ' 删除此合集'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('合集删除后将无法恢复，请谨慎操作',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: '请输入合集标题',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                    onChanged: (_) {
                      if (errorText != null) setDialogState(() => errorText = null);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    if (controller.text.trim() == title) {
                      Navigator.pop(ctx, true);
                    } else {
                      setDialogState(() => errorText = '输入标题与原标题不一致');
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('确认删除'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      final success = await _api.deletePlaylist(playlist['id']);
      if (success && mounted) {
        setState(() => _playlists.removeAt(index));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除成功')));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败')));
      }
    }
  }

  /// 查看审核不通过原因
  Future<void> _showReviewReason(int id) async {
    final remark = await _api.getPlaylistReviewRecord(id);
    if (mounted) {
      final colors = context.colors;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: colors.card,
          title: Text('审核不通过原因', style: TextStyle(color: colors.textPrimary)),
          content: Text(remark, style: TextStyle(color: colors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确认')),
          ],
        ),
      );
    }
  }

  String _getStatusText(int? status) {
    switch (status) {
      case 500:
        return '待审核';
      case 2000:
        return '审核不通过';
      case 0:
        return '';
      default:
        return '';
    }
  }

  Color _getStatusColor(int? status) {
    switch (status) {
      case 500:
        return Colors.blue;
      case 2000:
        return Colors.red;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('合集管理'),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.iconPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlaylistEditPage()),
              );
              if (result == true) _loadPlaylists();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
              ? _buildEmptyState(colors)
              : RefreshIndicator(
                  onRefresh: _loadPlaylists,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _playlists.length,
                    separatorBuilder: (_, __) => Divider(height: 24, color: colors.divider),
                    itemBuilder: (context, index) => _buildPlaylistItem(_playlists[index], index),
                  ),
                ),
    );
  }

  Widget _buildEmptyState(dynamic colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.playlist_play, size: 80, color: colors.iconSecondary),
          const SizedBox(height: 16),
          Text('暂无合集', style: TextStyle(fontSize: 16, color: colors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlaylistEditPage()),
              );
              if (result == true) _loadPlaylists();
            },
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('创建合集', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistItem(Map<String, dynamic> playlist, int index) {
    final colors = context.colors;
    final status = playlist['status'] as int?;
    final cover = playlist['cover']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 120,
              height: 80,
              color: colors.surfaceVariant,
              child: cover.isNotEmpty
                  ? CachedImage(
                      imageUrl: ImageUtils.getFullImageUrl(cover),
                      width: 120,
                      height: 80,
                      fit: BoxFit.cover,
                    )
                  : Icon(Icons.playlist_play, size: 40, color: colors.iconSecondary),
            ),
          ),
          const SizedBox(width: 12),

          // 信息
          Expanded(
            child: SizedBox(
              height: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    playlist['title'] ?? '未命名',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (playlist['desc'] != null && playlist['desc'].toString().isNotEmpty)
                    Text(
                      playlist['desc'],
                      style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Row(
                    children: [
                      Text(
                        '${playlist['videoCount'] ?? 0}个视频',
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                      if (_getStatusText(status).isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          _getStatusText(status),
                          style: TextStyle(fontSize: 12, color: _getStatusColor(status), fontWeight: FontWeight.w500),
                        ),
                      ],
                      if (status == 2000) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _showReviewReason(playlist['id']),
                          child: Text('查看原因', style: TextStyle(fontSize: 12, color: Colors.blue[700])),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 操作菜单
          SizedBox(
            height: 80,
            child: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20, color: colors.iconSecondary),
              onSelected: (value) async {
                switch (value) {
                  case 'edit':
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistEditPage(playlistData: playlist),
                      ),
                    );
                    if (result == true) _loadPlaylists();
                    break;
                  case 'videos':
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistVideoPage(
                          playlistId: playlist['id'],
                          playlistTitle: playlist['title'] ?? '',
                        ),
                      ),
                    );
                    if (result == true) _loadPlaylists();
                    break;
                  case 'delete':
                    _deletePlaylist(playlist, index);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('编辑')]),
                ),
                const PopupMenuItem(
                  value: 'videos',
                  child: Row(children: [Icon(Icons.video_library, size: 18), SizedBox(width: 8), Text('管理视频')]),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('删除合集', style: TextStyle(color: Colors.red)),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
