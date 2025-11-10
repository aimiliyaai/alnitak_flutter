# 历史记录与认证更新文档

## 更新概述

本次更新主要解决了两个问题：
1. **修复人机验证流程** - 使用服务端返回的 captchaId，而不是客户端生成
2. **实现历史记录功能** - 添加自动Token认证、播放进度保存和恢复

## 一、人机验证修复

### 问题描述
之前的实现中，客户端在登录失败时自己生成 `captchaId`，但正确的流程应该是使用服务端返回的 `captchaId`。

### 服务端响应格式
连续登录失败三次后，服务端返回：
```json
{
  "code": -1,
  "data": {"captchaId": "server-generated-id"},
  "msg": "需要人机验证"
}
```

### 修改内容

#### 1. 新增自定义异常类
**文件**: `lib/services/auth_service.dart`
```dart
/// 需要人机验证异常
class CaptchaRequiredException implements Exception {
  final String captchaId; // 服务端返回的 captchaId

  CaptchaRequiredException(this.captchaId);

  @override
  String toString() => '需要人机验证';
}
```

#### 2. 更新登录方法
**文件**: `lib/services/auth_service.dart`
```dart
Future<LoginResponse?> login({
  required String email,
  required String password,
  String? captchaId,
}) async {
  // ...
  if (response.data['code'] == -1) {
    // 从服务端响应中提取 captchaId
    final serverCaptchaId = response.data['data']?['captchaId'] as String? ?? '';
    throw CaptchaRequiredException(serverCaptchaId);
  }
  // ...
}
```

#### 3. 更新登录页面
**文件**: `lib/pages/login_page.dart`
```dart
try {
  final response = await _authService.login(
    email: email,
    password: password,
    captchaId: _captchaId,
  );
  // 成功处理...
} on CaptchaRequiredException catch (e) {
  // 使用服务端返回的 captchaId
  await _showCaptchaDialog(e.captchaId);
  _handlePasswordLogin(); // 验证成功后重试
  return;
} catch (e) {
  // 其他错误处理...
}

/// 显示人机验证对话框
Future<void> _showCaptchaDialog(String serverCaptchaId) async {
  await showDialog(
    context: context,
    builder: (context) => SliderCaptchaWidget(
      captchaId: serverCaptchaId, // 使用服务端提供的ID
      onSuccess: () => setState(() => _captchaId = serverCaptchaId),
      onCancel: () => setState(() => _captchaId = null),
    ),
  );
}
```

## 二、HTTP 认证拦截器

### 问题描述
之前调用 `addHistory` 接口时提示 token 无效，因为 HTTP 请求没有自动添加 Authorization header。

### 解决方案
在 HttpClient 中添加认证拦截器，自动为所有需要认证的请求添加 token。

### 修改内容

**文件**: `lib/utils/http_client.dart`
```dart
import 'package:shared_preferences/shared_preferences.dart';

class HttpClient {
  HttpClient._internal() {
    dio = Dio(BaseOptions(/* ... */));

    // 添加认证拦截器（第一个添加，确保优先执行）
    dio.interceptors.add(AuthInterceptor());

    // 其他拦截器...
  }
}

/// 认证拦截器 - 自动添加 Authorization header
class AuthInterceptor extends Interceptor {
  static const String _tokenKey = 'auth_token';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // 如果请求已包含 Authorization，不覆盖
    if (options.headers.containsKey('Authorization')) {
      return handler.next(options);
    }

    // 从 SharedPreferences 获取 token
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);

      if (token != null && token.isNotEmpty) {
        // 添加 Authorization header
        options.headers['Authorization'] = token;
        print('🔑 添加 Authorization: $token');
      }
    } catch (e) {
      print('⚠️ 获取 token 失败: $e');
    }

    return handler.next(options);
  }
}
```

### 工作原理
1. 每次发起 HTTP 请求前，拦截器自动运行
2. 从 SharedPreferences 读取已保存的 token
3. 如果 token 存在，自动添加到请求头
4. 已手动设置 Authorization 的请求不会被覆盖

