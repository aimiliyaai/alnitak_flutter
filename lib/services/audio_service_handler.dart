import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/foundation.dart';

/// AudioService Handler - 处理后台播放
///
/// 使用 audio_service 插件实现跨平台后台播放
/// - Android: MediaSession + Notification
/// - iOS: MPNowPlayingInfoCenter + MPRemoteCommandCenter
/// - macOS/Web: 自动支持
class VideoAudioHandler extends BaseAudioHandler {
  final Player player;

  VideoAudioHandler(this.player) {
    // 初始化播放状态
    playbackState.add(PlaybackState(
      playing: false,
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.pause,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 3],
      processingState: AudioProcessingState.idle,
      repeatMode: AudioServiceRepeatMode.none,
      shuffleMode: AudioServiceShuffleMode.none,
    ));
  }

  /// 更新播放信息（显示在通知栏/锁屏）
  void setMediaItem({
    required String title,
    String? artist,
    Duration? duration,
  }) {
    mediaItem.add(MediaItem(
      id: 'video_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      artist: artist ?? '',
      duration: duration ?? Duration.zero,
      artUri: null, // 可以添加视频封面 URI
    ));
  }

  /// 更新播放状态
  void updatePlaybackState({
    required bool playing,
    Duration? position,
  }) {
    playbackState.add(playbackState.value.copyWith(
      playing: playing,
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      updatePosition: position ?? player.state.position,
      processingState: playing
          ? AudioProcessingState.ready
          : AudioProcessingState.ready,
    ));
  }

  @override
  Future<void> play() async {
    debugPrint('🎵 [AudioService] Play command');
    player.play();
    updatePlaybackState(playing: true);
  }

  @override
  Future<void> pause() async {
    debugPrint('🎵 [AudioService] Pause command');
    player.pause();
    updatePlaybackState(playing: false);
  }

  @override
  Future<void> stop() async {
    debugPrint('🎵 [AudioService] Stop command');
    player.pause();
    updatePlaybackState(playing: false);
  }

  @override
  Future<void> seek(Duration position) async {
    debugPrint('🎵 [AudioService] Seek to $position');
    player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    debugPrint('🎵 [AudioService] Skip to next');
    // TODO: 实现播放下一个视频
  }

  @override
  Future<void> skipToPrevious() async {
    debugPrint('🎵 [AudioService] Skip to previous');
    // TODO: 实现播放上一个视频
  }
}
