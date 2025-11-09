# 人机验证功能实现

## 功能概述

实现了完整的滑块验证码系统，用于防止暴力登录和垃圾邮件注册。当用户登录失败次数过多或发送邮箱验证码时，会触发人机验证。

## 实现内容

### 1. 新增文件

**[lib/models/captcha_models.dart](lib/models/captcha_models.dart)** - 验证模型
- CaptchaData: 滑块验证响应数据
- CaptchaValidateRequest: 滑块验证请求
- EmailCodeRequest: 邮箱验证码请求

**[lib/services/captcha_service.dart](lib/services/captcha_service.dart)** - 验证服务
- `generateCaptchaId()`: 生成验证码ID
- `getCaptcha()`: 获取滑块验证数据
- `validateCaptcha()`: 验证滑块位置
- `sendEmailCode()`: 发送邮箱验证码

**[lib/widgets/slider_captcha_widget.dart](lib/widgets/slider_captcha_widget.dart)** - 滑块验证组件
- 显示背景图和滑块图
- 拖动滑块验证
- 验证成功/失败处理
- 重新加载功能

### 2. 修改文件

**[lib/pages/login_page.dart](lib/pages/login_page.dart)** - 登录页面
- 捕获"需要人机验证"错误
- 显示滑块验证对话框
- 验证成功后带captchaId重试登录

**[lib/pages/register_page.dart](lib/pages/register_page.dart)** - 注册页面
- 实现发送验证码功能
- 添加60秒倒计时
- 发送前显示人机验证

**[pubspec.yaml](pubspec.yaml)** - 依赖配置
- 添加 `uuid: ^4.2.0` 用于生成captchaId

---

## API 接口

### 1. 获取滑块验证

```http
GET /api/v1/verify/captcha/get?captchaId={captchaId}

Response:
{
  "code": 200,
  "data": {
    "slider_img": "base64编码的滑块图片",
    "bg_img": "base64编码的背景图片",
    "y": 120  // 滑块左上角y坐标
  },
  "msg": "ok"
}
```

### 2. 验证滑块

```http
POST /api/v1/verify/captcha/validate
Content-Type: application/json

{
  "captchaId": "550e8400-e29b-41d4-a716-446655440000",
  "x": 180  // 用户拖动的x坐标
}

Response:
{
  "code": 200,
  "data": null,
  "msg": "ok"
}
```

### 3. 发送邮箱验证码

```http
POST /api/v1/verify/getEmailCode
Content-Type: application/json

{
  "email": "user@example.com",
  "captchaId": "550e8400-e29b-41d4-a716-446655440000"
}

Response:
{
  "code": 200,
  "data": null,
  "msg": "ok"
}
```

---

## 核心功能

### 1. 生成验证码ID

使用UUID v4生成唯一ID：

```dart
import 'package:uuid/uuid.dart';

class CaptchaService {
  final Uuid _uuid = const Uuid();

  String generateCaptchaId() {
    return _uuid.v4(); // e.g., "550e8400-e29b-41d4-a716-446655440000"
  }
}
```

### 2. 获取滑块验证数据

```dart
Future<CaptchaData?> getCaptcha(String captchaId) async {
  final response = await _httpClient.dio.get(
    '/api/v1/verify/captcha/get',
    queryParameters: {'captchaId': captchaId},
  );

  if (response.data['code'] == 200) {
    return CaptchaData.fromJson(response.data['data']);
  }
  return null;
}
```

返回数据包含：
- `slider_img`: Base64编码的滑块图片
- `bg_img`: Base64编码的背景图片
- `y`: 滑块在背景图中的y坐标

### 3. 滑块验证组件

**UI结构**：

```
┌─────────────────────────────┐
│  安全验证            [X]    │
├─────────────────────────────┤
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │
│  │    [背景图]           │  │
│  │      ┌─┐              │  │  ← 滑块可拖动
│  │      └─┘              │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │░░░░░░░░[>]            │  │  ← 拖动滑块
│  └───────────────────────┘  │
│                             │
│  拖动滑块完成拼图            │
└─────────────────────────────┘
```

**核心代码**：

```dart
// 背景图和滑块
Stack(
  children: [
    // 背景图
    Image.memory(_decodeBase64(_captchaData!.bgImg)),

    // 滑块（位置由用户拖动控制）
    Positioned(
      left: _sliderPosition,
      top: _captchaData!.y.toDouble(),
      child: Image.memory(_decodeBase64(_captchaData!.sliderImg)),
    ),
  ],
)
```

