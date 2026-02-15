import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/playlist.dart';
import '../../../services/playlist_api_service.dart';
import '../../../theme/theme_extensions.dart';

/// 合集列表组件（样式与 PartList 一致）
class CollectionList extends StatefulWidget {
  final int vid;
  final int currentPart;
  final Function(int vid) onVideoTap;
  final Function(int part)? onPartTap;

  const CollectionList({
    super.key,
    required this.vid,
    this.currentPart = 1,
    required this.onVideoTap,
    this.onPartTap,
  });

  @override
  State<CollectionList> createState() => CollectionListState();
}

class CollectionListState extends State<CollectionList> {
  final PlaylistApiService _playlistApi = PlaylistApiService();

  bool _showTitleMode = true;
  bool _autoNext = true;
  bool _isLoading = true;

  PlaylistInfo? _playlist;
  List<PlaylistVideoItem> _videoList = [];
  List<PlaylistVideoItem> _partList = [];

  /// 是否有合集
  bool get hasPlaylist => _playlist != null;
  
  /// 列表类型
  String get _listType => _playlist != null ? 'collection' : 'parts';
  
  /// 当前显示的列表
  List<PlaylistVideoItem> get _displayList => _playlist != null ? _videoList : _partList;

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
      // 使用合并API获取合集和分P数据
      final data = await _playlistApi.getPlaylistVideoListWithParts(vid);
      
      if (data == null) {
        if (mounted) {
          setState(() {
            _playlist = null;
            _videoList = [];
            _partList = [];
            _isLoading = false;
          });
        }
        return;
      }

      final hasCollection = data['hasCollection'] == true;
      final playlistData = data['playlist'] as Map<String, dynamic>?;
      final videosData = data['videos'] as List<dynamic>?;
      final currentPartsData = data['currentVideoParts'] as List<dynamic>?;

      if (hasCollection && playlistData != null) {
        // 有合集
        _playlist = PlaylistInfo.fromJson(playlistData);
        
        if (videosData != null) {
          _videoList = videosData.map((v) => PlaylistVideoItem.fromJson(v)).toList();
        }
        
        if (mounted) {
          setState(() {
            _partList = [];
            _isLoading = false;
          });
        }
      } else if (currentPartsData != null && currentPartsData.isNotEmpty) {
        // 没有合集但有分P
        _playlist = null;
        _partList = currentPartsData.asMap().entries.map((entry) {
          final r = entry.value as Map<String, dynamic>;
          return PlaylistVideoItem(
            vid: vid,
            title: '',
            cover: '',
            duration: (r['duration'] ?? 0).toDouble(),
            clicks: 0,
            desc: '',
            resourceId: r['resourceId'] ?? r['ID'],
            partTitle: r['title'] ?? r['Title'] ?? 'P${entry.key + 1}',
          );
        }).toList();
        
        if (mounted) {
          setState(() {
            _videoList = [];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _playlist = null;
            _videoList = [];
            _partList = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _playlist = null;
          _videoList = [];
          _partList = [];
          _isLoading = false;
        });
      }
    }
  }

  /// 获取下一个视频
  int? getNextVideo() {
    if (!_autoNext || _displayList.isEmpty) return null;
    
    if (_listType == 'parts') {
      // 分P类型
      if (widget.currentPart < _displayList.length) {
        return _displayList[widget.currentPart].vid;
      }
    } else {
      // 合集类型
      final idx = _videoList.indexWhere((v) => v.vid == widget.vid);
      if (idx >= 0 && idx < _videoList.length - 1) {
        return _videoList[idx + 1].vid;
      }
    }
    return null;
  }

  int get _currentIndex {
    // 合集类型：优先精确匹配 vid
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
        for (int index = 0; index < _displayList.length; index++) ...[
          if (index > 0) Divider(height: 1, color: colors.divider),
          _buildListTile(index, colors),
        ],
      ],
    );
  }

  bool _isCurrentItem(int index) {
    if (_listType == 'parts') {
      return index + 1 == widget.currentPart;
    }
    final video = _displayList[index];
    if (video.vid == widget.vid) {
      final currentVideoParts = _displayList.where((v) => v.vid == widget.vid).toList();
      if (currentVideoParts.length > 1) {
        final firstIndex = _displayList.indexOf(currentVideoParts.first);
        return (index - firstIndex) + 1 == widget.currentPart;
      }
      return true;
    }
    return false;
  }

  int? _getPartIndex(int index) {
    final video = _displayList[index];
    if (video.vid == widget.vid) {
      final currentVideoParts = _displayList.where((v) => v.vid == widget.vid).toList();
      if (currentVideoParts.length > 1) {
        final firstIndex = _displayList.indexOf(currentVideoParts.first);
        return (index - firstIndex) + 1;
      }
    }
    return null;
  }

  Widget _buildListTile(int index, dynamic colors) {
    final video = _displayList[index];
    final isCurrent = _isCurrentItem(index);
    final partIndex = _getPartIndex(index);

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
          if (_listType == 'parts') {
            widget.onPartTap?.call(index + 1);
          } else if (video.vid == widget.vid && partIndex != null) {
            widget.onPartTap?.call(partIndex);
          } else {
            widget.onVideoTap(video.vid);
          }
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
        for (int index = 0; index < _displayList.length; index++)
          _buildGridItem(index, colors),
      ],
    );
  }

  Widget _buildGridItem(int index, dynamic colors) {
    final video = _displayList[index];
    final isCurrent = _isCurrentItem(index);
    final partIndex = _getPartIndex(index);

    return InkWell(
      onTap: () {
        if (!isCurrent) {
          if (_listType == 'parts') {
            widget.onPartTap?.call(index + 1);
          } else if (video.vid == widget.vid && partIndex != null) {
            widget.onPartTap?.call(partIndex);
          } else {
            widget.onVideoTap(video.vid);
          }
        }
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
    // 加载中或内容少于2条时不显示
    if (_isLoading || _displayList.length < 2) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final title = _playlist != null ? _playlist!.title : '视频分集';
    final currentIndex = _listType == 'parts' ? widget.currentPart : _currentIndex;
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
                    '$title ($currentIndex/${_displayList.length})',
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
