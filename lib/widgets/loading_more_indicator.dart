import 'package:flutter/material.dart';

/// 列表底部「加载更多」统一指示器：24×24 小圆，避免全尺寸转圈占位过大
class LoadingMoreIndicator extends StatelessWidget {
  const LoadingMoreIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
