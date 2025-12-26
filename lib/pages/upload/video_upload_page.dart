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

  bool get isEditMode => widget.vid != null;

  @override
  void initState() {
    super.initState();
    _checkLoginAndLoad();
  }

  /// 检查登录状态并加载数据
  Future<void> _checkLoginAndLoad() async {
    // 检查登录状态
    final isLoggedIn = await LoginGuard.isLoggedIn();

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
      print('🚫 用户离开上传页面，设置取消标志');
    }

    _titleController.dispose();
    _descController.dispose();
    _tagInputController.dispose();
    super.dispose();
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

      print('📝 编辑模式 - 加载视频数据:');
      print('  - VID: ${videoStatus.vid}');
      print('  - 标题: ${videoStatus.title}');
      print('  - 封面: ${videoStatus.cover}');
      print('  - 标签: ${videoStatus.tags}');
      print('  - 分区ID: ${videoStatus.partitionId}');
      print('  - 资源数量: ${videoStatus.resources.length}');

      // 打印每个资源的详细信息
      for (var i = 0; i < videoStatus.resources.length; i++) {
        final resource = videoStatus.resources[i];
        print('  - 资源[$i]: id=${resource.id}, title="${resource.title}", status=${resource.status}');
      }

      setState(() {
        // 如果标题为空且有资源，使用第一个资源的标题（去除.mp4后缀）
        if (videoStatus.title.isEmpty && videoStatus.resources.isNotEmpty) {
          final firstResourceTitle = videoStatus.resources[0].title;
          _titleController.text = firstResourceTitle.endsWith('.mp4')
              ? firstResourceTitle.substring(0, firstResourceTitle.length - 4)
              : firstResourceTitle;
          print('✅ 使用第一个资源标题作为默认标题: ${_titleController.text}');
        } else {
          _titleController.text = videoStatus.title;
        }

        _descController.text = videoStatus.desc;
        _tags = videoStatus.tags.split(',').where((t) => t.isNotEmpty).toList();
        _copyright = videoStatus.copyright;
        _coverUrl = videoStatus.cover;
        _resources = videoStatus.resources; // 加载资源列表

        print('✅ 封面URL已设置: $_coverUrl');
        print('✅ 标签列表: $_tags');
        print('✅ 资源列表已加载: ${_resources.length} 个资源');

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

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('加载视频数据失败: $e');
      print('❌ 加载视频数据失败: $e');
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
    print('\n🖼️ ========== 开始选择封面 ==========');
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final fileSize = await file.length();
      print('✅ 封面文件选择成功');
      print('📁 文件路径: ${pickedFile.path}');
      print('📝 文件名: ${pickedFile.name}');
      print('📦 文件大小: ${(fileSize / 1024).toStringAsFixed(2)} KB');
      print('🖼️ ========== 封面选择完成 ==========\n');

      setState(() {
        _coverFile = file;
      });
    } else {
      print('❌ 未选择封面文件');
      print('🖼️ ========== 封面选择取消 ==========\n');
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

        print('🎥 [FilePicker] 选中视频路径: ${file.path}');
        print('📝 [FilePicker] 原始文件名: $originalName');

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
        print('❌ 未选择视频');
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

      print('🚀 准备上传: $actualFilename (标题: $videoTitle)');

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
      print('📦 视频上传完成:');
      print('  - Resource ID: ${videoInfo['id']}');
      print('  - VID: $vid');
      print('  - 标题: $videoTitle');

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
      print('❌ 上传异常: $e');

      // 如果是用户主动取消，不显示错误提示
      if (e.toString().contains('上传已取消') || e.toString().contains('MD5计算已取消')) {
        print('ℹ️ 用户主动取消上传，不显示错误提示');
      } else if (mounted) {
        // 其他错误才显示错误提示
        _showError('视频上传失败: $e');
      }

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

      print('\n🎬 ========== 开始提交视频信息 ==========');
      print('📋 视频ID: ${widget.vid}');
      print('📝 标题: ${_titleController.text.trim()}');
      print('🏷️ 标签数量: ${_tags.length}');
      print('📂 分区ID: $partitionId');

      // 上传封面（如果有新选择的封面）
      if (_coverFile != null) {
        print('🖼️ 检测到新封面文件，开始上传...');
        print('📁 封面文件路径: ${_coverFile!.path}');
        try {
          coverUrl = await UploadApiService.uploadImage(_coverFile!);
          print('✅ 封面上传成功，URL: $coverUrl');
        } catch (e) {
          print('❌ 封面上传失败: $e');
          rethrow;
        }
      } else if (_coverUrl != null) {
        // 使用后端返回的封面
        coverUrl = _coverUrl;
        print('📷 使用已有封面URL: $coverUrl');
      } else {
        print('⚠️ 没有封面图片');
      }

      final tagsString = _tags.join(',');
      print('🏷️ 标签字符串: $tagsString');

      // 参考PC端逻辑（UploadVideoInfo.vue:143）：
      // - 如果 partitionId 为 0（未设置分区） → 使用 uploadVideoInfo 接口（包含 partitionId）
      // - 如果 partitionId 不为 0（已设置分区） → 使用 editVideoInfo 接口（不包含 partitionId，分区不可修改）
      final currentPartitionId = _resources.isNotEmpty && _resources[0].vid != null
          ? await _getCurrentPartitionId()
          : 0;

      print('📂 当前分区ID: $currentPartitionId (0=未设置，需要使用uploadVideoInfo)');

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

        print('\n📤 【首次提交】使用 uploadVideoInfo 接口提交视频信息（包含分区）...');
        print('📦 提交数据: ${uploadVideo.toJson()}');

        await VideoSubmitApiService.uploadVideo(uploadVideo);
        print('✅ 视频信息提交成功！');
      } else {
        // 后续编辑：使用 editVideoInfo（不包含 partitionId）
        final editVideo = EditVideo(
          vid: widget.vid!,
          title: _titleController.text.trim(),
          cover: coverUrl!,
          desc: _descController.text.trim(),
          tags: tagsString,
        );

        print('\n📤 【编辑模式】使用 editVideoInfo 接口提交视频信息（不含分区）...');
        print('📦 提交数据: ${editVideo.toJson()}');

        await VideoSubmitApiService.editVideo(editVideo);
        print('✅ 视频编辑提交成功！');
      }

      print('🎬 ========== 视频投稿完成 ==========\n');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(currentPartitionId == 0 ? '稿件发布成功，请等待审核' : '稿件更新成功，请等待审核')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ 提交失败: $e');
      print('🎬 ========== 视频投稿失败 ==========\n');
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
      print('⚠️ 获取当前分区ID失败，默认为0: $e');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '分区',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        // 父分区选择
        DropdownButtonFormField<Partition>(
          initialValue: _selectedParentPartition,
          decoration: const InputDecoration(
            labelText: '主分区',
            border: OutlineInputBorder(),
          ),
          items: _parentPartitions.map((partition) {
            return DropdownMenuItem(
              value: partition,
              child: Text(partition.name),
            );
          }).toList(),
          onChanged: (value) {
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
            decoration: const InputDecoration(
              labelText: '子分区',
              border: OutlineInputBorder(),
            ),
            items: _subPartitions.map((partition) {
              return DropdownMenuItem(
                value: partition,
                child: Text(partition.subpartition ?? partition.name),
              );
            }).toList(),
            onChanged: (value) {
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
