import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../controllers/video_player_controller.dart';
import '../../../models/loop_mode.dart';

/// 视频播放器组件
///
/// 使用 media_kit (基于 AndroidX Media3) 播放 HLS 视频流
/// 使用 VideoPlayerController 管理业务逻辑
/// Widget 只负责 UI 渲染
class MediaPlayerWidget extends StatefulWidget {
  final int resourceId;
  final double? initialPosition;
  final VoidCallback? onVideoEnd;
  final Function(Duration position)? onProgressUpdate;
  final Function(String quality)? onQualityChanged;
  final String? title;
  final VoidCallback? onFullscreenToggle;
  final int? totalParts;
  final int? currentPart;
  final Function(int part)? onPartChange;

  const MediaPlayerWidget({
    super.key,
    required this.resourceId,
    this.initialPosition,
    this.onVideoEnd,
    this.onProgressUpdate,
    this.onQualityChanged,
    this.title,
    this.onFullscreenToggle,
    this.totalParts,
    this.currentPart,
    this.onPartChange,
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

    // 初始化播放器
    _controller.initialize(
      resourceId: widget.resourceId,
      initialPosition: widget.initialPosition,
    );

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
      valueListenable: _controller.isLoading,
      builder: (context, isLoading, _) {
        if (isLoading) {
          return _buildLoadingWidget();
        }

        return ValueListenableBuilder<String?>(
          valueListenable: _controller.errorMessage,
          builder: (context, errorMessage, _) {
            if (errorMessage != null) {
              return _buildErrorWidget(errorMessage);
            }

            return ValueListenableBuilder<bool>(
              valueListenable: _controller.isPlayerInitialized,
              builder: (context, isInitialized, _) {
                if (!isInitialized) {
                  return _buildLoadingWidget();
                }

                return _buildPlayer();
              },
            );
          },
        );
      },
    );
  }

  /// 构建播放器主体
  Widget _buildPlayer() {
    return Container(
      color: Colors.black,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                // 视频播放区域
                Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: MaterialVideoControlsTheme(
                      normal: _buildNormalControls(),
                      fullscreen: _buildFullscreenControls(),
                      child: Video(controller: _controller.videoController),
                    ),
                  ),
                ),

                // 切换清晰度加载指示器
                ValueListenableBuilder<bool>(
                  valueListenable: _controller.isSwitchingQuality,
                  builder: (context, isSwitching, _) {
                    if (!isSwitching) return const SizedBox.shrink();

                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('切换中...', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 构建普通模式控制栏
  MaterialVideoControlsThemeData _buildNormalControls() {
    return MaterialVideoControlsThemeData(
      topButtonBar: [
        MaterialCustomButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              widget.title!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const Spacer(),
        ValueListenableBuilder<LoopMode>(
          valueListenable: _controller.loopMode,
          builder: (context, loopMode, _) {
            return MaterialCustomButton(
              icon: Icon(_getLoopModeIcon(loopMode)),
              onPressed: _controller.toggleLoopMode,
            );
          },
        ),
      ],
      bottomButtonBar: [
        const MaterialPlayOrPauseButton(),
        const MaterialPositionIndicator(),
        const Spacer(),
        _buildQualityButton(),
        const MaterialFullscreenButton(),
      ],
      bottomButtonBarMargin: const EdgeInsets.only(bottom: 0, left: 8, right: 8),
      seekBarMargin: const EdgeInsets.only(bottom: 44),
      seekBarThumbColor: Colors.blue,
      seekBarPositionColor: Colors.blue,
      backdropColor: Colors.transparent,
      volumeGesture: true,
      brightnessGesture: true,
      seekGesture: true,
      primaryButtonBar: [],
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
      bufferingIndicatorBuilder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }

  /// 构建全屏模式控制栏
  MaterialVideoControlsThemeData _buildFullscreenControls() {
    return MaterialVideoControlsThemeData(
      topButtonBarMargin: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 8,
        right: 8,
      ),
      bottomButtonBarMargin: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
        left: 8,
        right: 8,
      ),
      topButtonBar: [
        MaterialCustomButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              widget.title!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const Spacer(),
        ValueListenableBuilder<LoopMode>(
          valueListenable: _controller.loopMode,
          builder: (context, loopMode, _) {
            return MaterialCustomButton(
              icon: Icon(_getLoopModeIcon(loopMode)),
              onPressed: _controller.toggleLoopMode,
            );
          },
        ),
      ],
      bottomButtonBar: [
        const MaterialPlayOrPauseButton(),
        const MaterialPositionIndicator(),
        const Spacer(),
        _buildQualityButton(isFullscreen: true),
        const MaterialFullscreenButton(),
      ],
      seekBarMargin: EdgeInsets.only(
        bottom: 60 + MediaQuery.of(context).padding.bottom,
      ),
      seekBarThumbColor: Colors.blue,
      seekBarPositionColor: Colors.blue,
      displaySeekBar: true,
      backdropColor: Colors.transparent,
      volumeGesture: true,
      brightnessGesture: true,
      seekGesture: true,
      primaryButtonBar: [],
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
    );
  }

  /// 构建清晰度按钮
  Widget _buildQualityButton({bool isFullscreen = false}) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: _controller.availableQualities,
      builder: (context, qualities, _) {
        if (qualities.length <= 1) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<String?>(
          valueListenable: _controller.currentQuality,
          builder: (context, currentQuality, _) {
            return MaterialCustomButton(
              icon: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isFullscreen ? 8 : 6,
                  vertical: isFullscreen ? 4 : 2,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isFullscreen ? Colors.white70 : Colors.white60,
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  currentQuality != null
                      ? _controller.getQualityDisplayName(currentQuality)
                      : '画质',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isFullscreen ? 12 : 11,
                  ),
                ),
              ),
              onPressed: () => _showQualityMenu(context),
            );
          },
        );
      },
    );
  }

  /// 显示清晰度选择菜单
  void _showQualityMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final qualities = _controller.availableQualities.value;
    final currentQuality = _controller.currentQuality.value;

    showMenu(
      context: context,
      position: position,
      color: Colors.black.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: qualities.map((quality) {
        final isSelected = quality == currentQuality;
        final displayName = _controller.getQualityDisplayName(quality);

        return PopupMenuItem(
          value: quality,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? Colors.blue : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 12),
              Text(
                displayName,
                style: TextStyle(
                  color: isSelected ? Colors.blue : Colors.white,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((selectedQuality) {
      if (selectedQuality != null && selectedQuality != currentQuality) {
        _controller.changeQuality(selectedQuality);
      }
    });
  }

  /// 获取循环模式图标
  IconData _getLoopModeIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return Icons.repeat;
      case LoopMode.on:
        return Icons.repeat_one;
    }
  }

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
