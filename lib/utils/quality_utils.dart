/// 清晰度排序（按分辨率降序，同分辨率按帧率降序）
List<String> sortQualities(List<String> qualities) {
  final sorted = List<String>.from(qualities);
  sorted.sort((a, b) {
    final resA = _parseResolution(a);
    final resB = _parseResolution(b);
    if (resA != resB) return resB.compareTo(resA);
    return _parseFrameRate(b).compareTo(_parseFrameRate(a));
  });
  return sorted;
}

/// 获取推荐的默认清晰度（选择列表中第二高的）
String getDefaultQuality(List<String> qualities) {
  if (qualities.isEmpty) return '';
  final sorted = sortQualities(qualities);
  return sorted.length > 1 ? sorted[1] : sorted[0];
}

/// 清晰度标签（用于 UI 显示，YouTube风格：取短边作为分辨率标签）
///
/// 横屏: "1920x1080_3000k_30" → "1080P"
/// 竖屏: "1080x1920_2000k_30" → "1080P"
/// 高帧率: "1920x1080_6000k_60" → "1080P60"
/// 旧资源: "720p" → "720P"
String getQualityLabel(String quality) {
  final fps = _parseFrameRate(quality);
  final fpsSuffix = fps > 30 ? '$fps' : '';

  // 动态解析短边
  final shortSide = _extractShortSide(quality);
  if (shortSide > 0) {
    if (shortSide >= 2160) return '4K$fpsSuffix';
    if (shortSide >= 1440) return '2K$fpsSuffix';
    return '${shortSide}P$fpsSuffix';
  }

  // 旧资源格式：直接是 "720p"、"480p" 等，统一转大写
  final lowerQ = quality.toLowerCase();
  if (lowerQ == '1080p' || lowerQ == '720p' || lowerQ == '480p' ||
      lowerQ == '360p' || lowerQ == '4k' || lowerQ == '2k') {
    return quality.toUpperCase();
  }
  return quality;
}

/// 格式化清晰度显示名（更详细的映射，用于设置偏好匹配）
///
/// YouTube风格：取短边作为分辨率标签
/// 横屏: "1920x1080_6000k_30" → "1080p"
/// 竖屏: "1080x1920_2000k_30" → "1080p"
/// 高帧率: "1920x1080_8000k_60" → "1080p60"
String formatQualityDisplayName(String quality) {
  try {
    final parts = quality.split('_');
    final resolution = parts[0];
    final fps = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 30) : 30;

    if (resolution.contains('x')) {
      final dims = resolution.split('x');
      final w = int.tryParse(dims[0]);
      final h = int.tryParse(dims[1]);
      if (w != null && h != null) {
        final shortSide = w < h ? w : h;
        final suffix = fps > 30 ? '$fps' : '';
        if (shortSide <= 360) return '360p$suffix';
        if (shortSide <= 480) return '480p$suffix';
        if (shortSide <= 720) return '720p$suffix';
        if (shortSide <= 1080) return '1080p$suffix';
        if (shortSide <= 1440) return '2K$suffix';
        return '4K$suffix';
      }
    }
  } catch (_) {
    // 格式解析失败，返回原始 quality 字符串
  }

  return quality;
}

/// 在给定可用清晰度列表中，基于用户保存的显示名查找最佳匹配
///
/// 策略：
/// 1. 精确匹配显示名（例如 '1080p60'）
/// 2. 如果显示名包含帧率后缀（如 '1080p60'），尝试匹配基础名（'1080p'）
/// 3. 尝试选取不高于首选分辨率的最高清晰度
/// 4. 最后回退到 getDefaultQuality
String findBestQualityMatch(List<String> qualities, String? preferredDisplayName) {
  if (qualities.isEmpty) return '';
  final sorted = sortQualities(qualities);

  if (preferredDisplayName == null || preferredDisplayName.isEmpty) {
    return getDefaultQuality(qualities);
  }

  // 构建 displayName -> quality 映射（保留排序后首个匹配）
  final Map<String, String> displayToQuality = {};
  for (final q in sorted) {
    final dn = formatQualityDisplayName(q);
    displayToQuality.putIfAbsent(dn, () => q);
  }

  // 1. 精确匹配
  if (displayToQuality.containsKey(preferredDisplayName)) {
    return displayToQuality[preferredDisplayName]!;
  }

  // 2. 帧率后缀降级（例如 1080p60 -> 1080p）
  final fpsMatch = RegExp(r'^(\d+p)(\d+) ? ?$').firstMatch(preferredDisplayName);
  if (fpsMatch != null) {
    final base = fpsMatch.group(1)!;
    if (displayToQuality.containsKey(base)) return displayToQuality[base]!;
  }

  // 3. 尝试按分辨率降级
  final prefResMatch = RegExp(r'^(\d+)p').firstMatch(preferredDisplayName);
  if (prefResMatch != null) {
    final prefHeight = int.tryParse(prefResMatch.group(1)!) ?? 0;
    if (prefHeight > 0) {
      for (final q in sorted) {
        final height = _extractHeight(q);
        if (height > 0 && height <= prefHeight) return q;
      }
    }
  }

  // 4. 回退默认
  return getDefaultQuality(qualities);
}

// ============ 内部方法 ============

/// 解析分辨率用于排序
///
/// 新资源: "1920x1080_3000k_30" → 1920*1080
/// 旧资源: "720p" → 按已知分辨率映射
int _parseResolution(String quality) {
  try {
    final parts = quality.split('_');
    if (parts.isNotEmpty) {
      final dims = parts[0].split('x');
      if (dims.length == 2) {
        final w = int.tryParse(dims[0]);
        final h = int.tryParse(dims[1]);
        if (w != null && h != null) return w * h;
      }
    }
    final lowerQ = quality.toLowerCase().replaceAll('p', '');
    final height = int.tryParse(lowerQ);
    if (height != null) return (height * 16 ~/ 9) * height;
    if (lowerQ == '4k') return 3840 * 2160;
    if (lowerQ == '2k') return 2560 * 1440;
    return 0;
  } catch (_) {
    // 非标格式，像素数按 0 处理
    return 0;
  }
}

int _parseFrameRate(String quality) {
  final parts = quality.split('_');
  return parts.length >= 3 ? (int.tryParse(parts[2]) ?? 30) : 30;
}

/// 从 quality 字符串提取短边（YouTube风格）
/// 新格式: "1920x1080_3000k_30" → 1080
/// 竖屏: "1080x1920_2000k_30" → 1080
/// 旧格式: "720p" → 720
int _extractShortSide(String quality) {
  final parts = quality.split('_');
  if (parts.isNotEmpty) {
    final dims = parts[0].split('x');
    if (dims.length == 2) {
      final w = int.tryParse(dims[0]);
      final h = int.tryParse(dims[1]);
      if (w != null && h != null) return w < h ? w : h;
    }
  }
  final match = RegExp(r'^(\d+)p', caseSensitive: false).firstMatch(quality);
  if (match != null) {
    return int.tryParse(match.group(1)!) ?? 0;
  }
  return 0;
}

/// 从 quality 字符串提取短边（兼容别名）
int _extractHeight(String quality) => _extractShortSide(quality);
