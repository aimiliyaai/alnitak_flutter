import 'package:flutter/material.dart';
import 'media_progress_slider.dart';

/// 播放器底部控制栏
/// 包含播放/暂停、进度条、清晰度切换、倍速、全屏等控制
class PlayerBottomBar extends StatelessWidget {
  final bool isPlaying;
  final bool isFullscreen;
  final Duration currentPosition;
  final Duration totalDuration;
  final Duration bufferedPosition;
  final VoidCallback? onPlayPause;
  final VoidCallback? onFullscreen;
  final ValueChanged<Duration>? onSeek;
  final ValueChanged<Duration>? onSeekEnd;
  final String? currentQuality;
  final List<String>? availableQualities;
  final ValueChanged<String>? onQualityChanged;
  final double playbackSpeed;
  final ValueChanged<double>? onSpeedChanged;

  const PlayerBottomBar({
    super.key,
    required this.isPlaying,
    required this.isFullscreen,
    required this.currentPosition,
    required this.totalDuration,
    required this.bufferedPosition,
    this.onPlayPause,
    this.onFullscreen,
    this.onSeek,
    this.onSeekEnd,
    this.currentQuality,
    this.availableQualities,
    this.onQualityChanged,
    required this.playbackSpeed,
    this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条和时间
          Row(
            children: [
              // 当前时间
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: MediaProgressIndicatorText(
                  currentPosition: currentPosition,
                  totalDuration: totalDuration,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 进度条
          MediaProgressSlider(
            currentPosition: currentPosition,
            totalDuration: totalDuration,
            bufferedPosition: bufferedPosition,
            onChanged: (position) => onSeek?.call(position),
            onChangeEnd: (position) => onSeekEnd?.call(position),
          ),
          const SizedBox(height: 8),
          // 控制按钮行
          Row(
            children: [
              // 播放/暂停按钮
              IconButton(
                onPressed: onPlayPause,
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                iconSize: 32,
              ),
              const Spacer(),
              // 清晰度切换
              if (availableQualities != null && availableQualities!.length > 1)
                _buildQualityButton(context),
              // 倍速按钮
              _buildSpeedButton(context),
              const SizedBox(width: 8),
              // 全屏按钮
              IconButton(
                onPressed: onFullscreen,
                icon: Icon(
                  isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white,
                ),
                iconSize: 28,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQualityButton(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: currentQuality,
      onSelected: (value) => onQualityChanged?.call(value),
      offset: const Offset(0, -100),
      color: Colors.black87,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          currentQuality ?? '画质',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
          ),
        ),
      ),
      itemBuilder: (context) {
        return availableQualities!.map((quality) {
          return PopupMenuItem<String>(
            value: quality,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quality == currentQuality)
                  const Icon(Icons.check, color: Colors.blue, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(
                  quality,
                  style: TextStyle(
                    color: quality == currentQuality ? Colors.blue : Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
    );
  }

  Widget _buildSpeedButton(BuildContext context) {
    final speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

    return PopupMenuButton<double>(
      initialValue: playbackSpeed,
      onSelected: (value) => onSpeedChanged?.call(value),
      offset: const Offset(0, -200),
      color: Colors.black87,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          playbackSpeed == 1.0 ? '倍速' : '${playbackSpeed}x',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
          ),
        ),
      ),
      itemBuilder: (context) {
        return speedOptions.map((speed) {
          return PopupMenuItem<double>(
            value: speed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (speed == playbackSpeed)
                  const Icon(Icons.check, color: Colors.blue, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(
                  '${speed}x',
                  style: TextStyle(
                    color: speed == playbackSpeed ? Colors.blue : Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
    );
  }
}
