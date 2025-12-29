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
    debugPrint('📹 [MediaPlayerWidget] 初始化 - resourceId: ${widget.resourceId}');

    // 1. 【必须】创建 Controller 实例
    _controller = VideoPlayerController();

    // 2. 【必须】绑定回调函数
    _controller.onVideoEnd = widget.onVideoEnd;

    // 绑定进度回调 (注意参数透传)
    _controller.onProgressUpdate = (pos, total) {
      widget.onProgressUpdate?.call(pos, total);
    };

    _controller.onQualityChanged = widget.onQualityChanged;

    // 3. 设置视频元数据（用于后台播放通知）
    if (widget.title != null) {
      _controller.setVideoMetadata(
        title: widget.title!,
        author: widget.author,
        coverUri: widget.coverUrl != null ? Uri.tryParse(widget.coverUrl!) : null,
      );
    }

    // 4. 初始化播放器
    _controller.initialize(
      resourceId: widget.resourceId,
      initialPosition: widget.initialPosition,
    );

    // 5. 【优化】在下一帧通知父组件，避免构建期间 setState 报错
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onControllerReady?.call(_controller);
      }
    });

    // 6. 添加生命周期监听
    WidgetsBinding.instance.addObserver(this);
  }

  // 【关键】跟踪是否已应用初始进度，避免重复 seek
  bool _hasAppliedInitialPosition = false;

  @override
  void didUpdateWidget(MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 如果 resourceId 没变，但回调变了，需要重新绑定回调
    if (oldWidget.onProgressUpdate != widget.onProgressUpdate) {
      _controller.onProgressUpdate = (pos, total) => widget.onProgressUpdate?.call(pos, total);
    }
    // ... 其他回调更新同理

    if (oldWidget.resourceId != widget.resourceId) {
      debugPrint('📹 [didUpdateWidget] resourceId 改变，重新初始化');
      _hasAppliedInitialPosition = false; // 切换视频时重置

      // 更新视频元数据
      if (widget.title != null) {
        _controller.setVideoMetadata(
          title: widget.title!,
          author: widget.author,
          coverUri: widget.coverUrl != null ? Uri.tryParse(widget.coverUrl!) : null,
        );
      }

      // 重新加载视频
      _controller.initialize(
        resourceId: widget.resourceId,
        initialPosition: widget.initialPosition,
      );
    } else if (!_hasAppliedInitialPosition &&
               widget.initialPosition != null &&
               oldWidget.initialPosition == null) {
      // 【关键修复】initialPosition 从 null 变为有值（异步加载历史记录完成）
      // 此时播放器已初始化，需要手动 seek 到目标位置
      debugPrint('📹 [didUpdateWidget] 历史进度加载完成: ${widget.initialPosition}s，执行 seek');
      _hasAppliedInitialPosition = true;
      _controller.seek(Duration(seconds: widget.initialPosition!.toInt()));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _controller.handleAppLifecycleState(state == AppLifecycleState.paused);
  }

  @override
  void dispose() {
    debugPrint('📹 [MediaPlayerWidget] 销毁');
    WidgetsBinding.instance.removeObserver(this);

    // 【关键修复】直接调用 controller 的 dispose 方法
    // Controller 内部已经实现了"同步切断 + 延迟销毁"的逻辑
    _controller.dispose();

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
          child: ValueListenableBuilder<bool>(
            valueListenable: _controller.backgroundPlayEnabled,
            builder: (context, bgEnabled, _) {
              return Video(
                controller: _controller.videoController,
                // 关键：后台播放开启时，不在进入后台时暂停
                pauseUponEnteringBackgroundMode: !bgEnabled,
                controls: (state) {
                  return CustomPlayerUI(
                    controller: state.widget.controller,
                    logic: _controller,
                    title: widget.title ?? '',
                    onBack: () => Navigator.of(context).maybePop(),
                  );
                },
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