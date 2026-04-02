import 'package:flutter_test/flutter_test.dart';
import 'package:alnitak_flutter/utils/video_route.dart';

void main() {
  group('pgcVideoPlayRef', () {
    test('带 epId', () {
      expect(pgcVideoPlayRef(42, epId: 7), 'pgc:42:7');
    });
    test('无 epId 为尾部冒号形式', () {
      expect(pgcVideoPlayRef(42), 'pgc:42:');
    });
    test('epId 为 0 与缺省一致', () {
      expect(pgcVideoPlayRef(42, epId: 0), 'pgc:42:');
    });
  });

  group('tryParsePgcVideoPlayRef', () {
    test('解析 vid 与 epId', () {
      final p = tryParsePgcVideoPlayRef('pgc:10:99');
      expect(p!.vid, 10);
      expect(p.epId, 99);
    });
    test('仅尾部为空 ep', () {
      final p = tryParsePgcVideoPlayRef('pgc:10:');
      expect(p!.vid, 10);
      expect(p.epId, isNull);
    });
    test('前后空白可 trim', () {
      final p = tryParsePgcVideoPlayRef('  pgc:1:2  ');
      expect(p!.vid, 1);
      expect(p.epId, 2);
    });
    test('非 PGC 返回 null', () {
      expect(tryParsePgcVideoPlayRef('abc123'), isNull);
    });
    test('vid 非数字返回 null', () {
      expect(tryParsePgcVideoPlayRef('pgc:abc:1'), isNull);
    });
  });

  group('resolveVideoRefForPlayback', () {
    test('PGC 转为 vid 数字串', () {
      expect(resolveVideoRefForPlayback('pgc:5:1'), '5');
    });
    test('普通 shortId 不变', () {
      expect(resolveVideoRefForPlayback('xyz'), 'xyz');
    });
    test('畸形 pgc 但第二段存在时退回第二段', () {
      expect(resolveVideoRefForPlayback('pgc:shortid:'), 'shortid');
    });
  });

  group('isPgcVideoPlayRef', () {
    test('前缀判断', () {
      expect(isPgcVideoPlayRef('pgc:1:2'), isTrue);
      expect(isPgcVideoPlayRef('1:2'), isFalse);
    });
  });
}
