import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../config/api_config.dart';
import '../models/data_source.dart';
import '../models/dash_models.dart';

/// 清晰度查询结果
class QualityInfo {
  final List<String> qualities;
  final bool supportsDash; // true=新资源(SegmentBase), false=旧资源(SegmentList/Legacy)
  const QualityInfo({required this.qualities, required this.supportsDash});
}

/// 视频流服务类
///
/// pilipala 风格：通过 JSON 接口获取视频/音频直链 URL
/// 播放器直接加载 URL，通过 audio-files 挂载外部音频
class HlsService {
  static final HlsService _instance = HlsService._internal();
  factory HlsService() => _instance;
  HlsService._internal();

  final Dio _dio = HttpClient().dio;

  /// 播放器默认 HTTP 请求头（参考 pili_plus）
  /// 视频/音频 URL 请求需要携带这些头信息，否则可能被服务器拒绝
  static Map<String, String> get _defaultHttpHeaders => {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'referer': ApiConfig.baseUrl,
  };

  /// 获取清晰度信息
  Future<QualityInfo> getQualityInfo(int resourceId) async {
    try {
      final response = await _dio.get(
        '/api/v1/video/getResourceQuality',
        queryParameters: {'resourceId': resourceId},
      );

      if (response.data['code'] == 200) {
        final qualities = List<String>.from(response.data['data']['quality']);
        final supportsDash = response.data['data']['supportsDash'] == true;
        return QualityInfo(qualities: qualities, supportsDash: supportsDash);
      }

      throw Exception('获取清晰度列表失败: ${response.data['msg']}');
    } catch (e) {
      rethrow;
    }
  }

  /// 获取可用的清晰度列表
  Future<List<String>> getAvailableQualities(int resourceId) async {
    final info = await getQualityInfo(resourceId);
    return info.qualities;
  }

