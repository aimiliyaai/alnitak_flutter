import 'dart:async' show StreamSubscription, Timer;
import 'dart:convert';
import 'dart:io' show WebSocket;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'logger_service.dart';

/// 弹幕消息回调
typedef DanmakuCallback = void Function(Map<String, dynamic> danmaku);

/// 在线人数 WebSocket 服务
class OnlineWebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  bool _isManualClose = false;
  bool _isPaused = false; // 后台暂停重连
  DateTime? _lastMessageTime;

  String? _currentVid;
  String? _currentRid;
  String? _clientId;

  /// 在线人数，播放器 UI 直接监听此 ValueNotifier
  final ValueNotifier<int> onlineCount = ValueNotifier<int>(0);

  /// 弹幕消息回调列表
  final List<DanmakuCallback> _danmakuCallbacks = [];

  /// 注册弹幕消息监听
  void addDanmakuListener(DanmakuCallback callback) {
    _danmakuCallbacks.add(callback);
  }

  /// 移除弹幕消息监听
  void removeDanmakuListener(DanmakuCallback callback) {
    _danmakuCallbacks.remove(callback);
  }

  /// 获取或创建客户端ID（持久化存储）
  Future<String> _getClientId() async {
    if (_clientId != null) return _clientId!;

    final prefs = await SharedPreferences.getInstance();
    _clientId = prefs.getString('ws-client-id');
    if (_clientId == null) {
      _clientId = const Uuid().v4();
      await prefs.setString('ws-client-id', _clientId!);
    }
    return _clientId!;
  }

/// 根据 ApiConfig 的 HTTPS 设置自动选择 ws/wss
  String _buildUrl(String vid, String clientId, String? rid) {
    final protocol = ApiConfig.httpsEnabled ? 'wss' : 'ws';
    final base = '$protocol://${ApiConfig.host}:${ApiConfig.port}'
        '/api/v1/online/video?vid=$vid&clientId=$clientId';
    if (rid == null || rid.isEmpty) return base;
    return '$base&rid=${Uri.encodeQueryComponent(rid)}';
  }

  /// 连接到指定视频房间
  Future<void> connect(String vid, {String? rid}) async {
    if (_currentVid == vid && _currentRid == rid && _channel != null) return;

    _cleanup();

    _currentVid = vid;
    _currentRid = rid;
    _isManualClose = false;
    _reconnectAttempts = 0;

    await _doConnect();
  }

  /// 切换视频房间
  Future<void> switchVideo(String vid, {String? rid}) async {
    if (_currentVid == vid && _currentRid == rid && _channel != null) return;
    await connect(vid, rid: rid);
  }

  /// 执行 WebSocket 连接
  Future<void> _doConnect() async {
    if (_currentVid == null || _isManualClose) return;

    try {
      final clientId = await _getClientId();
      final url = _buildUrl(_currentVid!, clientId, _currentRid);

      // 使用 IOWebSocketChannel 以获得更好的移动平台支持
      // 先建立原生 WebSocket 连接，然后包装为 channel
      final webSocket = await WebSocket.connect(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('WebSocket 连接超时');
        },
      );

      // 连接建立后检查是否已被取消
      if (_isManualClose || _currentVid == null) {
        webSocket.close();
        return;
      }

      final channel = IOWebSocketChannel(webSocket);
      _channel = channel;
      _lastMessageTime = DateTime.now();
      _reconnectAttempts = 0;

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _startHeartbeat();
    } catch (e) {
      LoggerService.instance.logWarning('WebSocket 连接失败: $e', tag: 'OnlineWebSocket');
      _scheduleReconnect();
    }
  }

void _onMessage(dynamic data) {
    _lastMessageTime = DateTime.now();
    try {
      final json = jsonDecode(data as String);
      // 后端返回 {"number": N}
      if (json['number'] != null) {
        final count = json['number'] as int;
        onlineCount.value = count;
      }
      // 处理弹幕消息 {"type": "danmaku", "danmaku": {...}}
      if (json['type'] == 'danmaku' && json['danmaku'] != null) {
        final danmaku = json['danmaku'] as Map<String, dynamic>;
        // 复制一份监听器列表，避免回调中修改列表导致异常
        final callbacks = List<DanmakuCallback>.from(_danmakuCallbacks);
        for (final callback in callbacks) {
          try {
            callback(danmaku);
          } catch (e) {
            LoggerService.instance.logWarning('弹幕回调异常: $e', tag: 'OnlineWebSocket');
          }
        }
      }
    } catch (e) {
      LoggerService.instance.logWarning('WebSocket 消息解析失败: $e', tag: 'OnlineWebSocket');
    }
  }

  void _onError(dynamic error) {
    LoggerService.instance.logWarning('WebSocket 错误: $error', tag: 'OnlineWebSocket');
  }

  void _onDone() {
    _channel = null;
    _stopHeartbeat();

    if (!_isManualClose && _currentVid != null) {
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_lastMessageTime != null &&
          DateTime.now().difference(_lastMessageTime!).inSeconds > 45) {
        _channel?.sink.close();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    if (_isManualClose || _isPaused || _currentVid == null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      LoggerService.instance.logWarning('WebSocket 重连次数已达上限', tag: 'OnlineWebSocket');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delay = Duration(
      milliseconds: (1000 * _reconnectAttempts).clamp(1000, 10000),
    );

    _reconnectTimer = Timer(delay, () {
      if (!_isManualClose && _currentVid != null) {
        _doConnect();
      }
    });
  }

  /// 清理当前连接（不重置 _currentVid）
  void _cleanup() {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    onlineCount.value = 0;
  }

  /// 后台暂停：断开连接但保留 vid，回前台自动恢复
  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    _cleanup();
  }

  /// 前台恢复：重新连接之前的 vid
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    if (_currentVid != null && !_isManualClose) {
      _reconnectAttempts = 0;
      _doConnect();
    }
  }

  /// 断开连接
  void disconnect() {
    _isManualClose = true;
    _isPaused = false;
    _currentVid = null;
    _currentRid = null;
    _cleanup();
  }

  /// 销毁服务
  void dispose() {
    disconnect();
    onlineCount.dispose();
  }
}
