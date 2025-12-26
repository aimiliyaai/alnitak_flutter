import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../utils/http_client.dart';
import '../config/api_config.dart';

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

  /// [推荐] 获取 m3u8 内容字符串
  ///
  /// 这种方式避免了本地I/O，更高效且能避免因文件读写延迟导致的问题
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
  String _convertToAbsoluteUrls(String m3u8Content) {
    final lines = m3u8Content.split('\n');
    final convertedLines = <String>[];
    bool hasAddedCacheTag = false;

    for (var line in lines) {
      // 如果是 .ts 文件路径（以 / 开头的相对路径）
      if (line.trim().startsWith('/api/v1/video/slice/')) {
        // 在第一个TS文件前添加缓存配置（如果还没添加过）
        if (!hasAddedCacheTag) {
          // 添加允许缓存标签，帮助播放器缓存TS分片
          convertedLines.add('#EXT-X-ALLOW-CACHE:YES');
          hasAddedCacheTag = true;
        }
        convertedLines.add('${ApiConfig.baseUrl}$line');
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

      // 【修复】清理临时目录中的 .ts 分片文件（MPV 可能直接存储在 temp 根目录）
      try {
        final tempFiles = tempDir.listSync();
        for (final entity in tempFiles) {
          if (entity is File) {
            final fileName = entity.path.split('/').last;
            // 清理可能的 TS 分片和临时视频文件
            if (fileName.endsWith('.ts') ||
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
        print('⚠️ 清理临时目录 ts 文件失败: $e');
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
      // 1. 清理HLS临时文件
      await cleanupTempFiles();

      // 2. 清理MPV缓存
      await cleanupMpvCache();

      print('🗑️  播放器缓存已清理完成');
    } catch (e) {
      print('❌ 清理播放器缓存错误: $e');
    }
  }

  /// 预加载TS分片（用于秒开优化）
  /// 
  /// [m3u8Content] m3u8内容字符串
  /// [segmentCount] 预加载的分片数量（默认3个）
  /// 返回预加载的分片URL列表
  Future<List<String>> preloadTsSegments(String m3u8Content, {int segmentCount = 3}) async {
    try {
      final lines = m3u8Content.split('\n');
      final tsUrls = <String>[];
      
      // 解析TS分片URL
      for (var line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
          tsUrls.add(trimmed);
        } else if (trimmed.startsWith('/api/v1/video/slice/')) {
          // 相对路径，转换为绝对URL
          tsUrls.add('${ApiConfig.baseUrl}$trimmed');
        }
      }
      
      if (tsUrls.isEmpty) {
        print('⚠️ 未找到TS分片URL');
        return [];
      }
      
      // 只预加载前N个分片
      final segmentsToPreload = tsUrls.take(segmentCount).toList();
      
      print('🚀 开始预加载 ${segmentsToPreload.length} 个TS分片...');
      
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
      print('❌ 预加载TS分片失败: $e');
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
    // 如果有多个清晰度，选择第二个（通常是720P），否则选第一个
    if (qualities.length > 1) {
      return qualities[1];
    }
    return qualities[0];
  }
}
