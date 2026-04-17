import 'package:flutter_test/flutter_test.dart';
import 'package:alnitak_flutter/pages/video/progress_tracker.dart';
import 'package:alnitak_flutter/services/history_service.dart';

/// 轻量 HistoryService mock：记录所有 addHistory 调用，不发网络请求
class MockHistoryService extends HistoryService {
  final List<Map<String, dynamic>> calls = [];

  MockHistoryService() : super.forTest();

  @override
  Future<bool> addHistory({
    required String vid,
    String? rid,
    int part = 1,
    required double time,
    required int duration,
  }) async {
    calls.add({'vid': vid, 'rid': rid, 'part': part, 'time': time, 'duration': duration});
    return true;
  }

  @override
  void resetProgressState() {
    // no-op
  }

  Map<String, dynamic>? get lastCall => calls.isNotEmpty ? calls.last : null;
}

void main() {
  late MockHistoryService mockHistory;
  late ProgressTracker tracker;

  setUp(() {
    mockHistory = MockHistoryService();
    tracker = ProgressTracker(historyService: mockHistory);
  });

  group('lock / unlock / reset', () {
    test('初始状态未锁定', () {
      expect(tracker.reportVid, isNull);
      expect(tracker.reportRid, isNull);
      expect(tracker.reportPart, isNull);
    });

    test('lock 设置 vid/rid/part', () {
      tracker.lock('100', 'r1', 2);
      expect(tracker.reportVid, '100');
      expect(tracker.reportRid, 'r1');
      expect(tracker.reportPart, 2);
    });

    test('lock 不带 rid', () {
      tracker.lock('100', null, 2);
      expect(tracker.reportVid, '100');
      expect(tracker.reportRid, isNull);
      expect(tracker.reportPart, 2);
    });

    test('unlock 清空 vid/rid/part', () {
      tracker.lock('100', 'r1', 2);
      tracker.unlock();
      expect(tracker.reportVid, isNull);
      expect(tracker.reportRid, isNull);
      expect(tracker.reportPart, isNull);
    });

    test('reset 清空所有播放状态', () {
      tracker.lock('1', null, 1);
      tracker.onProgressUpdate(
        const Duration(seconds: 30),
        const Duration(seconds: 120),
      );
      tracker.reset();

      expect(tracker.lastReportedPosition, isNull);
      expect(tracker.hasReportedCompleted, false);
      expect(tracker.currentDuration, 0);
    });
  });

  group('onProgressUpdate', () {
    test('未锁定时返回 null 且不上报', () {
      final result = tracker.onProgressUpdate(
        const Duration(seconds: 10),
        const Duration(seconds: 120),
      );
      expect(result, isNull);
      expect(mockHistory.calls, isEmpty);
    });

    test('锁定后返回 (vid, rid, part)', () {
      tracker.lock('1', 'r1', 1);
      final result = tracker.onProgressUpdate(
        const Duration(seconds: 10),
        const Duration(seconds: 120),
      );
      expect(result, ('1', 'r1', 1));
    });

    test('首次上报立即写入', () {
      tracker.lock('1', null, 1);
      tracker.onProgressUpdate(
        const Duration(seconds: 10),
        const Duration(seconds: 120),
      );
      expect(mockHistory.calls.length, 1);
      expect(mockHistory.lastCall!['time'], 10.0);
      expect(mockHistory.lastCall!['duration'], 120);
      expect(mockHistory.lastCall!['vid'], '1');
      expect(mockHistory.lastCall!['rid'], isNull);
    });

    test('5秒内不重复上报（节流）', () {
      tracker.lock('1', 'r1', 1);
      tracker.onProgressUpdate(
        const Duration(seconds: 10),
        const Duration(seconds: 120),
      );
      // 11秒、12秒、13秒、14秒 —— 都不到 5 秒间隔
      for (var s = 11; s <= 14; s++) {
        tracker.onProgressUpdate(
          Duration(seconds: s),
          const Duration(seconds: 120),
        );
      }
      expect(mockHistory.calls.length, 1); // 仍然只有1次
    });

    test('超过5秒间隔触发第二次上报', () {
      tracker.lock('1', 'r1', 1);
      tracker.onProgressUpdate(
        const Duration(seconds: 10),
        const Duration(seconds: 120),
      );
      tracker.onProgressUpdate(
        const Duration(seconds: 15),
        const Duration(seconds: 120),
      );
      expect(mockHistory.calls.length, 2);
      expect(mockHistory.lastCall!['time'], 15.0);
    });

    test('duration 为 0 时不上报但更新 lastReportedPosition', () {
      tracker.lock('1', null, 1);
      final result = tracker.onProgressUpdate(
        const Duration(seconds: 5),
        Duration.zero,
      );
      expect(result, ('1', null, 1));
      expect(mockHistory.calls, isEmpty);
      expect(tracker.lastReportedPosition, const Duration(seconds: 5));
    });

    test('进度超过时长+2秒不上报', () {
      tracker.lock('1', null, 1);
      // 先设置 duration
      tracker.onProgressUpdate(
        const Duration(seconds: 10),
        const Duration(seconds: 120),
      );
      mockHistory.calls.clear();

      // position 超过 duration+2
      tracker.onProgressUpdate(
        const Duration(seconds: 123),
        const Duration(seconds: 120),
      );
      expect(mockHistory.calls, isEmpty);
    });

    test('已上报完成后不再上报进度', () {
      tracker.lock('1', null, 1);
      // 模拟播放到结束
      tracker.onProgressUpdate(
        const Duration(seconds: 100),
        const Duration(seconds: 120),
      );
      tracker.onVideoEnded('1', null, 1, null);
      mockHistory.calls.clear();

      // 继续收到进度回调
      tracker.onProgressUpdate(
        const Duration(seconds: 110),
        const Duration(seconds: 120),
      );
      expect(mockHistory.calls, isEmpty);
    });
  });

  group('onVideoEnded', () {
    test('duration 为 0 时返回 false', () {
      tracker.lock('1', null, 1);
      final result = tracker.onVideoEnded('1', null, 1, null);
      expect(result, false);
    });

    test('正常结束：上报 -1 并返回 true', () {
      tracker.lock('1', null, 1);
      tracker.onProgressUpdate(
        const Duration(seconds: 100),
        const Duration(seconds: 120),
      );
      mockHistory.calls.clear();

      final result = tracker.onVideoEnded('1', null, 1, null);
      expect(result, true);
      expect(tracker.hasReportedCompleted, true);
      expect(mockHistory.lastCall!['time'], -1);
      expect(mockHistory.lastCall!['vid'], '1');
    });

    test('重复调用 onVideoEnded 返回 false', () {
      tracker.lock('1', null, 1);
      tracker.onProgressUpdate(
        const Duration(seconds: 100),
        const Duration(seconds: 120),
      );
      tracker.onVideoEnded('1', null, 1, null);

      final result = tracker.onVideoEnded('1', null, 1, null);
      expect(result, false);
    });

    test('使用锁定的 vid/rid/part 而非传入参数', () {
      tracker.lock('10', 'r2', 3);
      tracker.onProgressUpdate(
        const Duration(seconds: 50),
        const Duration(seconds: 60),
      );
      mockHistory.calls.clear();

      // 传入不同的 vid/rid/part，但应使用锁定值
      tracker.onVideoEnded('99', 'r99', 99, null);
      expect(mockHistory.lastCall!['vid'], '10');
      expect(mockHistory.lastCall!['rid'], 'r2');
      expect(mockHistory.lastCall!['part'], 3);
    });
  });

  group('saveBeforeSwitch', () {
    test('有进度时上报当前位置', () async {
      tracker.lock('1', null, 1);
      tracker.onProgressUpdate(
        const Duration(seconds: 30),
        const Duration(seconds: 120),
      );
      mockHistory.calls.clear();

      await tracker.saveBeforeSwitch('1', null, 1);
      expect(mockHistory.lastCall!['time'], 30.0);
      expect(mockHistory.lastCall!['vid'], '1');
    });

    test('有rid时上报rid', () async {
      tracker.lock('1', 'r1', 1);
      tracker.onProgressUpdate(
        const Duration(seconds: 30),
        const Duration(seconds: 120),
      );
      mockHistory.calls.clear();

      await tracker.saveBeforeSwitch('1', 'r1', 1);
      expect(mockHistory.lastCall!['rid'], 'r1');
    });

    test('已上报完成时保存 -1', () async {
      tracker.lock('1', null, 1);
      tracker.onProgressUpdate(
        const Duration(seconds: 100),
        const Duration(seconds: 120),
      );
      tracker.onVideoEnded('1', null, 1, null);
      mockHistory.calls.clear();

      await tracker.saveBeforeSwitch('1', null, 1);
      expect(mockHistory.lastCall!['time'], -1);
    });

    test('无进度时不上报', () async {
      await tracker.saveBeforeSwitch('1', null, 1);
      expect(mockHistory.calls, isEmpty);
    });
  });

  group('resetCompletionState', () {
    test('重置后可以重新上报进度', () {
      tracker.lock('1', null, 1);
      tracker.onProgressUpdate(
        const Duration(seconds: 100),
        const Duration(seconds: 120),
      );
      tracker.onVideoEnded('1', null, 1, null);
      mockHistory.calls.clear();

      tracker.resetCompletionState();
      expect(tracker.hasReportedCompleted, false);

      // 重播后应该能重新上报
      tracker.onProgressUpdate(
        const Duration(seconds: 5),
        const Duration(seconds: 120),
      );
      expect(mockHistory.calls.length, 1);
      expect(mockHistory.lastCall!['time'], 5.0);
    });
  });
}
