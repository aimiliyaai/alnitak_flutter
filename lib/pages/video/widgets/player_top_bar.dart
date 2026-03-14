import 'package:flutter/material.dart';

/// 播放器顶部栏（返回 + 全屏标题滚动 + 在看人数），从 CustomPlayerUI 拆出。
/// 全屏状态变化与标题动画由父组件通过回调驱动。
class PlayerTopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final bool fullscreen;
  final bool wasFullscreen;
  final VoidCallback onFullscreenEnter;
  final VoidCallback onFullscreenExit;
  final AnimationController titleScrollController;
  final Animation<double> titleScrollAnimation;
  final VoidCallback checkAndStartTitleAnimation;
  final ValueNotifier<int>? onlineCount;

  const PlayerTopBar({
    super.key,
    required this.title,
    this.onBack,
    required this.fullscreen,
    required this.wasFullscreen,
    required this.onFullscreenEnter,
    required this.onFullscreenExit,
    required this.titleScrollController,
    required this.titleScrollAnimation,
    required this.checkAndStartTitleAnimation,
    this.onlineCount,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (fullscreen && !wasFullscreen) {
                      onFullscreenEnter();
                    } else if (!fullscreen && wasFullscreen) {
                      onFullscreenExit();
                    }

                    if (!fullscreen || title.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final maxTitleWidth = constraints.maxWidth * 0.5;
                        return _buildScrollableTitle(context, maxTitleWidth);
                      },
                    );
                  },
                ),
              ),
              if (onlineCount != null && fullscreen)
                ValueListenableBuilder<int>(
                  valueListenable: onlineCount!,
                  builder: (context, count, _) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.remove_red_eye_outlined,
                            color: Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            count > 0 ? '$count人在看' : '连接中...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableTitle(BuildContext context, double maxWidth) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AnimatedBuilder(
        animation: titleScrollAnimation,
        builder: (context, child) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout();

          final isOverflow = textPainter.width > maxWidth;

          // 无溢出或动画已结束：固定宽度 + 省略号，避免超长标题撑出边界
          if (!isOverflow || titleScrollController.isCompleted) {
            return SizedBox(
              width: maxWidth,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            );
          }

          final scrollDistance = textPainter.width - maxWidth + 30;
          final offset = titleScrollAnimation.value * scrollDistance;

          return ClipRect(
            child: Transform.translate(
              offset: Offset(-offset, 0),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
              ),
            ),
          );
        },
      ),
    );
  }
}
