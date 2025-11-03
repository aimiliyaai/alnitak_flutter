import 'package:flutter/material.dart';

/// 播放器顶部导航栏
/// 包含返回按钮、标题、设置按钮等
class PlayerTopBar extends StatelessWidget {
  final String? title;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  const PlayerTopBar({
    super.key,
    this.title,
    this.onBack,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // 返回按钮
          IconButton(
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            iconSize: 24,
          ),
          // 标题
          if (title != null)
            Expanded(
              child: Text(
                title!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          // 右侧操作按钮
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}
