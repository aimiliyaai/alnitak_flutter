import 'package:flutter/material.dart';
import '../../services/playlist_api_service.dart';
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
  bool _isOpen = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) {
      _titleController.text = widget.playlistData!['title'] ?? '';
      _descController.text = widget.playlistData!['desc'] ?? '';
      _isOpen = widget.playlistData!['isOpen'] ?? true;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
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

    bool success;
    if (widget.isEdit) {
      success = await _api.editPlaylist(
        id: widget.playlistData!['id'],
        title: title,
        desc: _descController.text.trim(),
        cover: widget.playlistData!['cover'] ?? '',
        isOpen: _isOpen,
      );
    } else {
      success = await _api.addPlaylist(
        title: title,
        desc: _descController.text.trim(),
      );
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
          Text('合集标题', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
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

          // 公开设置（仅编辑模式）
          if (widget.isEdit) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('公开合集', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                Switch(
                  value: _isOpen,
                  onChanged: (val) => setState(() => _isOpen = val),
                ),
              ],
            ),
            Text(
              _isOpen ? '所有人可见此合集' : '仅自己可见',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],

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
