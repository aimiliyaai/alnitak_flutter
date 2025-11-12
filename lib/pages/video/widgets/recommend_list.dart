import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/video_service.dart';
import '../../../utils/image_utils.dart';
import '../../../widgets/cached_image_widget.dart';

/// 视频推荐列表
class RecommendList extends StatefulWidget {
  final int vid;
  final Function(int) onVideoTap;

  const RecommendList({
    super.key,
    required this.vid,
    required this.onVideoTap,
  });

  @override
  State<RecommendList> createState() => _RecommendListState();
}

class _RecommendListState extends State<RecommendList> {
  final VideoService _videoService = VideoService();
  List<Map<String, dynamic>> _recommendVideos = [];
  bool _isLoading = true;
  bool _autoNext = false;
  int _currentPlayIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _fetchRecommendVideos();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoNext = prefs.getBool('video_recommend_auto_next') ?? false;
    });
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('video_recommend_auto_next', _autoNext);
  }

  /// 获取推荐视频
  Future<void> _fetchRecommendVideos() async {
    setState(() {
      _isLoading = true;
    });

    final videos = await _videoService.getRecommendedVideos(widget.vid);

    setState(() {
      _recommendVideos = videos;
      _isLoading = false;
    });
  }

  /// 切换自动连播
  void _toggleAutoNext() {
    setState(() {
      _autoNext = !_autoNext;
    });
    _saveSettings();
  }

  /// 获取下一个视频
  int? getNextVideo() {
    if (!_autoNext || _recommendVideos.isEmpty) return null;
    if (_currentPlayIndex < _recommendVideos.length - 1) {
      _currentPlayIndex++;
      return _recommendVideos[_currentPlayIndex]['vid'];
    }
    return null;
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

  /// 格式化时长
  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '相关推荐',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // 自动连播开关
                Row(
                  children: [
                    Text(
                      '自动连播',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 4),
                    Switch(
                      value: _autoNext,
                      onChanged: (value) => _toggleAutoNext(),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),

            // 加载状态
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),

            // 推荐视频列表
            if (!_isLoading && _recommendVideos.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recommendVideos.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final video = _recommendVideos[index];
                  return _buildVideoCard(video, index);
                },
              ),

            // 空状态
            if (!_isLoading && _recommendVideos.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    '暂无推荐视频',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建视频卡片
  Widget _buildVideoCard(Map<String, dynamic> video, int index) {
    final vid = video['vid'] ?? 0;
    final title = video['title'] ?? '';
    final coverPath = video['cover'] ?? '';
    final cover = ImageUtils.getFullImageUrl(coverPath);
    final clicks = video['clicks'] ?? 0;
    final duration = video['duration'] ?? 0;
    final authorName = video['author']?['name'] ?? '';

    return InkWell(
      onTap: () {
        _currentPlayIndex = index;
        widget.onVideoTap(vid);
      },
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                // 封面图片
                SizedBox(
                  width: 160,
                  height: 90,
                  child: cover.isNotEmpty
                      ? CachedImage(
                          imageUrl: cover,
                          width: 160,
                          height: 90,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(Icons.videocam, color: Colors.grey, size: 40),
                          ),
                        ),
                ),

                // 时长标签
                if (duration > 0)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // 作者
                if (authorName.isNotEmpty)
                  Text(
                    authorName,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),

                // 播放量
                Row(
                  children: [
                    Icon(Icons.play_circle_outline, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      _formatNumber(clicks),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
