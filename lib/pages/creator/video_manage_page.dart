import 'package:flutter/material.dart';
import '../../services/video_service.dart';
import '../../services/review_api_service.dart';
import '../../widgets/cached_image_widget.dart';
import '../../utils/image_utils.dart';
import '../upload/video_upload_page.dart';

/// 稿件管理页面 - 参考PC端实现
class VideoManagePage extends StatefulWidget {
  const VideoManagePage({super.key});

  @override
  State<VideoManagePage> createState() => _VideoManagePageState();
}

class _VideoManagePageState extends State<VideoManagePage> {
  final VideoService _videoService = VideoService();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _videos = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  final int _pageSize = 20; // 增加分页数量

  @override
  void initState() {
    super.initState();
    _loadVideos();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动监听
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMoreVideos();
      }
    }
  }

  /// 加载视频列表
  Future<void> _loadVideos() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _videoService.getUploadVideos(_currentPage, _pageSize);
      if (response != null) {
        if (response['videos'] != null) {
          setState(() {
            _videos.addAll(List<Map<String, dynamic>>.from(response['videos']));
          });
        } else {
          setState(() {
            _hasMore = false;
          });
        }
      } else {
        setState(() {
          _hasMore = false;
        });
      }
    } catch (e) {
      // print('加载视频列表失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载失败，请重试')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 加载更多视频
  Future<void> _loadMoreVideos() async {
    _currentPage++;
    await _loadVideos();
  }

  /// 删除视频 (参考PC端的实现)
  Future<void> _deleteVideo(Map<String, dynamic> video, int index) async {
    final TextEditingController titleController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DeleteConfirmDialog(
        videoTitle: video['title'] ?? '',
        titleController: titleController,
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final success = await _videoService.deleteVideo(video['vid']);
        if (success) {
          setState(() {
            _videos.removeAt(index);
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('删除成功')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('删除失败，请重试')),
            );
          }
        }
      } catch (e) {
        // print('删除视频失败: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除失败，请重试')),
          );
        }
      }
    }
  }

  /// 编辑视频 (参考PC端跳转到编辑页)
  Future<void> _editVideo(Map<String, dynamic> video) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoUploadPage(vid: video['vid']),
      ),
    );

    // 如果编辑成功，刷新列表
    if (result == true) {
      setState(() {
        _videos.clear();
        _currentPage = 1;
        _hasMore = true;
      });
      _loadVideos();
    }
  }

  /// 查看审核不通过原因 (参考PC端实现)
  Future<void> _showReviewReason(int vid) async {
    try {
      final review = await ReviewApiService.getVideoReviewRecord(vid);
      final remark = review['remark'] ?? '暂无原因说明';

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('审核不通过原因'),
            content: Text(remark),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确认'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取审核原因失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('视频管理'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _videos.isEmpty && !_isLoading
          ? _buildEmptyState()
          : ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _videos.length + (_hasMore && _isLoading ? 1 : 0),
              separatorBuilder: (context, index) => const Divider(height: 24),
              itemBuilder: (context, index) {
                if (index == _videos.length) {
                  return _buildLoadingIndicator();
                }
                return _buildVideoItem(_videos[index], index);
              },
            ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            '暂无稿件',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建加载指示器
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
    );
  }

  /// 构建视频项
  Widget _buildVideoItem(Map<String, dynamic> video, int index) {
    return InkWell(
      onTap: () {
        // TODO: 跳转到视频播放页
      },
      child: Container(
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
                color: Colors.grey[200],
                child: video['cover'] != null && video['cover'].toString().isNotEmpty
                    ? CachedImage(
                        imageUrl: ImageUtils.getFullImageUrl(video['cover']),
                        width: 120,
                        height: 80,
                        fit: BoxFit.cover,
                      )
                    : Icon(
                        Icons.video_library_outlined,
                        size: 40,
                        color: Colors.grey[400],
                      ),
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
                    // 标题
                    Text(
                      video['title'] ?? '未命名',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // 简介
                    if (video['desc'] != null && video['desc'].toString().isNotEmpty)
                      Text(
                        video['desc'],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                    // 创建时间和状态
                    Flexible(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              '创建于：${_formatTime(video['createdAt'])}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_getStatusText(video['status']) != null) ...[
                            const SizedBox(width: 8),
                            _buildStatusChip(video['status']),
                          ],
                          // 审核不通过时显示"查看原因"按钮
                          if (video['status'] == 600) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _showReviewReason(video['vid']),
                              child: Text(
                                '查看原因',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue[700],
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 操作菜单
            SizedBox(
              height: 80,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) {
                  if (value == 'edit') {
                    _editVideo(video);
                  } else if (value == 'delete') {
                    _deleteVideo(video, index);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('编辑'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('删除稿件', style: TextStyle(color: Colors.red)),
                      ],
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

  /// 格式化时间
  String _formatTime(dynamic time) {
    if (time == null) return '';
    try {
      final dateTime = DateTime.parse(time.toString());
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return time.toString();
    }
  }

  /// 获取状态文本 (参考PC端)
  String? _getStatusText(int? status) {
    if (status == null) return null;
    switch (status) {
      case 200: // VIDEO_PROCESSING
      case 300: // SUBMIT_REVIEW
        return '转码中';
      case 500: // WAITING_REVIEW
        return '待审核';
      case 600: // REVIEW_FAILED
        return '审核不通过';
      case 700: // PROCESSING_FAIL
        return '视频处理失败';
      default:
        return null;
    }
  }

  /// 获取状态颜色
  Color _getStatusColor(int? status) {
    if (status == null) return Colors.green;
    switch (status) {
      case 200:
      case 300:
        return Colors.orange;
      case 500:
        return Colors.blue;
      case 600:
      case 700:
        return Colors.red;
      default:
        return Colors.green;
    }
  }

  /// 构建状态标签
  Widget _buildStatusChip(int? status) {
    final text = _getStatusText(status);
    if (text == null) return const SizedBox.shrink();

    final color = _getStatusColor(status);

    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: color,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// 删除确认对话框 (参考PC端实现)
class _DeleteConfirmDialog extends StatefulWidget {
  final String videoTitle;
  final TextEditingController titleController;

  const _DeleteConfirmDialog({
    required this.videoTitle,
    required this.titleController,
  });

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('删除稿件'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 提示文本 (参考PC端格式)
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              children: [
                const TextSpan(text: '请输入 '),
                TextSpan(
                  text: widget.videoTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' 删除此视频'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '视频删除后将无法恢复，请谨慎操作',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),

          // 输入框
          TextField(
            controller: widget.titleController,
            decoration: InputDecoration(
              hintText: '请输入视频标题',
              border: const OutlineInputBorder(),
              errorText: _errorText,
            ),
            onChanged: (value) {
              if (_errorText != null) {
                setState(() {
                  _errorText = null;
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            // 验证输入标题是否匹配 (参考PC端)
            if (widget.titleController.text.trim() == widget.videoTitle) {
              Navigator.pop(context, true);
            } else {
              setState(() {
                _errorText = '输入标题与原标题不一致';
              });
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
          ),
          child: const Text('确认删除'),
        ),
      ],
    );
  }
}
