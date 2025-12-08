import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/partition.dart';
import '../../models/upload_article.dart';
import '../../services/partition_api_service.dart';
import '../../services/upload_api_service.dart';
import '../../services/article_submit_api_service.dart';

class ArticleUploadPage extends StatefulWidget {
  final int? aid; // 如果是编辑模式，传入aid

  const ArticleUploadPage({super.key, this.aid});

  @override
  State<ArticleUploadPage> createState() => _ArticleUploadPageState();
}

class _ArticleUploadPageState extends State<ArticleUploadPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagsController = TextEditingController();

  List<Partition> _allPartitions = [];
  List<Partition> _parentPartitions = [];
  List<Partition> _subPartitions = [];

  Partition? _selectedParentPartition;
  Partition? _selectedSubPartition;

  File? _coverFile;
  bool _copyright = true;
  bool _isLoading = false;
  String? _errorMessage;

  bool get isEditMode => widget.aid != null;

  @override
  void initState() {
    super.initState();
    _loadPartitions();
    if (isEditMode) {
      _loadArticleData();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadPartitions() async {
    try {
      final partitions = await PartitionApiService.getArticlePartitions();
      setState(() {
        _allPartitions = partitions;
        _parentPartitions = PartitionApiService.getParentPartitions(partitions);
      });
    } catch (e) {
      _showError('加载分区失败: $e');
    }
  }

  Future<void> _loadArticleData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final articleStatus = await ArticleSubmitApiService.getArticleStatus(widget.aid!);

      setState(() {
        _titleController.text = articleStatus.title;
        _contentController.text = articleStatus.content;
        _tagsController.text = articleStatus.tags;
        _copyright = articleStatus.copyright;

        // 设置分区
        final partition = PartitionApiService.findPartitionById(
          _allPartitions,
          articleStatus.partitionId,
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
      _showError('加载文章数据失败: $e');
    }
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _coverFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_coverFile == null && !isEditMode) {
      _showError('请选择封面图片');
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
        coverUrl = await UploadApiService.uploadImage(_coverFile!);
      }

      if (isEditMode) {
        // 编辑模式
        final editArticle = EditArticle(
          aid: widget.aid!,
          title: _titleController.text.trim(),
          cover: coverUrl ?? '', // 如果没有新封面，后端应该保留原封面
          content: _contentController.text.trim(),
          tags: _tagsController.text.trim(),
        );

        await ArticleSubmitApiService.editArticle(editArticle);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文章编辑成功')),
          );
          Navigator.pop(context, true);
        }
      } else {
        // 上传模式
        final uploadArticle = UploadArticle(
          title: _titleController.text.trim(),
          cover: coverUrl!,
          content: _contentController.text.trim(),
          tags: _tagsController.text.trim(),
          copyright: _copyright,
          partitionId: partitionId,
        );

        await ArticleSubmitApiService.uploadArticle(uploadArticle);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文章投稿成功')),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
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
        title: Text(isEditMode ? '编辑文章' : '文章投稿'),
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
                    // 封面选择
                    _buildCoverSection(),
                    const SizedBox(height: 24),

                    // 标题
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: '标题',
                        hintText: '请输入文章标题',
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

                    // 内容
                    TextFormField(
                      controller: _contentController,
                      decoration: const InputDecoration(
                        labelText: '内容',
                        hintText: '请输入文章内容（支持Markdown）',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 15,
                      maxLength: 50000,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入内容';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // 标签
                    TextFormField(
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: '标签',
                        hintText: '请输入标签，用逗号分隔',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入标签';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // 分区选择
                    _buildPartitionSection(),
                    const SizedBox(height: 16),

                    // 版权声明
                    SwitchListTile(
                      title: const Text('原创声明'),
                      subtitle: const Text('声明文章为原创内容'),
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
            child: _coverFile != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _coverFile!,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('点击选择封面图片', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
          ),
        ),
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
