import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/hls_service.dart';
import '../services/history_service.dart';
import '../services/logger_service.dart';
import '../models/loop_mode.dart';
import '../utils/wakelock_manager.dart';
import '../utils/error_handler.dart';
import '../utils/quality_utils.dart';

class VideoPlayerController extends ChangeNotifier {
  final HlsService _hlsService = HlsService();
  final LoggerService _logger = LoggerService.instance;
  late final Player player;
  late final VideoController videoController;

  final ValueNotifier<List<String>> availableQualities = ValueNotifier([]);
  final ValueNotifier<String?> currentQuality = ValueNotifier(null);
  final ValueNotifier<bool> isLoading = ValueNotifier(true);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<bool> isPlayerInitialized = ValueNotifier(false);
  final ValueNotifier<bool> isSwitchingQuality = ValueNotifier(false);
  final ValueNotifier<LoopMode> loopMode = ValueNotifier(LoopMode.off);
  final ValueNotifier<bool> backgroundPlayEnabled = ValueNotifier(false);
  final ValueNotifier<bool> isBuffering = ValueNotifier(false);

  final StreamController<Duration> _positionStreamController = StreamController.broadcast();
  Stream<Duration> get positionStream => _positionStreamController.stream;

  int? _currentResourceId;
  bool _isDisposed = false;
  bool _hasTriggeredCompletion = false;
  bool _isInitializing = false;
  bool _hasPlaybackStarted = false;

  Duration _userIntendedPosition = Duration.zero;
  double? _pendingSeekPosition;
  double? _validationTargetPosition;
  bool _userManuallySeeked = false;
  Timer? _progressValidationTimer;
  bool _isSeeking = false;
  String _currentLoadId = '';
  int? _lastProgressFetchTime;

  Timer? _qualityDebounceTimer;
  int _qualityEpoch = 0;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Timer? _stalledTimer;
  final Map<String, MediaSource> _qualityCache = {};
  Duration _lastReportedPosition = Duration.zero;
  bool _useDash = false;

  static const String _preferredQualityKey = 'preferred_video_quality_display_name';
  static const String _loopModeKey = 'video_loop_mode';
  static const String _backgroundPlayKey = 'background_play_enabled';

  VoidCallback? onVideoEnd;
  Function(Duration position, Duration totalDuration)? onProgressUpdate;
  Function(String quality)? onQualityChanged;
  Function(bool playing)? onPlayingStateChanged;

  int? _currentVid;
  int _currentPart = 1;

