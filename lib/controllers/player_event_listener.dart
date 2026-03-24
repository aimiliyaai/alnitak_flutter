/// 播放器事件回调接口
///
/// 统一 VideoPlayerController 的 5 个松散回调为类型安全接口。
/// 实现方只需 override 关心的方法（默认空实现）。
mixin PlayerEventListener {
  /// 视频播放结束（进度 >= 90%）
  void onVideoEnd() {}

  /// 播放进度更新（约每秒 1 次，已节流 500ms）
  void onProgressUpdate(Duration position, Duration totalDuration) {}

  /// 清晰度切换完成
  void onQualityChanged(String quality) {}

  /// 播放/暂停状态变化
  void onPlayingStateChanged(bool playing) {}
}
