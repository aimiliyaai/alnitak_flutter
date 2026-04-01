// 后端偶发返回非预期类型时，避免 List/num 等强转 String 崩溃。

String jsonAsString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is List) {
    return v
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .join(', ');
  }
  if (v is num || v is bool) return v.toString();
  return v.toString();
}

String? jsonAsStringOrNull(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  if (v is num) return v.toString();
  if (v is List) {
    if (v.isEmpty) return null;
    final s = jsonAsString(v);
    return s.isEmpty ? null : s;
  }
  final s = v.toString();
  return s.isEmpty ? null : s;
}

DateTime jsonAsDateTime(dynamic v, {DateTime? fallback}) {
  final fb = fallback ?? DateTime.now();
  if (v == null) return fb;
  if (v is String) {
    if (v.isEmpty) return fb;
    return DateTime.tryParse(v) ?? fb;
  }
  if (v is int) {
    if (v > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
    }
    return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true).toLocal();
  }
  return fb;
}

int jsonAsInt(dynamic v, [int defaultValue = 0]) {
  if (v == null) return defaultValue;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? defaultValue;
  return defaultValue;
}
