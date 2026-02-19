import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';
import 'logger_service.dart';

/// AudioService Handler - 处理后台播放
///
/// 使用 audio_service 插件实现跨平台后台播放
/// - Android: MediaSession + Notification
/// - iOS: MPNowPlayingInfoCenter + MPRemoteCommandCenter
/// - macOS/Web: 自动支持
class VideoAudioHandler extends BaseAudioHandler with SeekHandler {
  final LoggerService _logger = LoggerService.instance;
  Player? _player;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;

  VideoAudioHandler() {
    _initPlaybackState();
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
      processingState: AudioProcessingState.idle,
      repeatMode: AudioServiceRepeatMode.none,
      shuffleMode: AudioServiceShuffleMode.none,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
    ));
  }

  /// 绑定播放器实例（Player 延迟创建，绑定后才开始监听）
  void attachPlayer(Player player) {
    if (_player == player) return;
    _disposeListeners();
    _player = player;
    _setupPlayerListeners();
    _logger.logDebug('[AudioService] Player 已绑定', tag: 'AudioService');
  }

  /// 监听播放器状态变化，自动同步到 AudioService
  void _setupPlayerListeners() {
    if (_player == null) return;

    _playingSubscription = _player!.stream.playing.listen((playing) {
      _updatePlaybackState(playing: playing);
    });

    _positionSubscription = _player!.stream.position.listen((position) {
      _updatePlaybackState(position: position);
    });

    _durationSubscription = _player!.stream.duration.listen((duration) {
      if (mediaItem.value != null && duration > Duration.zero) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });
  }

  /// 更新播放信息（显示在通知栏/锁屏）
  void setMediaItem({
    required String id,
    required String title,
    String? artist,
    Duration? duration,
    Uri? artUri,
  }) {
    mediaItem.add(MediaItem(
      id: id,
      title: title,
      artist: artist ?? '',
      duration: duration ?? _player?.state.duration ?? Duration.zero,
      artUri: artUri,
    ));
    _logger.logDebug('[AudioService] 设置媒体信息: $title', tag: 'AudioService');
  }

  /// 内部更新播放状态
  void _updatePlaybackState({
    bool? playing,
    Duration? position,
  }) {
    if (_player == null) return;
    final currentPlaying = playing ?? _player!.state.playing;
    final currentPosition = position ?? _player!.state.position;

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

  @override
  Future<void> play() async {
    await _player?.play();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> stop() async {
    await _player?.pause();

    // 清除媒体信息（移除通知栏显示内容）
    mediaItem.add(null);

    // pili_plus 模式：先转 completed 再转 idle，触发 AudioService 内部 _stop()
    // AudioService 源码中仅在 idle 且 previousState != idle 时调用 _stop() 清理通知
    if (playbackState.value.processingState == AudioProcessingState.idle) {
      playbackState.add(PlaybackState(
        processingState: AudioProcessingState.completed,
        playing: false,
      ));
    }
    playbackState.add(PlaybackState(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));

    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> fastForward() async {
    if (_player == null) return;
    final newPos = _player!.state.position + const Duration(seconds: 10);
    final maxPos = _player!.state.duration;
    await _player!.seek(newPos > maxPos ? maxPos : newPos);
  }

  @override
  Future<void> rewind() async {
    if (_player == null) return;
    final newPos = _player!.state.position - const Duration(seconds: 10);
    await _player!.seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  @override
  Future<void> skipToNext() async {}

  @override
  Future<void> skipToPrevious() async {}

  /// 清理监听器
  void _disposeListeners() {
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription = null;
    _positionSubscription = null;
    _durationSubscription = null;
  }

  /// 解绑播放器并清除通知
  void detachPlayer() {
    _disposeListeners();
    _player = null;
    // 清除媒体信息
    mediaItem.add(null);
    // pili_plus 模式：completed → idle 触发 AudioService 清理通知
    if (playbackState.value.processingState == AudioProcessingState.idle) {
      playbackState.add(PlaybackState(
        processingState: AudioProcessingState.completed,
        playing: false,
      ));
    }
    playbackState.add(PlaybackState(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }
}