  VideoPlayerController() {
    player = Player(
      configuration: const PlayerConfiguration(
        title: '',
        bufferSize: 32 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );

    videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    _setupListeners();
  }

  Future<void> initialize({
    required int resourceId,
    double? initialPosition,
  }) async {
    if (_isInitializing) {
      
      return;
    }
    _isInitializing = true;

    try {
      _qualityCache.clear();
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;
      _userIntendedPosition = Duration(seconds: initialPosition?.toInt() ?? 0);
      _hasPlaybackStarted = false;

      await _loadSettings();

      final qualityInfo = await _hlsService.getQualityInfo(resourceId);
      if (qualityInfo.qualities.isEmpty) throw Exception('没有可用的清晰度');

      _useDash = HlsService.shouldUseDash() && qualityInfo.supportsDash;
      

      await _configurePlayer();

      availableQualities.value = _sortQualities(qualityInfo.qualities);
      currentQuality.value = await _getPreferredQuality(availableQualities.value);

      if (backgroundPlayEnabled.value) {
        _ensureAudioServiceReady().catchError((_) {});
      }

      await _loadVideo(currentQuality.value!, initialPosition: initialPosition);
    } catch (e) {
      _logger.logError(message: '初始化失败', error: e, stackTrace: StackTrace.current);
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> initializeWithPreloadedData({
    required int resourceId,
    required List<String> qualities,
    required String selectedQuality,
    required MediaSource mediaSource,
    double? initialPosition,
  }) async {
    final loadId = '${DateTime.now().millisecondsSinceEpoch}_${resourceId}_${initialPosition?.toInt() ?? 0}';
    _currentLoadId = loadId;

    

    if (isPlayerInitialized.value && _currentResourceId == resourceId && errorMessage.value == null) {
      final currentPosition = _userIntendedPosition.inSeconds;
      final newPosition = initialPosition?.toInt() ?? 0;
      if (currentPosition == newPosition || newPosition == 0) {
        
        _currentLoadId = '';
        return;
      }
      
      isPlayerInitialized.value = false;
    }

    isPlayerInitialized.value = false;

    try {
      _qualityCache.clear();
      _currentResourceId = resourceId;
      isLoading.value = true;
      errorMessage.value = null;
      _userIntendedPosition = Duration(seconds: initialPosition?.toInt() ?? 0);
      _hasPlaybackStarted = false;

      _useDash = mediaSource.isDirectUrl && mediaSource.videoSegmentBase != null;
      

      await Future.wait([
        _configurePlayer(),
        _loadSettings(),
      ]);

      availableQualities.value = _sortQualities(qualities);
      currentQuality.value = selectedQuality;

      if (backgroundPlayEnabled.value) {
        _ensureAudioServiceReady().catchError((_) {});
      }

      await _loadVideoWithMediaSource(
        mediaSource: mediaSource,
        quality: selectedQuality,
        initialPosition: initialPosition,
      );
      
    } catch (e) {
      _logger.logError(message: '预加载初始化失败', error: e, stackTrace: StackTrace.current);
      isLoading.value = false;
      errorMessage.value = ErrorHandler.getErrorMessage(e);
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _loadVideo(String quality, {double? initialPosition}) async {
    if (_isDisposed) return;

    final loadingResourceId = _currentResourceId;

    try {
      

      final mediaSource = await _hlsService.getMediaSource(loadingResourceId!, quality, useDash: false);

      if (_currentResourceId != loadingResourceId) return;

      await _loadMediaInternal(
        mediaSource: mediaSource,
        quality: quality,
        initialPosition: initialPosition,
        autoPlay: false,
        resourceIdCheck: () => _currentResourceId == loadingResourceId,
      );
    } catch (e) {
      if (_currentResourceId == loadingResourceId) {
        
        rethrow;
      }
    }
  }

  Future<void> _loadVideoWithMediaSource({
    required MediaSource mediaSource,
    required String quality,
    double? initialPosition,
  }) async {
    if (_isDisposed) return;

    

    await _loadMediaInternal(
      mediaSource: mediaSource,
      quality: quality,
      initialPosition: initialPosition,
      autoPlay: true,
      resourceIdCheck: null,
    );
  }

  Future<void> _loadMediaInternal({
    required MediaSource mediaSource,
    required String quality,
    double? initialPosition,
    required bool autoPlay,
    bool Function()? resourceIdCheck,
  }) async {
    final loadId = _currentLoadId;
    if (loadId.isEmpty) return;

    try {
      _hasTriggeredCompletion = false;
      final needSeek = initialPosition != null && initialPosition > 0;
      final targetPosition = Duration(seconds: initialPosition?.toInt() ?? 0);

      

      if (!mediaSource.isDirectUrl) {
        _qualityCache[quality] = mediaSource;
      }

      final isDashMode = mediaSource.isDirectUrl && mediaSource.videoSegmentBase != null;
      

      _isSeeking = true;

      if (isDashMode) {
        if (needSeek) _userIntendedPosition = targetPosition;

        final startPos = needSeek ? targetPosition : null;
        final media = await _createMedia(mediaSource, start: startPos);

        
        await player.open(media, play: false);
        

        if (mediaSource.audioUrl != null) {
          await Future.delayed(const Duration(milliseconds: 100));
          await _setAudioFiles(mediaSource.audioUrl!);
        }

        if (resourceIdCheck != null && !resourceIdCheck()) {
          
          _isSeeking = false;
          return;
        }

        await Future.delayed(const Duration(milliseconds: 500));
        
        final initialPos = player.state.position.inSeconds;
        
        
          if (initialPos == 0 && !player.state.playing) {
          
          _useDash = false;
          
          final hlsMediaSource = await _hlsService.getMediaSource(
            _currentResourceId!,
            quality,
            useDash: false,
          );
          
          
          final hlsMedia = await _createMedia(hlsMediaSource);
          await player.open(hlsMedia, play: false);
          
          // HLS 模式：等待一下让播放器解析
          await Future.delayed(const Duration(milliseconds: 500));
          
          // 尝试获取 duration
          try {
            await _waitForDuration(timeout: const Duration(seconds: 3));
          } catch (_) {
            
          }
          
          if (autoPlay) {
            
            await player.play();
            
            // 等待播放状态
            int waitPlay = 0;
            while (!player.state.playing && waitPlay < 20) {
              await Future.delayed(const Duration(milliseconds: 50));
              waitPlay++;
            }
            
          }
          
          isLoading.value = false;
          isPlayerInitialized.value = true;
          _currentLoadId = '';
          
        } else {
          if (autoPlay) {
            await player.play();
          }

          isLoading.value = false;
          _userManuallySeeked = false;
          isPlayerInitialized.value = true;
          
        }
        
        _currentLoadId = '';

        if (_pendingSeekPosition != null) {
          await player.seek(Duration(seconds: _pendingSeekPosition!.toInt()));
          _pendingSeekPosition = null;
        }
      } else {
        final media = await _createMedia(mediaSource);
        
        await player.open(media, play: false);
        

        await _waitForVideoTrack();

        
        int waitCount = 0;
        while (player.state.buffering && waitCount < 10) {
          await Future.delayed(const Duration(milliseconds: 50));
          waitCount++;
        }
        

        if (player.state.playing) {
          await player.pause();
          await Future.delayed(const Duration(milliseconds: 30));
        }
        if (needSeek) {
          
          _userIntendedPosition = targetPosition;

          
          await player.play();
          await Future.delayed(const Duration(milliseconds: 80));
          await player.pause();

          await player.seek(targetPosition);
          await Future.delayed(const Duration(milliseconds: 100));

          final actualPos = player.state.position.inSeconds;
          

          if ((actualPos - targetPosition.inSeconds).abs() > 1) {
            await player.seek(targetPosition);
          }
        }

        if (resourceIdCheck != null && !resourceIdCheck()) {
          
          _isSeeking = false;
          return;
        }

        
        if (autoPlay && !player.state.playing) {
          
          try {
            await player.play();

            int waitPlaying = 0;
            while (!player.state.playing && waitPlaying < 20) {
              await Future.delayed(const Duration(milliseconds: 50));
              waitPlaying++;
            }

            
          } catch (_) {
            
          }
        }

        await Future.delayed(const Duration(milliseconds: 100));

        if (player.state.playing) {
          
          isLoading.value = false;
          _userManuallySeeked = false;
          isPlayerInitialized.value = true;
          
          _currentLoadId = '';

          if (_pendingSeekPosition != null) {
            
            await _seekWithValidation(Duration(seconds: _pendingSeekPosition!.toInt()), maxRetries: 5);
            _pendingSeekPosition = null;
          }

          _startContinuousValidation();
        } else {
          
        }

        if (needSeek) {
          await Future.delayed(const Duration(milliseconds: 200));
          final actualPos = player.state.position.inSeconds;
          final diff = (actualPos - targetPosition.inSeconds).abs();
          if (diff > 2) {
            
            await player.seek(targetPosition);
          }
          
        }
      }

      _isSeeking = false;
      _preloadAdjacentQualities();

    } catch (e) {
      _isSeeking = false;
      
      isLoading.value = false;
      errorMessage.value = e.toString();
      _currentLoadId = '';
    }
  }

  Future<void> seek(Duration position) async {
    if (position < Duration.zero) position = Duration.zero;
    

    _userIntendedPosition = position;
    _userManuallySeeked = true;
    _progressValidationTimer?.cancel();
    _validationTargetPosition = null;
    _isSeeking = true;

    try {
      if (player.state.duration.inSeconds != 0) {
        await player.seek(position);
        await Future.delayed(const Duration(milliseconds: 100));
      } else {
        _seekTimer?.cancel();
        _seekTimer = _startSeekTimer(position);
      }
    } finally {
      _isSeeking = false;
    }
  }

  Future<bool> _seekWithValidation(Duration targetPosition, {int maxRetries = 5}) async {
    

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_isDisposed) return false;

      try {
        if (!player.state.playing) {
          await player.play();
        }
      } catch (_) {
        
      }

      await Future.delayed(const Duration(milliseconds: 50));

      await player.seek(targetPosition);
      _userIntendedPosition = targetPosition;

      await Future.delayed(const Duration(milliseconds: 150));

      final actualPosition = player.state.position.inSeconds;
      final diff = (actualPosition - targetPosition.inSeconds).abs();

      if (diff <= 1) {
        
        return true;
      }

      

      try {
        if (player.state.playing) {
          await player.pause();
        }
      } catch (_) {}
    }

    
    return false;
  }

  Timer? _seekTimer;

  Timer? _startSeekTimer(Duration position) {
    return Timer.periodic(const Duration(milliseconds: 200), (Timer t) async {
      if (player.state.duration.inSeconds != 0) {
        await player.stream.buffer.first;
        await player.seek(position);
        t.cancel();
        _seekTimer = null;
      }
    });
  }

  void _startContinuousValidation() {
    if (_progressValidationTimer != null) return;
    if (_validationTargetPosition == null || _userManuallySeeked) return;

    

    _progressValidationTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_isDisposed ||
          _validationTargetPosition == null ||
          _userManuallySeeked ||
          !player.state.playing) {
        timer.cancel();
        _progressValidationTimer = null;
        _validationTargetPosition = null;
        return;
      }

      final currentPosition = player.state.position.inSeconds;
      final targetPosition = _validationTargetPosition!;
      final diff = (currentPosition - targetPosition).abs();

      if (diff > 1) {
        
        await _seekWithValidation(Duration(seconds: targetPosition.toInt()), maxRetries: 3);
      }
    });
  }

