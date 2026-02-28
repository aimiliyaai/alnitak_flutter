import 'dart:math';

import 'package:flutter/rendering.dart';

/// 参考 pili_plus: SliverGridDelegateWithExtentAndRatio
///
/// 自动计算列数（基于 maxCrossAxisExtent），然后用 childAspectRatio 计算
/// 主轴尺寸，再追加 mainAxisExtent 的固定高度。
/// 这样缩略图区域由 aspectRatio 控制，内容区由 mainAxisExtent 控制。
class SliverGridDelegateWithExtentAndRatio extends SliverGridDelegate {
  SliverGridDelegateWithExtentAndRatio({
    required this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.childAspectRatio = 1.0,
    this.mainAxisExtent = 0.0,
  })  : assert(maxCrossAxisExtent > 0),
        assert(mainAxisSpacing >= 0),
        assert(crossAxisSpacing >= 0),
        assert(childAspectRatio > 0);

  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;

  /// 追加到主轴的固定高度（用于内容区：标题 + 作者 + 统计）
  final double mainAxisExtent;

  SliverGridLayout? _layoutCache;
  double? _crossAxisExtentCache;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    if (_layoutCache != null &&
        constraints.crossAxisExtent == _crossAxisExtentCache) {
      return _layoutCache!;
    }
    _crossAxisExtentCache = constraints.crossAxisExtent;

    int crossAxisCount =
        ((constraints.crossAxisExtent - crossAxisSpacing) /
                (maxCrossAxisExtent + crossAxisSpacing))
            .ceil();
    crossAxisCount = max(1, crossAxisCount);

    final double usableCrossAxisExtent = max(
      0.0,
      constraints.crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1),
    );
    final double childCrossAxisExtent = usableCrossAxisExtent / crossAxisCount;
    final double childMainAxisExtent =
        childCrossAxisExtent / childAspectRatio + mainAxisExtent;

    return _layoutCache = SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: childMainAxisExtent + mainAxisSpacing,
      crossAxisStride: childCrossAxisExtent + crossAxisSpacing,
      childMainAxisExtent: childMainAxisExtent,
      childCrossAxisExtent: childCrossAxisExtent,
      reverseCrossAxis:
          axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(SliverGridDelegateWithExtentAndRatio oldDelegate) {
    final flag = oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
        oldDelegate.mainAxisSpacing != mainAxisSpacing ||
        oldDelegate.crossAxisSpacing != crossAxisSpacing ||
        oldDelegate.childAspectRatio != childAspectRatio ||
        oldDelegate.mainAxisExtent != mainAxisExtent;
    if (flag) _layoutCache = null;
    return flag;
  }
}
