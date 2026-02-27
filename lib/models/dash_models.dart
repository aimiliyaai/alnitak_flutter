import '../config/api_config.dart';
import 'data_source.dart';

/// DASH 视频流信息
class DashVideoItem {
  final String id;
  final String baseUrl;
  final int bandwidth;
  final String mimeType;
  final String codecs;
  final int width;
  final int height;
  final String frameRate;

  const DashVideoItem({
    required this.id,
    required this.baseUrl,
    required this.bandwidth,
    required this.mimeType,
    required this.codecs,
    required this.width,
    required this.height,
    required this.frameRate,
  });

  factory DashVideoItem.fromJson(Map<String, dynamic> json) {
    return DashVideoItem(
      id: json['id']?.toString() ?? '',
      baseUrl: json['baseUrl']?.toString() ?? '',
      bandwidth: json['bandwidth'] as int? ?? 0,
      mimeType: json['mimeType']?.toString() ?? 'video/mp4',
      codecs: json['codecs']?.toString() ?? '',
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      frameRate: json['frameRate']?.toString() ?? '30.000',
    );
  }
}

/// DASH 音频流信息
class DashAudioItem {
  final String id;
  final String baseUrl;
  final int bandwidth;
  final String mimeType;
  final String codecs;

  const DashAudioItem({
    required this.id,
    required this.baseUrl,
    required this.bandwidth,
    required this.mimeType,
    required this.codecs,
  });

  factory DashAudioItem.fromJson(Map<String, dynamic> json) {
    return DashAudioItem(
      id: json['id']?.toString() ?? '',
      baseUrl: json['baseUrl']?.toString() ?? '',
      bandwidth: json['bandwidth'] as int? ?? 0,
      mimeType: json['mimeType']?.toString() ?? 'audio/mp4',
      codecs: json['codecs']?.toString() ?? '',
    );
  }
}

/// 单个清晰度的 DASH 数据
class DashStreamInfo {
  final String quality;
  final double duration;
  final DashVideoItem video;
  final DashAudioItem? audio;

  const DashStreamInfo({
    required this.quality,
    required this.duration,
    required this.video,
    this.audio,
  });
}

/// 完整 DASH manifest（所有清晰度）
///
/// 仿 pili_plus：一次性缓存所有清晰度数据，
/// 切换清晰度时直接从缓存取 DataSource，无需再次请求 API。
class DashManifest {
  final Map<String, DashStreamInfo> streams;
  final List<String> qualities;
  final bool supportsDash;
  final DateTime fetchedAt;

  const DashManifest({
    required this.streams,
    required this.qualities,
    required this.supportsDash,
    required this.fetchedAt,
  });

  /// 从缓存获取指定清晰度的 DataSource
  DataSource? getDataSource(String quality) {
    final stream = streams[quality];
    if (stream == null) return null;

    final videoUrl = _resolveUrl(stream.video.baseUrl);
    final audioUrl = stream.audio != null
        ? _resolveUrl(stream.audio!.baseUrl)
        : null;

    return DataSource(
      videoSource: videoUrl,
      audioSource: audioUrl,
      httpHeaders: _defaultHttpHeaders,
    );
  }

  /// 播放器默认 HTTP 请求头（参考 pili_plus）
  static Map<String, String> get _defaultHttpHeaders => {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'referer': ApiConfig.baseUrl,
  };

  /// 缓存是否已过期（默认 25 分钟，服务端 key TTL 通常 30 分钟）
  bool get isExpired =>
      DateTime.now().difference(fetchedAt).inMinutes >= 25;

  /// 解析 URL：相对路径拼接 baseUrl，绝对路径直接使用
  static String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return '${ApiConfig.baseUrl}$url';
  }
}
