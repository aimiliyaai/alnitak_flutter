import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../controllers/video_player_controller.dart';
import '../../../controllers/danmaku_controller.dart';
import 'custom_player_ui.dart';

/// 全屏播放页：使用与 [MediaPlayerWidget] 相同的 controller，仅做全屏展示与退出。
/// 进入时隐藏系统 UI；根据视频画面比例决定横屏或竖屏（横屏视频只允许横屏，竖屏视频只允许竖屏），退出时恢复。
class FullscreenPlayerPage extends StatefulWidget {
  final VideoPlayerController controller;
  final String title;
  final DanmakuController? danmakuController;
  final ValueNotifier<int>? onlineCount;

  const FullscreenPlayerPage({
    super.key,
    required this.controller,
    this.title = '',
    this.danmakuController,
    this.onlineCount,
  });

  @override
  State<FullscreenPlayerPage> createState() => _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState extends State<FullscreenPlayerPage> {
  Timer? _orientationUpdateTimer;

  @override
  void initState() {
    super.initState();
    _setFullscreenUI(true);
    // 若进入时尚未拿到视频尺寸，延迟再试一次（首帧解码后会有 width/height）
    _orientationUpdateTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final w = widget.controller.player.state.width ?? 0;
      final h = widget.controller.player.state.height ?? 0;
      if (w > 0 && h > 0) _setFullscreenUI(true);
    });
  }

  @override
  void dispose() {
    _orientationUpdateTimer?.cancel();
    // 退出时已在 _exitFullscreen 中恢复过，此处兜底（如系统返回键）
    _setFullscreenUI(false);
    super.dispose();
  }

  void _setFullscreenUI(bool fullscreen) {
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      final w = widget.controller.player.state.width ?? 0;
      final h = widget.controller.player.state.height ?? 0;
      if (w > 0 && h > 0) {
        if (w >= h) {
          // 横屏或方形视频 → 仅允许横屏
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } else {
          // 竖屏视频 → 仅允许竖屏
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
        }
      } else {
        // 尚未拿到尺寸时允许所有方向，避免黑屏期锁错
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  void _exitFullscreen() {
    // 先恢复系统 UI（方向 + 状态栏），再 pop，使退出动画与界面状态同步、更丝滑
    _setFullscreenUI(false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!c.isPlayerInitialized.value) {
      return const ColoredBox(
        color: Colors.transparent,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: c.backgroundPlayEnabled,
            builder: (context, bgEnabled, _) {
              return Video(
                controller: c.videoController,
                pauseUponEnteringBackgroundMode: !bgEnabled,
              );
            },
          ),
          Positioned.fill(
            child: CustomPlayerUI(
              controller: c.videoController,
              logic: c,
              title: widget.title,
              onBack: _exitFullscreen,
              danmakuController: widget.danmakuController,
              onlineCount: widget.onlineCount,
              forceFullscreen: true,
              onFullscreenToggle: _exitFullscreen,
            ),
          ),
        ],
      ),
    );
  }
}