## 三、历史记录功能

### API 接口

根据文档 `https://alnitak.interastral-peace.com/api/history.html`，实现了三个接口：

1. **添加历史记录**: `POST /api/v1/history/video/addHistory`
   - 参数: `vid` (视频ID), `part` (分P), `time` (进度/秒)
   - 需要认证

2. **获取播放进度**: `GET /api/v1/history/video/getProgress?vid={vid}&part={part}`
   - 返回: `{part: int, progress: float}`
   - 需要认证

3. **获取历史记录列表**: `GET /api/v1/history/video/getHistory?page={page}&page_size={size}`
   - 返回: 视频列表及总数
   - 需要认证

### 实现文件

#### 1. 数据模型
**文件**: `lib/models/history_models.dart`
```dart
/// 添加历史记录请求
class AddHistoryRequest {
  final int vid;
  final int part;
  final double time; // 播放进度(秒)

  Map<String, dynamic> toJson() => {
    'vid': vid,
    'part': part,
    'time': time,
  };
}

/// 播放进度响应
class PlayProgressData {
  final int part;
  final double progress; // 播放位置(秒)

  factory PlayProgressData.fromJson(Map<String, dynamic> json) {
    return PlayProgressData(
      part: json['part'] as int,
      progress: (json['progress'] as num).toDouble(),
    );
  }
}

/// 历史记录项
class HistoryItem {
  final int vid;
  final String title;
  final String cover;
  final double time; // 播放进度
  final String updatedAt; // 更新时间
  // ... 其他字段
}

/// 历史记录列表响应
class HistoryListResponse {
  final List<HistoryItem> videos;
  final int total;
}
```

#### 2. 历史记录服务
**文件**: `lib/services/history_service.dart`
```dart
class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;

  final Dio _dio = HttpClient().dio; // 自动包含认证拦截器

  /// 添加历史记录
  Future<bool> addHistory({
    required int vid,
    int part = 1,
    required double time,
  }) async {
    final response = await _dio.post(
      '/api/v1/history/video/addHistory',
      data: AddHistoryRequest(vid: vid, part: part, time: time).toJson(),
    );
    return response.data['code'] == 200;
  }

  /// 获取播放进度
  Future<double?> getProgress({
    required int vid,
    int part = 1,
  }) async {
    final response = await _dio.get(
      '/api/v1/history/video/getProgress',
      queryParameters: {'vid': vid, 'part': part},
    );

    if (response.data['code'] == 200) {
      final data = PlayProgressData.fromJson(response.data['data']);
      return data.progress;
    } else if (response.data['code'] == 404) {
      return null; // 无历史记录
    }
    return null;
  }

  /// 获取历史记录列表
  Future<HistoryListResponse?> getHistoryList({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/v1/history/video/getHistory',
      queryParameters: {'page': page, 'page_size': pageSize},
    );

    if (response.data['code'] == 200) {
      return HistoryListResponse.fromJson(response.data['data']);
    }
    return null;
  }
}
```

#### 3. 集成到视频播放页面
**文件**: `lib/pages/video/video_play_page.dart`

##### 加载时恢复进度
```dart
class _VideoPlayPageState extends State<VideoPlayPage> {
  final HistoryService _historyService = HistoryService();

  Future<void> _loadVideoData() async {
    // 并发请求多个接口
    final results = await Future.wait([
      _videoService.getVideoDetail(widget.vid),
      _videoService.getVideoStat(widget.vid),
      _historyService.getProgress(vid: widget.vid, part: _currentPart), // 获取进度
    ]);

    final progress = results[2] as double?;
    setState(() {
      _initialProgress = progress; // 设置初始播放位置
      _isLoading = false;
    });
  }
}
```

