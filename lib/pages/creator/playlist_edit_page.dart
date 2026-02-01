import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/playlist_api_service.dart';
import '../../services/upload_api_service.dart';
import '../../utils/image_utils.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';

/// 合集编辑页面（创建/编辑）
class PlaylistEditPage extends StatefulWidget {
  final Map<String, dynamic>? playlistData;

  const PlaylistEditPage({super.key, this.playlistData});

  bool get isEdit => playlistData != null;

  @override
  State<PlaylistEditPage> createState() => _PlaylistEditPageState();
}

class _PlaylistEditPageState extends State<PlaylistEditPage> {
  final PlaylistApiService _api = PlaylistApiService();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  bool _submitting = false;
  String _coverUrl = '';
  File? _coverFile;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) {
      _titleController.text = widget.playlistData!['title'] ?? '';
      _descController.text = widget.playlistData!['desc'] ?? '';
      _coverUrl = widget.playlistData!['cover'] ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
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
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入合集标题')),
      );
      return;
    }

    setState(() => _submitting = true);

    // 如果选择了新封面，先上传
    if (_coverFile != null) {
      try {
        final url = await UploadApiService.uploadImage(_coverFile!);
        _coverUrl = url;
      } catch (e) {
        if (mounted) {
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('封面上传失败: $e')),
          );
        }
        return;
      }
    }

    bool success;
    if (widget.isEdit) {
      final result = await _api.editPlaylist(
        id: widget.playlistData!['id'],
        title: title,
        desc: _descController.text.trim(),
        cover: _coverUrl,
      );
      success = result.success;
    } else {
      final result = await _api.addPlaylist(
        title: title,
        desc: _descController.text.trim(),
        cover: _coverUrl,
      );
      success = result.success;
    }

    if (mounted) {
      setState(() => _submitting = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.isEdit ? '编辑成功' : '创建成功')),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.isEdit ? '编辑失败' : '创建失败')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(widget.isEdit ? '编辑合集' : '创建合集'),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.iconPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 标题
          RichText(
            text: TextSpan(
              children: [
                TextSpan(text: '合集标题', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                const TextSpan(text: ' *', style: TextStyle(fontSize: 14, color: Colors.red)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            maxLength: 50,
            decoration: InputDecoration(
              hintText: '请输入合集标题',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: colors.card,
            ),
          ),
          const SizedBox(height: 16),

          // 封面
          RichText(
            text: TextSpan(
              children: [
                TextSpan(text: '合集封面', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                const TextSpan(text: ' *', style: TextStyle(fontSize: 14, color: Colors.red)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickCover,
            child: Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(8),
                color: colors.card,
              ),
              child: _coverFile != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _coverFile!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('点击更换', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      ],
                    )
                  : _coverUrl.isNotEmpty
                      ? Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedImage(
                                imageUrl: ImageUtils.getFullImageUrl(_coverUrl),
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('点击更换', style: TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate, size: 48, color: colors.textTertiary),
                            const SizedBox(height: 8),
                            Text('点击上传封面', style: TextStyle(color: colors.textTertiary)),
                          ],
                        ),
            ),
          ),
          const SizedBox(height: 16),

          // 简介
          Text('合集简介', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            maxLength: 200,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '请输入合集简介（选填）',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: colors.card,
            ),
          ),

          const SizedBox(height: 32),

          // 提交按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: _submitting
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      widget.isEdit ? '保存修改' : '创建合集',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
