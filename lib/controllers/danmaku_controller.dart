import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/danmaku.dart';
import '../services/danmaku_service.dart';

/// 弹幕显示项（包含运行时状态）
class DanmakuItem {
  final Danmaku danmaku;
  /// 弹幕所在轨道索引
  int trackIndex;
  /// 弹幕动画开始时间（毫秒时间戳）
  int startTime;
  /// 弹幕宽度（像素）
  double width;
  /// 是否已经显示完毕
  bool isExpired;

  DanmakuItem({
    required this.danmaku,
    this.trackIndex = 0,
    this.startTime = 0,
    this.width = 0,
    this.isExpired = false,
  });
}

/// 弹幕控制器
///
/// 商业级弹幕方案核心功能：
/// - 轨道管理：防止弹幕重叠
/// - 碰撞检测：确保弹幕不会追尾
/// - 时间同步：与视频播放进度精确同步
/// - 性能优化：弹幕池复用、过期清理
class DanmakuController extends ChangeNotifier {
  /// 弹幕服务
  final DanmakuService _danmakuService = DanmakuService();

  /// 原始弹幕数据（按时间排序）
  List<Danmaku> _danmakuList = [];

  /// 当前显示的弹幕
  final List<DanmakuItem> _activeDanmakus = [];

  /// 当前视频ID
  int? _currentVid;
  /// 当前分P
  int _currentPart = 1;

  /// 弹幕配置
  DanmakuConfig _config = const DanmakuConfig();

  /// 当前播放进度（秒）
  double _currentTime = 0;

  /// 上次处理的弹幕索引（用于快速查找）
  int _lastProcessedIndex = 0;

  /// 是否正在播放
  bool _isPlaying = false;

  /// 是否显示弹幕
  bool _isVisible = true;

  /// 轨道占用状态：记录每个轨道最后一个弹幕的离开时间
  /// key: 轨道索引, value: 轨道空闲时间点（毫秒时间戳）
  final Map<int, int> _scrollTrackEndTimes = {};
  final Map<int, int> _topTrackEndTimes = {};
  final Map<int, int> _bottomTrackEndTimes = {};

  /// 获取当前显示的弹幕列表
  List<DanmakuItem> get activeDanmakus => List.unmodifiable(_activeDanmakus);

  /// 获取弹幕配置
  DanmakuConfig get config => _config;

  /// 是否显示弹幕
  bool get isVisible => _isVisible;

  /// 弹幕总数
  int get totalCount => _danmakuList.length;

  /// 加载弹幕数据
  Future<void> loadDanmaku({
    required int vid,
    int part = 1,
  }) async {
    _currentVid = vid;
    _currentPart = part;

    try {
      final list = await _danmakuService.getDanmakuList(
        vid: vid,
        part: part,
      );

      // 按时间排序
      list.sort((a, b) => a.time.compareTo(b.time));
      _danmakuList = list;

      // 重置状态
      _reset();

      print('📝 弹幕加载完成: ${list.length}条');
      notifyListeners();
    } catch (e) {
      print('📝 弹幕加载失败: $e');
    }
  }

  /// 重置弹幕状态
  void _reset() {
    _activeDanmakus.clear();
    _lastProcessedIndex = 0;
    _currentTime = 0;
    _scrollTrackEndTimes.clear();
    _topTrackEndTimes.clear();
    _bottomTrackEndTimes.clear();
  }

  /// 更新播放进度
  /// [time] 当前播放时间（秒）
  /// [screenWidth] 屏幕宽度（用于计算弹幕飞行时间）
  void updateTime(double time, {double screenWidth = 0}) {
    // 检测 seek 操作（进度跳跃超过2秒）
    if ((time - _currentTime).abs() > 2) {
      _onSeek(time);
    }

    _currentTime = time;

    if (!_isPlaying || !_isVisible) return;

    // 处理新弹幕
    _processNewDanmakus(screenWidth);

    // 清理过期弹幕
    _cleanExpiredDanmakus();

    notifyListeners();
  }

