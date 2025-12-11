import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/partition.dart';
import '../../models/upload_video.dart';
import '../../services/partition_api_service.dart';
import '../../services/upload_api_service.dart';
import '../../services/video_submit_api_service.dart';
import '../../utils/image_utils.dart';
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

  bool get isEditMode => widget.vid != null;

  @override
  void initState() {
    super.initState();
    _loadPartitions();
    if (isEditMode) {
      _loadVideoData();
    }
  }

  @override
  void dispose() {
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

      setState(() {
        _titleController.text = videoStatus.title;
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
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _videoFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _uploadVideo() async {
    if (_videoFile == null) {
      _showError('请选择视频文件');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      final videoInfo = await UploadApiService.uploadVideo(
        file: _videoFile!,
        title: _titleController.text.trim(),
        onProgress: (progress) {
          setState(() {
            _uploadProgress = progress;
          });
        },
      );

      setState(() {
        _isUploading = false;
      });

      final vid = videoInfo['vid'] as int?;
      print('📦 视频上传完成:');
      print('  - Resource ID: ${videoInfo['id']}');
      print('  - VID: $vid');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('视频上传成功，跳转到编辑页面')),
        );

        // 上传完成后跳转到编辑页面（参考PC端逻辑）
        if (vid != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => VideoUploadPage(vid: vid),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      _showError('视频上传失败: $e');
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

      // 编辑模式：提交视频信息（调用编辑接口）
      final editVideo = EditVideo(
        vid: widget.vid!,
        title: _titleController.text.trim(),
        cover: coverUrl!,
        desc: _descController.text.trim(),
        tags: tagsString,
      );

      print('\n📤 准备提交视频编辑信息到服务器...');
      print('📦 提交数据: ${editVideo.toJson()}');

      await VideoSubmitApiService.editVideo(editVideo);
      print('✅ 视频编辑提交成功！');
      print('🎬 ========== 视频投稿完成 ==========\n');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('稿件信息更新成功，已提交审核')),
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
      ),
      body: _isLoading && isEditMode
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 编辑模式：显示两区域布局（文件上传区 + 基本信息区）
                    if (isEditMode) ...[
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
                        color: Colors.grey[100],
                      ),
                      const SizedBox(height: 24),
                      // 基本信息标题
                      const Text(
                        '基本信息',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 上传模式：只显示视频上传区域
                    if (!isEditMode) ...[
                      _buildVideoSection(),
                      const SizedBox(height: 24),
                    ],

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
            ),
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
                            : Image.network(
                                ImageUtils.getFullImageUrl(_coverUrl),
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded /
                                              loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  print('⚠️ 封面加载失败: $error');
                                  print('⚠️ URL: ${ImageUtils.getFullImageUrl(_coverUrl)}');
                                  return const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.error, color: Colors.red),
                                        SizedBox(height: 8),
                                        Text('封面加载失败', style: TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                  );
                                },
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

  Widget _buildVideoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '视频文件',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        if (_videoFile == null)
          OutlinedButton.icon(
            onPressed: _pickVideo,
            icon: const Icon(Icons.video_library),
            label: const Text('选择视频文件'),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.video_file),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _videoFile!.path.split('/').last,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _videoFile = null;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 上传按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isUploading ? null : _uploadVideo,
              child: _isUploading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: _uploadProgress,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('上传中 ${(_uploadProgress * 100).toStringAsFixed(0)}%'),
                      ],
                    )
                  : const Text('上传视频'),
            ),
          ),
        ],
      ],
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
