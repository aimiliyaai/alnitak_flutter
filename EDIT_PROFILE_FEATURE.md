# 个人资料编辑功能

## 功能概述

实现了完整的个人资料编辑功能，包括头像选择、昵称、性别、生日和个性签名的编辑。

## 实现内容

### 1. 新增文件

**[lib/pages/edit_profile_page.dart](lib/pages/edit_profile_page.dart)** - 个人资料编辑页面
- 完整的表单编辑功能
- 头像选择（支持从相册选择）
- 性别选择（未知、男、女）
- 生日选择（DatePicker）
- 昵称和个性签名编辑
- 表单验证
- 保存功能

### 2. 修改文件

**[lib/pages/profile_page.dart](lib/pages/profile_page.dart)** - 个人中心页面
- 添加"编辑资料"按钮
- 添加导航到编辑页面的方法
- 编辑成功后自动刷新用户数据

**[pubspec.yaml](pubspec.yaml)** - 依赖配置
- 添加 `image_picker: ^1.0.7` 用于头像选择

---

## UI 设计

### 编辑页面布局

```
┌─────────────────────────────┐
│    [X]  Edit Profile        │  ← AppBar
├─────────────────────────────┤
│                             │
│ Profile Photo        [头像] │  ← 头像选择
│                             │
├─────────────────────────────┤
│ Nickname              Sophia│  ← 昵称编辑
├─────────────────────────────┤
│ Gender               Female │  ← 性别选择
├─────────────────────────────┤
│ Birthday         1995-08-15 │  ← 生日选择
├─────────────────────────────┤
│ Signature  Live life to...  │  ← 个性签名
├─────────────────────────────┤
│                             │
│      ┌─────────────┐        │
│      │    保存     │        │  ← 保存按钮
│      └─────────────┘        │
│                             │
└─────────────────────────────┘
```

### 个人中心编辑入口

```
┌─────────────────────────────┐
│          我的          [🚪] │
├─────────────────────────────┤
│                             │
│         ┌─────┐             │
│         │ 😊  │  (头像)     │
│         └─────┘             │
│                             │
│          用户名              │
│       UID: 123456           │
│      这是我的个性签名        │
│                             │
│      ┌─────────────┐        │
│      │  编辑资料   │        │  ← 新增按钮
│      └─────────────┘        │
│                             │
└─────────────────────────────┘
```

---

## 核心功能

### 1. 头像选择

```dart
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
    // TODO: 上传图片到服务器
  }
}
```

**功能说明**：
- 从相册选择图片
- 自动压缩到 512x512
- 图片质量设置为 85%
- 本地预览（待实现上传到服务器）

**注意**：
- 目前图片上传功能待实现
- 需要后端提供图片上传接口

### 2. 性别选择

使用 `SimpleDialog` 显示性别选择器：

```dart
Future<void> _selectGender() async {
  final result = await showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('选择性别'),
      children: [
        // 0 = 未知, 1 = 男, 2 = 女
        SimpleDialogOption(onPressed: () => Navigator.pop(context, 0)),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, 1)),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, 2)),
      ],
    ),
  );

  if (result != null) {
    setState(() => _selectedGender = result);
  }
}
```

**显示效果**：
- 当前选中的选项显示 ✓ 图标
- 使用主题颜色高亮选中项

### 3. 生日选择

使用 Flutter 内置的 `DatePicker`：

```dart
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
```

**日期格式**：
- 显示格式：`1995-08-15`
- API 格式：`yyyy-MM-dd`

### 4. 表单验证

```dart
Form(
  key: _formKey,
  child: ListView(
    children: [
      TextFormField(
        controller: _nicknameController,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return '昵称不能为空';
          }
          return null;
        },
      ),
    ],
  ),
)
```

**验证规则**：
- 昵称不能为空
- 生日必须选择
- 其他字段可选

### 5. 保存功能

```dart
Future<void> _saveProfile() async {
  if (!_formKey.currentState!.validate()) {
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
      Navigator.pop(context, true); // 返回 true 表示更新成功
    }
  } catch (e) {
    _showMessage('保存失败：${e.toString()}');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**保存流程**：
1. 验证表单
2. 显示加载状态
3. 调用 API 保存
4. 成功后返回上一页
5. 刷新个人中心数据

---

## API 对接

### 编辑用户信息接口

```http
PUT /api/v1/user/editUserInfo
Authorization: Bearer {token}
Content-Type: application/json

