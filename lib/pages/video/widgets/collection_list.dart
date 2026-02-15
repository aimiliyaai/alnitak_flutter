import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/playlist.dart';
import '../../../services/playlist_api_service.dart';
import '../../../services/video_service.dart';
import '../../../theme/theme_extensions.dart';

/// 合集列表组件（样式与 PartList 一致）
class CollectionList extends StatefulWidget {
  final int vid;
  final Function(int vid) onVideoTap;

  const CollectionList({
    super.key,
    required this.vid,
    required this.onVideoTap,
  });

  @override
  State<CollectionList> createState() => CollectionListState();
}

class CollectionListState extends State<CollectionList> {
  final PlaylistApiService _playlistApi = PlaylistApiService();
  final VideoService _videoService = VideoService();

  bool _showTitleMode = true;
  bool _autoNext = true;
  bool _isLoading = true;
  bool _isExpandingParts = false;

  PlaylistInfo? _playlist;
  List<PlaylistVideoItem> _videoList = [];

  /// 是否有合集
  bool get hasPlaylist => _playlist != null;

  /// 是否开启自动连播
  bool get autoNext => _autoNext;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPlaylist(widget.vid);
  }

  @override
  void didUpdateWidget(CollectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vid != widget.vid) {
      _loadPlaylist(widget.vid);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showTitleMode = prefs.getBool('video_collection_show_title') ?? true;
      _autoNext = prefs.getBool('video_collection_auto_next') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('video_collection_show_title', _showTitleMode);
    await prefs.setBool('video_collection_auto_next', _autoNext);
  }

  Future<void> _loadPlaylist(int vid) async {
    setState(() => _isLoading = true);

    try {
      final playlists = await _playlistApi.getVideoPlaylists(vid);
      if (playlists.isEmpty) {
        setState(() {
          _playlist = null;
          _videoList = [];
          _isLoading = false;
        });
        return;
      }

      final first = PlaylistInfo.fromJson(playlists[0]);
      final videosRaw = await _playlistApi.getPlaylistVideos(first.id);
      final rawVideoList = videosRaw.map((v) => PlaylistVideoItem.fromJson(v)).toList();

      // 展开多分P视频
      final expandedList = await _expandMultiPartVideos(rawVideoList);

      if (mounted) {
        setState(() {
          _playlist = first;
          _videoList = expandedList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _playlist = null;
          _videoList = [];
          _isLoading = false;
        });
      }
    }
  }

  /// 展开多分P视频
  Future<List<PlaylistVideoItem>> _expandMultiPartVideos(List<PlaylistVideoItem> rawVideos) async {
    if (_isExpandingParts) return rawVideos;
    _isExpandingParts = true;

    final expandedList = <PlaylistVideoItem>[];

    for (final video in rawVideos) {
      try {
        final detail = await _videoService.getVideoDetail(video.vid);
        if (detail != null && detail.resources.isNotEmpty && detail.resources.length > 1) {
          // 视频有多分P，展开为多个项
          for (final resource in detail.resources) {
            expandedList.add(PlaylistVideoItem(
              vid: video.vid,
              title: video.title,
              cover: video.cover,
              duration: resource.duration,
              clicks: video.clicks,
              desc: video.desc,
              resourceId: resource.id,
              partTitle: resource.title,
            ));
          }
        } else {
          // 单分P或无资源，保持原样
          final resourceId = detail?.resources.isNotEmpty == true ? detail!.resources.first.id : null;
          final partTitle = detail?.resources.isNotEmpty == true ? detail!.resources.first.title : null;
          expandedList.add(PlaylistVideoItem(
            vid: video.vid,
            title: video.title,
            cover: video.cover,
            duration: video.duration,
            clicks: video.clicks,
            desc: video.desc,
            resourceId: resourceId,
            partTitle: partTitle,
          ));
        }
      } catch (e) {
        // 获取视频详情失败，保持原样
        expandedList.add(video);
      }
    }

    _isExpandingParts = false;
    return expandedList;
  }

  /// 获取下一个合集视频 vid
  int? getNextVideo() {
    if (!_autoNext || _videoList.isEmpty) return null;
    final idx = _videoList.indexWhere((v) => v.vid == widget.vid);
    if (idx >= 0 && idx < _videoList.length - 1) {
      return _videoList[idx + 1].vid;
    }
    return null;
  }

  int get _currentIndex {
    // 优先精确匹配 vid（当前分P）
    final idx = _videoList.indexWhere((v) => v.vid == widget.vid);
    return idx >= 0 ? idx + 1 : 0;
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  void _toggleViewMode() {
    setState(() => _showTitleMode = !_showTitleMode);
    _saveSettings();
  }

  void _toggleAutoNext() {
    setState(() => _autoNext = !_autoNext);
    _saveSettings();
  }

  Widget _buildTitleMode() {
    final colors = context.colors;
    return Column(
      children: [
        for (int index = 0; index < _videoList.length; index++) ...[
          if (index > 0) Divider(height: 1, color: colors.divider),
          _buildListTile(index, colors),
        ],
      ],
    );
  }

  Widget _buildListTile(int index, dynamic colors) {
    final video = _videoList[index];
    final isCurrent = video.vid == widget.vid;

    return ListTile(
      selected: isCurrent,
      selectedTileColor: colors.accentColor.withValues(alpha: 0.15),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isCurrent ? colors.accentColor : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isCurrent ? Colors.white : colors.textSecondary,
            ),
          ),
        ),
      ),
      title: Text(
        video.partTitle ?? video.title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isCurrent ? colors.accentColor : colors.textPrimary,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _formatDuration(video.duration),
        style: TextStyle(fontSize: 12, color: colors.textSecondary),
      ),
      trailing: isCurrent
          ? Icon(Icons.play_circle, color: colors.accentColor)
          : null,
      onTap: () {
        if (!isCurrent) {
          widget.onVideoTap(video.vid);
        }
      },
    );
  }

  Widget _buildGridMode() {
    final colors = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int index = 0; index < _videoList.length; index++)
          _buildGridItem(index, colors),
      ],
    );
  }

  Widget _buildGridItem(int index, dynamic colors) {
    final video = _videoList[index];
    final isCurrent = video.vid == widget.vid;

    return InkWell(
      onTap: () {
        if (!isCurrent) widget.onVideoTap(video.vid);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 32,
        decoration: BoxDecoration(
          color: isCurrent ? colors.accentColor : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: isCurrent
              ? Border.all(color: colors.accentColor, width: 2)
              : null,
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isCurrent ? Colors.white : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 加载中或无合集时不显示
    if (_isLoading || _playlist == null || _videoList.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    return Card(
      elevation: 2,
      color: colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_playlist!.title} ($_currentIndex/${_videoList.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // 自动连播开关
                Row(
                  children: [
                    Text(
                      '自动连播',
                      style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                    const SizedBox(width: 4),
                    Switch(
                      value: _autoNext,
                      onChanged: (value) => _toggleAutoNext(),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),

                // 视图切换按钮
                IconButton(
                  icon: Icon(
                    _showTitleMode ? Icons.grid_view : Icons.list,
                    size: 20,
                    color: colors.iconPrimary,
                  ),
                  onPressed: _toggleViewMode,
                  tooltip: _showTitleMode ? '网格视图' : '列表视图',
                ),
              ],
            ),
            Divider(height: 16, color: colors.divider),

            // 视频列表
            _showTitleMode ? _buildTitleMode() : _buildGridMode(),
          ],
        ),
      ),
    );
  }
}
