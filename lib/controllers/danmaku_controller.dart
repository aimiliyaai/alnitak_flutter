import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/danmaku.dart';
import '../services/danmaku_service.dart';
import '../services/logger_service.dart';

/// 弹幕显示项（包含运行时状态）
class DanmakuItem {
  final Danmaku danmaku;
  /// 弹幕所在轨道索引
  int trackIndex;
  /// 弹幕动画开始时间（毫秒时间戳）
  int startTime;
  /// 暂停时累计的已播放时间（毫秒）
  int elapsedWhenPaused;
  /// 弹幕宽度（像素）
  double width;
  /// 是否已经显示完毕
  bool isExpired;

  DanmakuItem({
    required this.danmaku,
    this.trackIndex = 0,
    this.startTime = 0,
    this.elapsedWhenPaused = 0,
    this.width = 0,
    this.isExpired = false,
  });
}

/// 弹幕屏蔽类型
class DanmakuFilter {
  /// 屏蔽的弹幕类型：0-滚动, 1-顶部, 2-底部, 3-彩色
  final Set<int> disabledTypes;
  /// 弹幕屏蔽等级 (0-10)，随机过滤一定比例的弹幕
  final int disableLevel;

  const DanmakuFilter({
    this.disabledTypes = const {},
    this.disableLevel = 0,
  });

  DanmakuFilter copyWith({
    Set<int>? disabledTypes,
    int? disableLevel,
  }) {
    return DanmakuFilter(
      disabledTypes: disabledTypes ?? this.disabledTypes,
      disableLevel: disableLevel ?? this.disableLevel,
    );
  }

  /// 检查弹幕是否应该被屏蔽
  bool shouldFilter(Danmaku danmaku) {
    // 按类型屏蔽
    if (disabledTypes.contains(danmaku.type)) {
      return true;
    }

    // 彩色弹幕屏蔽（类型3）
    if (disabledTypes.contains(3)) {
      final color = danmaku.color.toLowerCase().replaceAll('#', '');
      // 非白色弹幕被视为彩色弹幕
      if (color != 'fff' && color != 'ffffff' && color != 'white') {
        return true;
      }
    }

    // 按等级随机屏蔽
    if (disableLevel > 0) {
      final random = (danmaku.id % 10) + 1;
      if (random <= disableLevel) {
        return true;
      }
    }

    return false;
  }
}

/// 弹幕控制器
class DanmakuController extends ChangeNotifier {
  /// 弹幕服务
  final DanmakuService _danmakuService = DanmakuService();
  final LoggerService _logger = LoggerService.instance;

  /// 原始弹幕数据（按时间排序）
  List<Danmaku> _danmakuList = [];

  /// 过滤后的弹幕数据
  List<Danmaku> _filteredDanmakuList = [];

  /// 当前显示的弹幕
  final List<DanmakuItem> _activeDanmakus = [];

  /// 当前视频ID
  int? _currentVid;
  /// 当前分P
  int _currentPart = 1;

  /// 弹幕配置
  DanmakuConfig _config = const DanmakuConfig();

  /// 弹幕屏蔽设置
  DanmakuFilter _filter = const DanmakuFilter();

  /// 当前播放进度（秒）
  double _currentTime = 0;

  /// 上次处理的弹幕索引（用于快速查找）
  int _lastProcessedIndex = 0;

  /// 是否正在播放
  bool _isPlaying = false;

  /// 是否显示弹幕
  bool _isVisible = false;

  /// 暂停时的时间戳
  int _pauseTime = 0;

  /// 记录最近一次的屏幕宽度，用于发送弹幕时立即计算轨道
  double _lastScreenWidth = 0;

  /// 记录最近一次的屏幕高度，用于动态计算轨道数
  double _lastScreenHeight = 0;

  /// 是否正在初始化阶段（surface 重建期间）
  bool _isInitializing = true;

  /// 轨道占用状态：记录每个轨道最后一个弹幕的离开时间
  /// key: 轨道索引, value: 轨道空闲时间点（毫秒时间戳）
  final Map<int, int> _scrollTrackEndTimes = {};
  final Map<int, int> _topTrackEndTimes = {};
  final Map<int, int> _bottomTrackEndTimes = {};

