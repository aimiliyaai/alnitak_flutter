import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../controllers/video_player_controller.dart';
import '../../../controllers/danmaku_controller.dart';
import 'custom_player_ui.dart';

/// 视频播放器组件
///
/// 使用 media_kit (基于 libmpv) 播放 HLS/DASH 视频流
///
/// 传入 resourceId，组件内部创建并管理 Controller
///
/// UI 和手势由 CustomPlayerUI 负责
class MediaPlayerWidget extends StatefulWidget {
  /// 资源ID
  final int? resourceId;

  final double? initialPosition;
  final VoidCallback? onVideoEnd;
  // 【关键】参数签名必须匹配 Controller 中的定义 (进度, 总时长)
  final Function(Duration position, Duration totalDuration)? onProgressUpdate;
  final Function(String quality)? onQualityChanged;
  final String? title;
  final String? author;
  final String? coverUrl;
  final VoidCallback? onFullscreenToggle;
  final int? totalParts;
  final int? currentPart;
  final Function(int part)? onPartChange;
  final Function(VideoPlayerController)? onControllerReady;
  /// 弹幕控制器（可选）
  final DanmakuController? danmakuController;
  /// 播放状态变化回调
  final Function(bool playing)? onPlayingStateChanged;
  /// 在看人数（可选）
  final ValueNotifier<int>? onlineCount;

  const MediaPlayerWidget({
    super.key,
    this.resourceId,
    this.initialPosition,
    this.onVideoEnd,
    this.onProgressUpdate,
    this.onQualityChanged,
    this.title,
    this.author,
    this.coverUrl,
    this.onFullscreenToggle,
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

    if (widget.resourceId != null) {
      _controller!.initialize(
        resourceId: widget.resourceId!,
        initialPosition: widget.initialPosition,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller != null) {
        widget.onControllerReady?.call(_controller!);
      }
    });

    WidgetsBinding.instance.addObserver(this);
  }

  /// 绑定回调函数
  void _bindCallbacks() {
    if (_controller == null) return;

    _controller!.onVideoEnd = widget.onVideoEnd;
    _controller!.onProgressUpdate = (pos, total) {
      widget.onProgressUpdate?.call(pos, total);
    };
    _controller!.onQualityChanged = widget.onQualityChanged;
    _controller!.onPlayingStateChanged = widget.onPlayingStateChanged;
  }

  /// 设置视频元数据
  void _setMetadata() {
    if (_controller == null || widget.title == null) return;

    _controller!.setVideoMetadata(
      title: widget.title!,
      author: widget.author,
      coverUri: widget.coverUrl != null ? Uri.tryParse(widget.coverUrl!) : null,
    );
  }

  @override
  void didUpdateWidget(MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_controller == null) return;

    // 更新回调绑定
    if (oldWidget.onProgressUpdate != widget.onProgressUpdate) {
      _controller!.onProgressUpdate = (pos, total) => widget.onProgressUpdate?.call(pos, total);
    }
    if (oldWidget.onVideoEnd != widget.onVideoEnd) {
      _controller!.onVideoEnd = widget.onVideoEnd;
    }
    if (oldWidget.onPlayingStateChanged != widget.onPlayingStateChanged) {
      _controller!.onPlayingStateChanged = widget.onPlayingStateChanged;
    }

    // 如果 resourceId 变了，重新初始化
    if (oldWidget.resourceId != widget.resourceId && widget.resourceId != null) {
      if (widget.title != null) {
        _controller!.setVideoMetadata(
          title: widget.title!,
          author: widget.author,
          coverUri: widget.coverUrl != null ? Uri.tryParse(widget.coverUrl!) : null,
        );
      }

      _controller!.initialize(
        resourceId: widget.resourceId!,
        initialPosition: widget.initialPosition,
      );
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

  /// 构建带手势控制的播放器
  Widget _buildPlayerWithGestures() {
    if (_controller == null) return _buildLoadingWidget();

    return Stack(
      children: [
        ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ValueListenableBuilder<bool>(
                valueListenable: _controller!.isPlayerInitialized,
                builder: (context, isInit, _) {
                  // Player 和 VideoController 在 setDataSource 中 ??= 创建
                  // 未初始化前不渲染 Video widget，避免 null 访问
                  if (!isInit) {
                    return const SizedBox.shrink();
                  }
                  return ValueListenableBuilder<bool>(
                    valueListenable: _controller!.backgroundPlayEnabled,
                    builder: (context, bgEnabled, _) {
                      return Video(
                        controller: _controller!.videoController,
                        pauseUponEnteringBackgroundMode: !bgEnabled,
                        controls: (state) {
                          return CustomPlayerUI(
                            controller: state.widget.controller,
                            logic: _controller!,
                            title: widget.title ?? '',
                            onBack: () => Navigator.of(context).maybePop(),
                            danmakuController: widget.danmakuController,
                            onlineCount: widget.onlineCount,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============ UI 部分 ============

  /// 加载中界面
  Widget _buildLoadingWidget() {
    return ColoredBox(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(color: Colors.white),
            ),
            SizedBox(height: 12),
            Text(
              '加载中...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// 错误界面
  Widget _buildErrorWidget(String errorMessage) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
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

  /// 处理重试
  void _handleRetry() {
    if (_controller != null && widget.resourceId != null) {
      _controller!.initialize(
        resourceId: widget.resourceId!,
        initialPosition: widget.initialPosition,
      );
    }
  }
}