  void setPendingSeekPosition(double? position) {
    if (position != null && position > 0) {
      _pendingSeekPosition = position;
      _validationTargetPosition = position;
      _userManuallySeeked = false;
      _progressValidationTimer?.cancel();
      _userIntendedPosition = Duration(seconds: position.toInt());
      
    }
  }

  Future<void> fetchAndRestoreProgress() async {
    if (_isDisposed) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastProgressFetchTime != null && now - _lastProgressFetchTime! < 500) {
      
      return;
    }
    _lastProgressFetchTime = now;

    if (_currentVid == null) {
      
      return;
    }

    if (!isPlayerInitialized.value) {
      
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!_isDisposed && _currentVid != null) {
          
          await _doFetchAndRestoreProgress();
        }
      });
      return;
    }

    await _doFetchAndRestoreProgress();
  }

  Future<void> _doFetchAndRestoreProgress() async {
    if (_currentVid == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastProgressFetchTime != null && now - _lastProgressFetchTime! < 500) {
      
      return;
    }
    _lastProgressFetchTime = now;

    final requestVid = _currentVid!;
    final requestPart = _currentPart;

    try {
      
      final historyService = HistoryService();
      final progressData = await historyService.getProgress(vid: requestVid, part: requestPart);

      if (_isDisposed || _currentVid != requestVid || _currentPart != requestPart) {
        
        return;
      }

      if (progressData == null) {
        
        return;
      }

      final progress = progressData.progress;
      

      final currentPos = player.state.position.inSeconds;
      final targetPos = progress.toInt();

      if ((targetPos - currentPos).abs() > 3) {
        

        if (!_useDash && !player.state.playing) {
          await player.play();
          await Future.delayed(const Duration(milliseconds: 80));
          await player.pause();
        }

        await seek(Duration(seconds: targetPos));
      } else {
        
      }
    } catch (_) {
      
    }
  }

  Future<void> changeQuality(String quality) async {
    if (currentQuality.value == quality) return;

    final wasPlaying = player.state.playing;
    final currentPos = player.state.position;
    final rawTargetPosition = currentPos.inMilliseconds > 0 ? currentPos : _userIntendedPosition;

    final targetPosition = _useDash
        ? rawTargetPosition
        : (rawTargetPosition.inSeconds > 2
            ? Duration(seconds: rawTargetPosition.inSeconds - 2)
            : rawTargetPosition);

    

    await player.pause();

    _qualityDebounceTimer?.cancel();
    _qualityEpoch++;
    final myEpoch = _qualityEpoch;
    isSwitchingQuality.value = true;

    _qualityDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (myEpoch != _qualityEpoch || _isDisposed) return;

      try {
        final mediaSource = await _hlsService.getMediaSource(_currentResourceId!, quality, useDash: _useDash);

        if (_useDash) {
          final startPos = targetPosition.inMilliseconds > 0 ? targetPosition : null;
          final media = await _createMedia(mediaSource, start: startPos);
          await player.open(media, play: wasPlaying);

          currentQuality.value = quality;
          await _savePreferredQuality(quality);
          _userIntendedPosition = targetPosition;

          
        } else {
          final media = await _createMedia(mediaSource);
          await player.open(media, play: false);
          await _waitForDuration();
          if (targetPosition.inMilliseconds > 0) {
            await _seekWithRetry(targetPosition, maxRetries: 3);
          }

          currentQuality.value = quality;
          await _savePreferredQuality(quality);
          _userIntendedPosition = targetPosition;

          if (wasPlaying) {
            await player.play();

            await Future.delayed(const Duration(milliseconds: 150));
            final afterPlayPos = player.state.position;
            final diff = (afterPlayPos.inSeconds - targetPosition.inSeconds).abs();

            if (diff > 3 && targetPosition.inSeconds > 3) {
              
              await player.seek(targetPosition);
            }
          }

          
        }

        onQualityChanged?.call(quality);
        _preloadAdjacentQualities();

      } catch (e) {
        
        errorMessage.value = '切换清晰度失败';
      } finally {
        isSwitchingQuality.value = false;
      }
    });
  }

  Future<void> _seekWithRetry(Duration targetPosition, {int maxRetries = 3}) async {
    final targetSeconds = targetPosition.inSeconds;
    

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await player.play();
        await Future.delayed(const Duration(milliseconds: 80));
        await player.pause();

        await player.seek(targetPosition);
        await Future.delayed(const Duration(milliseconds: 200));

        final actualPos = player.state.position.inSeconds;
        final diff = (actualPos - targetSeconds).abs();

        if (diff <= 3) {
          
          return;
        }

        if (attempt < maxRetries) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } catch (e) {
        
        if (attempt == maxRetries) rethrow;
      }
    }

    
    await player.seek(targetPosition);
  }

  void _setupListeners() {
    _positionSubscription = player.stream.position.listen((position) {
      _positionStreamController.add(position);

      if (_isSeeking || isSwitchingQuality.value) return;

      if (!_hasPlaybackStarted) {
        if (position.inSeconds == 0) return;
        _hasPlaybackStarted = true;
      }

      _userIntendedPosition = position;

      if (onProgressUpdate != null) {
        if (position.inSeconds == 0) return;
        
        final diff = (position.inMilliseconds - _lastReportedPosition.inMilliseconds).abs();
        if (diff >= 500) {
          _lastReportedPosition = position;
          onProgressUpdate!(position, player.state.duration);
        }
      }
    });

    _completedSubscription = player.stream.completed.listen((completed) {
      if (completed && !_hasTriggeredCompletion && !_isSeeking) {
        _hasTriggeredCompletion = true;
        _handlePlaybackEnd();
      }
    });

    _playingSubscription = player.stream.playing.listen((playing) async {
      if (playing && _hasTriggeredCompletion) {
        _hasTriggeredCompletion = false;
      }

      onPlayingStateChanged?.call(playing);

      if (playing && _validationTargetPosition != null && !_userManuallySeeked) {
        
        _startContinuousValidation();
      }

      if (!playing) {
        _progressValidationTimer?.cancel();
        _progressValidationTimer = null;
        _validationTargetPosition = null;
      }

      if (playing) {
        WakelockManager.enable();
      } else {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!player.state.playing) {
            WakelockManager.disable();
          }
        });
      }
    });

    _bufferingSubscription = player.stream.buffering.listen((buffering) {
      isBuffering.value = buffering;

      if (buffering) {
        _stalledTimer?.cancel();
        _stalledTimer = Timer(const Duration(seconds: 15), () {
          if (player.state.buffering) {
            
            _handleStalled();
          }
        });
      } else {
        _stalledTimer?.cancel();
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final isConnected = results.any((r) => r != ConnectivityResult.none);
      if (isConnected && errorMessage.value != null) {
        errorMessage.value = null;
        _handleStalled();
      }
    });

    _setupAudioInterruptionListener();
  }

  void _handlePlaybackEnd() {
    if (loopMode.value == LoopMode.on) {
      seek(Duration.zero).then((_) => player.play());
    } else {
      onVideoEnd?.call();
    }
  }

  Future<void> _handleStalled() async {
    if (_isInitializing || isLoading.value) {
      
      return;
    }
    
    if (_currentResourceId == null || currentQuality.value == null) return;

    try {
      final position = _userIntendedPosition;
      

      final mediaSource = await _hlsService.getMediaSource(_currentResourceId!, currentQuality.value!, useDash: _useDash);

      if (_useDash && mediaSource.audioUrl != null) {
        final nativePlayer = player.platform as NativePlayer?;
        if (nativePlayer != null) {
          await nativePlayer.setProperty('audio-files', mediaSource.audioUrl!);
        }
      }

      final startPos = position.inSeconds > 0 ? position : null;
      final media = await _createMedia(mediaSource, start: _useDash ? startPos : null);

      await player.open(media, play: false);
      if (!_useDash) await _waitForDuration();

      if (!_useDash && position.inSeconds > 0) {
        await player.seek(position);
        await Future.delayed(const Duration(milliseconds: 200));
      }

      await player.play();
    } catch (_) {
      
    }
  }

  Future<void> _configurePlayer() async {
    try {
      if (Platform.isAndroid) {
        final nativePlayer = player.platform as NativePlayer;
        await nativePlayer.setProperty("volume-max", "100");

        final decodeMode = await getDecodeMode();
        await nativePlayer.setProperty("hwdec", decodeMode);
      }
    } catch (_) {}
  }

  Future<Media> _createMedia(MediaSource source, {Duration? start}) async {
    if (source.isDirectUrl) {
      if (source.audioUrl != null && source.videoSegmentBase != null) {
        final videoUrl = source.content;
        final audioUrl = source.audioUrl!;
        final videoInit = source.videoSegmentBase!.initialization;
        final videoIndex = source.videoSegmentBase!.indexRange;
        final audioInit = source.audioSegmentBase?.initialization ?? '';
        final audioIndex = source.audioSegmentBase?.indexRange ?? '';

        
        

        String mediainfo = 'mediainfo://video=${Uri.encodeComponent(videoUrl)}#$videoInit:$videoIndex&audio=${Uri.encodeComponent(audioUrl)}';
        if (audioInit.isNotEmpty && audioIndex.isNotEmpty) {
          mediainfo = '$mediainfo#$audioInit:$audioIndex';
        }

        
        return Media(mediainfo, start: start);
      }

      
      return Media(source.content, start: start);
    } else {
      final tempFile = await _writeTempM3u8File(source.content);
      return Media(tempFile.path, start: start);
    }
  }

  Future<void> _setAudioFiles(String audioUrl) async {
    try {
      final nativePlayer = player.platform as NativePlayer?;
      if (nativePlayer != null) {
        await nativePlayer.setProperty('audio-files', audioUrl);
        
      }
    } catch (_) {
      
    }
  }

  int _tempFileCounter = 0;
  final List<Directory> _tempDirs = [];

  Future<File> _writeTempM3u8File(String content) async {
    final tempDir = await Directory.systemTemp.createTemp('hls_');
    _tempDirs.add(tempDir);
    final fileName = 'playlist_${_tempFileCounter++}_${DateTime.now().millisecondsSinceEpoch}.m3u8';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(content);
    return file;
  }

  Future<void> _waitForVideoTrack({Duration timeout = const Duration(seconds: 5)}) async {
    

    final currentTrack = player.state.track;
    final hasVideo = currentTrack.video.id.isNotEmpty;
    if (hasVideo) {
      
      return;
    }

    final completer = Completer<void>();
    StreamSubscription? sub;

    sub = player.stream.track.listen((track) {
      final trackHasVideo = track.video.id.isNotEmpty;
      if (trackHasVideo && !completer.isCompleted) {
        
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(timeout, onTimeout: () {
        
      });
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _waitForDuration({Duration timeout = const Duration(seconds: 5)}) async {
    
    if (player.state.duration.inSeconds > 0) {
      
      return;
    }

    final completer = Completer<void>();
    StreamSubscription? sub;

    sub = player.stream.duration.listen((duration) {
      
      if (duration.inSeconds > 0 && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      
      await completer.future.timeout(timeout, onTimeout: () {
        
      });
    } finally {
      await sub.cancel();
    }
  }

  void _preloadAdjacentQualities() {
    final current = currentQuality.value;
    if (current == null) return;

    final qualities = availableQualities.value;
    final index = qualities.indexOf(current);
    if (index == -1) return;

    if (index > 0) {
      final lower = qualities[index - 1];
      unawaited(_hlsService.getMediaSource(_currentResourceId!, lower, useDash: _useDash));
    }

    if (index < qualities.length - 1) {
      final higher = qualities[index + 1];
      unawaited(_hlsService.getMediaSource(_currentResourceId!, higher, useDash: _useDash));
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      backgroundPlayEnabled.value = prefs.getBool(_backgroundPlayKey) ?? false;
      final loopModeValue = prefs.getInt(_loopModeKey) ?? 0;
      loopMode.value = LoopMode.values[loopModeValue];
    } catch (_) {}
  }

  Future<String> _getPreferredQuality(List<String> qualities) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferredName = prefs.getString(_preferredQualityKey);
      return findBestQualityMatch(qualities, preferredName);
    } catch (_) {}
    return HlsService.getDefaultQuality(qualities);
  }

  Future<void> _savePreferredQuality(String quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferredQualityKey, quality);
    } catch (_) {}
  }

  List<String> _sortQualities(List<String> qualities) {
    return HlsService.sortQualities(qualities);
  }

  void setVideoMetadata({required String title, String? author, Uri? coverUri}) {}

  void setVideoContext({required int vid, int part = 1}) {
    _currentVid = vid;
    _currentPart = part;
  }

  static const String _decodeModeKey = 'video_decode_mode';

  static Future<String> getDecodeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_decodeModeKey) ?? 'no';
  }

  static Future<void> setDecodeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_decodeModeKey, mode);
  }

  static String getDecodeModeDisplayName(String mode) {
    switch (mode) {
      case 'no':
        return '软解码';
      case 'auto-copy':
        return '硬解码';
      default:
        return '软解码';
    }
  }

  String getQualityDisplayName(String quality) {
    return HlsService.getQualityLabel(quality);
  }

  Future<void> toggleBackgroundPlay() async {
    backgroundPlayEnabled.value = !backgroundPlayEnabled.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundPlayKey, backgroundPlayEnabled.value);
  }

  void toggleLoopMode() {
    final nextMode = (loopMode.value.index + 1) % LoopMode.values.length;
    loopMode.value = LoopMode.values[nextMode];
  }

  void _setupAudioInterruptionListener() {}

  void handleAppLifecycleState(bool isPaused) {}

  Future<void> play() async {
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> _ensureAudioServiceReady() async {}

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _progressValidationTimer?.cancel();
    _seekTimer?.cancel();
    _qualityDebounceTimer?.cancel();
    _stalledTimer?.cancel();

    await _positionSubscription?.cancel();
    await _completedSubscription?.cancel();
    await _playingSubscription?.cancel();
    await _bufferingSubscription?.cancel();
    await _connectivitySubscription?.cancel();

    await _cleanupTempFiles();

    await player.dispose();

    _positionStreamController.close();

    super.dispose();
  }

  Future<void> _cleanupTempFiles() async {
    for (final dir in _tempDirs) {
      try {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          
        }
      } catch (_) {
        
      }
    }
    _tempDirs.clear();
  }
}
