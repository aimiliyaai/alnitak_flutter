/// 自动连播数据源接口
///
/// 由 CollectionListState、RecommendListState、PgcSeasonPanelState 等实现，
/// 替代 VideoPageController.onVideoEnded 中的 dynamic 调用。
mixin AutoPlaySource {
  /// 获取下一个分P编号（仅分P列表提供）
  int? getNextPart() => null;

  /// 获取下一个视频 vid（合集/推荐列表提供）
  int? getNextVideo() => null;
}
