import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../controllers/video_player_controller.dart';

/// 手势反馈数据（不可变，用于 ValueNotifier 驱动局部重建）
class GestureFeedback {
  final IconData icon;
  final String text;
  final double? value;

  const GestureFeedback({required this.icon, required this.text, this.value});
}

/// 播放器手势处理 mixin
///
/// 从 CustomPlayerUI 中提取，负责：
/// - 垂直拖拽：音量（右侧）& 亮度（左侧）
/// - 水平拖拽：进度调节
/// - 长按：2.0x 加速
/// - 双击：±10s / 播放暂停
/// - 设置持久化（音量、亮度）
mixin PlayerGestureHandler<T extends StatefulWidget> on State<T> {
  static const String _volumeKey = 'player_volume';
  static const String _brightnessKey = 'player_brightness';

  // ============ 子类需提供的依赖 ============
  Player get gesturePlayer;
  VideoPlayerController get gestureLogic;
  bool get isLocked;

  // ============ 手势反馈 ============
  final ValueNotifier<GestureFeedback?> gestureFeedback = ValueNotifier(null);
  final ValueNotifier<bool> isLongPressing = ValueNotifier(false);

  // ============ 拖拽状态 ============
  Offset _dragStartPos = Offset.zero;
  int _gestureType = 0; // 0=idle, 1=volume, 2=brightness, 3=seek

  double playerBrightness = 1.0;
  double _startVolumeSnapshot = 1.0;
  double _startBrightnessSnapshot = 1.0;
  Duration _seekPos = Duration.zero;

  // ============ 长按状态 ============
  double _normalSpeed = 1.0;

  // ============ 设置持久化 ============
  SharedPreferences? _gesturePrefs;

  /// 加载保存的音量和亮度设置
  Future<void> loadGestureSettings() async {
    try {
      _gesturePrefs ??= await SharedPreferences.getInstance();
      final savedVolume = _gesturePrefs!.getDouble(_volumeKey) ?? 100.0;
      gesturePlayer.setVolume(savedVolume);
      final savedBrightness = _gesturePrefs!.getDouble(_brightnessKey) ?? 1.0;
      setState(() {
        playerBrightness = savedBrightness;
      });
    } catch (e) {
      // 加载播放器设置失败
    }
  }

  Future<void> _saveVolume(double volume) async {
    try {
      _gesturePrefs ??= await SharedPreferences.getInstance();
      await _gesturePrefs!.setDouble(_volumeKey, volume);
    } catch (e) {
      // 保存音量设置失败
    }
  }

  Future<void> _saveBrightness(double brightness) async {
    try {
      _gesturePrefs ??= await SharedPreferences.getInstance();
      await _gesturePrefs!.setDouble(_brightnessKey, brightness);
    } catch (e) {
      // 保存亮度设置失败
    }
  }

  void disposeGesture() {
    gestureFeedback.dispose();
    isLongPressing.dispose();
  }

  // ============ 拖拽手势 ============

  void onDragStart(DragStartDetails details, double width) {
    if (isLocked) return;
    _dragStartPos = details.localPosition;
    onGestureDragStarted();
    _startVolumeSnapshot = gesturePlayer.state.volume / 100.0;
    _startBrightnessSnapshot = playerBrightness;
  }

  /// 子类实现：拖拽开始时隐藏控制UI
  void onGestureDragStarted();

  void onDragUpdate(DragUpdateDetails details, double width) {
    if (isLocked) return;
    final delta = details.localPosition - _dragStartPos;

    if (_gestureType == 0 && delta.distance < 10) return;

    if (_gestureType == 0) {
      if (delta.dx.abs() > delta.dy.abs()) {
        _gestureType = 3;
      } else {
        _gestureType = _dragStartPos.dx < width / 2 ? 2 : 1;
      }
    }

    const double sensitivity = 600.0;

    if (_gestureType == 1) {
      final val = (_startVolumeSnapshot - delta.dy / sensitivity).clamp(0.0, 1.0);
      final volumePercent = val * 100;
      gesturePlayer.setVolume(volumePercent);
      _showFeedback(Icons.volume_up, '音量 ${volumePercent.toInt()}%', val);
    } else if (_gestureType == 2) {
      final val = (_startBrightnessSnapshot - delta.dy / 1200).clamp(0.0, 1.0);
      playerBrightness = val;
      setState(() {});
      _showFeedback(Icons.brightness_medium, '亮度 ${(val * 100).toInt()}%', val);
    } else if (_gestureType == 3) {
      final total = gesturePlayer.state.duration.inSeconds;
      final current = gesturePlayer.state.position.inSeconds;
      final seekDelta = (delta.dx / width) * 90;
      final target = (current + seekDelta).clamp(0, total);
      _seekPos = Duration(seconds: target.toInt());
      final diff = _seekPos.inSeconds - current;
      final sign = diff > 0 ? '+' : '';
      _showFeedback(
        diff > 0 ? Icons.fast_forward : Icons.fast_rewind,
        '${formatDuration(_seekPos)} / ${formatDuration(gesturePlayer.state.duration)}\n($sign$diff秒)',
        null,
      );
    }
  }

  void onDragEnd() {
    if (_gestureType == 3) {
      gestureLogic.seek(_seekPos);
    } else if (_gestureType == 1) {
      _saveVolume(gesturePlayer.state.volume);
    } else if (_gestureType == 2) {
      _saveBrightness(playerBrightness);
    }
    _gestureType = 0;

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) gestureFeedback.value = null;
    });
  }

  // ============ 长按手势 ============

  void onLongPressStart() {
    if (isLocked) return;
    isLongPressing.value = true;
    _normalSpeed = gesturePlayer.state.rate;
    gesturePlayer.setRate(2.0);
  }

  void onLongPressEnd() {
    if (!isLongPressing.value) return;
    isLongPressing.value = false;
    gesturePlayer.setRate(_normalSpeed);
    gestureFeedback.value = null;
  }

  // ============ 双击手势 ============

  void onDoubleTap(Offset pos, double width) {
    if (isLocked) return;
    final leftZone = width * 0.3;
    final rightZone = width * 0.7;

    if (pos.dx < leftZone) {
      seekRelative(-10, Icons.fast_rewind, '-10秒');
    } else if (pos.dx > rightZone) {
      seekRelative(10, Icons.fast_forward, '+10秒');
    } else {
      if (gesturePlayer.state.playing) {
        gestureLogic.pause();
      } else {
        gestureLogic.play();
      }
      onDoubleTapCenter();
    }
  }

  /// 子类实现：双击中部时切换控制UI
  void onDoubleTapCenter();

  void seekRelative(int seconds, IconData icon, String label) {
    final currentPos = gesturePlayer.state.position;
    final maxPos = gesturePlayer.state.duration;
    final newPos = currentPos + Duration(seconds: seconds);
    final clampedPos = Duration(
      milliseconds: newPos.inMilliseconds.clamp(0, maxPos.inMilliseconds),
    );
    gestureLogic.seek(clampedPos);
    _showFeedback(icon, label, null);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) gestureFeedback.value = null;
    });
  }

  // ============ 工具方法 ============

  void _showFeedback(IconData icon, String text, double? value) {
    gestureFeedback.value = GestureFeedback(icon: icon, text: text, value: value);
  }

  String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
