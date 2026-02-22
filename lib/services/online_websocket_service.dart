import 'dart:async' show StreamSubscription, Timer;
import 'dart:convert';
import 'dart:io' show WebSocket;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

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

  int? _currentVid;
  String? _clientId;

  /// 在线人数，播放器 UI 直接监听此 ValueNotifier
  final ValueNotifier<int> onlineCount = ValueNotifier<int>(0);

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
  String _buildUrl(int vid, String clientId) {
    final protocol = ApiConfig.httpsEnabled ? 'wss' : 'ws';
    return '$protocol://${ApiConfig.host}:${ApiConfig.port}'
        '/api/v1/online/video?vid=$vid&clientId=$clientId';
  }

  /// 连接到指定视频房间
  Future<void> connect(int vid) async {
    if (_currentVid == vid && _channel != null) return;

    _cleanup();

    _currentVid = vid;
    _isManualClose = false;
    _reconnectAttempts = 0;

    await _doConnect();
  }

  /// 切换视频房间
  Future<void> switchVideo(int vid) async {
    if (_currentVid == vid && _channel != null) return;
    await connect(vid);
  }

  /// 执行 WebSocket 连接
  Future<void> _doConnect() async {
    if (_currentVid == null || _isManualClose) return;

    try {
      final clientId = await _getClientId();
      final url = _buildUrl(_currentVid!, clientId);

      if (kDebugMode) {
        print('[OnlineWS] 开始连接: $url');
      }

      // 使用 IOWebSocketChannel 以获得更好的移动平台支持
      // 先建立原生 WebSocket 连接，然后包装为 channel
      final webSocket = await WebSocket.connect(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('WebSocket 连接超时');
        },
      );

      if (kDebugMode) {
        print('[OnlineWS] 原生 WebSocket 连接成功');
      }

      // 连接建立后检查是否已被取消
      if (_isManualClose || _currentVid == null) {
        webSocket.close();
        return;
      }

      final channel = IOWebSocketChannel(webSocket);
      _channel = channel;
      _lastMessageTime = DateTime.now();
      _reconnectAttempts = 0;

      if (kDebugMode) {
        print('[OnlineWS] 开始监听消息流');
      }

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _startHeartbeat();

      if (kDebugMode) {
        print('[OnlineWS] WebSocket 已启动，等待服务器消息');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[OnlineWS] 连接失败: $e');
      }
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    _lastMessageTime = DateTime.now();
    if (kDebugMode) {
      print('[OnlineWS] 收到消息: $data');
    }
    try {
      final json = jsonDecode(data as String);
      // 后端返回 {"number": N}
      if (json['number'] != null) {
        final count = json['number'] as int;
        onlineCount.value = count;
        if (kDebugMode) {
          print('[OnlineWS] 在线人数更新: $count');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[OnlineWS] 解析消息失败: $e, 原始数据: $data');
      }
    }
  }

  void _onError(dynamic error) {
    if (kDebugMode) {
      print('[OnlineWS] 错误: $error');
    }
  }

  void _onDone() {
    if (kDebugMode) {
      print('[OnlineWS] 连接关闭');
    }
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
        if (kDebugMode) {
          print('[OnlineWS] 心跳超时，主动断开');
        }
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
      if (kDebugMode) {
        print('[OnlineWS] 达到最大重连次数');
      }
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delay = Duration(
      milliseconds: (1000 * _reconnectAttempts).clamp(1000, 10000),
    );

    if (kDebugMode) {
      print('[OnlineWS] ${delay.inSeconds}s 后第 $_reconnectAttempts 次重连');
    }

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
    if (kDebugMode) {
      print('[OnlineWS] 后台暂停');
    }
  }

  /// 前台恢复：重新连接之前的 vid
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    if (_currentVid != null && !_isManualClose) {
      _reconnectAttempts = 0;
      _doConnect();
      if (kDebugMode) {
        print('[OnlineWS] 前台恢复, vid=$_currentVid');
      }
    }
  }

  /// 断开连接
  void disconnect() {
    _isManualClose = true;
    _isPaused = false;
    _currentVid = null;
    _cleanup();
  }

  /// 销毁服务
  void dispose() {
    disconnect();
    onlineCount.dispose();
  }
}