{
  "avatar": "https://...",
  "name": "新用户名",
  "gender": 1,
  "birthday": "2000-01-01",
  "sign": "新签名",
  "spaceCover": "https://..."
}

Response:
{
  "code": 200,
  "data": null,
  "msg": "ok"
}
```

**字段说明**：
- `avatar`: 头像URL（必填）
- `name`: 用户名（必填）
- `gender`: 性别 0=未知, 1=男, 2=女（可选）
- `birthday`: 生日，格式 `yyyy-MM-dd`（必填）
- `sign`: 个性签名（可选）
- `spaceCover`: 空间封面URL（必填）

---

## 数据流转

### 1. 初始化

```dart
@override
void initState() {
  super.initState();
  // 从传入的 UserBaseInfo 初始化表单
  _nicknameController = TextEditingController(text: widget.userInfo.name);
  _signatureController = TextEditingController(text: widget.userInfo.sign);
  _avatarUrl = widget.userInfo.avatar;
  _selectedGender = widget.userInfo.gender;

  // 解析生日
  if (widget.userInfo.birthday.isNotEmpty) {
    _selectedBirthday = DateTime.parse(widget.userInfo.birthday);
  }
}
```

### 2. 编辑流程

```
用户点击"编辑资料"
    ↓
传递 UserBaseInfo 到编辑页面
    ↓
初始化表单数据
    ↓
用户修改字段
    ↓
点击"保存"按钮
    ↓
表单验证
    ↓
调用 API 保存
    ↓
成功后返回 true
    ↓
个人中心刷新数据
```

### 3. 导航

**ProfilePage → EditProfilePage**
```dart
final result = await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => EditProfilePage(userInfo: _userInfo!),
  ),
);

