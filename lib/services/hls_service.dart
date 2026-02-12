import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../config/api_config.dart';

/// DASH SegmentBase 信息
class SegmentBaseInfo {
  final String initialization;
  final String indexRange;

  const SegmentBaseInfo({
    required this.initialization,
    required this.indexRange,
  });

  factory SegmentBaseInfo.fromJson(dynamic json) {
    if (json == null) {
      return const SegmentBaseInfo(initialization: '', indexRange: '');
    }
    // Dart Map 键名大小写敏感，需要精确匹配
    Map<String, dynamic> map = json as Map<String, dynamic>;
    return SegmentBaseInfo(
      initialization: map['Initialization']?.toString() ?? '',
      indexRange: map['indexRange']?.toString() ?? '',
    );
  }
}

/// 媒体源信息（用于播放器加载）
class MediaSource {
  /// 是否为直接视频URL（mp4/m4s等），false 表示是 m3u8 内容
  final bool isDirectUrl;

  /// m3u8 内容（isDirectUrl=false）或 直接视频URL（isDirectUrl=true）
  final String content;

  /// DASH 模式下的外挂音频URL（pilipala 风格：视频+音频分离）
  final String? audioUrl;

  /// DASH SegmentBase 信息
  final SegmentBaseInfo? videoSegmentBase;
  final SegmentBaseInfo? audioSegmentBase;

  const MediaSource({
    required this.isDirectUrl,
    required this.content,
    this.audioUrl,
    this.videoSegmentBase,
    this.audioSegmentBase,
  });
}

/// 清晰度查询结果（包含 supportsDash 信息）
class QualityInfo {
  final List<String> qualities;
  final bool supportsDash;
  const QualityInfo({required this.qualities, required this.supportsDash});
}

