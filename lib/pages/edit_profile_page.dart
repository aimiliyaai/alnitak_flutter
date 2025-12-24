import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../widgets/cached_image_widget.dart';
import '../utils/image_utils.dart';
import '../theme/theme_extensions.dart';

/// 编辑个人资料页面
class EditProfilePage extends StatefulWidget {
  final UserBaseInfo userInfo;

  const EditProfilePage({
    super.key,
    required this.userInfo,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final UserService _userService = UserService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nicknameController;
  late TextEditingController _signatureController;

  String? _avatarUrl;
  File? _avatarFile;
  int _selectedGender = 0; // 0=未知, 1=男, 2=女
  DateTime? _selectedBirthday;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.userInfo.name);
    _signatureController = TextEditingController(text: widget.userInfo.sign);
    _avatarUrl = widget.userInfo.avatar;
    _selectedGender = widget.userInfo.gender;

    // 解析生日
    if (widget.userInfo.birthday.isNotEmpty) {
      try {
        _selectedBirthday = DateTime.parse(widget.userInfo.birthday);
      } catch (e) {
        _selectedBirthday = null;
      }
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  /// 选择头像
  Future<void> _pickAvatar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _avatarFile = File(image.path);
      });
      // TODO: 上传图片到服务器，获取URL
      // final uploadedUrl = await _uploadImage(_avatarFile!);
      // if (uploadedUrl != null) {
      //   setState(() => _avatarUrl = uploadedUrl);
      // }
      _showMessage('图片上传功能待实现，请先使用现有头像');
    }
  }

  /// 选择性别
  Future<void> _selectGender() async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择性别'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 0),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Icon(
                  _selectedGender == 0 ? Icons.check_circle : Icons.circle_outlined,
                  color: _selectedGender == 0 ? Theme.of(context).primaryColor : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Text('未知'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 1),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Icon(
                  _selectedGender == 1 ? Icons.check_circle : Icons.circle_outlined,
                  color: _selectedGender == 1 ? Theme.of(context).primaryColor : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Text('男'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 2),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Icon(
                  _selectedGender == 2 ? Icons.check_circle : Icons.circle_outlined,
                  color: _selectedGender == 2 ? Theme.of(context).primaryColor : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Text('女'),
              ],
            ),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() => _selectedGender = result);
    }
  }

  /// 选择生日
  Future<void> _selectBirthday() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthday ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => _selectedBirthday = picked);
    }
  }

  /// 获取性别文本
  String _getGenderText() {
    switch (_selectedGender) {
      case 1:
        return '男';
      case 2:
        return '女';
      default:
        return '未知';
    }
  }

  /// 格式化日期
  String _formatDate(DateTime? date) {
    if (date == null) return '未设置';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 保存个人资料
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final nickname = _nicknameController.text.trim();
    final signature = _signatureController.text.trim();

    if (nickname.isEmpty) {
      _showMessage('昵称不能为空');
      return;
    }

    if (_selectedBirthday == null) {
      _showMessage('请选择生日');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await _userService.editUserInfo(
        avatar: _avatarUrl ?? widget.userInfo.avatar,
        name: nickname,
        gender: _selectedGender,
        birthday: _formatDate(_selectedBirthday),
        sign: signature.isEmpty ? null : signature,
        spaceCover: widget.userInfo.spaceCover,
      );

      if (success) {
        if (mounted) {
          _showMessage('保存成功');
          Navigator.pop(context, true); // 返回 true 表示更新成功
        }
      } else {
        _showMessage('保存失败，请重试');
      }
    } catch (e) {
      _showMessage('保存失败：${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 显示消息
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.close, color: colors.iconPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('编辑资料'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 头像选择
            _buildAvatarSection(),
            const SizedBox(height: 32),

            // 昵称
            _buildProfileItem(
              label: '昵称',
              value: _nicknameController.text,
              onTap: null, // 直接在输入框中编辑
              trailing: SizedBox(
                width: 200,
                child: TextFormField(
                  controller: _nicknameController,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '请输入昵称',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '昵称不能为空';
                    }
                    return null;
                  },
                ),
              ),
            ),
            const Divider(height: 1),

            // 性别
            _buildProfileItem(
              label: '性别',
              value: _getGenderText(),
              onTap: _selectGender,
            ),
            const Divider(height: 1),

            // 生日
            _buildProfileItem(
              label: '生日',
              value: _formatDate(_selectedBirthday),
              onTap: _selectBirthday,
            ),
            const Divider(height: 1),

            // 个性签名
            _buildProfileItem(
              label: '个性签名',
              value: _signatureController.text.isEmpty
                  ? '添加个性签名'
                  : _signatureController.text,
              onTap: null,
              trailing: SizedBox(
                width: 200,
                child: TextField(
                  controller: _signatureController,
                  textAlign: TextAlign.right,
                  maxLines: null,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '添加个性签名',
                  ),
                ),
              ),
            ),
            const Divider(height: 1),

            const SizedBox(height: 40),

            // 保存按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '保存',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建头像选择区域
  Widget _buildAvatarSection() {
    final colors = context.colors;
    return GestureDetector(
      onTap: _pickAvatar,
      child: Row(
        children: [
          Text(
            '头像',
            style: TextStyle(
              fontSize: 15,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          // 显示头像
          Stack(
            children: [
              if (_avatarFile != null)
                // 本地选择的图片
                CircleAvatar(
                  radius: 24,
                  backgroundImage: FileImage(_avatarFile!),
                )
              else if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                // 网络头像
                CachedCircleAvatar(
                  imageUrl: ImageUtils.getFullImageUrl(_avatarUrl!),
                  radius: 24,
                )
              else
                // 默认头像
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFE8D5C4),
                  child: const Icon(
                    Icons.person,
                    size: 28,
                    color: Color(0xFF8B7355),
                  ),
                ),
              // 编辑图标
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt,
                    size: 12,
                    color: colors.iconPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建个人资料项
  Widget _buildProfileItem({
    required String label,
    required String value,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: colors.textPrimary,
              ),
            ),
            const Spacer(),
            if (trailing != null)
              trailing
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      color: value.contains('Not set') || value.contains('添加')
                          ? colors.textTertiary
                          : colors.textSecondary,
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: colors.iconSecondary,
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