  /// 处理进度跳跃
  void _onSeek(double newTime) {
    print('📝 弹幕 seek: ${_currentTime.toStringAsFixed(1)}s -> ${newTime.toStringAsFixed(1)}s');

    // 清空当前显示的弹幕
    _activeDanmakus.clear();
    _scrollTrackEndTimes.clear();
    _topTrackEndTimes.clear();
    _bottomTrackEndTimes.clear();

    // 二分查找新的起始位置
    _lastProcessedIndex = _findStartIndex(newTime);
  }

  /// 二分查找起始索引
  int _findStartIndex(double time) {
    if (_danmakuList.isEmpty) return 0;

    int left = 0;
    int right = _danmakuList.length - 1;

    while (left < right) {
      final mid = (left + right) ~/ 2;
      if (_danmakuList[mid].time < time) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }

    return left;
  }

  /// 处理新弹幕
  void _processNewDanmakus(double screenWidth) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 扫描即将出现的弹幕（当前时间前后0.5秒内）
    while (_lastProcessedIndex < _danmakuList.length) {
      final danmaku = _danmakuList[_lastProcessedIndex];

      // 弹幕时间还没到
      if (danmaku.time > _currentTime + 0.1) break;

      // 弹幕时间已过（可能是 seek 导致跳过的）
      if (danmaku.time < _currentTime - 0.5) {
        _lastProcessedIndex++;
        continue;
      }

      // 尝试分配轨道
      final trackIndex = _allocateTrack(danmaku, now, screenWidth);
      if (trackIndex != -1) {
        final item = DanmakuItem(
          danmaku: danmaku,
          trackIndex: trackIndex,
          startTime: now,
        );
        _activeDanmakus.add(item);
      }

      _lastProcessedIndex++;
    }
  }

  /// 分配弹幕轨道
  /// 返回 -1 表示没有可用轨道（丢弃弹幕）
  int _allocateTrack(Danmaku danmaku, int now, double screenWidth) {
    final type = danmaku.danmakuType;

    switch (type) {
      case DanmakuType.scroll:
        return _allocateScrollTrack(now, screenWidth);
      case DanmakuType.top:
        return _allocateFixedTrack(_topTrackEndTimes, now);
      case DanmakuType.bottom:
        return _allocateFixedTrack(_bottomTrackEndTimes, now);
    }
  }

  /// 分配滚动弹幕轨道
  int _allocateScrollTrack(int now, double screenWidth) {
    final trackCount = _config.scrollTrackCount;
    final duration = _config.scrollDuration.inMilliseconds;

    // 估算弹幕完全进入屏幕所需时间（假设弹幕宽度为屏幕的1/4）
    final enterTime = duration ~/ 4;

    for (int i = 0; i < trackCount; i++) {
      final endTime = _scrollTrackEndTimes[i] ?? 0;
      if (now >= endTime) {
        // 轨道空闲，分配
        _scrollTrackEndTimes[i] = now + enterTime;
        return i;
      }
    }

    // 没有空闲轨道
    return _config.allowOverlap ? 0 : -1;
  }

  /// 分配固定弹幕轨道
  int _allocateFixedTrack(Map<int, int> trackEndTimes, int now) {
    final trackCount = _config.fixedTrackCount;
    final duration = _config.fixedDuration.inMilliseconds;

    for (int i = 0; i < trackCount; i++) {
      final endTime = trackEndTimes[i] ?? 0;
      if (now >= endTime) {
        // 轨道空闲，分配
        trackEndTimes[i] = now + duration;
        return i;
      }
    }

    // 没有空闲轨道
    return _config.allowOverlap ? 0 : -1;
  }

  /// 清理过期弹幕
  void _cleanExpiredDanmakus() {
    final now = DateTime.now().millisecondsSinceEpoch;

    _activeDanmakus.removeWhere((item) {
      final type = item.danmaku.danmakuType;
      final duration = type == DanmakuType.scroll
          ? _config.scrollDuration.inMilliseconds
          : _config.fixedDuration.inMilliseconds;

      return now - item.startTime > duration;
    });
  }

  /// 开始播放
  void play() {
    _isPlaying = true;
    notifyListeners();
  }

  /// 暂停播放
  void pause() {
    _isPlaying = false;
    notifyListeners();
  }

  /// 切换弹幕显示/隐藏
  void toggleVisibility() {
    _isVisible = !_isVisible;
    if (!_isVisible) {
      _activeDanmakus.clear();
    }
    notifyListeners();
  }

  /// 设置弹幕显示状态
  void setVisibility(bool visible) {
    if (_isVisible == visible) return;
    _isVisible = visible;
    if (!_isVisible) {
      _activeDanmakus.clear();
    }
    notifyListeners();
  }

  /// 更新弹幕配置
  void updateConfig(DanmakuConfig config) {
    _config = config;
    notifyListeners();
  }

  /// 发送弹幕
  Future<bool> sendDanmaku({
    required String text,
    int type = 0,
    String color = '#ffffff',
  }) async {
    if (_currentVid == null) return false;

    final request = SendDanmakuRequest(
      vid: _currentVid!,
      part: _currentPart,
      time: _currentTime,
      type: type,
      color: color,
      text: text,
    );

    final success = await _danmakuService.sendDanmaku(request);

    if (success) {
      // 立即显示自己发送的弹幕
      final danmaku = Danmaku(
        id: DateTime.now().millisecondsSinceEpoch,
        time: _currentTime,
        type: type,
        color: color,
        text: text,
      );

      final trackIndex = _allocateTrack(
        danmaku,
        DateTime.now().millisecondsSinceEpoch,
        0,
      );

      if (trackIndex != -1) {
        _activeDanmakus.add(DanmakuItem(
          danmaku: danmaku,
          trackIndex: trackIndex,
          startTime: DateTime.now().millisecondsSinceEpoch,
        ));
        notifyListeners();
      }
    }

    return success;
  }

  /// 清空弹幕
  void clear() {
    _danmakuList.clear();
    _activeDanmakus.clear();
    _reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _activeDanmakus.clear();
    _danmakuList.clear();
    super.dispose();
  }
}

