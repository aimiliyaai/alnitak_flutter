# 评论区输入优化

## 问题描述

用户在使用评论功能时遇到以下体验问题:

1. **输入框被遮挡**: 点击输入框后,软键盘弹出会遮挡输入区域,用户看不到自己输入的内容
2. **二级回复不明确**: 点击二级评论的回复按钮时,不清楚是在回复哪个用户
3. **回复上下文丢失**: 在回复时缺少明确的视觉提示,用户可能忘记自己在回复谁

## 解决方案

### 1. 输入框置顶设计

将评论输入框从页面底部移动到顶部,确保输入框始终可见。

#### 实施细节

**布局调整** ([comment_list.dart:373-377](lib/pages/video/widgets/comment_list.dart#L373-L377))
```dart
@override
Widget build(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 评论输入框（置顶）
      _buildInputArea(),

      // 评论列表...
    ],
  );
}
```

**自动滚动到顶部** ([comment_list.dart:75-92](lib/pages/video/widgets/comment_list.dart#L75-L92))
```dart
// 监听焦点变化
_commentFocusNode.addListener(_onFocusChange);

void _onFocusChange() {
  if (_commentFocusNode.hasFocus) {
    // 输入框获得焦点时,延迟滚动到顶部
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
```

**效果**:
- ✅ 输入框获得焦点时自动滚动到页面顶部
- ✅ 300ms 延迟确保键盘动画完成后再滚动
- ✅ 平滑的 Curves.easeOut 动画效果

### 2. @ 回复模式

实现明确的 @ 提及系统,用户点击回复时会看到正在回复谁。

#### 回复上下文管理 ([comment_list.dart:62-63](lib/pages/video/widgets/comment_list.dart#L62-L63))

```dart
// 回复上下文
Comment? _replyToComment;        // 当前回复的评论（一级或二级）
Comment? _replyToParentComment;  // 当前回复的父评论（仅用于二级回复）
```

#### 回复触发方法 ([comment_list.dart:333-339](lib/pages/video/widgets/comment_list.dart#L333-L339))

```dart
void _replyToUser(Comment comment, {Comment? parentComment}) {
  setState(() {
    _replyToComment = comment;
    _replyToParentComment = parentComment;
  });
  _commentFocusNode.requestFocus();
}
```

**一级评论回复**:
```dart
_replyToUser(comment) // parentComment 为 null
```

**二级评论回复**:
```dart
_replyToUser(reply, parentComment: comment)
```

#### 视觉提示栏 ([comment_list.dart:463-487](lib/pages/video/widgets/comment_list.dart#L463-L487))

```dart
// 回复提示条
if (_replyToComment != null)
  Container(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '回复 @${_replyToComment!.username}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue[700],
            ),
          ),
        ),
        GestureDetector(
          onTap: _cancelReply,
          child: Icon(Icons.close, size: 18),
        ),
      ],
    ),
  ),
```

**效果**:
- ✅ 明确显示 "回复 @用户名"
- ✅ 蓝色文字突出显示
- ✅ 关闭按钮可取消回复

#### 输入框提示文本 ([comment_list.dart:507-509](lib/pages/video/widgets/comment_list.dart#L507-L509))

```dart
hintText: _replyToComment != null
    ? '回复 @${_replyToComment!.username}'
    : '添加公开评论...',
```

### 3. 提交评论逻辑 ([comment_list.dart:260-293](lib/pages/video/widgets/comment_list.dart#L260-L293))

```dart
Future<void> _submitComment() async {
  final content = _commentController.text.trim();
  if (content.isEmpty) return;

  bool success;

  if (_replyToComment != null) {
    // 回复评论（一级或二级）
    success = await _videoService.postComment(
      cid: widget.vid,
      content: content,
      parentID: _replyToParentComment?.id ?? _replyToComment!.id,
      replyUserID: _replyToComment!.uid,
      replyUserName: _replyToComment!.username,
      replyContent: _replyToComment!.content,
    );
  } else {
    // 发表新评论
    success = await _videoService.postComment(
      cid: widget.vid,
      content: content,
    );
  }

  if (success) {
    _commentController.clear();
    setState(() {
      _replyToComment = null;
      _replyToParentComment = null;
    });
    _commentFocusNode.unfocus();

    // 刷新评论列表
    _currentPage = 1;
    await _loadComments();
  } else {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评论发送失败,请重试')),
      );
    }
  }
}
```

**关键逻辑**:
- 一级评论回复: `parentID = _replyToComment.id`
- 二级评论回复: `parentID = _replyToParentComment.id`
- 同时传递被回复用户的 ID、用户名和内容用于 @ 显示

### 4. 回复项组件优化

创建独立的 `_ReplyItem` 组件用于显示二级评论 ([comment_list.dart:774-887](lib/pages/video/widgets/comment_list.dart#L774-L887))。

#### 关键特性

**@ 提及显示**:
```dart
RichText(
  text: TextSpan(
    style: TextStyle(color: Colors.black87, fontSize: 14),
    children: [
      // @ 提及部分（蓝色）
      if (reply.replyUserName != null && reply.replyUserName!.isNotEmpty)
        TextSpan(
          text: '@${reply.replyUserName} ',
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      // 评论内容
      TextSpan(text: reply.content),
    ],
  ),
),
```

**回复按钮触发**:
```dart
Row(
  children: [
    InkWell(
      onTap: onReply, // 触发 _replyToUser
      child: const Text('回复'),
    ),
  ],
),
```

## 文件结构

```
lib/pages/video/widgets/comment_list.dart (888 行)

├── CommentList Widget               # 独立使用的评论列表
├── CommentListContent Widget        # 可复用的评论内容（支持外部 ScrollController）
│
└── _CommentListContentState
    ├── 状态变量
    │   ├── _comments: List<Comment>
    │   ├── _replyToComment: Comment?
    │   ├── _replyToParentComment: Comment?
    │   ├── _commentFocusNode: FocusNode
    │   └── _scrollController: ScrollController
    │
    ├── 生命周期方法
    │   ├── initState() - 初始化焦点监听
    │   └── dispose() - 清理资源
    │
    ├── 核心方法
    │   ├── _onFocusChange() - 焦点变化时滚动到顶部
    │   ├── _replyToUser() - 设置回复上下文
    │   ├── _cancelReply() - 取消回复
    │   ├── _submitComment() - 提交评论/回复
    │   └── _loadComments() - 加载评论列表
    │
    └── UI 构建方法
        ├── build() - 主布局（Column: 输入框 + 列表）
        ├── _buildInputArea() - 输入区域（@ 提示 + TextField）
        └── _buildCommentItem() - 评论项

辅助组件:
├── _CommentItem - 一级评论组件
└── _ReplyItem - 二级回复组件（新增）
```

## 代码改进

### 移除的代码

#### 1. 每条评论的独立 TextEditingController
**旧代码**:
```dart
final Map<int, TextEditingController> _replyControllers = {};

TextEditingController _getReplyController(int commentId) {
  if (!_replyControllers.containsKey(commentId)) {
    _replyControllers[commentId] = TextEditingController();
  }
  return _replyControllers[commentId]!;
}

@override
void dispose() {
  for (var controller in _replyControllers.values) {
    controller.dispose();
  }
  // ...
}
```

**新代码**: 统一使用 `_commentController`,通过回复上下文区分

#### 2. 评论项内的内联回复输入框
**旧代码**:
```dart
// 在每个评论下方显示回复输入框
if (showReplyInput[comment.id] == true)
  Padding(
    padding: const EdgeInsets.only(left: 56),
    child: TextField(
      controller: _getReplyController(comment.id),
      // ...
    ),
  ),
```

**新代码**: 所有回复统一在顶部输入框完成

### 新增的代码

#### 1. FocusNode 焦点管理
```dart
final FocusNode _commentFocusNode = FocusNode();

@override
void initState() {
  super.initState();
  _commentFocusNode.addListener(_onFocusChange);
}
```

#### 2. 回复上下文状态
```dart
Comment? _replyToComment;
Comment? _replyToParentComment;
```

#### 3. 视觉提示栏
```dart
if (_replyToComment != null)
  Container(
    child: Row(
      children: [
        Text('回复 @${_replyToComment!.username}'),
        GestureDetector(onTap: _cancelReply, child: Icon(Icons.close)),
      ],
    ),
  ),
```

## 用户体验改进

### 修改前

| 问题 | 描述 |
|------|------|
| 🔴 输入框被遮挡 | 键盘弹出后看不到输入内容 |
| 🔴 回复不明确 | 不知道在回复谁 |
| 🔴 操作分散 | 每条评论都有自己的输入框 |
| 🔴 状态管理复杂 | 多个 TextEditingController 需要管理 |

### 修改后

| 改进 | 描述 |
|------|------|
| ✅ 输入框可见 | 置顶设计 + 自动滚动,始终可见 |
| ✅ 回复明确 | @ 提示栏 + 输入框提示文本 |
| ✅ 操作统一 | 所有回复在顶部完成 |
| ✅ 状态简化 | 单个控制器 + 回复上下文管理 |
| ✅ 视觉反馈 | 蓝色 @ 提及,关闭按钮 |

## 交互流程

### 发表新评论

```
用户点击输入框
    ↓
输入框获得焦点
    ↓
自动滚动到顶部（300ms 动画）
    ↓
输入评论内容
    ↓
点击发送按钮
    ↓
调用 API (postComment)
    ↓
刷新评论列表
```

### 回复一级评论

```
用户点击一级评论的"回复"按钮
    ↓
调用 _replyToUser(comment)
    ↓
设置 _replyToComment = comment
设置 _replyToParentComment = null
    ↓
输入框自动获得焦点
    ↓
显示"回复 @用户名"提示栏
    ↓
输入回复内容
    ↓
点击发送
    ↓
调用 API (parentID = comment.id)
    ↓
刷新评论列表
```

### 回复二级评论

```
用户点击二级回复的"回复"按钮
    ↓
调用 _replyToUser(reply, parentComment: comment)
    ↓
设置 _replyToComment = reply
设置 _replyToParentComment = comment
    ↓
输入框自动获得焦点
    ↓
显示"回复 @二级评论用户名"提示栏
    ↓
输入回复内容
    ↓
点击发送
    ↓
调用 API (parentID = comment.id, replyUserID = reply.uid)
    ↓
刷新评论列表,新回复显示为"@reply.username 内容"
```

### 取消回复

```
用户点击提示栏的关闭按钮
    ↓
调用 _cancelReply()
    ↓
清空 _replyToComment 和 _replyToParentComment
    ↓
输入框失去焦点
    ↓
提示栏消失,恢复为"添加公开评论"模式
```

## 技术要点

### 1. 焦点管理

使用 `FocusNode` 监听焦点状态,在获得焦点时触发自动滚动:

```dart
_commentFocusNode.addListener(_onFocusChange);

void _onFocusChange() {
  if (_commentFocusNode.hasFocus) {
    Future.delayed(const Duration(milliseconds: 300), () {
      _scrollController.animateTo(0, ...);
    });
  }
}
```

**为什么需要 300ms 延迟?**
- 键盘弹出有动画过程（约 200-300ms）
- 延迟确保键盘完全显示后再滚动
- 避免滚动位置被键盘动画干扰

### 2. 回复上下文传递

通过两个状态变量区分一级和二级回复:

| 回复类型 | _replyToComment | _replyToParentComment | parentID |
|---------|-----------------|----------------------|----------|
| 新评论 | null | null | - |
| 一级回复 | comment | null | comment.id |
| 二级回复 | reply | comment | comment.id |

这样设计的好处:
- ✅ 清晰区分回复类型
- ✅ 正确维护评论树结构
- ✅ 支持 @ 提及任意层级用户

### 3. 条件渲染

输入框的提示文本和视觉提示栏都根据回复上下文动态显示:

```dart
// 提示栏：仅在回复时显示
if (_replyToComment != null) ...

// 输入框提示文本：根据是否回复显示不同内容
hintText: _replyToComment != null
    ? '回复 @${_replyToComment!.username}'
    : '添加公开评论...'
```

### 4. RichText 实现 @ 高亮

在 `_ReplyItem` 中使用 `RichText` + `TextSpan` 实现 @ 提及高亮:

```dart
RichText(
  text: TextSpan(
    children: [
      // @ 部分 - 蓝色粗体
      if (reply.replyUserName != null)
        TextSpan(
          text: '@${reply.replyUserName} ',
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      // 内容部分 - 正常样式
      TextSpan(text: reply.content),
    ],
  ),
),
```

## API 对接

### 发表新评论

```dart
await _videoService.postComment(
  cid: widget.vid,
  content: content,
);
```

### 回复一级评论

```dart
await _videoService.postComment(
  cid: widget.vid,
  content: content,
  parentID: _replyToComment!.id,          // 父评论ID
  replyUserID: _replyToComment!.uid,      // 被回复用户ID
  replyUserName: _replyToComment!.username, // 被回复用户名
  replyContent: _replyToComment!.content,   // 被回复内容
);
```

### 回复二级评论

```dart
await _videoService.postComment(
  cid: widget.vid,
  content: content,
  parentID: _replyToParentComment!.id,   // 一级评论ID（父）
  replyUserID: _replyToComment!.uid,      // 被回复二级评论用户ID
  replyUserName: _replyToComment!.username,
  replyContent: _replyToComment!.content,
);
```

**注意**: `parentID` 始终指向一级评论,保持扁平的两层结构。

## 已知问题

### 分析警告

```bash
flutter analyze lib/pages/video/widgets/comment_list.dart
```

输出 4 个 info 级别警告:

1. `prefer_final_fields`: `_comments` 可以声明为 `final`
   - 影响: 无,仅建议性优化

2. `avoid_print`: 3 处 `print` 调用用于调试
   - 影响: 生产环境应移除或替换为日志系统
   - 位置: 152, 194, 319 行

**解决建议**:
```dart
// 替换 print 为条件日志
if (kDebugMode) {
  debugPrint('加载评论列表');
}
```

## 测试清单

### 功能测试

- [x] 点击输入框,页面自动滚动到顶部
- [x] 点击一级评论"回复",显示 @ 提示栏
- [x] 点击二级回复"回复",显示正确的 @ 用户名
- [x] 点击提示栏关闭按钮,取消回复模式
- [x] 发表新评论成功
- [x] 回复一级评论成功,显示在一级评论下方
- [x] 回复二级评论成功,显示 @ 提及
- [x] 输入框提示文本根据模式正确切换

### UI 测试

- [ ] 键盘弹出时输入框完全可见（不同屏幕尺寸）
- [ ] @ 提示栏样式正确（蓝色文字,关闭按钮对齐）
- [ ] 滚动动画流畅（300ms Curves.easeOut）
- [ ] 二级评论的 @ 提及高亮显示

### 兼容性测试

- [ ] Android 设备测试（不同键盘）
- [ ] iOS 设备测试
- [ ] 平板横屏模式
- [ ] 深色模式适配

## 性能优化

### 1. 减少状态管理复杂度

**改进前**: 每条评论维护独立的 `TextEditingController`
```dart
final Map<int, TextEditingController> _replyControllers = {};
// dispose 时需要循环销毁
```

**改进后**: 单一 `TextEditingController` + 回复上下文
```dart
final TextEditingController _commentController = TextEditingController();
Comment? _replyToComment;
```

**收益**:
- ✅ 减少内存占用
- ✅ 简化 dispose 逻辑
- ✅ 避免控制器泄漏

### 2. 局部状态更新

使用 `setState` 只更新必要的状态变量:

```dart
void _replyToUser(Comment comment, {Comment? parentComment}) {
  setState(() {
    _replyToComment = comment;          // 只更新这两个变量
    _replyToParentComment = parentComment;
  });
  _commentFocusNode.requestFocus();     // 不在 setState 内
}
```

### 3. 组件拆分

将 `_ReplyItem` 拆分为独立组件,避免不必要的重建:

```dart
class _ReplyItem extends StatelessWidget {
  // 仅当 reply 数据变化时重建
}
```

## 未来改进方向

### 1. 评论草稿保存

在用户切换回复目标时保存草稿:

```dart
final Map<int?, String> _drafts = {}; // null key = 新评论

void _replyToUser(Comment comment, {Comment? parentComment}) {
  // 保存当前草稿
  _drafts[_replyToComment?.id] = _commentController.text;

  setState(() {
    _replyToComment = comment;
    _replyToParentComment = parentComment;
  });

  // 恢复目标评论的草稿
  _commentController.text = _drafts[comment.id] ?? '';
  _commentFocusNode.requestFocus();
}
```

### 2. @ 用户列表补全

输入 `@` 时显示用户列表:

```dart
// 监听输入内容
_commentController.addListener(() {
  final text = _commentController.text;
  if (text.endsWith('@')) {
    _showUserSuggestions();
  }
});
```

### 3. 表情选择器

添加表情面板:

```dart
// 输入框右侧添加表情按钮
IconButton(
  icon: const Icon(Icons.emoji_emotions_outlined),
  onPressed: _showEmojiPicker,
)
```

### 4. 图片上传

支持评论中添加图片:

```dart
IconButton(
  icon: const Icon(Icons.image_outlined),
  onPressed: _pickImage,
)
```

## 相关文档

- [PROFILE_PAGE_REDESIGN.md](PROFILE_PAGE_REDESIGN.md) - 个人中心页面重新设计
- [BUGFIX_QUALITY_BUTTON.md](BUGFIX_QUALITY_BUTTON.md) - 清晰度按钮状态修复
- [NETWORK_OPTIMIZATION.md](NETWORK_OPTIMIZATION.md) - 网络优化指南

## 总结

通过输入框置顶和 @ 回复模式的实现,评论功能的用户体验得到显著提升:

| 指标 | 改进前 | 改进后 |
|------|--------|--------|
| 输入可见性 | ❌ 被键盘遮挡 | ✅ 始终可见 |
| 回复明确性 | ❌ 不清楚回复谁 | ✅ @ 提示栏 + 提示文本 |
| 代码复杂度 | ❌ 多控制器管理 | ✅ 单控制器 + 上下文 |
| 代码行数 | 980 行 | 888 行（-9%）|
| 操作步骤 | 滚动 → 找评论 → 点回复 | 点回复 → 自动置顶 |

这些优化为应用提供了现代化、流畅的评论交互体验。

---

**优化日期**: 2025-01-09
**优化版本**: v2.0
**影响文件**: `lib/pages/video/widgets/comment_list.dart`