if (result == true) {
  _loadUserData(); // 刷新数据
}
```

**EditProfilePage → ProfilePage**
```dart
if (success) {
  Navigator.pop(context, true); // 返回 true
}
```

---

## UI 组件

### 1. 头像选择区域

```dart
Widget _buildAvatarSection() {
  return GestureDetector(
    onTap: _pickAvatar,
    child: Row(
      children: [
        const Text('Profile Photo'),
        const Spacer(),
        Stack(
          children: [
            // 头像 (本地文件 / 网络图片 / 默认图标)
            if (_avatarFile != null)
              CircleAvatar(backgroundImage: FileImage(_avatarFile!))
            else if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
              CachedCircleAvatar(imageUrl: _avatarUrl!)
            else
              CircleAvatar(child: Icon(Icons.person)),

            // 编辑图标
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                child: Icon(Icons.camera_alt),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
```

### 2. 可编辑项

```dart
Widget _buildProfileItem({
  required String label,
  required String value,
  VoidCallback? onTap,
  Widget? trailing,
}) {
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Text(label),
          const Spacer(),
          if (trailing != null)
            trailing  // 自定义尾部 widget (如 TextField)
          else
            Row(
              children: [
                Text(value),
                if (onTap != null)
                  Icon(Icons.chevron_right),
              ],
            ),
        ],
      ),
    ),
  );
}
```

**使用示例**：

**性别选择（点击弹窗）**：
```dart
_buildProfileItem(
  label: 'Gender',
  value: _getGenderText(),
  onTap: _selectGender,
)
```

**昵称编辑（内联输入）**：
```dart
_buildProfileItem(
  label: 'Nickname',
  value: _nicknameController.text,
  onTap: null,
  trailing: SizedBox(
    width: 200,
    child: TextFormField(
      controller: _nicknameController,
      textAlign: TextAlign.right,
      decoration: const InputDecoration(
        border: InputBorder.none,
        hintText: '请输入昵称',
      ),
    ),
  ),
)
```

---

## 性别映射

### Dart 枚举值

```dart
int _selectedGender = 0; // 0=未知, 1=男, 2=女
```

### 显示文本映射

```dart
String _getGenderText() {
  switch (_selectedGender) {
    case 1:
      return 'Male';
    case 2:
      return 'Female';
    default:
      return 'Unknown';
  }
}
```

### API 传递

```dart
await _userService.editUserInfo(
  gender: _selectedGender, // 直接传递 int 值
)
```

---

## 待实现功能

### 1. 图片上传服务

**需要实现**：
```dart
Future<String?> uploadImage(File imageFile) async {
  // 1. 压缩图片
  // 2. 上传到服务器
  // 3. 返回图片URL
}
```

**集成到 _pickAvatar**：
```dart
if (image != null) {
  setState(() => _avatarFile = File(image.path));

  // 上传图片
  final uploadedUrl = await uploadImage(_avatarFile!);
  if (uploadedUrl != null) {
    setState(() => _avatarUrl = uploadedUrl);
  }
}
```

### 2. 空间封面编辑

当前使用的是用户原有的 `spaceCover`，未来可以添加：
- 空间封面选择
- 封面上传
- 封面裁剪

### 3. 权限处理

**Android**：
- 需要在 `AndroidManifest.xml` 中添加相册权限

**iOS**：
- 需要在 `Info.plist` 中添加相册访问说明

**示例配置**：

**android/app/src/main/AndroidManifest.xml**：
```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
```

**ios/Runner/Info.plist**：
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>需要访问您的相册以选择头像</string>
```

### 4. 图片裁剪

**建议依赖**：
```yaml
dependencies:
  image_cropper: ^5.0.0
```

**使用示例**：
```dart
Future<void> _pickAndCropAvatar() async {
  final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);

  if (image != null) {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: image.path,
      aspectRatio: CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 85,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (croppedFile != null) {
      setState(() => _avatarFile = File(croppedFile.path));
    }
  }
}
```

---

## 测试清单

### 功能测试

- [x] 进入编辑页面显示当前用户信息
- [x] 昵称编辑正常工作
- [x] 性别选择弹窗显示和选择
- [x] 生日选择器显示和选择
- [x] 个性签名编辑正常工作
- [x] 头像选择器打开
- [ ] 头像上传到服务器
- [x] 表单验证（昵称为空提示）
- [x] 保存按钮加载状态
- [x] 保存成功返回并刷新

### UI 测试

- [x] AppBar 显示正确
- [x] 关闭按钮功能正常
- [x] 头像显示（网络/默认）
- [x] 相机图标显示
- [x] 性别选择对话框样式
- [x] 日期选择器样式
- [x] 保存按钮样式和禁用状态
- [x] 分割线显示

### 异常测试

- [x] 昵称为空验证
- [x] 未选择生日验证
- [x] 网络错误提示
- [ ] 权限拒绝处理
- [ ] 图片选择失败处理

---

## 依赖

### 新增依赖

```yaml
dependencies:
  image_picker: ^1.0.7  # 头像选择
```

### 已有依赖（复用）

```yaml
dependencies:
  cached_network_image: ^3.3.1  # 头像显示
  dio: ^5.4.0                   # API 请求
  shared_preferences: ^2.2.0    # Token 存储
```

---

## 代码统计

**新增文件**：
- `lib/pages/edit_profile_page.dart` - 451 行

**修改文件**：
- `lib/pages/profile_page.dart` - 新增约 30 行
- `pubspec.yaml` - 新增 1 行

**总计**：约 482 行新代码

---

## 总结

### 已实现 ✅

1. ✅ 完整的个人资料编辑页面
2. ✅ 头像选择（从相册）
3. ✅ 昵称编辑
4. ✅ 性别选择
5. ✅ 生日选择
6. ✅ 个性签名编辑
7. ✅ 表单验证
8. ✅ 保存功能
9. ✅ 个人中心编辑入口
10. ✅ 编辑成功后自动刷新

### 待完善 📋

1. 📋 图片上传服务
2. 📋 空间封面编辑
3. 📋 图片裁剪功能
4. 📋 权限处理优化
5. 📋 加载骨架屏
6. 📋 更多字段支持（手机号、邮箱等）

### 技术亮点 ⭐

1. **简洁的 UI 设计**：参考现代应用的编辑页面设计
2. **灵活的组件设计**：`_buildProfileItem` 支持点击和内联编辑两种模式
3. **完善的状态管理**：加载状态、验证状态、保存状态
4. **友好的用户体验**：
   - 实时预览
   - 加载反馈
   - 错误提示
   - 保存后自动刷新
5. **可扩展性**：易于添加新的编辑字段

---

**文档版本**: v1.0
**创建日期**: 2025-01-09
**最后更新**: 2025-01-09
