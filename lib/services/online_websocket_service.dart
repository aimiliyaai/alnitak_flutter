import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

/// 在线人数 WebSocket 服务
/// 用于获取视频实时在看人数
class OnlineWebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  bool _isManualClose = false;
  DateTime? _lastMessageTime;

  int? _currentVid;
  String? _clientId;

  // 在线人数回调
  final ValueNotifier<int> onlineCount = ValueNotifier<int>(0);

  // 连接状态
  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);

  /// 获取或创建客户端ID
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

  /// 获取 WebSocket URL
  /// 根据当前 HTTPS 设置自动选择 ws:// 或 wss://
  String _getWebSocketUrl(int vid, String clientId) {
    final wsProtocol = ApiConfig.httpsEnabled ? 'wss' : 'ws';
    return '$wsProtocol://${ApiConfig.host}:${ApiConfig.port}/api/v1/online/video?vid=$vid&clientId=$clientId';
  }

  /// 连接到视频房间
  Future<void> connect(int vid) async {
    // 如果已经连接到同一个视频，不重复连接
    if (_currentVid == vid && _channel != null && isConnected.value) {
      return;
    }

    // 先断开旧连接
    await disconnect();

    _currentVid = vid;
    _isManualClose = false;
    _reconnectAttempts = 0;

    await _initWebSocket();
  }

  /// 初始化 WebSocket 连接
  Future<void> _initWebSocket() async {
    if (_currentVid == null) return;

    try {
      final clientId = await _getClientId();
      final url = _getWebSocketUrl(_currentVid!, clientId);

      if (kDebugMode) {
        print('[WebSocket] 开始连接: $url');
      }

      _channel = WebSocketChannel.connect(Uri.parse(url));

      // 监听消息
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      // 标记连接成功
      isConnected.value = true;
      _reconnectAttempts = 0;
      _lastMessageTime = DateTime.now();

      if (kDebugMode) {
        print('[WebSocket] 连接成功');
      }

      // 启动心跳检测
      _startHeartbeat();

    } catch (e) {
      if (kDebugMode) {
        print('[WebSocket] 连接失败: $e');
      }
      isConnected.value = false;
      _scheduleReconnect();
    }
  }

  /// 处理收到的消息
  void _onMessage(dynamic data) {
    _lastMessageTime = DateTime.now();

    try {
      final json = jsonDecode(data as String);

      // 处理在线人数
      if (json['number'] != null) {
        final count = json['number'] as int;
        onlineCount.value = count;
        if (kDebugMode) {
          print('[WebSocket] 更新在线人数: $count');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[WebSocket] 解析消息失败: $e');
      }
    }
  }

  /// 处理错误
  void _onError(dynamic error) {
    if (kDebugMode) {
      print('[WebSocket] 连接错误: $error');
    }
    isConnected.value = false;
  }

  /// 连接关闭回调
  void _onDone() {
    if (kDebugMode) {
      print('[WebSocket] 连接关闭');
    }
    isConnected.value = false;
    _stopHeartbeat();

    // 非手动关闭时尝试重连
    if (!_isManualClose && _currentVid != null) {
      _scheduleReconnect();
    }
  }

  /// 启动心跳检测
  void _startHeartbeat() {
    _stopHeartbeat();

    // 每15秒检查一次连接状态
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_lastMessageTime != null) {
        final now = DateTime.now();
        // 如果超过45秒没收到消息，可能连接已断开，主动重连
        if (now.difference(_lastMessageTime!).inSeconds > 45) {
          if (kDebugMode) {
            print('[WebSocket] 心跳超时，主动重连');
          }
          _channel?.sink.close();
        }
      }
    });
  }

  /// 停止心跳检测
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 安排重连
  void _scheduleReconnect() {
    if (_isManualClose || _currentVid == null) return;

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (kDebugMode) {
        print('[WebSocket] 达到最大重连次数，停止重连');
      }
      return;
    }

    _reconnectTimer?.cancel();

    // 指数退避重连
    final delay = Duration(seconds: (_reconnectAttempts + 1) * 2);
    _reconnectAttempts++;

    if (kDebugMode) {
      print('[WebSocket] ${delay.inSeconds}秒后尝试第 $_reconnectAttempts 次重连');
    }

    _reconnectTimer = Timer(delay, () {
      if (!_isManualClose && _currentVid != null) {
        _initWebSocket();
      }
    });
  }

  /// 断开连接
  Future<void> disconnect() async {
    _isManualClose = true;
    _currentVid = null;

    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;

    onlineCount.value = 0;
    isConnected.value = false;

    if (kDebugMode) {
      print('[WebSocket] 已断开连接');
    }
  }

  /// 切换视频（先断开旧连接，再连接新视频）
  Future<void> switchVideo(int vid) async {
    if (_currentVid == vid && isConnected.value) {
      return; // 同一个视频，不需要重连
    }
    await connect(vid);
  }

  /// 销毁服务
  void dispose() {
    disconnect();
    onlineCount.dispose();
    isConnected.dispose();
  }
}