  /// 获取当前显示的弹幕列表
  List<DanmakuItem> get activeDanmakus => List.unmodifiable(_activeDanmakus);

  /// 获取弹幕配置
  DanmakuConfig get config => _config;

  /// 获取弹幕屏蔽设置
  DanmakuFilter get filter => _filter;

  /// 是否显示弹幕
  bool get isVisible => _isVisible;

  /// 是否正在播放
  bool get isPlaying => _isPlaying;

  /// 弹幕总数（过滤后）
  int get totalCount => _filteredDanmakuList.length;

  /// 原始弹幕总数
  int get rawTotalCount => _danmakuList.length;

  DanmakuController() {
    _loadSettings();
  }

  /// 加载保存的设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载弹幕显示开关（默认关闭）
      _isVisible = prefs.getBool('danmaku_visible') ?? false;

      // 加载屏蔽类型
      final disabledTypesStr = prefs.getString('danmaku_disabled_types');
      Set<int> disabledTypes = {};
      if (disabledTypesStr != null && disabledTypesStr.isNotEmpty) {
        disabledTypes = disabledTypesStr.split(',').map((e) => int.tryParse(e) ?? -1).where((e) => e >= 0).toSet();
      }

      // 加载屏蔽等级
      final disableLevel = prefs.getInt('danmaku_disable_level') ?? 0;

      // 加载透明度
      final opacity = prefs.getDouble('danmaku_opacity') ?? 1.0;

      // 加载字体大小
      final fontSize = prefs.getDouble('danmaku_font_size') ?? 18.0;

      // 加载显示区域
      final displayArea = prefs.getDouble('danmaku_display_area') ?? 0.75;

      // 加载速度
      final speedMultiplier = prefs.getDouble('danmaku_speed') ?? 1.0;

      _filter = DanmakuFilter(
        disabledTypes: disabledTypes,
        disableLevel: disableLevel,
      );

      _config = _config.copyWith(
        opacity: opacity,
        fontSize: fontSize,
        displayArea: displayArea,
        speedMultiplier: speedMultiplier,
        scrollDuration: Duration(milliseconds: (8000 / speedMultiplier).toInt()),
      );

