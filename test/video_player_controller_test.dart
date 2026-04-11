import 'package:flutter_test/flutter_test.dart';
import 'package:alnitak_flutter/controllers/video_player_controller.dart';

void main() {
  group('hasValidVideoSize', () {
    test('空字符串返回 false', () {
      expect(VideoPlayerController.hasValidVideoSize(''), false);
    });

    test('有效 JSON 且 w/h > 0 返回 true', () {
      expect(
        VideoPlayerController.hasValidVideoSize('{"w": 1920, "h": 1080}'),
        true,
      );
    });

    test('w = 0 返回 false', () {
      expect(
        VideoPlayerController.hasValidVideoSize('{"w": 0, "h": 1080}'),
        false,
      );
    });

    test('h = 0 返回 false', () {
      expect(
        VideoPlayerController.hasValidVideoSize('{"w": 1920, "h": 0}'),
        false,
      );
    });

    test('缺少 w/h 字段返回 false', () {
      expect(
        VideoPlayerController.hasValidVideoSize('{"codec": "h264"}'),
        false,
      );
    });

    test('无效 JSON 返回 false', () {
      expect(
        VideoPlayerController.hasValidVideoSize('not json'),
        false,
      );
    });

    test('JSON 数组返回 false', () {
      expect(
        VideoPlayerController.hasValidVideoSize('[1, 2, 3]'),
        false,
      );
    });

    test('负数尺寸返回 false（toInt 后为负数，不满足 > 0）', () {
      expect(
        VideoPlayerController.hasValidVideoSize('{"w": -1, "h": 1080}'),
        false,
      );
    });

    test('浮点数尺寸可正常解析', () {
      expect(
        VideoPlayerController.hasValidVideoSize('{"w": 1920.0, "h": 1080.5}'),
        true,
      );
    });

    test('包含额外字段不影响结果', () {
      expect(
        VideoPlayerController.hasValidVideoSize(
            '{"w": 1920, "h": 1080, "pixelformat": "yuv420p"}'),
        true,
      );
    });
  });

  group('isRealCompletion', () {
    test('durMs = 0 时默认为真完成', () {
      expect(VideoPlayerController.isRealCompletion(5000, 0), true);
    });

    test('durMs < 0 时默认为真完成', () {
      expect(VideoPlayerController.isRealCompletion(0, -1), true);
    });

    test('播放进度 >= 90% 为真完成', () {
      // 90秒/100秒 = 90%
      expect(VideoPlayerController.isRealCompletion(90000, 100000), true);
    });

    test('播放进度 100% 为真完成', () {
      expect(VideoPlayerController.isRealCompletion(100000, 100000), true);
    });

    test('播放进度 < 90% 为假完成（断网）', () {
      // 50秒/100秒 = 50%
      expect(VideoPlayerController.isRealCompletion(50000, 100000), false);
    });

    test('播放进度 89% 为假完成', () {
      expect(VideoPlayerController.isRealCompletion(89000, 100000), false);
    });

    test('posMs = 0, durMs > 0 为假完成', () {
      expect(VideoPlayerController.isRealCompletion(0, 100000), false);
    });

    test('恰好 90% 边界为真完成', () {
      // 精确到毫秒: 9000/10000 = 0.9
      expect(VideoPlayerController.isRealCompletion(9000, 10000), true);
    });

    test('略低于 90% 边界为假完成', () {
      expect(VideoPlayerController.isRealCompletion(8999, 10000), false);
    });
  });
}
