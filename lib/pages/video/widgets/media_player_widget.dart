import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../controllers/video_player_controller.dart';
import '../../../controllers/danmaku_controller.dart';
import '../../../managers/video_player_manager.dart';
import '../../../services/logger_service.dart';
import 'custom_player_ui.dart';

/// 视频播放器组件
///
/// 使用 media_kit (基于 AndroidX Media3) 播放 HLS 视频流
///
/// 支持两种模式：
/// 1. 传统模式：传入 resourceId，组件内部创建 Controller
/// 2. Manager模式：传入 VideoPlayerManager，使用预加载的资源（推荐）
///
/// UI 和手势由 CustomPlayerUI 负责
class MediaPlayerWidget extends StatefulWidget {
  /// 资源ID（传统模式必需）
  final int? resourceId;

  /// 播放管理器（Manager模式，推荐使用）
  /// 传入此参数时，resourceId 将被忽略
  final VideoPlayerManager? manager;

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
    this.manager,
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
  }) : assert(resourceId != null || manager != null, 'resourceId 或 manager 必须提供其一');

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isUsingManager = false;
  bool _ownsController = false;
  bool _controllerReady = false;
  final LoggerService _logger = LoggerService.instance;

  @override
  void initState() {
    super.initState();

    _isUsingManager = widget.manager != null;

    if (_isUsingManager) {
      _logger.logDebug('[MediaPlayerWidget] Manager模式初始化', tag: 'MediaPlayer');

      _controller = VideoPlayerController();
      _ownsController = true;
      _bindCallbacks();
      _setMetadata();

      _controllerReady = true;

      _initWithManager();
    } else {
      _logger.logDebug('[MediaPlayerWidget] 传统模式初始化 - resourceId: ${widget.resourceId}', tag: 'MediaPlayer');

      _ownsController = true;
      _controller = VideoPlayerController();
      _bindCallbacks();
      _setMetadata();

      _controller!.initialize(
        resourceId: widget.resourceId!,
        initialPosition: widget.initialPosition,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller != null) {
          _controllerReady = true;
          widget.onControllerReady?.call(_controller!);
        }
      });
    }

    WidgetsBinding.instance.addObserver(this);
  }

  /// Manager 模式初始化
  Future<void> _initWithManager() async {
    final manager = widget.manager!;

    manager.onVideoEnd = widget.onVideoEnd;
    manager.onProgressUpdate = widget.onProgressUpdate;
    manager.onQualityChanged = widget.onQualityChanged;
    manager.onPlayingStateChanged = widget.onPlayingStateChanged;

    manager.bindController(_controller!);

    await manager.waitForReady();

    if (mounted) {
      setState(() {
        _controllerReady = true;
      });
      widget.onControllerReady?.call(_controller!);
    }
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

  // 【关键】跟踪是否已应用初始进度，避免重复 seek
  bool _hasAppliedInitialPosition = false;

   @override
   void didUpdateWidget(MediaPlayerWidget oldWidget) {
     super.didUpdateWidget(oldWidget);
     _logger.logDebug('[Widget] didUpdateWidget 被调用', tag: 'MediaPlayer');
     _logger.logDebug('[Widget]   oldWidget.manager: ${oldWidget.manager?.hashCode}', tag: 'MediaPlayer');
     _logger.logDebug('[Widget]   widget.manager: ${widget.manager?.hashCode}', tag: 'MediaPlayer');
     _logger.logDebug('[Widget]   oldWidget.onVideoEnd: ${oldWidget.onVideoEnd?.hashCode}', tag: 'MediaPlayer');
     _logger.logDebug('[Widget]   widget.onVideoEnd: ${widget.onVideoEnd?.hashCode}', tag: 'MediaPlayer');

    // Manager 模式下，资源切换由 Manager 处理
    if (_isUsingManager) {
      // 更新回调绑定
      if (widget.manager != null) {
        widget.manager!.onVideoEnd = widget.onVideoEnd;
        widget.manager!.onProgressUpdate = widget.onProgressUpdate;
        widget.manager!.onQualityChanged = widget.onQualityChanged;
      }
      return;
    }

    // ============ 传统模式逻辑 ============
    if (_controller == null) return;

    // 如果 resourceId 没变，但回调变了，需要重新绑定回调
    if (oldWidget.onProgressUpdate != widget.onProgressUpdate) {
      _controller!.onProgressUpdate = (pos, total) => widget.onProgressUpdate?.call(pos, total);
    }

     if (oldWidget.resourceId != widget.resourceId) {
       _logger.logDebug('[didUpdateWidget] resourceId 改变，重新初始化', tag: 'MediaPlayer');
       _hasAppliedInitialPosition = false; // 切换视频时重置

      // 更新视频元数据
      if (widget.title != null) {
        _controller!.setVideoMetadata(
          title: widget.title!,
          author: widget.author,
          coverUri: widget.coverUrl != null ? Uri.tryParse(widget.coverUrl!) : null,
        );
      }

      // 重新加载视频
      _controller!.initialize(
        resourceId: widget.resourceId!,
        initialPosition: widget.initialPosition,
      );
    } else if (!_hasAppliedInitialPosition &&
               widget.initialPosition != null &&
               oldWidget.initialPosition == null) {
       // 【关键修复】initialPosition 从 null 变为有值（异步加载历史记录完成）
       // 此时播放器已初始化，需要手动 seek 到目标位置
       _logger.logDebug('[didUpdateWidget] 历史进度加载完成: ${widget.initialPosition}s，执行 seek', tag: 'MediaPlayer');
       _hasAppliedInitialPosition = true;
      _controller!.seek(Duration(seconds: widget.initialPosition!.toInt()));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _controller?.handleAppLifecycleState(state == AppLifecycleState.paused);
  }

   @override
   void dispose() {
     _logger.logDebug('[MediaPlayerWidget] 销毁', tag: 'MediaPlayer');
     WidgetsBinding.instance.removeObserver(this);

    // 只有拥有 Controller 所有权时才销毁
    // Manager 模式下，Controller 由 Manager 管理
    if (_ownsController && _controller != null) {
      _controller!.dispose();
    }

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
    if (_isUsingManager && widget.manager != null) {
      // Manager 模式：重新预加载资源
      widget.manager!.preloadResource(
        resourceId: widget.manager!.controller != null
            ? widget.resourceId ?? 0
            : widget.resourceId ?? 0,
        initialPosition: widget.initialPosition,
      );
    } else if (_controller != null && widget.resourceId != null) {
      // 传统模式：重新初始化
      _controller!.initialize(
        resourceId: widget.resourceId!,
        initialPosition: widget.initialPosition,
      );
    }
  }
}