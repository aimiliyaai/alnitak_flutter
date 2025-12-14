import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../controllers/video_player_controller.dart';
import 'custom_player_ui.dart';

/// 视频播放器组件
///
/// 使用 media_kit (基于 AndroidX Media3) 播放 HLS 视频流
/// 使用 VideoPlayerController 管理业务逻辑
/// UI 和手势由 CustomPlayerUI 负责
class MediaPlayerWidget extends StatefulWidget {
  final int resourceId;
  final double? initialPosition;
  final VoidCallback? onVideoEnd;
  final Function(Duration position)? onProgressUpdate;
  final Function(String quality)? onQualityChanged;
  final String? title;
  final String? author;
  final String? coverUrl;
  final VoidCallback? onFullscreenToggle;
  final int? totalParts;
  final int? currentPart;
  final Function(int part)? onPartChange;
  final Function(VideoPlayerController)? onControllerReady;

  const MediaPlayerWidget({
    super.key,
    required this.resourceId,
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
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> with WidgetsBindingObserver {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    print('📹 [MediaPlayerWidget] 初始化 - resourceId: ${widget.resourceId}');

    // 创建 Controller
    _controller = VideoPlayerController();

    // 设置回调
    _controller.onVideoEnd = widget.onVideoEnd;
    _controller.onProgressUpdate = widget.onProgressUpdate;
    _controller.onQualityChanged = widget.onQualityChanged;

    // 设置视频元数据（用于后台播放通知）
    if (widget.title != null) {
      _controller.setVideoMetadata(
        title: widget.title!,
        author: widget.author,
        coverUri: widget.coverUrl != null ? Uri.tryParse(widget.coverUrl!) : null,
      );
    }

    // 初始化播放器
    _controller.initialize(
      resourceId: widget.resourceId,
      initialPosition: widget.initialPosition,
    );

    // 通知父组件控制器已就绪
    widget.onControllerReady?.call(_controller);

    // 添加生命周期监听
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    print('📹 [didUpdateWidget] old resourceId: ${oldWidget.resourceId}, new resourceId: ${widget.resourceId}');

    if (oldWidget.resourceId != widget.resourceId) {
      print('📹 resourceId 改变，重新初始化');
      _controller.initialize(
        resourceId: widget.resourceId,
        initialPosition: widget.initialPosition,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _controller.handleAppLifecycleState(state == AppLifecycleState.paused);
  }

  @override
  void dispose() {
    print('📹 [MediaPlayerWidget] 销毁');
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();

    // 退出时恢复系统UI
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.isPlayerInitialized,
      builder: (context, isInitialized, _) {
        if (!isInitialized) {
          return _buildLoadingWidget();
        }

        return ValueListenableBuilder<String?>(
          valueListenable: _controller.errorMessage,
          builder: (context, error, _) {
            if (error != null && error.isNotEmpty) {
              return _buildErrorWidget(error);
            }
            return _buildPlayerWithGestures();
          },
        );
      },
    );
  }

  /// 构建带手势控制的播放器
  Widget _buildPlayerWithGestures() {
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Video(
            controller: _controller.videoController,
            controls: (state) {
              return CustomPlayerUI(
                controller: state.widget.controller,
                logic: _controller,
                title: widget.title ?? '',
                onBack: () => Navigator.of(context).maybePop(),
              );
            },
          ),
        ),
      ),
    );
  }

  // ============ UI 部分 ============

  /// 加载中界面
  Widget _buildLoadingWidget() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                '加载中...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
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
                onPressed: () {
                  _controller.initialize(
                    resourceId: widget.resourceId,
                    initialPosition: widget.initialPosition,
                  );
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
