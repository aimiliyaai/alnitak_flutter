/// 图片工具类
class ImageUtils {
  static const String baseUrl = 'http://anime.ayypd.cn:3000';

  /// 获取完整的图片URL
  static String getFullImageUrl(String? path) {
    if (path == null || path.isEmpty) return '';

    // 已经是完整URL
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    // 拼接baseUrl
    // API返回的是相对路径，例如: "/api/image/1887881468064043008.png"
    return '$baseUrl$path';
  }
}
