import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import '../utils/http_client.dart';
import '../config/api_config.dart';
import '../models/data_source.dart';
import '../models/dash_models.dart';
import '../utils/quality_utils.dart';

/// 视频流服务 — DASH / m3u8 加载
///
/// 职责：
///   1. 请求 dash-unified MPD XML，解析为 DashManifest（所有清晰度一次获取）
///   2. 旧资源回退到 m3u8 URL
///
/// 质量切换从缓存 manifest 取对应清晰度的直链数据源。
class VideoStreamService {
  static final VideoStreamService _instance = VideoStreamService._internal();
  factory VideoStreamService() => _instance;
  VideoStreamService._internal();

  final Dio _dio = HttpClient().dio;

  /// 播放器 HTTP 请求头
  static Map<String, String> get defaultHttpHeaders => {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Safari/537.36',
    'referer': ApiConfig.baseUrl,
  };

  // ──────────────────────────────────────────────
  //  DASH（新资源主路径）
  // ──────────────────────────────────────────────

  /// 获取完整 DASH manifest（一次请求所有清晰度）
  ///
  /// 失败时自动回退 m3u8 模式（[DashManifest.supportsDash] = false）。
  Future<DashManifest> getDashManifest(int resourceId) async {
    try {
      final response = await _dio.get(
        '/api/v1/video/getVideoFile',
        queryParameters: {
          'resourceId': resourceId,
          'format': 'dash-unified',
        },
        options: Options(responseType: ResponseType.plain),
      );

      final xml = (response.data as String).trim();
      if (!xml.startsWith('<?xml') && !xml.startsWith('<MPD')) {
        return _fallbackManifest(resourceId);
      }
      return _parseMpd(xml);
    } catch (e) {
      if (kDebugMode) debugPrint('dash-unified failed, fallback m3u8: $e');
      return _fallbackManifest(resourceId);
    }
  }

  // ──────────────────────────────────────────────
  //  m3u8（旧资源回退）
  // ──────────────────────────────────────────────

  /// 构造 m3u8 URL 给 mpv 直接加载
  Future<DataSource> getM3u8DataSource(int resourceId, String quality) async {
    final url = '${ApiConfig.baseUrl}/api/v1/video/getVideoFile'
        '?resourceId=$resourceId&quality=$quality&format=m3u8';
    return DataSource(videoSource: url, httpHeaders: defaultHttpHeaders);
  }

  // ──────────────────────────────────────────────
  //  内部：MPD 解析 & 回退
  // ──────────────────────────────────────────────

  DashManifest _parseMpd(String xmlContent) {
    final document = XmlDocument.parse(xmlContent);
    final mpd = document.rootElement;

    final durationStr = mpd.getAttribute('mediaPresentationDuration') ?? '';
    final duration = _parseDuration(durationStr);

    final period = mpd.findAllElements('Period').first;
    final adaptationSets = period.findAllElements('AdaptationSet').toList();

    // 音频（共享，取第一个 audio/mp4）
    String? audioUrl;
    for (final as_ in adaptationSets) {
      if (as_.getAttribute('mimeType') == 'audio/mp4') {
        final rep = as_.findAllElements('Representation').firstOrNull;
        if (rep != null) {
          final baseUrl = rep.findAllElements('BaseURL').firstOrNull?.innerText;
          if (baseUrl != null && baseUrl.isNotEmpty) audioUrl = baseUrl;
        }
        break;
      }
    }

    // 视频（所有清晰度）
    final streams = <String, DashStreamInfo>{};
    for (final as_ in adaptationSets) {
      if (as_.getAttribute('mimeType') != 'video/mp4') continue;

      for (final rep in as_.findAllElements('Representation')) {
        final id = rep.getAttribute('id') ?? '';
        final videoBaseUrl =
            rep.findAllElements('BaseURL').firstOrNull?.innerText ?? '';
        if (videoBaseUrl.isEmpty || id.isEmpty) continue;

        final video = DashVideoItem(
          id: id,
          baseUrl: videoBaseUrl,
          bandwidth:
              int.tryParse(rep.getAttribute('bandwidth') ?? '') ?? 0,
          mimeType: 'video/mp4',
          codecs: rep.getAttribute('codecs') ?? '',
          width: int.tryParse(rep.getAttribute('width') ?? '') ?? 0,
          height: int.tryParse(rep.getAttribute('height') ?? '') ?? 0,
          frameRate: rep.getAttribute('frameRate') ?? '30.000',
        );

        DashAudioItem? audio;
        if (audioUrl != null) {
          audio = DashAudioItem(
            id: 'audio',
            baseUrl: audioUrl,
            bandwidth: 0,
            mimeType: 'audio/mp4',
            codecs: 'mp4a.40.2',
          );
        }

        streams[id] = DashStreamInfo(
          quality: id,
          duration: duration,
          video: video,
          audio: audio,
        );
      }
    }

    return DashManifest(
      streams: streams,
      qualities: sortQualities(streams.keys.toList()),
      supportsDash: true,
      fetchedAt: DateTime.now(),
    );
  }

  /// ISO 8601 duration → seconds  ("PT0H1M59.700S" → 119.7)
  double _parseDuration(String s) {
    final m = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?').firstMatch(s);
    if (m == null) return 0;
    return (int.tryParse(m.group(1) ?? '') ?? 0) * 3600.0 +
        (int.tryParse(m.group(2) ?? '') ?? 0) * 60.0 +
        (double.tryParse(m.group(3) ?? '') ?? 0);
  }

  /// 旧资源回退：获取清晰度列表，返回 m3u8 模式 manifest
  Future<DashManifest> _fallbackManifest(int resourceId) async {
    try {
      final response = await _dio.get(
        '/api/v1/video/getResourceQuality',
        queryParameters: {'resourceId': resourceId},
      );
      if (response.data['code'] == 200) {
        final qualities =
            List<String>.from(response.data['data']['quality']);
        return DashManifest(
          streams: const {},
          qualities: sortQualities(qualities),
          supportsDash: false,
          fetchedAt: DateTime.now(),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('getResourceQuality failed: $e');
    }
    return DashManifest(
      streams: const {},
      qualities: const [],
      supportsDash: false,
      fetchedAt: DateTime.now(),
    );
  }
}
