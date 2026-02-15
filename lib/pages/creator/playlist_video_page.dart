import 'package:flutter/material.dart';
import '../../services/playlist_api_service.dart';
import '../../utils/image_utils.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';

/// 合集视频管理页面（添加/移除/拖拽排序）
class PlaylistVideoPage extends StatefulWidget {
  final int playlistId;
  final String playlistTitle;

  const PlaylistVideoPage({
    super.key,
    required this.playlistId,
    required this.playlistTitle,
  });

  @override
  State<PlaylistVideoPage> createState() => _PlaylistVideoPageState();
}

class _PlaylistVideoPageState extends State<PlaylistVideoPage> {
  final PlaylistApiService _api = PlaylistApiService();
  List<Map<String, dynamic>> _videoList = [];
  bool _isLoading = true;
  bool _hasChanged = false;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() => _isLoading = true);
    final videos = await _api.getPlaylistVideos(widget.playlistId);
    if (mounted) {
      setState(() {
        _videoList = videos;
        _isLoading = false;
      });
    }
  }

  /// 移除视频
  Future<void> _removeVideo(int vid, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除视频'),
        content: Text('确认从合集中移除「${_videoList[index]['title']}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _api.delPlaylistVideos(
        playlistId: widget.playlistId,
        vids: [vid],
      );
      if (success && mounted) {
        setState(() {
          _videoList.removeAt(index);
          _hasChanged = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移除')));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('移除失败')));
      }
    }
  }

  /// 保存排序
  Future<void> _saveSort() async {
    final vids = _videoList.map((v) => v['vid'] as int).toList();
    final success = await _api.sortPlaylistVideos(
      playlistId: widget.playlistId,
      vids: vids,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? '排序已保存' : '排序保存失败')),
      );
    }
  }

  /// 显示添加视频对话框
  Future<void> _showAddVideoDialog() async {
    final results = await Future.wait([
      _api.getAllVideoList(),
      _api.getMyPlaylistVideoIds(),
    ]);
    if (!mounted) return;

    final allVideos = results[0] as List<Map<String, dynamic>>;
    final videoPlaylistMap = results[1] as Map<int, int>;
    final existingVids = _videoList.map((v) => v['vid'] as int).toSet();

    // 为每个视频添加选中状态
    final selectableVideos = allVideos.map((v) {
      final vid = v['vid'] as int? ?? v['id'] as int? ?? 0;
      final belongsToPlaylistId = videoPlaylistMap[vid];
      final inCurrentPlaylist = existingVids.contains(vid);
      // 已在其他合集中（不是当前合集）
      final inOtherPlaylist = belongsToPlaylistId != null &&
          belongsToPlaylistId != widget.playlistId &&
          !inCurrentPlaylist;
      return {
        ...v,
        'vid': vid,
        'checked': false,
        'inPlaylist': inCurrentPlaylist,
        'inOtherPlaylist': inOtherPlaylist,
      };
    }).toList();

    final selected = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => _AddVideoDialog(videos: selectableVideos),
    );

    if (selected != null && selected.isNotEmpty) {
      final success = await _api.addPlaylistVideos(
        playlistId: widget.playlistId,
        vids: selected,
      );
      if (success && mounted) {
        _hasChanged = true;
        _loadVideos();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加${selected.length}个视频')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('添加失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _hasChanged) {
          // 通知上级页面刷新
        }
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: Text('${widget.playlistTitle} - 视频管理'),
          centerTitle: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: colors.iconPrimary),
            onPressed: () => Navigator.pop(context, _hasChanged),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddVideoDialog,
              tooltip: '添加视频',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _videoList.isEmpty
                ? _buildEmptyState(colors)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _videoList.length,
                    onReorder: _onReorder,
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final video = _videoList[index];
                      return _buildVideoItem(video, index, colors);
                    },
                  ),
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _videoList.removeAt(oldIndex);
      _videoList.insert(newIndex, item);
      _hasChanged = true;
    });
    _saveSort();
  }

  Widget _buildEmptyState(dynamic colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_library_outlined, size: 80, color: colors.iconSecondary),
          const SizedBox(height: 16),
          Text('暂无视频', style: TextStyle(fontSize: 16, color: colors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showAddVideoDialog,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('添加视频', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoItem(Map<String, dynamic> video, int index, dynamic colors) {
    final cover = video['cover']?.toString() ?? '';
    final vid = video['vid'] as int? ?? 0;

    return Container(
      key: ValueKey(vid),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 拖拽手柄
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Icon(Icons.drag_handle, color: colors.iconSecondary),
            ),
          ),

          // 序号
          SizedBox(
            width: 32,
            child: Text(
              'P${index + 1}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),

          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 80,
              height: 50,
              color: colors.surfaceVariant,
              child: cover.isNotEmpty
                  ? CachedImage(
                      imageUrl: ImageUtils.getFullImageUrl(cover),
                      width: 80,
                      height: 50,
                      fit: BoxFit.cover,
                    )
                  : Icon(Icons.image_outlined, size: 24, color: colors.iconSecondary),
            ),
          ),
          const SizedBox(width: 8),

          // 标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video['title'] ?? '',
                  style: TextStyle(fontSize: 13, color: colors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // 移除按钮
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.red),
            onPressed: () => _removeVideo(vid, index),
            tooltip: '移除',
          ),
        ],
      ),
    );
  }
}

