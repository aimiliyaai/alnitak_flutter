import '../../services/history_service.dart';
import '../../controllers/video_player_controller.dart';

/// 播放进度跟踪器
///
/// 从 VideoPlayPage 中提取，负责：
/// - 进度上报节流（每 5 秒写一次）
/// - 播放完成上报（-1）
/// - 切换视频/分P 时的竞态防护（progressReport vid/part 锁定）
/// - 页面退出时最终进度保存
class ProgressTracker {
  final HistoryService _historyService;

  ProgressTracker({HistoryService? historyService})
      : _historyService = historyService ?? HistoryService();

  // 最后上报的播放位置（用于切换分P前上报）
  Duration? lastReportedPosition;

  // 是否已上报播放完成(-1)
  bool hasReportedCompleted = false;

  // 最后一次保存到服务器的播放秒数（用于节流）
  int? _lastSavedSeconds;

  // 当前视频时长
  double currentDuration = 0;

  // 【关键】进度上报用的 vid/part，在播放开始时锁定，防止切换视频/分P时的竞态
  int? _reportVid;
  int? _reportPart;

  /// 当前锁定的 vid（只读）
  int? get reportVid => _reportVid;

  /// 当前锁定的 part（只读）
  int? get reportPart => _reportPart;

  /// 锁定进度上报的 vid/part（播放开始时调用）
  void lock(int vid, int part) {
    _reportVid = vid;
    _reportPart = part;
  }

  /// 清空进度上报锁定（切换视频/分P 前调用）
  void unlock() {
    _reportVid = null;
    _reportPart = null;
  }

  /// 重置播放状态（切换视频/分P 时调用）
  void reset() {
    lastReportedPosition = null;
    hasReportedCompleted = false;
    _lastSavedSeconds = null;
    currentDuration = 0;
  }

  /// 处理播放进度更新（每秒触发一次）
  ///
  /// 返回当前锁定的 (vid, part)，供调用方同步弹幕等。
  /// 返回 null 表示当前进度锁定无效（正在切换），调用方应跳过业务处理。
  (int vid, int part)? onProgressUpdate(Duration position, Duration totalDuration) {
    final reportVid = _reportVid;
    final reportPart = _reportPart;
    if (reportVid == null || reportPart == null) return null;

    // 只在 duration > 0 时更新，避免 open() 重置期间覆盖为 0
    if (totalDuration.inSeconds > 0) {
      currentDuration = totalDuration.inSeconds.toDouble();
    }
    lastReportedPosition = position;

    if (hasReportedCompleted) return (reportVid, reportPart);

    final currentSeconds = position.inSeconds;

    // duration 为 0 时不上报（可能是 open() 重置期间）
    if (currentDuration <= 0) return (reportVid, reportPart);

    // 进度不应超过总时长（允许 2 秒误差）
    if (currentSeconds > currentDuration + 2) return (reportVid, reportPart);

    if (_lastSavedSeconds == null ||
        (currentSeconds - _lastSavedSeconds!) >= 5) {
      _historyService.addHistory(
        vid: reportVid,
        part: reportPart,
        time: currentSeconds.toDouble(),
        duration: currentDuration.toInt(),
      );
      _lastSavedSeconds = currentSeconds;
    }

    return (reportVid, reportPart);
  }

  /// 处理播放结束事件
  ///
  /// 返回 true 表示应触发自动连播，false 表示循环模式不触发。
  bool onVideoEnded(int currentVid, int currentPart, VideoPlayerController? playerController) {
    if (hasReportedCompleted || currentDuration <= 0) return false;

    final reportVid = _reportVid ?? currentVid;
    final reportPart = _reportPart ?? currentPart;

    // 循环模式：不上报 -1，让播放器自动重新播放
    final isLooping = playerController?.loopMode.value.index == 1;
    if (isLooping) {
      _lastSavedSeconds = null;
      return false;
    }

    _historyService.addHistory(
      vid: reportVid,
      part: reportPart,
      time: -1,
      duration: currentDuration > 0 ? currentDuration.toInt() : 0,
    );
    hasReportedCompleted = true;
    return true;
  }

  /// 页面退出时保存最终进度
  void saveOnDispose(int currentVid, int currentPart, VideoPlayerController? playerController) {
    // 当 listeners 异常死亡导致 currentDuration 未更新时，直接从 player 读取
    var duration = currentDuration;
    if (duration <= 0 && playerController != null) {
      try {
        duration = playerController.player.state.duration.inSeconds.toDouble();
      } catch (_) {
        // player 已销毁时读取 state 可能抛异常，静默降级
      }
    }
    if (duration <= 0) return;

    // 优先从 player 读取实时位置（最准确），fallback 到上次回调记录的位置
    double? progressToSave;
    if (playerController != null) {
      try {
        final currentPosition = playerController.player.state.position;
        if (currentPosition.inSeconds > 0) {
          progressToSave = currentPosition.inSeconds.toDouble();
        }
      } catch (_) {
        // player 已销毁时读取 state 可能抛异常，使用 fallback
      }
    }
    progressToSave ??= lastReportedPosition?.inSeconds.toDouble();

    if (progressToSave == null || progressToSave <= 0) return;

    // 重置去重状态，确保退出时的最终上报不会被跳过
    _historyService.resetProgressState();

    final time = hasReportedCompleted ? -1.0 : progressToSave;
    _historyService.addHistory(
      vid: currentVid,
      part: currentPart,
      time: time,
      duration: duration.toInt(),
    );
  }

  /// 切换前上报当前进度（用于 _changePart / _switchToVideo）
  Future<void> saveBeforeSwitch(int vid, int part) async {
    final position = lastReportedPosition;
    final duration = currentDuration;
    if (position != null && duration > 0) {
      await _historyService.addHistory(
        vid: vid,
        part: part,
        time: hasReportedCompleted ? -1 : position.inSeconds.toDouble(),
        duration: duration.toInt(),
      );
    }
  }

  /// 重播时重置完成标记（UI 调用 onReplayAfterCompletion 时）
  void resetCompletionState() {
    hasReportedCompleted = false;
    _lastSavedSeconds = null;
  }
}
