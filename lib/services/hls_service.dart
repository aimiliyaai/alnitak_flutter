import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../config/api_config.dart';
import '../models/data_source.dart';

/// 清晰度查询结果（包含 supportsDash 信息）
class QualityInfo {
  final List<String> qualities;
  final bool supportsDash;
  const QualityInfo({required this.qualities, required this.supportsDash});
}

/// HLS/DASH 视频流服务类
///
/// 负责获取视频/音频源、临时文件管理
class HlsService {
  static final HlsService _instance = HlsService._internal();
  factory HlsService() => _instance;
  HlsService._internal();

  final Dio _dio = HttpClient().dio;

  // 临时文件缓存目录
  Directory? _cacheDir;

  // 当前使用的临时文件列表，用于清理
  final List<String> _tempFilePaths = [];

  /// 初始化缓存目录
  Future<void> _initCacheDir() async {
    if (_cacheDir == null) {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory('${tempDir.path}/hls_cache');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    }
  }

  /// 是否应使用 DASH 格式
  /// Android 用 DASH（media_kit/libmpv 原生支持 MPD）
  /// iOS 用 HLS（原生 HLS 支持更好）
  static bool shouldUseDash() {
    return Platform.isAndroid;
  }

  /// 获取清晰度信息（包含 supportsDash 字段）
  Future<QualityInfo> getQualityInfo(int resourceId) async {
    try {
      final response = await _dio.get(
        '/api/v1/video/getResourceQuality',
        queryParameters: {'resourceId': resourceId},
      );

      if (response.data['code'] == 200) {
        final qualities = List<String>.from(response.data['data']['quality']);
        final supportsDash = Platform.isAndroid;
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
  /// DASH 模式：返回 MPD URL + 音频 URL
  /// HLS 模式：返回本地临时 m3u8 文件路径 + 音频 URL
  ///
  /// 两种模式都通过 format=json 获取独立音频 URL，
  /// 由播放器通过 audio-files 属性挂载外部音频
  Future<DataSource> getDataSource(int resourceId, String quality, {bool useDash = false}) async {
    try {
      if (useDash) {
        // DASH 模式：MPD URL + 音频 URL
        final mpdUrl = '${ApiConfig.baseUrl}/api/v1/video/getVideoFile'
            '?resourceId=$resourceId&quality=$quality&format=mpd';

        // 获取音频 URL
        final audioUrl = await _fetchAudioUrl(resourceId, quality);

        return DataSource(
          videoSource: mpdUrl,
          audioSource: audioUrl,
        );
      }

      // HLS 模式：并行获取 m3u8 和音频信息
      final m3u8Future = _dio.get(
        '/api/v1/video/getVideoFile',
        queryParameters: {
          'resourceId': resourceId,
          'quality': quality,
        },
        options: Options(responseType: ResponseType.plain),
      );
      final audioFuture = _fetchAudioUrl(resourceId, quality);

      final m3u8Response = await m3u8Future;
      final audioUrl = await audioFuture;

      String content = (m3u8Response.data as String).trim();

      // 转换相对路径为绝对 URL
      if (content.startsWith('#EXTM3U') || (!content.startsWith('http://') && !content.startsWith('https://'))) {
        content = _convertToAbsoluteUrls(content);
      }

      // 将 m3u8 内容写入临时文件（media_kit 需要文件路径）
      final tempFile = await _writeTempM3u8File(content);

      return DataSource(
        videoSource: tempFile,
        audioSource: audioUrl,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// 获取音频 URL（从 format=json 端点）
  Future<String?> _fetchAudioUrl(int resourceId, String quality) async {
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
      if (jsonContent.startsWith('{')) {
        final json = _parseJson(jsonContent);
        final dash = json['data']?['dash'];
        final audioList = dash?['audio'] as List?;
        if (audioList != null && audioList.isNotEmpty) {
          return '${ApiConfig.baseUrl}${audioList[0]['baseUrl']}';
        }
      }
    } catch (_) {
      // 音频请求失败不影响主流程
    }
    return null;
  }

  /// 将 m3u8 内容写入临时文件
  Future<String> _writeTempM3u8File(String content) async {
    await _initCacheDir();
    final fileName = 'playlist_${DateTime.now().millisecondsSinceEpoch}.m3u8';
    final filePath = '${_cacheDir!.path}/$fileName';
    final file = File(filePath);
    await file.writeAsString(content);
    _tempFilePaths.add(filePath);
    return filePath;
  }

  /// 解析 JSON 字符串
  Map<String, dynamic> _parseJson(String content) {
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  /// 将 m3u8 内容中的相对路径转换为绝对URL
  /// 支持 TS 切片 (.ts) 和 fMP4 切片 (.m4s + _init.mp4)
  String _convertToAbsoluteUrls(String m3u8Content) {
    final lines = m3u8Content.split('\n');
    final convertedLines = <String>[];
    bool hasAddedCacheTag = false;

    for (var line in lines) {
      final trimmedLine = line.trim();

      // 处理 fMP4 格式的初始化文件 (EXT-X-MAP:URI="xxx")
      if (trimmedLine.startsWith('#EXT-X-MAP:URI=')) {
        final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(trimmedLine);
        if (uriMatch != null) {
          final uri = uriMatch.group(1)!;
          if (uri.startsWith('/api/v1/video/slice/')) {
            convertedLines.add('#EXT-X-MAP:URI="${ApiConfig.baseUrl}$uri"');
          } else {
            convertedLines.add(line);
          }
        } else {
          convertedLines.add(line);
        }
      }
      // 如果是切片文件路径
      else if (trimmedLine.startsWith('/api/v1/video/slice/')) {
        if (!hasAddedCacheTag) {
          convertedLines.add('#EXT-X-ALLOW-CACHE:YES');
          hasAddedCacheTag = true;
        }
        convertedLines.add('${ApiConfig.baseUrl}$trimmedLine');
      } else {
        convertedLines.add(line);
      }
    }

    return convertedLines.join('\n');
  }

  // ============ 缓存清理 ============

  /// 清理所有临时文件
  Future<void> cleanupTempFiles() async {
    try {
      for (final filePath in _tempFilePaths) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      _tempFilePaths.clear();
    } catch (e) {
    }
  }

  /// 清理过期的缓存文件（超过1小时的文件）
  Future<void> cleanupExpiredCache() async {
    try {
      await _initCacheDir();
      final now = DateTime.now();
      final files = _cacheDir!.listSync();

      for (final file in files) {
        if (file is File && file.path.endsWith('.m3u8')) {
          final stat = await file.stat();
          final age = now.difference(stat.modified);
          if (age.inHours > 1) {
            await file.delete();
          }
        }
      }
    } catch (e) {
    }
  }

  /// 清理所有缓存目录（包括HLS缓存和MPV缓存）
  Future<void> clearAllCache() async {
    try {
      await _initCacheDir();
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create();
        _tempFilePaths.clear();
      }
      await cleanupMpvCache();
    } catch (e) {
    }
  }

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
      ];

      for (final dir in mpvCacheDirs) {
        if (await dir.exists()) {
          final files = dir.listSync(recursive: true);
          for (final file in files) {
            if (file is File) {
              try {
                await file.delete();
              } catch (e) {
              }
            }
          }
          try {
            if (dir.listSync().isEmpty) {
              await dir.delete();
            }
          } catch (e) {
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
              } catch (e) {
              }
            }
          }
        }
      } catch (e) {
      }
    } catch (e) {
    }
  }

  /// 清理所有临时缓存（退出播放时调用）
  Future<void> cleanupAllTempCache() async {
    try {
      await cleanupTempFiles();
      await cleanupMpvCache();
    } catch (e) {
    }
  }

  // ============ 静态工具方法 ============

  /// 解析清晰度字符串，返回友好的显示名称
  static String getQualityLabel(String quality) {
    if (quality.contains('1920x1080')) {
      return '1080P';
    } else if (quality.contains('1280x720')) {
      return '720P';
    } else if (quality.contains('854x480')) {
      return '480P';
    } else if (quality.contains('640x360')) {
      return '360P';
    } else if (quality.contains('3840x2160')) {
      return '4K';
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

  static int _parseResolution(String quality) {
    try {
      final parts = quality.split('_');
      if (parts.isEmpty) return 0;
      final dims = parts[0].split('x');
      if (dims.length != 2) return 0;
      return (int.tryParse(dims[0]) ?? 0) * (int.tryParse(dims[1]) ?? 0);
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
