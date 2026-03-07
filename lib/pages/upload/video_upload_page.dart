import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/partition.dart';
import '../../models/upload_video.dart';
import '../../services/partition_api_service.dart';
import '../../services/upload_api_service.dart';
import '../../services/video_submit_api_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/login_guard.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/cached_image_widget.dart';
import 'widgets/video_resource_list.dart';

class VideoUploadPage extends StatefulWidget {
  final int? vid; // 如果是编辑模式，传入vid

  const VideoUploadPage({super.key, this.vid});

  @override
  State<VideoUploadPage> createState() => _VideoUploadPageState();
}

class _VideoUploadPageState extends State<VideoUploadPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _tagInputController = TextEditingController();

  List<Partition> _allPartitions = [];
  List<Partition> _parentPartitions = [];
  List<Partition> _subPartitions = [];

  Partition? _selectedParentPartition;
  Partition? _selectedSubPartition;

  File? _coverFile;
  File? _videoFile;
  String? _videoFileName; // <--- 新增：用于存储原始文件名（如 screen-xxx.mp4）
  String? _coverUrl; // 后端返回的封面URL

  // 标签列表
  List<String> _tags = [];

  // 视频资源列表（多分P）
  List<VideoResource> _resources = [];

  bool _copyright = true;
  bool _isLoading = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _errorMessage;

  // 上传取消标志：当用户主动离开页面时设为true
  bool _cancelUpload = false;

  // 分区是否已锁定（编辑模式下，如果分区已设置则不可修改）
  bool _isPartitionLocked = false;

  bool get isEditMode => widget.vid != null;

  @override
  void initState() {
    super.initState();
    _checkLoginAndLoad();
  }

  /// 检查登录状态并加载数据
  Future<void> _checkLoginAndLoad() async {
    // 检查登录状态
    final isLoggedIn = await LoginGuard.isLoggedInAsync();

    if (!isLoggedIn && mounted) {
      // 未登录，显示提示并跳转登录
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final result = await LoginGuard.navigateToLogin(context);
        if (result != true && mounted) {
          // 用户没有登录成功，返回上一页
          Navigator.pop(context);
        } else if (mounted) {
          // 登录成功，加载数据
          _loadPartitions();
          if (isEditMode) {
            _loadVideoData();
          }
        }
      });
      return;
    }

    // 已登录，正常加载数据
    _loadPartitions();
    if (isEditMode) {
      _loadVideoData();
    }
  }

  @override
  void dispose() {
    // 用户离开页面时，如果正在上传，设置取消标志
    if (_isUploading) {
      _cancelUpload = true;
    }

    // 【新增】清理临时文件
    _cleanupTempFiles().catchError((_) {});

    _titleController.dispose();
    _descController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  /// 清理投稿过程中产生的临时文件
  Future<void> _cleanupTempFiles() async {
    // 1. 清理 FilePicker 临时文件（视频）
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {}

    // 2. 清理封面临时文件（ImagePicker 产生）
    if (_coverFile != null) {
      try {
        if (await _coverFile!.exists()) {
          await _coverFile!.delete();
        }
      } catch (_) {}
      _coverFile = null;
    }

    // 3. 清理视频临时文件
    if (_videoFile != null) {
      try {
        if (await _videoFile!.exists()) {
          await _videoFile!.delete();
        }
      } catch (_) {}
      _videoFile = null;
    }
  }

  Future<void> _loadPartitions() async {
    try {
      final partitions = await PartitionApiService.getVideoPartitions();
      setState(() {
        _allPartitions = partitions;
        _parentPartitions = PartitionApiService.getParentPartitions(partitions);
      });
    } catch (e) {
      _showError('加载分区失败: $e');
    }
  }

  Future<void> _loadVideoData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final videoStatus = await VideoSubmitApiService.getVideoStatus(widget.vid!);

      setState(() {
        // 如果标题为空且有资源，使用第一个资源的标题（去除.mp4后缀）
        if (videoStatus.title.isEmpty && videoStatus.resources.isNotEmpty) {
          final firstResourceTitle = videoStatus.resources[0].title;
          _titleController.text = firstResourceTitle.endsWith('.mp4')
              ? firstResourceTitle.substring(0, firstResourceTitle.length - 4)
              : firstResourceTitle;
        } else {
          _titleController.text = videoStatus.title;
        }

        _descController.text = videoStatus.desc;
        _tags = videoStatus.tags.split(',').where((t) => t.isNotEmpty).toList();
        _copyright = videoStatus.copyright;
        _coverUrl = videoStatus.cover;
        _resources = videoStatus.resources; // 加载资源列表

        // 设置分区
        final partition = PartitionApiService.findPartitionById(
          _allPartitions,
          videoStatus.partitionId,
        );
        if (partition != null) {
          if (partition.parentId != null) {
            // 是子分区
            _selectedSubPartition = partition;
            _selectedParentPartition = PartitionApiService.findPartitionById(
              _allPartitions,
              partition.parentId!,
            );
            if (_selectedParentPartition != null) {
              _subPartitions = PartitionApiService.getSubPartitions(
                _allPartitions,
                _selectedParentPartition!.id,
              );
            }
          } else {
            // 是父分区
            _selectedParentPartition = partition;
          }
        }

        // 如果分区ID不为0，说明分区已设置，锁定分区选择
        _isPartitionLocked = videoStatus.partitionId != 0;

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('加载视频数据失败: $e');
    }
  }

  /// 添加标签
  void _addTag() {
    final tag = _tagInputController.text.trim();
    if (tag.isEmpty) return;

    if (_tags.contains(tag)) {
      _showError('不能重复添加标签');
      return;
    }

    // 检查标签是否包含特殊字符（参考PC端的isLegalTag）
    final legalPattern = RegExp(r'^[a-zA-Z0-9\u4e00-\u9fa5]+$');
    if (!legalPattern.hasMatch(tag)) {
      _showError('标签不可包含特殊字符');
      return;
    }

    setState(() {
      _tags.add(tag);
      _tagInputController.clear();
    });
  }

  /// 删除标签
  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final file = File(pickedFile.path);

      setState(() {
        _coverFile = file;
      });
    } else {
    }
  }

  Future<void> _pickVideo() async {
      // 【修改点1】使用 FilePicker 替代 ImagePicker
      // ImagePicker 会把文件名改成数字ID (如 1383.mp4)，FilePicker 能保留原始文件名
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video, // 限制只选视频
        allowMultiple: false, // 单选
      );

      if (result != null && result.files.single.path != null) {
        final platformFile = result.files.single;
        final file = File(platformFile.path!);
        
        // 【修改点2】获取真实的原始文件名 (例如: screen-20231212.mp4)
        final originalName = platformFile.name; 

        setState(() {
          _videoFile = file;
          _videoFileName = originalName; // 赋值给状态变量
        });


        // 初次投稿模式：选择视频后自动上传
        if (!isEditMode) {
          // 【修改点3】智能提取标题（去除任意后缀名，不仅限于.mp4）
          final dotIndex = originalName.lastIndexOf('.');
          final titleWithoutExtension = dotIndex != -1
              ? originalName.substring(0, dotIndex)
              : originalName;

          // 这里的 title 用于显示，_videoFileName (在_uploadVideo里用到) 用于告诉后端真实文件名
          await _uploadVideo(title: titleWithoutExtension);
        }
      } else {
      }
    }
