import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/foundation.dart';

/// AudioService Handler - 处理后台播放
///
/// 使用 audio_service 插件实现跨平台后台播放
/// - Android: MediaSession + Notification
/// - iOS: MPNowPlayingInfoCenter + MPRemoteCommandCenter
/// - macOS/Web: 自动支持
class VideoAudioHandler extends BaseAudioHandler with SeekHandler {
  final Player player;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;

  VideoAudioHandler(this.player) {
    // 初始化播放状态
    _initPlaybackState();
    // 监听播放器状态变化
    _setupPlayerListeners();
  }

  /// 初始化播放状态
  void _initPlaybackState() {
    playbackState.add(PlaybackState(
      playing: false,
      controls: [
        MediaControl.rewind,
        MediaControl.play,
        MediaControl.fastForward,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      repeatMode: AudioServiceRepeatMode.none,
      shuffleMode: AudioServiceShuffleMode.none,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
    ));
  }

  /// 监听播放器状态变化，自动同步到 AudioService
  void _setupPlayerListeners() {
    // 监听播放状态
    _playingSubscription = player.stream.playing.listen((playing) {
      _updatePlaybackState(playing: playing);
    });

    // 监听播放位置
    _positionSubscription = player.stream.position.listen((position) {
      _updatePlaybackState(position: position);
    });

    // 监听总时长
    _durationSubscription = player.stream.duration.listen((duration) {
      if (mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });
  }

  /// 更新播放信息（显示在通知栏/锁屏）
  void setMediaItem({
    required String title,
    String? artist,
    Duration? duration,
    Uri? artUri,
  }) {
    mediaItem.add(MediaItem(
      id: 'video_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      artist: artist ?? '',
      duration: duration ?? player.state.duration,
      artUri: artUri,
    ));
    debugPrint('🎵 [AudioService] 设置媒体信息: $title');
  }

  /// 内部更新播放状态
  void _updatePlaybackState({
    bool? playing,
    Duration? position,
  }) {
    final currentPlaying = playing ?? player.state.playing;
    final currentPosition = position ?? player.state.position;

    playbackState.add(playbackState.value.copyWith(
      playing: currentPlaying,
      controls: [
        MediaControl.rewind,
        currentPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      updatePosition: currentPosition,
      processingState: AudioProcessingState.ready,
    ));
  }

  /// 公开的更新播放状态方法
  void updatePlaybackState({
    required bool playing,
    Duration? position,
  }) {
    _updatePlaybackState(playing: playing, position: position);
  }

  @override
  Future<void> play() async {
    debugPrint('🎵 [AudioService] Play command');
    await player.play();
  }

  @override
  Future<void> pause() async {
    debugPrint('🎵 [AudioService] Pause command');
    await player.pause();
  }

  @override
  Future<void> stop() async {
    debugPrint('🎵 [AudioService] Stop command');
    await player.pause();

    // 停止时发送idle状态，这会让通知栏消失
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));

    // 【关键】调用父类stop，停止前台服务和通知
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    debugPrint('🎵 [AudioService] Seek to $position');
    await player.seek(position);
  }

  @override
  Future<void> fastForward() async {
    debugPrint('🎵 [AudioService] Fast forward 10s');
    final newPos = player.state.position + const Duration(seconds: 10);
    final maxPos = player.state.duration;
    await player.seek(newPos > maxPos ? maxPos : newPos);
  }

  @override
  Future<void> rewind() async {
    debugPrint('🎵 [AudioService] Rewind 10s');
    final newPos = player.state.position - const Duration(seconds: 10);
    await player.seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  @override
  Future<void> skipToNext() async {
    debugPrint('🎵 [AudioService] Skip to next');
    // 由外部实现（如果有多P视频）
  }

  @override
  Future<void> skipToPrevious() async {
    debugPrint('🎵 [AudioService] Skip to previous');
    // 由外部实现（如果有多P视频）
  }

  /// 清理资源
  void dispose() {
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
  }
}
