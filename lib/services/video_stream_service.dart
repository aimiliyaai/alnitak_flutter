import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import '../utils/http_client.dart';
import '../config/api_config.dart';
import '../models/data_source.dart';
import '../models/dash_models.dart';
import '../utils/quality_utils.dart';

/// 视频流服务 — MPD / JSON DASH / m3u8 加载
///
/// 职责：
///   1. 优先请求 dash-unified MPD（单次请求返回所有清晰度）
///   2. MPD 失败时回退 JSON（按清晰度逐个请求并聚合）
///   3. 最终回退到 m3u8 URL
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
/// 采用 MPD 优先策略（单次请求），失败时回退 JSON（1+N 请求），再失败回退 m3u8。
  Future<DashManifest> getDashManifest(Object resourceId) async {
    // 1) MPD 优先（单次请求返回所有清晰度）
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
      if (xml.startsWith('<?xml') || xml.startsWith('<MPD')) {
        return _parseMpd(xml);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('dash-unified failed, fallback JSON: $e');
    }

    // 2) JSON 回退（按清晰度逐个请求并聚合）
    try {
      final qualities = await _fetchQualities(resourceId);
      if (qualities.isNotEmpty) {
        final streams = <String, DashStreamInfo>{};
        // 限流并发：最多 3 个并发，使用信号量控制
        const maxConcurrent = 3;
        var running = 0;
        final pending = <MapEntry<String, Future<DashStreamInfo?>>>[];
        for (final quality in qualities) {
          if (running >= maxConcurrent) {
            final entry = pending.removeAt(0);
            final stream = await entry.value;
            if (stream != null) {
              streams[entry.key] = stream;
            }
            running--;
          }
          pending.add(MapEntry(quality, _getJsonStreamSafe(resourceId, quality)));
          running++;
        }
        for (final entry in pending) {
          final stream = await entry.value;
          if (stream != null) {
            streams[entry.key] = stream;
          }
        }
        if (streams.isNotEmpty) {
          return DashManifest(
            streams: streams,
            qualities: sortQualities(streams.keys.toList()),
            supportsDash: true,
            fetchedAt: DateTime.now(),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('getVideoFile json failed, fallback m3u8: $e');
    }

    // 3) m3u8 回退（旧资源）
    return _fallbackManifest(resourceId);
  }

  // ──────────────────────────────────────────────
  //  m3u8（旧资源回退）
  // ──────────────────────────────────────────────

  /// 构造 m3u8 URL 给 mpv 直接加载
  Future<DataSource> getM3u8DataSource(Object resourceId, String quality) async {
    final url = '${ApiConfig.baseUrl}/api/v1/video/getVideoFile'
        '?resourceId=$resourceId&quality=$quality&format=m3u8';
    return DataSource(videoSource: url, httpHeaders: defaultHttpHeaders);
  }

  // ──────────────────────────────────────────────
  //  内部：MPD 解析 & 回退
  // ──────────────────────────────────────────────

Future<DashStreamInfo?> _getJsonStream(Object resourceId, String quality) async {
    final response = await _dio.get(
      '/api/v1/video/getVideoFile',
      queryParameters: {
        'resourceId': resourceId,
        'quality': quality,
        'format': 'json',
      },
    );
    return _parseJsonStream(response.data, quality);
  }

  /// 安全并发请求：独立 try/catch，单个失败不影响整体
  Future<DashStreamInfo?> _getJsonStreamSafe(Object resourceId, String quality) async {
    try {
      return await _getJsonStream(resourceId, quality);
    } catch (e) {
      if (kDebugMode) debugPrint('$_getJsonStream quality=$quality failed: $e');
      return null;
    }
  }

  DashStreamInfo? _parseJsonStream(dynamic raw, String requestedQuality) {
    Map<String, dynamic>? root;
    if (raw is Map<String, dynamic>) {
      root = raw;
    } else if (raw is Map) {
      root = Map<String, dynamic>.from(raw);
    }
    if (root == null) return null;
    final code = root['code'];
    if (code is num && code != 0 && code != 200) return null;

    final dataObj = root['data'];
    final data = dataObj is Map<String, dynamic>
        ? dataObj
        : (dataObj is Map ? Map<String, dynamic>.from(dataObj) : root);

    final quality = _pickString(data, const ['quality']) ?? requestedQuality;
    final duration = _pickNum(data, const ['duration', 'timeLength']) ?? 0.0;

    final dash = _asMap(data['dash']) ?? data;
    final videoMap = _asMap(dash['video']) ?? _asMap(_asList(dash['video']).firstOrNull);
    if (videoMap == null) return null;
    final video = _toVideoItem(videoMap, quality);
    if (video == null) return null;

    final audioMap = _asMap(dash['audio']) ?? _asMap(_asList(dash['audio']).firstOrNull);
    final audio = _toAudioItem(audioMap);

    return DashStreamInfo(
      quality: quality,
      duration: _pickNum(dash, const ['duration']) ?? duration,
      video: video,
      audio: audio,
    );
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  List<dynamic> _asList(dynamic v) {
    if (v is List) return v;
    return const [];
  }

  String? _pickString(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  double? _pickNum(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final p = double.tryParse(v);
        if (p != null) return p;
      }
    }
    return null;
  }

  DashVideoItem? _toVideoItem(Map<String, dynamic> map, String fallbackQuality) {
    final baseUrl = _pickString(map, const ['baseUrl', 'base_url', 'url', 'videoUrl', 'video_url']);
    if (baseUrl == null || baseUrl.isEmpty) return null;
    final id = _pickString(map, const ['id', 'quality', 'name']) ?? fallbackQuality;
    return DashVideoItem(
      id: id,
      baseUrl: baseUrl,
      bandwidth: (_pickNum(map, const ['bandwidth', 'bandWidth']) ?? 0).toInt(),
      mimeType: _pickString(map, const ['mimeType', 'mime_type']) ?? 'video/mp4',
      codecs: _pickString(map, const ['codecs', 'codec']) ?? '',
      width: (_pickNum(map, const ['width']) ?? 0).toInt(),
      height: (_pickNum(map, const ['height']) ?? 0).toInt(),
      frameRate: _pickString(map, const ['frameRate', 'frame_rate', 'fps']) ?? '30.000',
    );
  }

  DashAudioItem? _toAudioItem(Map<String, dynamic>? map) {
    if (map == null) return null;
    final baseUrl = _pickString(map, const ['baseUrl', 'base_url', 'url', 'audioUrl', 'audio_url']);
    if (baseUrl == null || baseUrl.isEmpty) return null;
    return DashAudioItem(
      id: _pickString(map, const ['id', 'name']) ?? 'audio',
      baseUrl: baseUrl,
      bandwidth: (_pickNum(map, const ['bandwidth', 'bandWidth']) ?? 0).toInt(),
      mimeType: _pickString(map, const ['mimeType', 'mime_type']) ?? 'audio/mp4',
      codecs: _pickString(map, const ['codecs', 'codec']) ?? 'mp4a.40.2',
    );
  }

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

  Future<List<String>> _fetchQualities(Object resourceId) async {
    final response = await _dio.get(
      '/api/v1/video/getResourceQuality',
      queryParameters: {'resourceId': resourceId},
    );
    if (response.data['code'] != 200 || response.data['data'] == null) {
      return const [];
    }
    final qualityObj = response.data['data']['quality'];
    if (qualityObj is List) {
      return sortQualities(List<String>.from(qualityObj.map((e) => e.toString())));
    }
    return const [];
  }

  /// 旧资源回退：获取清晰度列表，返回 m3u8 模式 manifest
  Future<DashManifest> _fallbackManifest(Object resourceId) async {
    try {
      final qualities = await _fetchQualities(resourceId);
      if (qualities.isNotEmpty) {
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