Future<void> _uploadVideo({String? title}) async {
    if (_videoFile == null) {
      _showError('请选择视频文件');
      return;
    }

    // 重置取消标志
    _cancelUpload = false;

    // 初始状态更新
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      final videoTitle = title ?? _titleController.text.trim();

      final actualFilename = _videoFileName ?? _videoFile!.path.split('/').last;


      final videoInfo = await UploadApiService.uploadVideo(
        file: _videoFile!,
        filename: actualFilename,
        title: videoTitle,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        },
        // 传递取消检查回调：返回 _cancelUpload 的值
        onCancel: () => _cancelUpload,
      );

      // 异步操作结束后，必须检查页面是否还存在
      if (!mounted) return;

      setState(() {
        _isUploading = false;
      });

      final vid = videoInfo['vid'] as int?;

      // 【新增】上传成功后清理当前视频临时文件
      if (_videoFile != null) {
        try {
          if (await _videoFile!.exists()) {
            await _videoFile!.delete();
          }
        } catch (_) {}
        _videoFile = null;
      }

      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上传完成')),
      );

      if (vid != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => VideoUploadPage(vid: vid),
          ),
        );
      }
    } catch (e) {

      // 如果是用户主动取消，不显示错误提示
      if (e.toString().contains('上传已取消') || e.toString().contains('MD5计算已取消')) {
      } else if (mounted) {
        // 其他错误才显示错误提示
        _showError('视频上传失败: $e');
      }

      // 【新增】上传失败/取消后也清理临时文件
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }


  Future<void> _submit() async {
    // 只在编辑模式下允许提交
    if (!isEditMode) {
      _showError('上传模式请先上传视频');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 验证标签数量（至少3个）
    if (_tags.length < 3) {
      _showError('标签不能低于3个');
      return;
    }

    // 验证封面
    if (_coverFile == null && _coverUrl == null) {
      _showError('请上传视频封面');
      return;
    }

    final partitionId = _selectedSubPartition?.id ?? _selectedParentPartition?.id;
    if (partitionId == null) {
      _showError('请选择分区');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? coverUrl;


      // 上传封面（如果有新选择的封面）
      if (_coverFile != null) {
        try {
          coverUrl = await UploadApiService.uploadImage(_coverFile!);
        } catch (e) {
          rethrow;
        }
      } else if (_coverUrl != null) {
        // 使用后端返回的封面
        coverUrl = _coverUrl;
      } else {
      }

      final tagsString = _tags.join(',');

      // 参考PC端逻辑（UploadVideoInfo.vue:143）：
      // - 如果 partitionId 为 0（未设置分区） → 使用 uploadVideoInfo 接口（包含 partitionId）
      // - 如果 partitionId 不为 0（已设置分区） → 使用 editVideoInfo 接口（不包含 partitionId，分区不可修改）
      final currentPartitionId = _resources.isNotEmpty && _resources[0].vid != null
          ? await _getCurrentPartitionId()
          : 0;


      if (currentPartitionId == 0) {
        // 首次提交：使用 uploadVideoInfo（包含 partitionId）
        final uploadVideo = UploadVideo(
          vid: widget.vid!,
          title: _titleController.text.trim(),
          cover: coverUrl!,
          desc: _descController.text.trim(),
          tags: tagsString,
          copyright: _copyright,
          partitionId: partitionId,
        );


        await VideoSubmitApiService.uploadVideo(uploadVideo);
      } else {
        // 后续编辑：使用 editVideoInfo（不包含 partitionId）
        final editVideo = EditVideo(
          vid: widget.vid!,
          title: _titleController.text.trim(),
          cover: coverUrl!,
          desc: _descController.text.trim(),
          tags: tagsString,
        );


        await VideoSubmitApiService.editVideo(editVideo);
      }


      if (!mounted) return;
      // 【新增】投稿成功后清理临时文件
      await _cleanupTempFiles();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(currentPartitionId == 0 ? '稿件发布成功，请等待审核' : '稿件更新成功，请等待审核')),
      );
      Navigator.pop(context, true);
    } catch (e) {

      // 【新增】投稿失败后也清理临时文件
      await _cleanupTempFiles();

      _showError('提交失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 获取当前视频的分区ID（通过重新获取视频状态）
  Future<int> _getCurrentPartitionId() async {
    try {
      final videoStatus = await VideoSubmitApiService.getVideoStatus(widget.vid!);
      return videoStatus.partitionId;
    } catch (e) {
      return 0;
    }
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditMode ? '编辑视频' : '视频投稿'),
        actions: [
          if (isEditMode) ...[
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              TextButton(
                onPressed: _submit,
                child: const Text('提交'),
              ),
          ],
        ],
      ),
      body: _isLoading && isEditMode
          ? const Center(child: CircularProgressIndicator())
          : isEditMode
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 编辑模式：显示两区域布局（文件上传区 + 基本信息区）
                        // 文件上传区：视频资源列表（多分P管理）
                        VideoResourceList(
                          vid: widget.vid,
                          initialResources: _resources,
                          onResourcesChanged: (resources) {
                            setState(() {
                              _resources = resources;
                            });
                          },
                        ),
                        const SizedBox(height: 24),
                        // 分隔线
                        Container(
                          height: 24,
                          color: context.colors.surfaceVariant,
                        ),
                        const SizedBox(height: 24),
                        // 基本信息标题
                        const Text(
                          '基本信息',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),

                        // 封面选择
                        _buildCoverSection(),
                        const SizedBox(height: 24),

                        // 标题
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: '标题',
                            hintText: '请输入视频标题',
                            border: OutlineInputBorder(),
                          ),
                          maxLength: 80,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入标题';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // 简介
                        TextFormField(
                          controller: _descController,
                          decoration: const InputDecoration(
                            labelText: '简介',
                            hintText: '简单介绍一下视频~',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 5,
                          maxLength: 200,
                        ),
                        const SizedBox(height: 16),

                        // 标签
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '标签',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ..._tags.map((tag) => Chip(
                                        label: Text(tag),
                                        onDeleted: () => _removeTag(tag),
                                        deleteIconColor: Colors.grey[600],
                                      )),
                                  SizedBox(
                                    width: 120,
                                    child: TextField(
                                      controller: _tagInputController,
                                      decoration: const InputDecoration(
                                        hintText: '输入标签后回车',
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      onSubmitted: (_) => _addTag(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '已添加 ${_tags.length} 个标签，至少需要 3 个',
                              style: TextStyle(
                                fontSize: 12,
                                color: _tags.length < 3 ? Colors.red : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 分区选择
                        _buildPartitionSection(),
                        const SizedBox(height: 16),

                        // 版权声明
                        SwitchListTile(
                          title: const Text('原创声明'),
                          subtitle: const Text('声明视频为原创内容'),
                          value: _copyright,
                          onChanged: (value) {
                            setState(() {
                              _copyright = value;
                            });
                          },
                        ),

                        // 错误信息
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(color: Colors.red.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : _buildUploadOnlyView(),
    );
  }

  Widget _buildCoverSection() {
    // 显示优先级：手动上传的封面 > 后端返回的封面 > 空状态
    final hasCover = _coverFile != null || _coverUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '封面',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickCover,
          child: Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: hasCover
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _coverFile != null
                            ? Image.file(
                                _coverFile!,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : CachedImage(
                                imageUrl: ImageUtils.getFullImageUrl(_coverUrl),
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                                errorWidget: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.error, color: Colors.red),
                                      SizedBox(height: 8),
                                      Text('封面加载失败', style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '点击更换',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('点击选择封面图片', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 4),
                      Text('或视频上传后自动生成', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// 构建初次上传专用UI（参考PC端 VideoUploader.vue）
  Widget _buildUploadOnlyView() {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上传区域
              GestureDetector(
                onTap: _isUploading ? null : _pickVideo,
                child: Container(
                  padding: const EdgeInsets.all(48),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border, width: 2),
                    borderRadius: BorderRadius.circular(12),
                    color: colors.surfaceVariant,
                  ),
                  child: _isUploading
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                value: _uploadProgress,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '上传中 ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_upload_outlined,
                              size: 64,
                              color: colors.iconSecondary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '点击或拖拽视频到此处上传视频',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '仅支持.mp4格式文件',
                              style: TextStyle(
                                fontSize: 14,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _pickVideo,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 48,
                                  vertical: 16,
                                ),
                              ),
                              child: const Text(
                                '上传视频',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              // 错误信息
              if (_errorMessage != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildPartitionSection() {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '分区',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (_isPartitionLocked) ...[
              const SizedBox(width: 8),
              Icon(Icons.lock, size: 16, color: colors.textTertiary),
              const SizedBox(width: 4),
              Text(
                '(分区已锁定，不可修改)',
                style: TextStyle(fontSize: 12, color: colors.textTertiary),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // 父分区选择
        DropdownButtonFormField<Partition>(
          initialValue: _selectedParentPartition,
          decoration: InputDecoration(
            labelText: '主分区',
            border: const OutlineInputBorder(),
            filled: _isPartitionLocked,
            fillColor: _isPartitionLocked ? colors.inputBackground : null,
          ),
          items: _parentPartitions.map((partition) {
            return DropdownMenuItem(
              value: partition,
              child: Text(partition.name),
            );
          }).toList(),
          onChanged: _isPartitionLocked ? null : (value) {
            setState(() {
              _selectedParentPartition = value;
              _selectedSubPartition = null;
              _subPartitions = value != null
                  ? PartitionApiService.getSubPartitions(_allPartitions, value.id)
                  : [];
            });
          },
          validator: (value) {
            if (value == null && _selectedSubPartition == null) {
              return '请选择分区';
            }
            return null;
          },
        ),

        // 子分区选择（如果有）
        if (_subPartitions.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<Partition>(
            initialValue: _selectedSubPartition,
            decoration: InputDecoration(
              labelText: '子分区',
              border: const OutlineInputBorder(),
              filled: _isPartitionLocked,
              fillColor: _isPartitionLocked ? colors.inputBackground : null,
            ),
            items: _subPartitions.map((partition) {
              return DropdownMenuItem(
                value: partition,
                child: Text(partition.subpartition ?? partition.name),
              );
            }).toList(),
            onChanged: _isPartitionLocked ? null : (value) {
              setState(() {
                _selectedSubPartition = value;
              });
            },
          ),
        ],
      ],
    );
  }
}