       notifyListeners();
     } catch (e) {
       _logger.logWarning('加载弹幕设置失败: $e', tag: 'Danmaku');
     }
   }

   /// 保存设置
   Future<void> _saveSettings() async {
     try {
       final prefs = await SharedPreferences.getInstance();

       // 保存弹幕显示开关
       await prefs.setBool('danmaku_visible', _isVisible);

       // 保存屏蔽类型
       await prefs.setString('danmaku_disabled_types', _filter.disabledTypes.join(','));

       // 保存屏蔽等级
       await prefs.setInt('danmaku_disable_level', _filter.disableLevel);

       // 保存透明度
       await prefs.setDouble('danmaku_opacity', _config.opacity);

       // 保存字体大小
       await prefs.setDouble('danmaku_font_size', _config.fontSize);

       // 保存显示区域
       await prefs.setDouble('danmaku_display_area', _config.displayArea);

       // 保存速度
       await prefs.setDouble('danmaku_speed', _config.speedMultiplier);
     } catch (e) {
       _logger.logWarning('保存弹幕设置失败: $e', tag: 'Danmaku');
     }
   }

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

      // 应用过滤
      _applyFilter();

       // 重置状态
       _reset();

       _logger.logDebug('弹幕加载完成: ${_filteredDanmakuList.length}/${list.length}条', tag: 'Danmaku');
       notifyListeners();
     } catch (e) {
       _logger.logWarning('弹幕加载失败: $e', tag: 'Danmaku');
     }
   }

  /// 应用弹幕过滤
  void _applyFilter() {
    _filteredDanmakuList = _danmakuList.where((d) => !_filter.shouldFilter(d)).toList();
  }

  /// 重置弹幕状态
  void _reset() {
    _activeDanmakus.clear();
    _lastProcessedIndex = 0;
    _currentTime = 0;
    _pauseTime = 0;
    _scrollTrackEndTimes.clear();
    _topTrackEndTimes.clear();
    _bottomTrackEndTimes.clear();
  }

  /// 更新播放进度
  /// [time] 当前播放时间（秒）
  /// [screenWidth] 屏幕宽度（用于计算弹幕飞行时间）
  void updateTime(double time, {double screenWidth = 0}) {
    // 记录屏幕宽度，供发送弹幕时使用
    if (screenWidth > 0) {
      _lastScreenWidth = screenWidth;
    }

    // 检测 seek 操作（进度跳跃超过2秒）
    // 【关键】初始化阶段忽略正常的 position 变化（可能是 surface 重建导致的）
    if (_isInitializing) {
      // 如果位置从 0 变成非 0，认为是初始播放完成，退出初始化状态
      if (_currentTime == 0 && time > 0) {
        _isInitializing = false;
      }
      // 初始化阶段，检测到位置跳跃时记录但不处理，等初始化完成再说
      if ((time - _currentTime).abs() > 2) {
        _logger.logDebug('[Danmaku] 初始化阶段位置跳跃忽略: ${_currentTime.toStringAsFixed(1)}s -> ${time.toStringAsFixed(1)}s', tag: 'Danmaku');
      }
      _currentTime = time;
      return;
    }

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
     _logger.logDebug('弹幕 seek: ${_currentTime.toStringAsFixed(1)}s -> ${newTime.toStringAsFixed(1)}s', tag: 'Danmaku');

     // 【新增】如果是 surface 重置导致的位置回跳（从较长时间跳回 0/1 秒），不清空弹幕
     // 因为播放器会在 100ms 后恢复到正确位置
     if (_currentTime > 5 && newTime <= 1) {
       _logger.logDebug('[Danmaku] 检测到 surface 重置位置回跳，暂不清空弹幕，等待恢复', tag: 'Danmaku');
       // 只更新时间，不清空弹幕
       _currentTime = newTime;
       return;
     }

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
    if (_filteredDanmakuList.isEmpty) return 0;

    int left = 0;
    int right = _filteredDanmakuList.length - 1;

    while (left < right) {
      final mid = (left + right) ~/ 2;
      if (_filteredDanmakuList[mid].time < time) {
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

    // 扫描即将出现的弹幕（当前时间前后0.1秒内）
    while (_lastProcessedIndex < _filteredDanmakuList.length) {
      final danmaku = _filteredDanmakuList[_lastProcessedIndex];

      // 1. 弹幕时间还没到，停止扫描
      if (danmaku.time > _currentTime + 0.1) break;

      // 2. 弹幕时间已过（可能是 seek 导致跳过的），标记为已处理
      if (danmaku.time < _currentTime - 0.5) {
        _lastProcessedIndex++;
        continue;
      }

      // 3. 【新增关键逻辑】检测是否与正在飞行的"本地临时弹幕"重复
      // 查找 activeDanmakus 中是否有：ID为负数(本地) && 内容相同 && 时间相近 的弹幕
      final existingLocalIndex = _activeDanmakus.indexWhere((item) =>
      item.danmaku.id < 0 && // 是本地发送的临时弹幕
          item.danmaku.text == danmaku.text && // 内容一致
          item.danmaku.color == danmaku.color && // 颜色一致
          (item.danmaku.time - danmaku.time).abs() < 1.0 // 时间误差在1秒内
      );

      if (existingLocalIndex != -1) {
        // 找到了对应的本地弹幕！
        // 策略：用服务器返回的真实弹幕(包含真实ID)替换掉本地临时弹幕对象
        // 但保留原有的轨道、开始时间等状态，这样视觉上不会有跳动，也不会出现两条
        final oldItem = _activeDanmakus[existingLocalIndex];
        _activeDanmakus[existingLocalIndex] = DanmakuItem(
          danmaku: danmaku, // 替换为真实的 server 端弹幕
          trackIndex: oldItem.trackIndex,
          startTime: oldItem.startTime,
          elapsedWhenPaused: oldItem.elapsedWhenPaused,
          width: oldItem.width,
        );

        // 跳过创建新轨道，继续处理下一条
        _lastProcessedIndex++;
        continue;
      }

      // 4. 正常逻辑：尝试分配轨道
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

  /// 根据显示区域高度计算实际可用轨道数
  /// 轨道高度公式与 DanmakuOverlay 渲染一致：fontSize * 1.2 + 2(描边) + 6(间距)
  int _effectiveTrackCount(int configTrackCount) {
    if (_lastScreenHeight <= 0) return configTrackCount;
    final displayHeight = _lastScreenHeight * _config.displayArea;
    final trackHeight = _config.fontSize * 1.2 + 2 + 6;
    final maxTracks = (displayHeight / trackHeight).floor();
    return maxTracks.clamp(1, configTrackCount);
  }

  /// 分配滚动弹幕轨道
  int _allocateScrollTrack(int now, double screenWidth) {
    final trackCount = _effectiveTrackCount(_config.scrollTrackCount);
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
    final trackCount = _effectiveTrackCount(_config.fixedTrackCount);
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

    int expiredCount = 0;
    for (int i = _activeDanmakus.length - 1; i >= 0; i--) {
      final item = _activeDanmakus[i];
      final type = item.danmaku.danmakuType;
      final duration = type == DanmakuType.scroll
          ? _config.scrollDuration.inMilliseconds
          : _config.fixedDuration.inMilliseconds;

      final elapsed = item.elapsedWhenPaused + (now - item.startTime);
      if (elapsed > duration) {
        _activeDanmakus.removeAt(i);
        expiredCount++;
      }
    }

    if (expiredCount > 0) {
      notifyListeners();
    }
  }

  /// 开始播放
  void play() {
    if (_isPlaying) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 恢复播放时，调整弹幕的开始时间
    if (_pauseTime > 0) {
      final pauseDuration = now - _pauseTime;
      for (final item in _activeDanmakus) {
        item.startTime += pauseDuration;
      }
      // 同时调整轨道占用时间
      for (final key in _scrollTrackEndTimes.keys.toList()) {
        _scrollTrackEndTimes[key] = (_scrollTrackEndTimes[key] ?? 0) + pauseDuration;
      }
      for (final key in _topTrackEndTimes.keys.toList()) {
        _topTrackEndTimes[key] = (_topTrackEndTimes[key] ?? 0) + pauseDuration;
      }
      for (final key in _bottomTrackEndTimes.keys.toList()) {
        _bottomTrackEndTimes[key] = (_bottomTrackEndTimes[key] ?? 0) + pauseDuration;
      }
    }

    _isPlaying = true;
    _pauseTime = 0;
    notifyListeners();
  }

  /// 暂停播放
  void pause() {
    if (!_isPlaying) return;

    _isPlaying = false;
    _pauseTime = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// 切换弹幕显示/隐藏
  void toggleVisibility() {
    _isVisible = !_isVisible;
    if (!_isVisible) {
      _activeDanmakus.clear();
    }
    _saveSettings();
    notifyListeners();
  }

  /// 设置弹幕显示状态
  void setVisibility(bool visible) {
    if (_isVisible == visible) return;
    _isVisible = visible;
    if (!_isVisible) {
      _activeDanmakus.clear();
    }
    _saveSettings();
    notifyListeners();
  }

  /// 更新显示区域尺寸（由 DanmakuOverlay 调用，用于动态计算轨道数）
  void setDisplaySize(double width, double height) {
    if (width > 0) _lastScreenWidth = width;
    if (height > 0) _lastScreenHeight = height;
  }

  /// 更新弹幕配置
  void updateConfig(DanmakuConfig config) {
    _config = config;
    _saveSettings();
    notifyListeners();
  }

  /// 更新弹幕屏蔽设置
  void updateFilter(DanmakuFilter filter) {
    _filter = filter;
    _applyFilter();
    // 重置弹幕状态
    _activeDanmakus.clear();
    _lastProcessedIndex = _findStartIndex(_currentTime);
    _saveSettings();
    notifyListeners();
  }

  /// 切换弹幕类型屏蔽
  void toggleTypeFilter(int type) {
    final newDisabledTypes = Set<int>.from(_filter.disabledTypes);
    if (newDisabledTypes.contains(type)) {
      newDisabledTypes.remove(type);
    } else {
      newDisabledTypes.add(type);
    }
    updateFilter(_filter.copyWith(disabledTypes: newDisabledTypes));
  }

  /// 设置屏蔽等级
  void setDisableLevel(int level) {
    updateFilter(_filter.copyWith(disableLevel: level.clamp(0, 10)));
  }

  /// 发送弹幕
  Future<bool> sendDanmaku({
    required String text,
    int type = 0,
    String color = '#ffffff',
  }) async {
    if (_currentVid == null) return false;

    // 确保颜色有 # 前缀
    if (!color.startsWith('#')) {
      color = '#$color';
    }

    // 1. 本地立即显示 (Optimistic UI)
    // 修改说明：删除了 vid 和 part 参数，因为通常 Danmaku 模型不包含这两个字段
    final localDanmaku = Danmaku(
      id: -DateTime.now().millisecondsSinceEpoch, // 使用负数ID防止冲突
      time: _currentTime, // 使用当前播放时间
      type: type,
      color: color,
      text: text,
    );

    // 立即加入渲染队列
    _playLocalDanmaku(localDanmaku);

    // 【新增】立即更新弹幕数量（乐观更新）
    _danmakuList.add(localDanmaku);
    notifyListeners();

    // 2. 发送网络请求
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
      // 3. 发送成功后，刷新弹幕列表
      await _refreshDanmakuList();
    }

    return success;
  }

  /// 立即显示本地发送的弹幕
  void _playLocalDanmaku(Danmaku danmaku) {
    if (!_isVisible) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    // 使用最近一次记录的屏幕宽度，如果未记录则使用默认值 1000
    final screenWidth = _lastScreenWidth > 0 ? _lastScreenWidth : 1000.0;

    final trackIndex = _allocateTrack(danmaku, now, screenWidth);
    
    if (trackIndex != -1) {
      final item = DanmakuItem(
        danmaku: danmaku,
        trackIndex: trackIndex,
        startTime: now,
      );
      
      // 添加到当前活动弹幕列表
      _activeDanmakus.add(item);
      
      // 也可以选择加入历史列表，但为了避免影响索引，等待接口刷新通常更安全
      // 如果需要在 seek 回去时也能看到刚才发的，可以取消下面注释：
      // _danmakuList.add(danmaku); 
      // _danmakuList.sort((a, b) => a.time.compareTo(b.time));
      // _applyFilter();
      
      notifyListeners();
    }
  }

  /// 刷新弹幕列表（发送弹幕后调用）
  Future<void> _refreshDanmakuList() async {
    if (_currentVid == null) return;

    try {
      final list = await _danmakuService.getDanmakuList(
        vid: _currentVid!,
        part: _currentPart,
      );

      // 按时间排序
      list.sort((a, b) => a.time.compareTo(b.time));
      _danmakuList = list;

      // 应用过滤
      _applyFilter();

      // 这里不重置 _activeDanmakus，让本地发送的弹幕继续飞完
       // 只需更新 _lastProcessedIndex 以匹配新列表位置
       _lastProcessedIndex = _findStartIndex(_currentTime);

       _logger.logDebug('弹幕刷新完成: ${_filteredDanmakuList.length}/${list.length}条', tag: 'Danmaku');
       notifyListeners();
     } catch (e) {
       _logger.logWarning('弹幕刷新失败: $e', tag: 'Danmaku');
     }
   }

  /// 清空弹幕
  void clear() {
    _danmakuList.clear();
    _filteredDanmakuList.clear();
    _activeDanmakus.clear();
    _reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _activeDanmakus.clear();
    _danmakuList.clear();
    _filteredDanmakuList.clear();
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