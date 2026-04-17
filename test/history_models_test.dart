import 'package:flutter_test/flutter_test.dart';
import 'package:alnitak_flutter/models/history_models.dart';

void main() {
  test('HistoryItem 解析 PGC 字段', () {
    final item = HistoryItem.fromJson({
      'vid': '1',
      'shortId': 'abc123',
      'rid': 'r456',
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
    expect(item.vid, '1');
    expect(item.shortId, 'abc123');
    expect(item.rid, 'r456');
    expect(item.pgcAttached, isTrue);
    expect(item.pgcTitle, '系列名');
    expect(item.episodeTitle, 'Hello');
    expect(item.episodeNumber, 3);
    expect(item.epId, 99);
  });

  test('HistoryItem 缺省 PGC 键时兼容旧接口', () {
    final item = HistoryItem.fromJson({
      'vid': '123',
      'uid': 2,
      'title': 't',
      'cover': 'c',
      'desc': 'd',
      'time': 0.0,
      'duration': 0,
      'updatedAt': 'x',
    });
    expect(item.vid, '123');
    expect(item.shortId, isNull);
    expect(item.rid, isNull);
    expect(item.pgcAttached, isFalse);
    expect(item.epId, 0);
    expect(item.episodeNumber, 0);
  });

  test('AddHistoryRequest 包含 rid 字段', () {
    final request = AddHistoryRequest(
      vid: '12345',
      rid: 'r678',
      part: 2,
      time: 30.0,
      duration: 120,
    );
    final json = request.toJson();
    expect(json['vid'], '12345');
    expect(json['rid'], 'r678');
    expect(json['part'], 2);
  });

  test('AddHistoryRequest 无 rid 时不包含该字段', () {
    final request = AddHistoryRequest(
      vid: '12345',
      part: 1,
      time: 10.0,
      duration: 60,
    );
    final json = request.toJson();
    expect(json.containsKey('rid'), isFalse);
  });
}
