/// 播放页路由/API 使用的视频标识：与后端 ParseVideoID 一致，优先 opaque shortId。
String videoPathRef({required int vid, String? shortId}) {
  final s = shortId?.trim();
  if (s != null && s.isNotEmpty) return s;
  return vid.toString();
}

// ---------------------------------------------------------------------------
// PGC 播放页 [VideoPlayPage.videoRef]：`pgc:<vid>[:<epId>]`
// ---------------------------------------------------------------------------

/// [videoRef] 是否以 PGC 协议开头（与 [pgcVideoPlayRef] / [tryParsePgcVideoPlayRef] 成对使用）。
const String kPgcVideoPlayRefPrefix = 'pgc:';

bool isPgcVideoPlayRef(String ref) => ref.trim().startsWith(kPgcVideoPlayRefPrefix);

/// 构造 PGC 播放路由字符串。
/// [epId] 缺省或 ≤0 时生成 `pgc:<vid>:`，仍进入 PGC 播放模式。
String pgcVideoPlayRef(int vid, {int? epId}) {
  if (epId != null && epId > 0) {
    return '$kPgcVideoPlayRefPrefix$vid:$epId';
  }
  return '$kPgcVideoPlayRefPrefix$vid:';
}

/// 从 `pgc:` 引用中解析出的 vid / 可选 epId（第二段须为正整数）。
class ParsedPgcVideoPlayRef {
  final int vid;
  final int? epId;

  const ParsedPgcVideoPlayRef({required this.vid, this.epId});
}

/// 解析成功返回结构化结果；格式非法或 vid 非正整数返回 null。
ParsedPgcVideoPlayRef? tryParsePgcVideoPlayRef(String raw) {
  final t = raw.trim();
  if (!isPgcVideoPlayRef(t)) return null;
  final parts = t.split(':');
  if (parts.length < 2) return null;
  final vidStr = parts[1].trim();
  if (vidStr.isEmpty) return null;
  final vid = int.tryParse(vidStr);
  if (vid == null || vid <= 0) return null;
  int? epId;
  if (parts.length >= 3) {
    final epStr = parts[2].trim();
    if (epStr.isNotEmpty) {
      final ep = int.tryParse(epStr);
      if (ep != null && ep > 0) epId = ep;
    }
  }
  return ParsedPgcVideoPlayRef(vid: vid, epId: epId);
}

/// 交给 [VideoPageController.init] / 拉取详情的「纯视频标识」：PGC 时去掉前缀只保留 vid 字符串。
///
/// 若带 `pgc:` 前缀但第二段无法解析为整数，仍退回旧逻辑取第二段字符串，以免误伤非数字 vid 的极端数据。
String resolveVideoRefForPlayback(String videoRef) {
  final t = videoRef.trim();
  final parsed = tryParsePgcVideoPlayRef(t);
  if (parsed != null) return parsed.vid.toString();
  if (isPgcVideoPlayRef(t)) {
    final parts = t.split(':');
    if (parts.length >= 2 && parts[1].trim().isNotEmpty) {
      return parts[1].trim();
    }
  }
  return t;
}
