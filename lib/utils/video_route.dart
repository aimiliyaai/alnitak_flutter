/// 播放页路由/API 使用的视频标识：与后端 ParseVideoID 一致，优先 opaque shortId。
String videoPathRef({required int vid, String? shortId}) {
  final s = shortId?.trim();
  if (s != null && s.isNotEmpty) return s;
  return vid.toString();
}