  /// 获取 DataSource（核心方法）
  ///
  /// 新资源（supportsDash=true）：请求 format=json，提取视频/音频直链 URL
  /// 旧资源（supportsDash=false）：直接构造 m3u8 URL 给 mpv 加载
  ///   mpv 原生支持 HTTP m3u8 URL，会自动解析相对路径
  Future<DataSource> getDataSource(int resourceId, String quality, {bool supportsDash = true}) async {
    try {
      if (supportsDash) {
        // 新资源：JSON 格式，提取视频/音频直链
        final response = await _dio.get(
          '/api/v1/video/getVideoFile',
          queryParameters: {
            'resourceId': resourceId,
            'quality': quality,
            'format': 'json',
          },
          options: Options(responseType: ResponseType.plain),
        );

        final jsonContent = (response.data as String).trim();
        if (!jsonContent.startsWith('{')) {
          throw Exception('无效的 JSON 响应');
        }

        final json = jsonDecode(jsonContent) as Map<String, dynamic>;
        final dash = json['data']?['dash'];
        if (dash == null) throw Exception('响应缺少 dash 字段');

        // 提取视频直链
        final videoList = dash['video'] as List?;
        if (videoList == null || videoList.isEmpty) {
          throw Exception('响应缺少视频流信息');
        }
        final videoUrl = '${ApiConfig.baseUrl}${videoList[0]['baseUrl']}';

        // 提取音频直链
        String? audioUrl;
        final audioList = dash['audio'] as List?;
        if (audioList != null && audioList.isNotEmpty) {
          audioUrl = '${ApiConfig.baseUrl}${audioList[0]['baseUrl']}';
        }

        return DataSource(
          videoSource: videoUrl,
          audioSource: audioUrl,
          httpHeaders: _defaultHttpHeaders,
        );
      } else {
        // 旧资源：直接构造 m3u8 URL，mpv 原生支持 HTTP HLS
        // mpv 请求此 URL 得到 m3u8 文本，自动基于请求 URL 解析相对路径
        final m3u8Url = '${ApiConfig.baseUrl}/api/v1/video/getVideoFile'
            '?resourceId=$resourceId&quality=$quality&format=m3u8';

        return DataSource(
          videoSource: m3u8Url,
          httpHeaders: _defaultHttpHeaders,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 获取完整 DASH manifest（所有清晰度并行请求）
  ///
  /// 仿 pili_plus：一次性获取所有清晰度数据并缓存，
  /// 切换清晰度时直接从缓存取 DataSource，无需再次请求 API。
  ///
  /// 对于旧资源（supportsDash=false），返回空 streams 的 manifest，
  /// 调用方应回退到 getDataSource() 的 m3u8 模式。
  Future<DashManifest> getDashManifest(int resourceId) async {
    final qualityInfo = await getQualityInfo(resourceId);
    final sortedQualities = sortQualities(qualityInfo.qualities);

    if (!qualityInfo.supportsDash) {
      // 旧资源不支持 DASH，返回空 manifest，调用方回退到 m3u8
      return DashManifest(
        streams: const {},
        qualities: sortedQualities,
        supportsDash: false,
        fetchedAt: DateTime.now(),
      );
    }

    // 并行请求所有清晰度的 DASH 数据
    final futures = <String, Future<DashStreamInfo?>>{};
    for (final quality in sortedQualities) {
      futures[quality] = _fetchDashStream(resourceId, quality);
    }

    final streams = <String, DashStreamInfo>{};
    for (final entry in futures.entries) {
      final stream = await entry.value;
      if (stream != null) {
        streams[entry.key] = stream;
      }
    }

    return DashManifest(
      streams: streams,
      qualities: sortedQualities,
      supportsDash: true,
      fetchedAt: DateTime.now(),
    );
  }

  /// 请求单个清晰度的 DASH JSON 并解析为 DashStreamInfo
  Future<DashStreamInfo?> _fetchDashStream(int resourceId, String quality) async {
    try {
      final response = await _dio.get(
        '/api/v1/video/getVideoFile',
        queryParameters: {
          'resourceId': resourceId,
          'quality': quality,
          'format': 'json',
        },
        options: Options(responseType: ResponseType.plain),
      );

      final jsonContent = (response.data as String).trim();
      if (!jsonContent.startsWith('{')) return null;

      final json = jsonDecode(jsonContent) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      final dash = data?['dash'] as Map<String, dynamic>?;
      if (dash == null) return null;

      final videoList = dash['video'] as List?;
      if (videoList == null || videoList.isEmpty) return null;

      final audioList = dash['audio'] as List?;

      return DashStreamInfo(
        quality: quality,
        duration: (data?['duration'] as num?)?.toDouble() ?? 0,
        video: DashVideoItem.fromJson(videoList[0] as Map<String, dynamic>),
        audio: (audioList != null && audioList.isNotEmpty)
            ? DashAudioItem.fromJson(audioList[0] as Map<String, dynamic>)
            : null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('获取 DASH 流失败 ($quality): $e');
      return null;
    }
  }

  // ============ 缓存清理 ============

  /// 清理 MPV 播放器缓存
  Future<void> cleanupMpvCache() async {
    try {
      final tempDir = await getTemporaryDirectory();

      final mpvCacheDirs = [
        Directory('${tempDir.path}/mpv_cache'),
        Directory('${tempDir.path}/.mpv_cache'),
        Directory('${tempDir.path}/media_kit_cache'),
        Directory('${tempDir.path}/libmpv'),
        Directory('${tempDir.path}/mpv'),
        Directory('${tempDir.path}/hls_cache'),
      ];

      for (final dir in mpvCacheDirs) {
        if (await dir.exists()) {
          final files = dir.listSync(recursive: true);
          for (final file in files) {
            if (file is File) {
              try {
                await file.delete();
              } catch (_) {
              }
            }
          }
          try {
            if (dir.listSync().isEmpty) {
              await dir.delete();
            }
          } catch (_) {
          }
        }
      }

      // 清理临时目录中的分片文件
      try {
        final tempFiles = tempDir.listSync();
        for (final entity in tempFiles) {
          if (entity is File) {
            final fileName = entity.path.split('/').last;
            if (fileName.endsWith('.ts') ||
                fileName.endsWith('.m4s') ||
                fileName.endsWith('.mp4') ||
                fileName.endsWith('.m3u8') ||
                fileName.startsWith('mpv') ||
                fileName.startsWith('libmpv')) {
              try {
                await entity.delete();
              } catch (_) {
              }
            }
          }
        }
      } catch (_) {
      }
    } catch (_) {
    }
  }

  /// 清理所有缓存
  Future<void> clearAllCache() async {
    await cleanupMpvCache();
  }

  /// 清理所有临时缓存（退出播放时调用）
  Future<void> cleanupAllTempCache() async {
    await cleanupMpvCache();
  }

  /// 清理过期的缓存文件
  Future<void> cleanupExpiredCache() async {
    // 不再需要清理 m3u8 临时文件，保留接口兼容性
  }

  // ============ 静态工具方法 ============

  /// 解析清晰度字符串，返回友好的显示名称
  ///
  /// 新资源格式: "1920x1080_3000k_30" → "1080P"
  /// 新资源高帧率: "1920x1080_8000k_60" → "1080P60"
  /// 旧资源格式: "720p" → "720P"
  static String getQualityLabel(String quality) {
    final fps = _parseFrameRate(quality);
    final fpsSuffix = fps > 30 ? '$fps' : '';

    // 新资源格式：包含 "x" 分辨率
    if (quality.contains('3840x2160')) {
      return '4K$fpsSuffix';
    } else if (quality.contains('2560x1440')) {
      return '2K$fpsSuffix';
    } else if (quality.contains('1920x1080')) {
      return '1080P$fpsSuffix';
    } else if (quality.contains('1280x720')) {
      return '720P$fpsSuffix';
    } else if (quality.contains('854x480')) {
      return '480P$fpsSuffix';
    } else if (quality.contains('640x360')) {
      return '360P$fpsSuffix';
    }
    // 旧资源格式：直接是 "720p"、"480p" 等，统一转大写
    final lowerQ = quality.toLowerCase();
    if (lowerQ == '1080p' || lowerQ == '720p' || lowerQ == '480p' ||
        lowerQ == '360p' || lowerQ == '4k' || lowerQ == '2k') {
      return quality.toUpperCase();
    }
    return quality;
  }

  /// 获取推荐的默认清晰度（选择列表中第二高的）
  static String getDefaultQuality(List<String> qualities) {
    if (qualities.isEmpty) return '';
    final sorted = sortQualities(qualities);
    if (sorted.length > 1) {
      return sorted[1];
    }
    return sorted[0];
  }

  /// 排序清晰度列表（按分辨率降序）
  static List<String> sortQualities(List<String> qualities) {
    final sorted = List<String>.from(qualities);
    sorted.sort((a, b) {
      final resA = _parseResolution(a);
      final resB = _parseResolution(b);
      if (resA != resB) return resB.compareTo(resA);
      return _parseFrameRate(b).compareTo(_parseFrameRate(a));
    });
    return sorted;
  }

  /// 解析分辨率用于排序
  ///
  /// 新资源: "1920x1080_3000k_30" → 1920*1080
  /// 旧资源: "720p" → 按已知分辨率映射
  static int _parseResolution(String quality) {
    try {
      // 新格式：包含 "x"，如 "1920x1080_3000k_30"
      final parts = quality.split('_');
      if (parts.isNotEmpty) {
        final dims = parts[0].split('x');
        if (dims.length == 2) {
          final w = int.tryParse(dims[0]);
          final h = int.tryParse(dims[1]);
          if (w != null && h != null) return w * h;
        }
      }
      // 旧格式：直接是 "720p"、"480p" 等
      final lowerQ = quality.toLowerCase().replaceAll('p', '');
      final height = int.tryParse(lowerQ);
      if (height != null) {
        // 按常见宽高比 16:9 估算像素总数
        return (height * 16 ~/ 9) * height;
      }
      if (lowerQ == '4k') return 3840 * 2160;
      if (lowerQ == '2k') return 2560 * 1440;
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static int _parseFrameRate(String quality) {
    try {
      final parts = quality.split('_');
      return parts.length >= 3 ? (int.tryParse(parts[2]) ?? 30) : 30;
    } catch (_) {
      return 30;
    }
  }
}
