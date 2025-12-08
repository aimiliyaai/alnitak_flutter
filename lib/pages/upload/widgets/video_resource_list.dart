import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../models/upload_video.dart';
import '../../../services/resource_api_service.dart';
import '../../../services/upload_api_service.dart';
import 'dart:io';

/// 视频资源列表组件（多分P管理）
/// 参考PC端: UploadVideoFile.vue
class VideoResourceList extends StatefulWidget {
  final int? vid; // 视频ID，用于添加分P时关联
  final List<VideoResource> initialResources;
  final ValueChanged<List<VideoResource>>? onResourcesChanged;

  const VideoResourceList({
    super.key,
    this.vid,
    required this.initialResources,
    this.onResourcesChanged,
  });

  @override
  State<VideoResourceList> createState() => _VideoResourceListState();
}

class _VideoResourceListState extends State<VideoResourceList> {
  late List<VideoResource> _resources;
  int _editingIndex = -1;
  final TextEditingController _titleEditController = TextEditingController();
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _resources = List.from(widget.initialResources);
  }

  @override
  void dispose() {
    _titleEditController.dispose();
    super.dispose();
  }

  /// 获取状态文本
  String _getStatusText(int status) {
    switch (status) {
      case 3:
        return '审核通过';
      case 4:
        return '处理失败';
      default:
        return '上传成功';
    }
  }

  /// 添加视频（多分P）
  Future<void> _addVideo() async {
    if (widget.vid == null) {
      _showError('请先上传第一个视频');
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final videoFile = File(pickedFile.path);

      // 上传视频到指定的vid
      final videoInfo = await UploadApiService.uploadVideo(
        file: videoFile,
        title: pickedFile.name,
        onProgress: (progress) {
          setState(() {
            _uploadProgress = progress;
          });
        },
      );

      // 添加到资源列表
      final newResource = VideoResource(
        id: videoInfo['id'] as int,
        title: videoInfo['title'] as String? ?? pickedFile.name,
        vid: widget.vid,
        duration: (videoInfo['duration'] as num?)?.toDouble(),
        status: videoInfo['status'] as int? ?? 0,
      );

      setState(() {
        _resources.add(newResource);
        _isUploading = false;
      });

      widget.onResourcesChanged?.call(_resources);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('视频添加成功')),
        );
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      _showError('视频上传失败: $e');
    }
  }

  /// 编辑标题
  void _startEditTitle(int index) {
    setState(() {
      _editingIndex = index;
      _titleEditController.text = _resources[index].title;
    });
  }

  /// 保存标题
  Future<void> _saveTitle(int index) async {
    final newTitle = _titleEditController.text.trim();
    if (newTitle.isEmpty) {
      setState(() {
        _editingIndex = -1;
      });
      return;
    }

    try {
      await ResourceApiService.modifyTitle(
        id: _resources[index].id,
        title: newTitle,
      );

      setState(() {
        // 创建新的VideoResource对象（因为字段是final）
        _resources[index] = VideoResource(
          id: _resources[index].id,
          title: newTitle,
          url: _resources[index].url,
          duration: _resources[index].duration,
          status: _resources[index].status,
          quality: _resources[index].quality,
          createdAt: _resources[index].createdAt,
          vid: _resources[index].vid,
        );
        _editingIndex = -1;
      });

      widget.onResourcesChanged?.call(_resources);
    } catch (e) {
      _showError('修改标题失败: $e');
    }
  }

  /// 删除资源
  Future<void> _deleteResource(int index) async {
    if (_resources.length <= 1) {
      _showError('至少保留一个视频');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('是否移除该条视频？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ResourceApiService.deleteResource(_resources[index].id);

      setState(() {
        _resources.removeAt(index);
      });

      widget.onResourcesChanged?.call(_resources);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
      }
    } catch (e) {
      _showError('删除失败: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '文件上传',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _addVideo,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加视频'),
              ),
            ],
          ),
        ),

        // 上传进度（如果正在上传）
        if (_isUploading)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.video_file, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('正在上传...'),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: _uploadProgress),
                          const SizedBox(height: 4),
                          Text(
                            '上传中 ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
              ],
            ),
          ),

        // 视频资源列表
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _resources.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final resource = _resources[index];
            final isEditing = _editingIndex == index;

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  // 视频图标和分P编号
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.video_library, size: 38, color: Colors.blue),
                      Positioned(
                        bottom: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            'P${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // 信息区域
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题编辑
                        Row(
                          children: [
                            Expanded(
                              child: isEditing
                                  ? TextField(
                                      controller: _titleEditController,
                                      autofocus: true,
                                      maxLength: 100,
                                      decoration: const InputDecoration(
                                        counterText: '',
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                        border: OutlineInputBorder(),
                                      ),
                                      onSubmitted: (_) => _saveTitle(index),
                                    )
                                  : GestureDetector(
                                      onTap: () => _startEditTitle(index),
                                      child: Text(
                                        resource.title.isEmpty ? '未命名视频' : resource.title,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                            ),
                            if (!isEditing && _resources.length > 1)
                              TextButton(
                                onPressed: () => _deleteResource(index),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: const Size(0, 32),
                                ),
                                child: const Text(
                                  '移除',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // 状态和进度条
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getStatusText(resource.status),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: 1.0,
                              backgroundColor: Colors.grey[200],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
