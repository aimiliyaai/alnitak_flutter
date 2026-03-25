import 'package:flutter_test/flutter_test.dart';
import 'package:alnitak_flutter/pages/video/video_page_controller.dart';
import 'package:alnitak_flutter/models/history_models.dart';

void main() {
  group('VideoPageController.resolveProgress', () {
    test('null 数据返回 fallbackPart + null 位置', () {
      final (part, position) = VideoPageController.resolveProgress(null, 3);
      expect(part, 3);
      expect(position, isNull);
    });

    test('progress == -1 (已看完) 返回历史 part + null 位置', () {
      final data = PlayProgressData(part: 5, progress: -1, duration: 120);
      final (part, position) = VideoPageController.resolveProgress(data, 1);
      expect(part, 5);
      expect(position, isNull);
    });

    test('正常进度回退 2 秒', () {
      final data = PlayProgressData(part: 1, progress: 60.0, duration: 120);
      final (part, position) = VideoPageController.resolveProgress(data, 1);
      expect(part, 1);
      expect(position, 58.0); // 60 - 2
    });

    test('进度 <= 2 秒时不回退', () {
      final data = PlayProgressData(part: 1, progress: 1.5, duration: 120);
      final (part, position) = VideoPageController.resolveProgress(data, 1);
      expect(part, 1);
      expect(position, 1.5);
    });

    test('进度接近结尾（剩余 <= 3秒）重置为 null', () {
      // duration 120, progress 119 → adjusted 117, remaining 3 → 重置
      final data = PlayProgressData(part: 2, progress: 119.0, duration: 120);
      final (part, position) = VideoPageController.resolveProgress(data, 1);
      expect(part, 2);
      expect(position, isNull);
    });

    test('进度恰好在结尾边界（剩余 = 4秒）不重置', () {
      // duration 120, progress 118 → adjusted 116, remaining 4 → 不重置
      final data = PlayProgressData(part: 2, progress: 118.0, duration: 120);
      final (part, position) = VideoPageController.resolveProgress(data, 1);
      expect(part, 2);
      expect(position, 116.0);
    });

    test('duration 为 0 时不做剩余时间检查，直接回退', () {
      final data = PlayProgressData(part: 1, progress: 50.0, duration: 0);
      final (part, position) = VideoPageController.resolveProgress(data, 1);
      expect(part, 1);
      expect(position, 48.0);
    });
  });
}
