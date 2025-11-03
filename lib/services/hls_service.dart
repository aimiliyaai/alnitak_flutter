import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../utils/http_client.dart';

/// HLS 视频流服务类
/// 负责处理 m3u8 文件的获取、转换和临时文件管理
class HlsService {
  static final HlsService _instance = HlsService._internal();
  factory HlsService() => _instance;
  HlsService._internal();

  final Dio _dio = HttpClient().dio;
  static const String baseUrl = 'http://anime.ayypd.cn:3000';

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

  /// 将 m3u8 内容中的相对路径转换为绝对URL
  String _convertToAbsoluteUrls(String m3u8Content) {
    final lines = m3u8Content.split('\n');
    final convertedLines = lines.map((line) {
      // 如果是 .ts 文件路径（以 / 开头的相对路径）
      if (line.trim().startsWith('/api/v1/video/slice/')) {
        return '$baseUrl$line';
      }
      return line;
    }).toList();

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

  /// 清理所有缓存目录
  Future<void> clearAllCache() async {
    try {
      await _initCacheDir();
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create();
        _tempFilePaths.clear();
        print('🗑️  已清空所有HLS缓存');
      }
    } catch (e) {
      print('❌ 清空缓存错误: $e');
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