**拖动处理**：

```dart
GestureDetector(
  onHorizontalDragUpdate: (details) {
    setState(() {
      _sliderPosition = (_sliderPosition + details.delta.dx)
          .clamp(0.0, maxWidth);
    });
  },
  onHorizontalDragEnd: (details) {
    // 验证位置
    final x = _sliderPosition.round();
    _validateSlider(x);
  },
  child: Container(...), // 滑块按钮
)
```

### 4. Base64图片解码

```dart
Uint8List _decodeBase64(String base64String) {
  // 移除可能的data:image前缀
  final cleanBase64 = base64String.replaceAll(
    RegExp(r'data:image/[^;]+;base64,'),
    '',
  );
  return base64Decode(cleanBase64);
}
```

### 5. 验证流程

```
用户拖动滑块
    ↓
松开手指 (onHorizontalDragEnd)
    ↓
获取滑块x坐标
    ↓
调用 /api/v1/verify/captcha/validate
    ↓
验证成功 → 回调 onSuccess() → 关闭对话框
    ↓
验证失败 → 显示错误 → 重新加载验证码
```

---

## 集成场景

### 场景1：登录失败次数过多

**触发条件**: 连续登录失败3次后，后端返回 code=-1

**实现代码**：

```dart
// login_page.dart
Future<void> _handlePasswordLogin() async {
  try {
    final response = await _authService.login(
      email: email,
      password: password,
      captchaId: _captchaId, // 首次为null
    );

    if (response != null) {
      _showMessage('登录成功');
      Navigator.pop(context, true);
    }
  } catch (e) {
    if (e.toString().contains('需要人机验证')) {
      // 显示人机验证
      setState(() => _isLoading = false);
      await _showCaptchaDialog();
      // 验证成功后重试登录
      _handlePasswordLogin();
      return;
    }
  }
}

Future<void> _showCaptchaDialog() async {
  final captchaId = _captchaService.generateCaptchaId();

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => SliderCaptchaWidget(
      captchaId: captchaId,
      onSuccess: () {
        setState(() => _captchaId = captchaId);
      },
    ),
  );
}
```

**流程**：

```
用户输入错误密码 (第1次)
    ↓
登录失败
    ↓
用户再次输入错误密码 (第2次)
    ↓
登录失败
    ↓
用户再次输入错误密码 (第3次)
    ↓
后端返回 code=-1 "需要人机验证"
    ↓
显示滑块验证对话框
    ↓
用户完成滑块验证
    ↓
获得 captchaId
    ↓
重新调用登录接口，携带 captchaId
    ↓
登录成功
```

### 场景2：发送邮箱验证码

**触发条件**: 用户点击"获取验证码"按钮

**实现代码**：

```dart
// register_page.dart
Future<void> _sendEmailCode() async {
  // 1. 验证邮箱
  if (!_isValidEmail(email)) {
    _showMessage('请输入有效的邮箱地址');
    return;
  }

  // 2. 防止重复发送（倒计时中）
  if (_countdown > 0) return;

  setState(() => _isSendingCode = true);

  // 3. 显示人机验证
  final captchaId = await _showCaptchaDialog();
  if (captchaId == null) {
    setState(() => _isSendingCode = false);
    return;
  }

  // 4. 发送验证码
  final success = await _captchaService.sendEmailCode(
    email: email,
    captchaId: captchaId,
  );

  if (success) {
    _showMessage('验证码已发送，请查收邮箱');
    // 5. 开始60秒倒计时
    setState(() => _countdown = 60);
    _startCountdown();
  }
}

void _startCountdown() {
  Future.delayed(const Duration(seconds: 1), () {
    if (!mounted) return;
    if (_countdown > 0) {
      setState(() => _countdown--);
      _startCountdown();
    }
  });
}
```

**流程**：

```
用户点击"获取验证码"
    ↓
验证邮箱格式
    ↓
显示滑块验证对话框
    ↓
用户完成滑块验证
    ↓
获得 captchaId
    ↓
调用 /api/v1/verify/getEmailCode
    ↓
后端发送邮件
    ↓
开始60秒倒计时
    ↓
按钮显示 "60s" → "59s" → ... → "获取验证码"
```