/// 弹幕配置
class DanmakuConfig {
  /// 滚动弹幕轨道数
  final int scrollTrackCount;
  /// 固定弹幕轨道数（顶部/底部共用）
  final int fixedTrackCount;
  /// 滚动弹幕持续时间
  final Duration scrollDuration;
  /// 固定弹幕持续时间
  final Duration fixedDuration;
  /// 弹幕字体大小
  final double fontSize;
  /// 弹幕透明度（0.0-1.0）
  final double opacity;
  /// 是否允许弹幕重叠（当轨道不足时）
  final bool allowOverlap;
  /// 弹幕显示区域（0.0-1.0，表示屏幕高度的比例）
  final double displayArea;
  /// 弹幕速度倍率（1.0为正常速度）
  final double speedMultiplier;

  const DanmakuConfig({
    this.scrollTrackCount = 8,
    this.fixedTrackCount = 4,
    this.scrollDuration = const Duration(seconds: 8),
    this.fixedDuration = const Duration(seconds: 4),
    this.fontSize = 18,
    this.opacity = 1.0,
    this.allowOverlap = false,
    this.displayArea = 0.75,
    this.speedMultiplier = 1.0,
  });

  DanmakuConfig copyWith({
    int? scrollTrackCount,
    int? fixedTrackCount,
    Duration? scrollDuration,
    Duration? fixedDuration,
    double? fontSize,
    double? opacity,
    bool? allowOverlap,
    double? displayArea,
    double? speedMultiplier,
  }) {
    return DanmakuConfig(
      scrollTrackCount: scrollTrackCount ?? this.scrollTrackCount,
      fixedTrackCount: fixedTrackCount ?? this.fixedTrackCount,
      scrollDuration: scrollDuration ?? this.scrollDuration,
      fixedDuration: fixedDuration ?? this.fixedDuration,
      fontSize: fontSize ?? this.fontSize,
      opacity: opacity ?? this.opacity,
      allowOverlap: allowOverlap ?? this.allowOverlap,
      displayArea: displayArea ?? this.displayArea,
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
    );
  }
}