##### 播放时自动保存进度
```dart
/// 播放进度更新回调（每秒触发一次）
void _onProgressUpdate(Duration position) {
  final seconds = position.inSeconds.toDouble();
  // 每5秒上报一次播放进度，减少请求频率
  if (position.inSeconds % 5 == 0) {
    _historyService.addHistory(
      vid: widget.vid,
      part: _currentPart,
      time: seconds,
    );
  }
}
```

##### 播放结束时保存最终进度
```dart
void _onVideoEnded() {
  // 上报最终播放进度
  final currentResource = _videoDetail?.resources[_currentPart - 1];
  if (currentResource != null) {
    _historyService.addHistory(
      vid: widget.vid,
      part: _currentPart,
      time: currentResource.duration,
    );
  }

  // 自动播放下一P...
}
```

##### 切换分P时恢复进度
```dart
Future<void> _changePart(int part) async {
  // 获取新分P的播放进度
  final progress = await _historyService.getProgress(
    vid: widget.vid,
    part: part,
  );

  setState(() {
    _currentPart = part;
    _initialProgress = progress; // 恢复播放位置
    _playerKey = GlobalKey(debugLabel: 'player_${widget.vid}_$part');
  });
}
```

#### 4. 清理旧代码
**文件**: `lib/services/video_service.dart`
```dart
// 移除旧的历史记录方法
// getPlayProgress() 和 reportPlayProgress() 已删除
// 请使用 HistoryService().getProgress() 和 HistoryService().addHistory()
```

## 四、数据流程

### 登录流程
```
用户输入邮箱密码
    ↓
调用 AuthService.login()
    ↓
登录失败3次 → 服务端返回 captchaId
    ↓
显示滑块验证 (使用服务端的 captchaId)
    ↓
用户完成验证 → 保存 captchaId
    ↓
重试登录 (携带 captchaId)
    ↓
登录成功 → 保存 token 到 SharedPreferences
```

### 视频播放进度流程
```
打开视频页面
    ↓
调用 HistoryService.getProgress() [自动携带 token]
    ↓
恢复播放位置
    ↓
每5秒调用 HistoryService.addHistory() [自动携带 token]
    ↓
播放结束时保存最终进度
```

### Token 自动注入流程
```
发起 HTTP 请求
    ↓
AuthInterceptor 拦截
    ↓
从 SharedPreferences 读取 token
    ↓
添加 Authorization header
    ↓
继续发送请求
```

## 五、测试要点

### 1. 人机验证测试
- [ ] 连续登录失败3次
- [ ] 验证是否显示滑块验证码
- [ ] 完成验证后是否自动重试登录
- [ ] 验证成功后是否能正常登录

### 2. 历史记录测试
- [ ] 播放视频时是否每5秒保存进度
- [ ] 退出后重新打开视频，是否从上次位置继续播放
- [ ] 切换分P时，是否正确恢复各分P的进度
- [ ] 播放结束时是否保存100%的进度
- [ ] 未登录时历史记录功能是否正常（应该返回404）

### 3. Token 认证测试
- [ ] 登录后 token 是否正确保存
- [ ] 调用需要认证的接口时是否自动添加 Authorization
- [ ] Token 失效时是否返回相应错误
- [ ] 退出登录后 token 是否清除

## 六、注意事项

1. **进度单位**: 统一使用秒（double 类型），与后端保持一致
2. **频率控制**: 每5秒保存一次进度，避免频繁请求
3. **错误处理**: 历史记录保存失败不影响视频播放
4. **未登录状态**: getProgress 返回 404 时正常处理（从头播放）
5. **Token 刷新**: 当前未实现自动 token 刷新，需要用户重新登录

## 七、后续优化建议

1. **Token 自动刷新**: 当 token 过期时自动调用 updateToken 接口
2. **离线缓存**: 保存进度到本地，在有网络时同步
3. **进度条显示**: 在视频封面上显示观看进度
4. **历史记录页面**: 创建独立的历史记录浏览页面
5. **观看统计**: 统计用户观看时长、完播率等数据