---

## UI组件详解

### SliderCaptchaWidget

**参数**：
- `captchaId`: 验证码ID（必需）
- `onSuccess`: 验证成功回调（必需）
- `onCancel`: 取消回调（可选）

**状态**：
- `_isLoading`: 加载验证码中
- `_isValidating`: 验证滑块中
- `_sliderPosition`: 滑块当前位置
- `_errorMessage`: 错误消息

**生命周期**：

```dart
@override
void initState() {
  super.initState();
  _loadCaptcha(); // 自动加载验证码
}

Future<void> _loadCaptcha() async {
  setState(() => _isLoading = true);

  final captchaData = await _captchaService.getCaptcha(widget.captchaId);

  setState(() {
    _captchaData = captchaData;
    _isLoading = false;
  });
}
```

**验证逻辑**：

```dart
Future<void> _validateSlider(int x) async {
  setState(() => _isValidating = true);

  final success = await _captchaService.validateCaptcha(
    captchaId: widget.captchaId,
    x: x,
  );

  if (success) {
    widget.onSuccess();
    Navigator.pop(context); // 关闭对话框
  } else {
    setState(() {
      _errorMessage = '验证失败，请重新滑动';
      _sliderPosition = 0;
      _isValidating = false;
    });
    await Future.delayed(const Duration(seconds: 1));
    _loadCaptcha(); // 重新加载
  }
}
```

---

## 倒计时功能

### 实现原理

使用递归 `Future.delayed` 实现倒计时：

```dart
int _countdown = 0;

void _startCountdown() {
  Future.delayed(const Duration(seconds: 1), () {
    if (!mounted) return; // 组件已销毁，停止

    if (_countdown > 0) {
      setState(() => _countdown--);
      _startCountdown(); // 递归调用
    }
  });
}

// 开始倒计时
setState(() => _countdown = 60);
_startCountdown();
```

### UI显示

```dart
TextButton(
  onPressed: (_isSendingCode || _countdown > 0) ? null : _sendEmailCode,
  child: _isSendingCode
      ? CircularProgressIndicator() // 发送中
      : Text(
          _countdown > 0 ? '${_countdown}s' : '获取验证码',
          style: TextStyle(
            color: (_countdown > 0) ? Colors.grey : null,
          ),
        ),
)
```

**状态变化**：

| 时间 | 显示 | 可点击 |
|------|------|-------|
| 初始 | "获取验证码" | ✅ 是 |
| 点击后 | 加载动画 | ❌ 否 |
| 发送成功 | "60s" | ❌ 否 |
| 1秒后 | "59s" | ❌ 否 |
| ... | ... | ❌ 否 |
| 60秒后 | "获取验证码" | ✅ 是 |

---

## 安全性考虑

### 1. 验证码ID唯一性

使用UUID v4确保每次验证都有唯一ID：

```dart
String generateCaptchaId() {
  return _uuid.v4(); // 随机生成，碰撞概率极低
}
```

### 2. 一次性使用

- 每个`captchaId`只能验证一次
- 验证失败后需要重新获取新的验证码
- 登录成功后`captchaId`失效

### 3. 防重放攻击

- 后端验证`captchaId`的有效期
- 验证成功后立即失效
- 不允许多次使用同一个`captchaId`

### 4. Base64图片

- 图片通过Base64编码传输
- 避免图片URL暴露
- 防止直接下载图片进行OCR识别

---

## 错误处理

### 加载失败

```dart
if (captchaData == null) {
  setState(() {
    _errorMessage = '加载验证码失败，请重试';
    _isLoading = false;
  });
}
```

显示错误界面，提供"重新加载"按钮。

### 验证失败

```dart
if (!success) {
  setState(() {
    _errorMessage = '验证失败，请重新滑动';
    _sliderPosition = 0;
  });
  await Future.delayed(const Duration(seconds: 1));
  _loadCaptcha(); // 自动重新加载
}
```

重置滑块位置，1秒后自动重新加载新的验证码。

### 网络错误

```dart
try {
  final response = await _httpClient.dio.get(...);
} catch (e) {
  print('❌ 获取验证码失败: $e');
  return null;
}
```

捕获所有网络异常，返回null触发错误UI。

---

## 依赖

### 新增依赖

