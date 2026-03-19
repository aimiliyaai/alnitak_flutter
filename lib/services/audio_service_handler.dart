import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';
import 'logger_service.dart';

/// AudioService Handler - 处理后台播放（对齐 pili_plus 委托模式）
///
/// 通知栏 play/pause/seek 通过 onPlay/onPause/onSeek 委托给 Controller，
/// 由 Controller 统一管理 AudioSession.setActive，不在此处直接操作 Player。
class VideoAudioHandler extends BaseAudioHandler with SeekHandler {
  final LoggerService _logger = LoggerService.instance;
  Player? _player;
  int? _ownerId;
  Future<void> Function()? _onPlay;
  Future<void> Function()? _onPause;
  Future<void> Function(Duration position)? _onSeek;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _bufferSubscription;

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
        MediaAction.fastForward,
        MediaAction.rewind,
      },
    ));
  }

  /// 绑定播放器实例（对齐 pili_plus：通过回调委托给 Controller，由 Controller 管理 setActive）
  void attachPlayer(
    Player player, {
    required int ownerId,
    Future<void> Function()? onPlay,
    Future<void> Function()? onPause,
    Future<void> Function(Duration position)? onSeek,
  }) {
    if (_player == player) return;
    _disposeListeners();
    _player = player;
    _ownerId = ownerId;
    _onPlay = onPlay;
    _onPause = onPause;
    _onSeek = onSeek;
    _setupPlayerListeners();
    _logger.logDebug('[AudioService] Player 已绑定', tag: 'AudioService');
  }

  bool isAttachedToOwner(int ownerId) {
    return _player != null && _ownerId == ownerId;
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

    _bufferSubscription = _player!.stream.buffer.listen((buffer) {
      _updatePlaybackState(bufferedPosition: buffer);
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
    Duration? bufferedPosition,
  }) {
    if (_player == null) return;
    final currentPlaying = playing ?? _player!.state.playing;
    final currentPosition = position ?? _player!.state.position;
    final currentBuffered = bufferedPosition ?? _player!.state.buffer;

    playbackState.add(playbackState.value.copyWith(
      playing: currentPlaying,
      controls: [
        MediaControl.rewind,
        currentPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      updatePosition: currentPosition,
      bufferedPosition: currentBuffered,
      speed: 1.0,
      processingState: AudioProcessingState.ready,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.fastForward,
        MediaAction.rewind,
      },
    ));
  }

  @override
  Future<void> play() async {
    await (_onPlay?.call() ?? _player?.play() ?? Future.value());
  }

  @override
  Future<void> pause() async {
    await (_onPause?.call() ?? _player?.pause() ?? Future.value());
  }

  @override
  Future<void> stop() async {
    await (_onPause?.call() ?? _player?.pause() ?? Future.value());

    // 清除媒体信息（移除通知栏显示内容）
    mediaItem.add(null);

    // pili_plus 模式：无论当前什么状态，都先转 completed 再转 idle
    // 这样 AudioService 才会调用内部 _stop() 销毁通知栏
    if (playbackState.value.processingState != AudioProcessingState.completed) {
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

  Future<void> stopIfOwner(int ownerId) async {
    if (!isAttachedToOwner(ownerId)) return;
    await stop();
  }

  Future<void> _seekTo(Duration target) async {
    if (_onSeek != null) {
      await _onSeek!(target);
    } else {
      await _player?.seek(target);
    }
  }

  @override
  Future<void> seek(Duration position) async => _seekTo(position);

  @override
  Future<void> fastForward() async {
    if (_player == null) return;
    final newPos = _player!.state.position + const Duration(seconds: 10);
    final maxPos = _player!.state.duration;
    await _seekTo(newPos > maxPos ? maxPos : newPos);
  }

  @override
  Future<void> rewind() async {
    if (_player == null) return;
    final newPos = _player!.state.position - const Duration(seconds: 10);
    await _seekTo(newPos < Duration.zero ? Duration.zero : newPos);
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
    _bufferSubscription?.cancel();
    _playingSubscription = null;
    _positionSubscription = null;
    _durationSubscription = null;
    _bufferSubscription = null;
  }

  /// 解绑播放器并清除通知
  void detachPlayer() {
    _disposeListeners();
    _player = null;
    _ownerId = null;
    _onPlay = null;
    _onPause = null;
    _onSeek = null;
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

  void detachPlayerIfOwner(int ownerId) {
    if (!isAttachedToOwner(ownerId)) return;
    detachPlayer();
  }
}
