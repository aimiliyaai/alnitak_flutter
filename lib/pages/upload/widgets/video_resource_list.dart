import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../models/upload_video.dart';
import '../../../services/resource_api_service.dart';
import '../../../services/upload_api_service.dart';
import 'dart:io';

/// 上传任务状态
class UploadTask {
  final String fileName;
  final File file;
  double progress;
  bool isUploading;
  bool isCompleted;
  bool isFailed;
  String? errorMessage;

  UploadTask({
    required this.fileName,
    required this.file,
    this.progress = 0.0,
    this.isUploading = false,
    this.isCompleted = false,
    this.isFailed = false,
    this.errorMessage,
  });
}

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

  // 上传队列
  final List<UploadTask> _uploadQueue = [];
  bool _isProcessingQueue = false;

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

  /// 添加视频（支持多选，队列上传）
  Future<void> _addVideos() async {
    if (widget.vid == null) {
      _showError('请先上传第一个视频');
      return;
    }

    // 使用 FilePicker 支持多选
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true, // 允许多选
    );

    if (result == null || result.files.isEmpty) return;

    // 将选中的文件添加到上传队列
    for (final platformFile in result.files) {
      if (platformFile.path != null) {
        final task = UploadTask(
          fileName: platformFile.name,
          file: File(platformFile.path!),
        );
        setState(() {
          _uploadQueue.add(task);
        });
      }
    }

    print('📁 添加 ${result.files.length} 个文件到上传队列');

    // 开始处理队列
    _processUploadQueue();
  }

  /// 处理上传队列（串行上传，避免服务端压力）
  Future<void> _processUploadQueue() async {
    if (_isProcessingQueue) return;

    _isProcessingQueue = true;

    while (_uploadQueue.any((task) => !task.isCompleted && !task.isFailed && !task.isUploading)) {
      // 找到下一个待上传的任务
      final taskIndex = _uploadQueue.indexWhere(
        (task) => !task.isCompleted && !task.isFailed && !task.isUploading,
      );

      if (taskIndex == -1) break;

      final task = _uploadQueue[taskIndex];

      setState(() {
        task.isUploading = true;
      });

      try {
        print('🚀 开始上传: ${task.fileName}');

        final videoInfo = await UploadApiService.uploadVideo(
          file: task.file,
          filename: task.fileName,
          title: _getFileNameWithoutExtension(task.fileName),
          vid: widget.vid,
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                task.progress = progress;
              });
            }
          },
        );

        // 上传成功，添加到资源列表
        final newResource = VideoResource(
          id: videoInfo['id'] as int,
          title: videoInfo['title'] as String? ?? task.fileName,
          vid: widget.vid,
          duration: (videoInfo['duration'] as num?)?.toDouble(),
          status: videoInfo['status'] as int? ?? 0,
        );

        if (mounted) {
          setState(() {
            task.isUploading = false;
            task.isCompleted = true;
            _resources.add(newResource);
          });

          widget.onResourcesChanged?.call(_resources);
          print('✅ 上传成功: ${task.fileName}');
        }
      } catch (e) {
        print('❌ 上传失败: ${task.fileName}, 错误: $e');
        if (mounted) {
          setState(() {
            task.isUploading = false;
            task.isFailed = true;
            task.errorMessage = e.toString();
          });
        }
      }
    }

    _isProcessingQueue = false;

    // 清理已完成的任务
    if (mounted) {
      setState(() {
        _uploadQueue.removeWhere((task) => task.isCompleted);
      });

      // 如果还有失败的任务，提示用户
      final failedCount = _uploadQueue.where((task) => task.isFailed).length;
      if (failedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$failedCount 个视频上传失败，请重试')),
        );
      }
    }
  }

  /// 重试失败的任务
  void _retryFailedTask(int index) {
    if (index >= 0 && index < _uploadQueue.length) {
      setState(() {
        _uploadQueue[index].isFailed = false;
        _uploadQueue[index].errorMessage = null;
        _uploadQueue[index].progress = 0.0;
      });
      _processUploadQueue();
    }
  }

  /// 移除失败的任务
  void _removeFailedTask(int index) {
    if (index >= 0 && index < _uploadQueue.length) {
      setState(() {
        _uploadQueue.removeAt(index);
      });
    }
  }

  /// 获取不带扩展名的文件名
  String _getFileNameWithoutExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex != -1 ? fileName.substring(0, dotIndex) : fileName;
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
                onPressed: _isProcessingQueue ? null : _addVideos,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加视频'),
              ),
            ],
          ),
        ),

        // 上传队列（显示正在上传和失败的任务）
        if (_uploadQueue.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _uploadQueue.length,
            itemBuilder: (context, index) {
              final task = _uploadQueue[index];
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      task.isFailed ? Icons.error : Icons.video_file,
                      size: 38,
                      color: task.isFailed ? Colors.red : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.fileName,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          if (task.isUploading) ...[
                            LinearProgressIndicator(value: task.progress),
                            const SizedBox(height: 4),
                            Text(
                              '上传中 ${(task.progress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ] else if (task.isFailed) ...[
                            Text(
                              '上传失败',
                              style: TextStyle(fontSize: 12, color: Colors.red[600]),
                            ),
                          ] else ...[
                            Text(
                              '等待上传...',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (task.isFailed) ...[
                      IconButton(
                        onPressed: () => _retryFailedTask(index),
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: '重试',
                      ),
                      IconButton(
                        onPressed: () => _removeFailedTask(index),
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: '移除',
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

        if (_uploadQueue.isNotEmpty) const Divider(height: 32),

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
