import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../controllers/video_player_controller.dart';
import '../../../controllers/danmaku_controller.dart';
import 'custom_player_ui.dart';

/// 视频播放器组件
class MediaPlayerWidget extends StatefulWidget {
  final int? resourceId;
  final double? initialPosition;
  final double? duration;
  final VoidCallback? onVideoEnd;
  final Function(Duration position, Duration totalDuration)? onProgressUpdate;
  final Function(String quality)? onQualityChanged;
  final String? title;
  final String? author;
  final String? coverUrl;
  final int? totalParts;
  final int? currentPart;
  final Function(int part)? onPartChange;
  final Function(VideoPlayerController)? onControllerReady;
  final DanmakuController? danmakuController;
  final Function(bool playing)? onPlayingStateChanged;
  final ValueNotifier<int>? onlineCount;

  const MediaPlayerWidget({
    super.key,
    this.resourceId,
    this.initialPosition,
    this.duration,
    this.onVideoEnd,
    this.onProgressUpdate,
    this.onQualityChanged,
    this.title,
    this.author,
    this.coverUrl,
    this.totalParts,
    this.currentPart,
    this.onPartChange,
    this.onControllerReady,
    this.danmakuController,
    this.onPlayingStateChanged,
    this.onlineCount,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _controllerReady = false;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController();
    _bindCallbacks();
    _setMetadata();
    _controllerReady = true;

    _initializePlayer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller != null) {
        widget.onControllerReady?.call(_controller!);
      }
    });

    WidgetsBinding.instance.addObserver(this);
  }

  void _bindCallbacks() {
    if (_controller == null) return;
    _controller!.onVideoEnd = widget.onVideoEnd;
    _controller!.onProgressUpdate = widget.onProgressUpdate;
    _controller!.onQualityChanged = widget.onQualityChanged;
    _controller!.onPlayingStateChanged = widget.onPlayingStateChanged;
  }

  void _setMetadata() {
    if (_controller == null || widget.title == null) return;
    _controller!.setVideoMetadata(
      title: widget.title!,
      author: widget.author,
      coverUri: widget.coverUrl != null ? Uri.tryParse(widget.coverUrl!) : null,
    );
  }

  void _initializePlayer() {
    if (_controller == null || widget.resourceId == null) return;
    _controller!.initialize(
      resourceId: widget.resourceId!,
      initialPosition: widget.initialPosition,
      duration: widget.duration,
    );
  }

  @override
  void didUpdateWidget(MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_controller == null) return;

    // 回调变化时重新绑定
    if (oldWidget.onVideoEnd != widget.onVideoEnd ||
        oldWidget.onProgressUpdate != widget.onProgressUpdate ||
        oldWidget.onQualityChanged != widget.onQualityChanged ||
        oldWidget.onPlayingStateChanged != widget.onPlayingStateChanged) {
      _bindCallbacks();
    }

    // resourceId 变化时重新初始化
    if (oldWidget.resourceId != widget.resourceId) {
      _setMetadata();
      _initializePlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _controller?.handleAppLifecycleState(state == AppLifecycleState.paused);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _controller?.dispose();

    // 退出时恢复系统UI方向
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controllerReady) {
      return _buildLoadingWidget();
    }

    return Stack(
      children: [
        _buildPlayerWithGestures(),
        ValueListenableBuilder<bool>(
          valueListenable: _controller!.isPlayerInitialized,
          builder: (context, isInitialized, _) {
            if (isInitialized) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: IgnorePointer(
                child: _buildLoadingWidget(),
              ),
            );
          },
        ),
        ValueListenableBuilder<String?>(
          valueListenable: _controller!.errorMessage,
          builder: (context, error, _) {
            if (error == null || error.isEmpty) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: IgnorePointer(
                child: _buildErrorWidget(error),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPlayerWithGestures() {
    if (_controller == null) return _buildLoadingWidget();

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ValueListenableBuilder<bool>(
            valueListenable: _controller!.isPlayerInitialized,
            builder: (context, isInit, _) {
              if (!isInit) return const SizedBox.shrink();
              return ValueListenableBuilder<bool>(
                valueListenable: _controller!.backgroundPlayEnabled,
                builder: (context, bgEnabled, _) {
                  return Video(
                    controller: _controller!.videoController,
                    pauseUponEnteringBackgroundMode: !bgEnabled,
                    controls: (state) => CustomPlayerUI(
                      controller: state.widget.controller,
                      logic: _controller!,
                      title: widget.title ?? '',
                      onBack: () => Navigator.of(context).maybePop(),
                      danmakuController: widget.danmakuController,
                      onlineCount: widget.onlineCount,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(color: Colors.white),
            ),
            SizedBox(height: 12),
            Text('加载中...', style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String errorMessage) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _handleRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleRetry() => _initializePlayer();
}
