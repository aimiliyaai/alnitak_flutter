import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../config/api_config.dart';
import 'logger_service.dart';

/// 媒体源信息（用于播放器加载）
class MediaSource {
  /// 是否为直接视频URL（mp4/m4s等），false 表示是 m3u8 内容
  final bool isDirectUrl;

  /// m3u8 内容（isDirectUrl=false）或 直接视频URL（isDirectUrl=true）
  final String content;

  const MediaSource({
    required this.isDirectUrl,
    required this.content,
  });
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

  /// 获取可用的清晰度列表
  ///
  /// [resourceId] 资源ID
  /// 返回清晰度列表，如 ["1920x1080_3000k_30", "1280x720_2000k_30"]
  Future<List<String>> getAvailableQualities(int resourceId) async {
    try {
      final response = await _dio.get(
        '/api/v1/video/getResourceQuality',
        queryParameters: {'resourceId': resourceId},
      );

      if (response.data['code'] == 200) {
        final qualities = List<String>.from(response.data['data']['quality']);
        return qualities;
      } else {
        throw Exception('获取清晰度列表失败: ${response.data['msg']}');
      }
    } catch (e) {
      print('❌ 获取清晰度列表错误: $e');
      rethrow;
    }
  }

  /// 获取媒体源信息
  ///
  /// 返回 MediaSource 对象，包含：
  /// - isDirectUrl: 是否为直接视频URL（mp4/m4s等）
  /// - content: m3u8内容 或 直接视频URL
  ///
  /// [resourceId] 资源ID
  /// [quality] 清晰度
  Future<MediaSource> getMediaSource(int resourceId, String quality) async {
    try {
      final response = await _dio.get(
        '/api/v1/video/getVideoFile',
        queryParameters: {
          'resourceId': resourceId,
          'quality': quality,
        },
        options: Options(
          responseType: ResponseType.plain,
        ),
      );

      String content = response.data as String;
      content = content.trim();

      // 判断返回内容类型
      if (content.startsWith('#EXTM3U')) {
        // HLS m3u8 内容，需要转换相对路径
        final m3u8Content = _convertToAbsoluteUrls(content);
        print('✅ M3U8 内容已获取 (HLS流)');
        return MediaSource(isDirectUrl: false, content: m3u8Content);
      } else if (content.startsWith('http://') || content.startsWith('https://')) {
        // 直接视频URL (mp4/m4s等)
        print('✅ 直接视频URL已获取: ${content.split('?').first.split('/').last}');
        return MediaSource(isDirectUrl: true, content: content);
      } else {
        // 未知格式，尝试作为m3u8处理
        print('⚠️ 未知响应格式，尝试作为M3U8处理');
        final m3u8Content = _convertToAbsoluteUrls(content);
        return MediaSource(isDirectUrl: false, content: m3u8Content);
      }
    } catch (e) {
      print('❌ 获取媒体源错误: $e');
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

      print('✅ M3U8 内容已获取');
      return m3u8Content;
    } catch (e) {
      print('❌ 获取 M3U8 内容错误: $e');
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

      print('✅ M3U8 临时文件已创建: $filePath');
      return filePath;
    } catch (e) {
      print('❌ 获取 M3U8 文件错误: $e');
      rethrow;
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
          print('🗑️  已删除临时文件: $filePath');
        }
      }
      _tempFilePaths.clear();
    } catch (e) {
      print('❌ 清理临时文件错误: $e');
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
            print('🗑️  已删除过期缓存: ${file.path}');
          }
        }
      }
    } catch (e) {
      print('❌ 清理过期缓存错误: $e');
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
        print('🗑️  已清空所有HLS缓存');
      }

      // 2. 清理MPV缓存
      await cleanupMpvCache();
    } catch (e) {
      print('❌ 清空缓存错误: $e');
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
      int totalSize = 0;

      for (final dir in mpvCacheDirs) {
        if (await dir.exists()) {
          final files = dir.listSync(recursive: true);
          for (final file in files) {
            if (file is File) {
              try {
                final stat = await file.stat();
                totalSize += stat.size;
                await file.delete();
                totalDeleted++;
              } catch (e) {
                // 文件可能正在使用中，跳过
                print('⚠️ 跳过文件: ${file.path}');
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
                final stat = await entity.stat();
                totalSize += stat.size;
                await entity.delete();
                totalDeleted++;
                print('🗑️  删除临时文件: $fileName');
              } catch (e) {
                // 文件可能正在使用
              }
            }
          }
        }
      } catch (e) {
        print('⚠️ 清理临时目录分片文件失败: $e');
      }

      if (totalDeleted > 0) {
        final sizeMB = (totalSize / (1024 * 1024)).toStringAsFixed(2);
        print('🗑️  已清理 MPV 缓存: $totalDeleted 个文件，释放 ${sizeMB}MB 空间');
      }
    } catch (e) {
      print('❌ 清理 MPV 缓存错误: $e');
    }
  }

   /// 清理所有临时缓存（退出播放时调用）
  ///
  /// 包括：HLS临时文件 + MPV缓存文件
  Future<void> cleanupAllTempCache() async {
    try {
      await cleanupTempFiles();
      await cleanupMpvCache();
      LoggerService.instance.logSuccess('播放器缓存已清理完成', tag: 'HLSService');
    } catch (e) {
      LoggerService.instance.logWarning('清理播放器缓存错误: $e', tag: 'HLSService');
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
        print('⚠️ 未找到分片URL');
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
        print('📍 智能预加载: 起始位置=${startPosition.toInt()}s, 从分片#$startIndex 开始');
      }

      // 获取要预加载的分片（从 startIndex 开始）
      final endIndex = (startIndex + segmentCount).clamp(0, segmentUrls.length);
      final segmentsToPreload = <String>[];

      // 如果有 fMP4 初始化片段，先预加载它（必须最先加载）
      if (initSegmentUrl != null) {
        segmentsToPreload.add(initSegmentUrl);
        print('📦 fMP4 初始化片段: $initSegmentUrl');
      }

      // 添加普通分片
      segmentsToPreload.addAll(segmentUrls.sublist(startIndex, endIndex));

      print('🚀 开始预加载 ${segmentsToPreload.length} 个分片 ($startIndex-${endIndex - 1})...');

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
            print('✅ 预加载完成: ${url.split('/').last}');
          } catch (e) {
            // 预加载失败不影响播放，静默处理
            print('⚠️ 预加载分片失败: ${url.split('/').last}');
          }
        }),
      ));

      return segmentsToPreload;
    } catch (e) {
      print('❌ 预加载分片失败: $e');
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
