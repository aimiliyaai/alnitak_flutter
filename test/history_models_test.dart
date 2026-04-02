import 'package:flutter_test/flutter_test.dart';
import 'package:alnitak_flutter/models/history_models.dart';

void main() {
  test('HistoryItem 解析 PGC 字段', () {
    final item = HistoryItem.fromJson({
      'vid': 1,
      'uid': 2,
      'title': '单集标题',
      'cover': 'c',
      'desc': 'd',
      'time': 1.0,
      'duration': 100,
      'updatedAt': '2020-01-01',
      'pgcAttached': true,
      'pgcTitle': '系列名',
      'episodeTitle': 'Hello',
      'episodeNumber': 3,
      'epId': 99,
    });
    expect(item.pgcAttached, isTrue);
    expect(item.pgcTitle, '系列名');
    expect(item.episodeTitle, 'Hello');
    expect(item.episodeNumber, 3);
    expect(item.epId, 99);
  });

  test('HistoryItem 缺省 PGC 键时兼容旧接口', () {
    final item = HistoryItem.fromJson({
      'vid': 1,
      'uid': 2,
      'title': 't',
      'cover': 'c',
      'desc': 'd',
      'time': 0.0,
      'duration': 0,
      'updatedAt': 'x',
    });
    expect(item.pgcAttached, isFalse);
    expect(item.epId, 0);
    expect(item.episodeNumber, 0);
  });
}