/// 添加视频对话框
class _AddVideoDialog extends StatefulWidget {
  final List<Map<String, dynamic>> videos;

  const _AddVideoDialog({required this.videos});

  @override
  State<_AddVideoDialog> createState() => _AddVideoDialogState();
}

class _AddVideoDialogState extends State<_AddVideoDialog> {
  late List<Map<String, dynamic>> _videos;

  @override
  void initState() {
    super.initState();
    _videos = List.from(widget.videos);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedCount = _videos.where((v) => v['checked'] == true && v['inPlaylist'] != true).length;

    return AlertDialog(
      backgroundColor: colors.card,
      title: Text('添加视频到合集', style: TextStyle(color: colors.textPrimary)),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _videos.isEmpty
            ? Center(child: Text('暂无可添加的视频', style: TextStyle(color: colors.textSecondary)))
            : ListView.builder(
                itemCount: _videos.length,
                itemBuilder: (context, index) {
                  final video = _videos[index];
                  final inPlaylist = video['inPlaylist'] == true;
                  final inOtherPlaylist = video['inOtherPlaylist'] == true;
                  final isDisabled = inPlaylist || inOtherPlaylist;
                  final cover = video['cover']?.toString() ?? '';

                  return CheckboxListTile(
                    value: inPlaylist ? true : (video['checked'] == true),
                    onChanged: isDisabled
                        ? null
                        : (val) {
                            setState(() => _videos[index]['checked'] = val);
                          },
                    secondary: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Opacity(
                        opacity: inOtherPlaylist ? 0.5 : 1.0,
                        child: Container(
                          width: 60,
                          height: 40,
                          color: colors.surfaceVariant,
                          child: cover.isNotEmpty
                              ? CachedImage(
                                  imageUrl: ImageUtils.getFullImageUrl(cover),
                                  width: 60,
                                  height: 40,
                                  fit: BoxFit.cover,
                                )
                              : Icon(Icons.image_outlined, size: 20, color: colors.iconSecondary),
                        ),
                      ),
                    ),
                    title: Text(
                      video['title'] ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDisabled ? colors.textTertiary : colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: inPlaylist
                        ? Text('已在合集中', style: TextStyle(fontSize: 11, color: colors.textTertiary))
                        : inOtherPlaylist
                            ? Text('已在其他合集中', style: TextStyle(fontSize: 11, color: const Color(0xFFE6A23C)))
                            : null,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: selectedCount > 0
              ? () {
                  final selected = _videos
                      .where((v) => v['checked'] == true && v['inPlaylist'] != true)
                      .map((v) => v['vid'] as int)
                      .toList();
                  Navigator.pop(context, selected);
                }
              : null,
          child: Text('添加 ($selectedCount)'),
        ),
      ],
    );
  }
}
