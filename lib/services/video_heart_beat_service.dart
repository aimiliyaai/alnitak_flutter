import 'dart:async';
import 'history_service.dart';
import 'logger_service.dart';

class VideoHeartBeatService {
  static final VideoHeartBeatService _instance = VideoHeartBeatService._internal();
  factory VideoHeartBeatService() => _instance;
  VideoHeartBeatService._internal();

  final LoggerService _logger = LoggerService.instance;
  final HistoryService _historyService = HistoryService();

  Timer? _heartBeatTimer;
  int _lastReportedProgress = 0;
  int _currentVid = 0;
  int _currentPart = 1;
  int _currentDuration = 0;
  bool _enableHeart = true;

  static const int _heartBeatInterval = 5;

  void startHeartBeat({
    required int vid,
    required int part,
    required int duration,
    bool enableHeart = true,
  }) {
    if (!enableHeart) {
      _logger.logDebug('[HeartBeat] 心跳已禁用', tag: 'VideoHeartBeat');
      return;
    }

    _currentVid = vid;
    _currentPart = part;
    _currentDuration = duration;
    _enableHeart = enableHeart;
    _lastReportedProgress = 0;

    _stopHeartBeat();
    _heartBeatTimer = Timer.periodic(
      const Duration(seconds: _heartBeatInterval),
      _onHeartBeatTick,
    );

    _logger.logDebug('[HeartBeat] 启动: vid=$vid, part=$part, duration=$duration', tag: 'VideoHeartBeat');
  }

  void _onHeartBeatTick(Timer timer) {
    if (!_enableHeart || _currentVid == 0) {
      return;
    }
    _reportProgress(_lastReportedProgress);
  }

  Future<void> _reportProgress(int progress) async {
    if (_currentVid == 0) return;

    final success = await _historyService.addHistory(
      vid: _currentVid,
      part: _currentPart,
      time: progress.toDouble(),
      duration: _currentDuration,
    );

    if (success) {
      _lastReportedProgress = progress;
      _logger.logDebug('[HeartBeat] 上报成功: progress=${progress}s', tag: 'VideoHeartBeat');
    }
  }

  void onPlaying({
    required int progress,
  }) {
    if (!_enableHeart || _currentVid == 0) return;
    if (progress - _lastReportedProgress >= _heartBeatInterval) {
      _reportProgress(progress);
    }
  }

  Future<void> onPaused({
    required int progress,
  }) async {
    if (!_enableHeart || _currentVid == 0) return;
    await _reportProgress(progress);
    _stopHeartBeat();
  }

  Future<void> onCompleted({
    required int duration,
  }) async {
    if (!_enableHeart || _currentVid == 0) return;
    await _historyService.addHistory(
      vid: _currentVid,
      part: _currentPart,
      time: -1,
      duration: duration,
    );
    _logger.logDebug('[HeartBeat] 播放完成，上报-1', tag: 'VideoHeartBeat');
    _stopHeartBeat();
    _resetState();
  }

  void _resetState() {
    _currentVid = 0;
    _currentPart = 1;
    _currentDuration = 0;
    _lastReportedProgress = 0;
  }

  void _stopHeartBeat() {
    _heartBeatTimer?.cancel();
    _heartBeatTimer = null;
  }

  void stopHeartBeat() {
    _stopHeartBeat();
    _resetState();
    _logger.logDebug('[HeartBeat] 已停止', tag: 'VideoHeartBeat');
  }

  void updateDuration(int duration) {
    _currentDuration = duration;
  }
}
