import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../../controllers/video_player_controller.dart';
import '../../../controllers/danmaku_controller.dart';
import 'player_quality_panel.dart';

/// 播放器底栏控制按钮行
///
/// 从 CustomPlayerUI._buildControlButtonsRow() 提取，包含：
/// 播放/暂停、弹幕控制、弹幕发送、倍速、清晰度、后台播放、循环、全屏
class PlayerControlButtons extends StatelessWidget {
  final Player player;
  final VideoPlayerController logic;
  final DanmakuController? danmakuController;
  final bool fullscreen;

  // 状态
  final bool showDanmakuSettings;
  final bool showDanmakuInput;
  final double currentSpeed;

  // 回调
  final VoidCallback onPlayPause;
  final VoidCallback onToggleDanmakuSettings;
  final VoidCallback onToggleDanmakuInput;
  final VoidCallback onToggleSpeedPanel;
  final VoidCallback onToggleQualityPanel;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onInteraction;
  final GlobalKey qualityButtonKey;
  final GlobalKey speedButtonKey;

  const PlayerControlButtons({
    super.key,
    required this.player,
    required this.logic,
    this.danmakuController,
    required this.fullscreen,
    required this.showDanmakuSettings,
    required this.showDanmakuInput,
    required this.currentSpeed,
    required this.onPlayPause,
    required this.onToggleDanmakuSettings,
    required this.onToggleDanmakuInput,
    required this.onToggleSpeedPanel,
    required this.onToggleQualityPanel,
    required this.onToggleFullscreen,
    required this.onInteraction,
    required this.qualityButtonKey,
    required this.speedButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 播放/暂停按钮
        StreamBuilder<bool>(
          stream: player.stream.playing,
          builder: (context, snapshot) {
            final playing = snapshot.data ?? player.state.playing;
            return IconButton(
              icon: Icon(
                playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: fullscreen ? 24 : 22,
              ),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: fullscreen ? 36 : 32, minHeight: 32),
              onPressed: () {
                onPlayPause();
                onInteraction();
              },
            );
          },
        ),

        // 弹幕控制按钮
        if (danmakuController != null)
          _DanmakuButtons(
            danmakuController: danmakuController!,
            fullscreen: fullscreen,
            showDanmakuSettings: showDanmakuSettings,
            showDanmakuInput: showDanmakuInput,
            onToggleVisibility: onInteraction,
            onToggleSettings: onToggleDanmakuSettings,
            onToggleInput: onToggleDanmakuInput,
          ),

        const Spacer(),

        // 倍速选择
        TextButton(
          key: speedButtonKey,
          onPressed: onToggleSpeedPanel,
          style: TextButton.styleFrom(
            foregroundColor: currentSpeed != 1.0 ? Colors.blue : Colors.white,
            padding: EdgeInsets.symmetric(horizontal: fullscreen ? 8 : 4, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            currentSpeed == 1.0 ? '倍速' : '${currentSpeed}x',
            style: TextStyle(fontSize: fullscreen ? 13 : 12),
          ),
        ),

        // 清晰度选择
        ValueListenableBuilder<List<String>>(
          valueListenable: logic.availableQualities,
          builder: (context, qualities, _) {
            if (qualities.length <= 1) return const SizedBox.shrink();

            return ValueListenableBuilder<String?>(
              valueListenable: logic.currentQuality,
              builder: (context, currentQuality, _) {
                final qualityDisplayName = currentQuality != null
                    ? logic.getQualityDisplayName(currentQuality)
                    : '画质';
                return TextButton(
                  key: qualityButtonKey,
                  onPressed: onToggleQualityPanel,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: fullscreen ? 8 : 4, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: PlayerQualityPanel.buildQualityLabel(qualityDisplayName, false),
                );
              },
            );
          },
        ),

        // 后台播放按钮（全屏时显示）
        if (fullscreen)
          ValueListenableBuilder<bool>(
            valueListenable: logic.backgroundPlayEnabled,
            builder: (context, bgEnabled, _) {
              return IconButton(
                icon: Icon(
                  bgEnabled ? Icons.headphones : Icons.headphones_outlined,
                  color: bgEnabled ? Colors.blue : Colors.white,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: bgEnabled ? '后台播放：开' : '后台播放：关',
                onPressed: () {
                  logic.toggleBackgroundPlay();
                  onInteraction();
                },
              );
            },
          ),

        // 循环模式按钮（全屏时显示）
        if (fullscreen)
          ValueListenableBuilder(
            valueListenable: logic.loopMode,
            builder: (context, loopMode, _) {
              return IconButton(
                icon: Icon(
                  loopMode.index == 1 ? Icons.repeat_one : Icons.repeat,
                  color: loopMode.index == 1 ? Colors.blue : Colors.white,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  logic.toggleLoopMode();
                  onInteraction();
                },
              );
            },
          ),

        // 全屏按钮
        IconButton(
          icon: Icon(
            fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            color: Colors.white,
            size: fullscreen ? 24 : 22,
          ),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: fullscreen ? 36 : 32, minHeight: 32),
          onPressed: onToggleFullscreen,
        ),
      ],
    );
  }
}

/// 弹幕控制按钮组（开关 + 设置 + 发送）
class _DanmakuButtons extends StatelessWidget {
  final DanmakuController danmakuController;
  final bool fullscreen;
  final bool showDanmakuSettings;
  final bool showDanmakuInput;
  final VoidCallback onToggleVisibility;
  final VoidCallback onToggleSettings;
  final VoidCallback onToggleInput;

  const _DanmakuButtons({
    required this.danmakuController,
    required this.fullscreen,
    required this.showDanmakuSettings,
    required this.showDanmakuInput,
    required this.onToggleVisibility,
    required this.onToggleSettings,
    required this.onToggleInput,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: danmakuController,
      builder: (context, _) {
        final isVisible = danmakuController.isVisible;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 弹幕开关
            GestureDetector(
              onTap: () {
                danmakuController.toggleVisibility();
                onToggleVisibility();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isVisible
                      ? Colors.blue.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isVisible ? Colors.blue : Colors.white54,
                    width: 1,
                  ),
                ),
                child: Text(
                  '弹',
                  style: TextStyle(
                    color: isVisible ? Colors.blue : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // 弹幕设置
            IconButton(
              icon: Icon(
                Icons.tune,
                color: showDanmakuSettings ? Colors.blue : Colors.white,
                size: fullscreen ? 20 : 18,
              ),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: fullscreen ? 32 : 28, minHeight: 28),
              onPressed: onToggleSettings,
            ),
            // 弹幕发送按钮（全屏时显示）
            if (fullscreen)
              GestureDetector(
                onTap: onToggleInput,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: showDanmakuInput
                        ? Colors.blue.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: showDanmakuInput ? Colors.blue : Colors.white54,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '发弹幕',
                    style: TextStyle(
                      color: showDanmakuInput ? Colors.blue : Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