```yaml
dependencies:
  uuid: ^4.2.0  # 生成唯一验证码ID
```

### 已有依赖（复用）

```yaml
dependencies:
  dio: ^5.4.0  # HTTP请求
```

---

## 测试清单

### 功能测试

- [x] 登录失败3次触发人机验证
- [x] 滑块验证成功后重新登录
- [x] 滑块验证失败后重新加载
- [x] 发送验证码前显示人机验证
- [x] 验证成功后发送验证码
- [x] 60秒倒计时正常工作
- [x] 倒计时期间不能重复发送
- [ ] 取消验证码对话框

### UI测试

- [x] 验证码对话框显示
- [x] 背景图和滑块图正确加载
- [x] 滑块可拖动
- [x] 滑动进度条显示
- [x] 加载状态显示
- [x] 验证中状态显示
- [x] 错误提示显示
- [x] 倒计时文字更新

### 异常测试

- [x] 网络错误处理
- [x] 加载失败处理
- [x] 验证失败处理
- [x] 组件销毁时停止倒计时
- [ ] 图片解码失败处理

---

## 已知问题

### 1. 图片格式

如果后端返回的Base64有`data:image/png;base64,`前缀，需要移除：

```dart
final cleanBase64 = base64String.replaceAll(
  RegExp(r'data:image/[^;]+;base64,'),
  '',
);
```

### 2. 滑块位置精度

用户很难完全精确对齐滑块，后端应该有容错范围（如±5像素）。

### 3. 拖动边界

当前限制滑块在屏幕宽度内，实际应该限制在背景图宽度内：

```dart
_sliderPosition = (_sliderPosition + details.delta.dx)
    .clamp(0.0, backgroundImageWidth - sliderWidth);
```

---

## 未来优化

### 1. 缓存验证码图片

避免重复加载相同验证码：

```dart
final Map<String, CaptchaData> _cache = {};

Future<CaptchaData?> getCaptcha(String captchaId) async {
  if (_cache.containsKey(captchaId)) {
    return _cache[captchaId];
  }

  final data = await _loadFromServer(captchaId);
  if (data != null) {
    _cache[captchaId] = data;
  }
  return data;
}
```

### 2. 添加音频验证

为视障用户提供音频验证选项：

```dart
IconButton(
  icon: const Icon(Icons.volume_up),
  onPressed: _playAudioCaptcha,
)
```

### 3. 滑动轨迹验证

记录用户滑动轨迹，检测是否为机器人：

```dart
List<Offset> _dragPath = [];

onHorizontalDragUpdate: (details) {
  _dragPath.add(details.globalPosition);
  // 分析轨迹：速度、加速度、是否为直线等
}
```

### 4. 多语言支持

```dart
Text(
  AppLocalizations.of(context).captchaHint,
  // '拖动滑块完成拼图' / 'Drag slider to complete puzzle'
)
```

---

## 代码统计

**新增文件**：
- `lib/models/captcha_models.dart` - 58 行
- `lib/services/captcha_service.dart` - 77 行
- `lib/widgets/slider_captcha_widget.dart` - 274 行

**修改文件**：
- `lib/pages/login_page.dart` - 新增约 30 行
- `lib/pages/register_page.dart` - 新增约 100 行
- `pubspec.yaml` - 新增 1 行

**总计**：约 540 行新代码

---

## 总结

### 已实现 ✅

1. ✅ 滑块验证模型和服务
2. ✅ 滑块验证UI组件
3. ✅ 登录失败触发验证
4. ✅ 验证成功后重试登录
5. ✅ 发送验证码前验证
6. ✅ 60秒倒计时
7. ✅ 错误处理和重试
8. ✅ Base64图片解码

### 技术亮点 ⭐

1. **UUID生成**: 使用uuid库生成唯一验证码ID
2. **Base64解码**: 支持带前缀和不带前缀的Base64图片
3. **拖动手势**: GestureDetector实现流畅的滑块拖动
4. **状态管理**: 完善的加载、验证、错误状态
5. **递归倒计时**: 优雅的倒计时实现
6. **用户体验**:
   - 验证失败自动重新加载
   - 倒计时期间禁用按钮
   - 加载状态反馈
   - 错误提示

---

**文档版本**: v1.0
**创建日期**: 2025-01-09
**最后更新**: 2025-01-09