/// HLS 视频流服务类
/// 负责处理 m3u8 文件的获取、转换和临时文件管理
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
  ///
  /// [resourceId] 资源ID
  /// 返回 QualityInfo，包含清晰度列表和是否支持 DASH
  Future<QualityInfo> getQualityInfo(int resourceId) async {
    try {
      final response = await _dio.get(
        '/api/v1/video/getResourceQuality',
        queryParameters: {'resourceId': resourceId},
      );

      if (response.data['code'] == 200) {
        final qualities = List<String>.from(response.data['data']['quality']);
        
        // 【修复】后端采用 SegmentBase 模式（音画分离），所有平台都支持 DASH
        // Android：使用 format=json 解析 DASH URL
        // iOS：使用 format=m3u8 获取 HLS 子清单
        // 关键是：资源是同一份 m4s 文件，都需要挂载音频
        final supportsDash = Platform.isAndroid;
        
        return QualityInfo(qualities: qualities, supportsDash: supportsDash);
      }
      
      throw Exception('获取清晰度列表失败: ${response.data['msg']}');
    } catch (e) {
      rethrow;
    }
  }

  /// 获取可用的清晰度列表（兼容旧接口）
  ///
  /// [resourceId] 资源ID
  /// 返回清晰度列表，如 ["1920x1080_3000k_30", "1280x720_2000k_30"]
  Future<List<String>> getAvailableQualities(int resourceId) async {
    final info = await getQualityInfo(resourceId);
    return info.qualities;
  }

  /// 获取媒体源信息
  ///
  /// 返回 MediaSource 对象，包含：
  /// - isDirectUrl: 是否为直接视频URL（mp4/m4s等）
  /// - content: m3u8内容 或 直接视频URL
  ///
  /// [resourceId] 资源ID
  /// [quality] 清晰度
  /// [useDash] 是否使用 DASH MPD 格式（默认 false，使用 HLS）
   Future<MediaSource> getMediaSource(int resourceId, String quality, {bool useDash = false}) async {
     try {
       // DASH 模式：直接使用 MPD URL，让 media_kit 原生解析 DASH
       if (useDash) {
         // Android + SegmentBase 模式：使用 MPD 格式
         // mediainfo:// 格式在某些 media_kit 版本有问题，直接用 MPD URL 更稳定
         final mpdUrl = '${ApiConfig.baseUrl}/api/v1/video/getVideoFile?resourceId=$resourceId&quality=$quality&format=mpd';
         
         return MediaSource(
           isDirectUrl: true,
           content: mpdUrl,
         );
       }

      // HLS 模式：获取 m3u8，同时获取音频 URL（用于外挂音频）
      // 【修复】并行请求 m3u8 和 JSON 音频信息
      // 【修复】并行获取 m3u8 和音频信息
      final m3u8Future = _dio.get(
        '/api/v1/video/getVideoFile',
        queryParameters: {
          'resourceId': resourceId,
          'quality': quality,
        },
        options: Options(responseType: ResponseType.plain),
      );
      final audioFuture = _getAudioUrl(resourceId, quality);

      final m3u8Response = await m3u8Future;
      final jsonResponse = await audioFuture;

      String content = m3u8Response.data as String;
      content = content.trim();

      // 解析音频 URL（如果 JSON 请求成功）
      String? audioUrl;
      if (jsonResponse != null) {
        try {
          final jsonContent = (jsonResponse.data as String).trim();
          if (jsonContent.startsWith('{')) {
            final json = _parseJson(jsonContent);
            final dash = json['data']?['dash'];
            final audioList = dash?['audio'] as List?;
            if (audioList != null && audioList.isNotEmpty) {
              audioUrl = '${ApiConfig.baseUrl}${audioList[0]['baseUrl']}';
            }
          }
        } catch (e) {
          // 解析失败，忽略音频
        }
      }

      // 判断返回内容类型
      if (content.startsWith('#EXTM3U')) {
        // HLS m3u8 内容，需要转换相对路径
        final m3u8Content = _convertToAbsoluteUrls(content);
        
        return MediaSource(isDirectUrl: false, content: m3u8Content, audioUrl: audioUrl);
      } else if (content.startsWith('http://') || content.startsWith('https://')) {
        // 直接视频URL (mp4/m4s等)
        return MediaSource(isDirectUrl: true, content: content, audioUrl: audioUrl);
      } else {
        // 未知格式，尝试作为m3u8处理
        
        final m3u8Content = _convertToAbsoluteUrls(content);
        return MediaSource(isDirectUrl: false, content: m3u8Content, audioUrl: audioUrl);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// [已废弃] 获取 m3u8 内容字符串（兼容旧接口）
  ///
  /// 注意：此方法仅用于 HLS 流，如果后端返回直接 URL 会报错
  /// 推荐使用 getMediaSource() 方法
  /// [resourceId] 资源ID
  /// [quality] 清晰度
  /// 返回 m3u8 内容字符串
  Future<String> getHlsStreamContent(int resourceId, String quality) async {
    try {
      // 1. 获取 m3u8 内容字符串
      final response = await _dio.get(
        '/api/v1/video/getVideoFile',
        queryParameters: {
          'resourceId': resourceId,
          'quality': quality,
        },
        options: Options(
          responseType: ResponseType.plain, // 获取纯文本
        ),
      );

      String m3u8Content = response.data as String;

      // 2. 转换相对路径为绝对URL
      m3u8Content = _convertToAbsoluteUrls(m3u8Content);

      
      return m3u8Content;
    } catch (e) {
      rethrow;
    }
  }

  /// 获取 m3u8 内容并转换为本地临时文件
  ///
  /// [resourceId] 资源ID
  /// [quality] 清晰度，如 "1920x1080_3000k_30"
  /// 返回本地 m3u8 文件的绝对路径
  Future<String> getLocalM3u8File(int resourceId, String quality) async {
    try {
      await _initCacheDir();

      // 1. 获取 m3u8 内容字符串
      final response = await _dio.get(
        '/api/v1/video/getVideoFile',
        queryParameters: {
          'resourceId': resourceId,
          'quality': quality,
        },
        options: Options(
          responseType: ResponseType.plain, // 获取纯文本
        ),
      );

      String m3u8Content = response.data as String;

      // 2. 转换相对路径为绝对URL
      m3u8Content = _convertToAbsoluteUrls(m3u8Content);

      // 3. 保存为临时文件
      final fileName = 'video_${resourceId}_${quality}_${DateTime.now().millisecondsSinceEpoch}.m3u8';
      final filePath = '${_cacheDir!.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(m3u8Content);

      // 4. 记录临时文件路径，用于后续清理
      _tempFilePaths.add(filePath);

      
      return filePath;
    } catch (e) {
      rethrow;
    }
  }

  /// 解析 JSON 字符串
  Map<String, dynamic> _parseJson(String content) {
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  /// 【新增】获取音频 URL（用于 HLS 模式的外挂音频）
  Future<Response<dynamic>?> _getAudioUrl(int resourceId, String quality) async {
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
      return response;
    } catch (e) {
      // 音频请求失败不影响主流程
      return null;
    }
  }

  /// 将 m3u8 内容中的相对路径转换为绝对URL，并添加优化配置
  /// 支持 TS 切片 (.ts) 和 fMP4 切片 (.m4s + _init.mp4)
  String _convertToAbsoluteUrls(String m3u8Content) {
    final lines = m3u8Content.split('\n');
    final convertedLines = <String>[];
    bool hasAddedCacheTag = false;

    for (var line in lines) {
      final trimmedLine = line.trim();

      // 处理 fMP4 格式的初始化文件 (EXT-X-MAP:URI="xxx")
      if (trimmedLine.startsWith('#EXT-X-MAP:URI=')) {
        // 提取 URI 中的路径
        final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(trimmedLine);
        if (uriMatch != null) {
          final uri = uriMatch.group(1)!;
          // 如果是相对路径，转换为绝对URL
          if (uri.startsWith('/api/v1/video/slice/')) {
            convertedLines.add('#EXT-X-MAP:URI="${ApiConfig.baseUrl}$uri"');
          } else {
            convertedLines.add(line);
          }
        } else {
          convertedLines.add(line);
        }
      }
      // 如果是切片文件路径 (.ts 或 .m4s，以 / 开头的相对路径)
      else if (trimmedLine.startsWith('/api/v1/video/slice/')) {
        // 在第一个切片文件前添加缓存配置（如果还没添加过）
        if (!hasAddedCacheTag) {
          // 添加允许缓存标签，帮助播放器缓存分片
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

          // 删除超过1小时的文件
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
      // 1. 清理HLS缓存
      await _initCacheDir();
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create();
        _tempFilePaths.clear();
      }

      // 2. 清理MPV缓存
      await cleanupMpvCache();
    } catch (e) {
    }
  }

  /// 清理 MPV 播放器缓存
  ///
  /// MPV 会在临时目录中缓存 TS 分片，需要定期清理以节省存储空间
  /// 【修复】增加更多可能的缓存位置，确保彻底清理
  Future<void> cleanupMpvCache() async {
    try {
      final tempDir = await getTemporaryDirectory();

       // MPV 缓存目录可能的位置（扩展列表）
       final mpvCacheDirs = [
         Directory('${tempDir.path}/mpv_cache'),
         Directory('${tempDir.path}/.mpv_cache'),
         Directory('${tempDir.path}/media_kit_cache'),
         Directory('${tempDir.path}/libmpv'),
         Directory('${tempDir.path}/mpv'),
       ];

       int totalDeleted = 0;

       for (final dir in mpvCacheDirs) {
         if (await dir.exists()) {
           final files = dir.listSync(recursive: true);
           for (final file in files) {
             if (file is File) {
               try {
                 await file.delete();
                 totalDeleted++;
               } catch (e) {
                 // 文件可能正在使用中，跳过
                
              }
            }
          }

          // 尝试删除空目录
          try {
            if (dir.listSync().isEmpty) {
              await dir.delete();
            }
          } catch (e) {
            // 目录可能不为空或正在使用
          }
        }
      }

      // 【修复】清理临时目录中的分片文件（MPV 可能直接存储在 temp 根目录）
      try {
        final tempFiles = tempDir.listSync();
        for (final entity in tempFiles) {
          if (entity is File) {
            final fileName = entity.path.split('/').last;
            // 清理可能的 TS/fMP4 分片和临时视频文件
            if (fileName.endsWith('.ts') ||
                fileName.endsWith('.m4s') ||
                fileName.endsWith('.mp4') ||
                fileName.endsWith('.m3u8') ||
                fileName.startsWith('mpv') ||
                fileName.startsWith('libmpv')) {
              try {
                await entity.delete();
                totalDeleted++;
              } catch (e) {
                // 文件可能正在使用
              }
            }
          }
        }
      } catch (e) {
      }

      if (totalDeleted > 0) {
      }
    } catch (e) {
    }
  }

    /// 清理所有临时缓存（退出播放时调用）
  ///
  /// 包括：HLS临时文件 + MPV缓存文件
  Future<void> cleanupAllTempCache() async {
    try {
      await cleanupTempFiles();
      await cleanupMpvCache();
    } catch (e) {
    }
  }

  /// 预加载视频分片（用于秒开优化）
  ///
  /// 支持 TS 切片 (.ts) 和 fMP4 切片 (.m4s)
  /// [m3u8Content] m3u8内容字符串
  /// [segmentCount] 预加载的分片数量（默认3个）
  /// [startPosition] 起始播放位置（秒），用于智能预加载对应位置的分片
  /// 返回预加载的分片URL列表
  Future<List<String>> preloadTsSegments(String m3u8Content, {int segmentCount = 3, double? startPosition}) async {
    try {
      final lines = m3u8Content.split('\n');
      final segmentUrls = <String>[];
      final segmentDurations = <double>[];
      String? initSegmentUrl; // fMP4 初始化片段

      // 解析分片URL和时长
      for (int i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();

        // 解析 fMP4 初始化片段
        if (trimmed.startsWith('#EXT-X-MAP:URI=')) {
          final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(trimmed);
          if (uriMatch != null) {
            initSegmentUrl = uriMatch.group(1)!;
          }
        }

        // 解析分片时长
        if (trimmed.startsWith('#EXTINF:')) {
          final durationStr = trimmed.substring(8).split(',')[0];
          final duration = double.tryParse(durationStr) ?? 4.0;
          segmentDurations.add(duration);
        }

        // 解析分片URL (.ts 或 .m4s)
        if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
          segmentUrls.add(trimmed);
        } else if (trimmed.startsWith('/api/v1/video/slice/')) {
          // 相对路径，转换为绝对URL
          segmentUrls.add('${ApiConfig.baseUrl}$trimmed');
        }
      }

      if (segmentUrls.isEmpty) {
        
        return [];
      }

      // 【智能预加载】根据起始位置确定预加载的分片索引
      int startIndex = 0;
      if (startPosition != null && startPosition > 0) {
        double accumulatedDuration = 0;
        for (int i = 0; i < segmentDurations.length && i < segmentUrls.length; i++) {
          if (accumulatedDuration >= startPosition) {
            startIndex = i > 0 ? i - 1 : 0; // 从前一个分片开始，确保无缝
            break;
          }
          accumulatedDuration += segmentDurations[i];
        }
        // 如果累计时长仍小于起始位置，从最后几个分片开始
        if (startIndex == 0 && accumulatedDuration < startPosition) {
          startIndex = segmentUrls.length > segmentCount ? segmentUrls.length - segmentCount : 0;
        }
      }

      // 获取要预加载的分片（从 startIndex 开始）
      final endIndex = (startIndex + segmentCount).clamp(0, segmentUrls.length);
      final segmentsToPreload = <String>[];

      // 如果有 fMP4 初始化片段，先预加载它（必须最先加载）
      if (initSegmentUrl != null) {
        segmentsToPreload.add(initSegmentUrl);
      }

      // 添加普通分片
      segmentsToPreload.addAll(segmentUrls.sublist(startIndex, endIndex));


      // 并发下载分片（不等待完成，让播放器边播边加载）
      unawaited(Future.wait(
        segmentsToPreload.map((url) async {
          try {
            await _dio.get(
              url,
              options: Options(
                responseType: ResponseType.bytes,
                receiveTimeout: const Duration(seconds: 5),
              ),
            );
          } catch (e) {
            // 预加载失败不影响播放，静默处理
          }
        }),
      ));

      return segmentsToPreload;
    } catch (e) {
      return [];
    }
  }

  /// 解析清晰度字符串，返回友好的显示名称
  ///
  /// 示例: "1920x1080_3000k_30" -> "1080P"
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
    return quality; // 默认返回原始字符串
  }

  /// 获取推荐的默认清晰度（选择列表中第二高的）
  static String getDefaultQuality(List<String> qualities) {
    if (qualities.isEmpty) return '';
    // 先排序，确保按清晰度降序
    final sorted = sortQualities(qualities);
    // 如果有多个清晰度，选择第二个（通常是720P），否则选第一个
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
