import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import '../utils/http_client.dart';

/// 上传API服务 - 参考PC端实现
///
/// Token 刷新机制说明：
/// - 使用 HttpClient 的 AuthInterceptor 统一管理 token
/// - 当请求返回 code=3000 时拦截器自动刷新 token 并重试
class UploadApiService {
  static final Dio _dio = HttpClient().dio;

  /// 上传图片
  /// 返回图片URL
  static Future<String> uploadImage(File file) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        file.path,
        filename: path.basename(file.path),
      ),
    });

    final response = await _dio.post(
      '/api/v1/upload/image',
      data: formData,
    );

    final data = response.data as Map<String, dynamic>;
    if (data['code'] == 200) {
      final imageUrl = data['data']['url'] as String;
      return imageUrl;
    } else {
      throw Exception(data['msg'] ?? '上传图片失败');
    }
  }

  /// 上传视频 - 参考PC端实现
  /// 返回视频资源信息
  ///
  /// [vid] 可选的视频ID，用于添加多分P（参考PC端：有vid时使用不同的endpoint）
  /// [filename] 可选的原始文件名，如果不传则使用file路径的文件名
  /// [onCancel] 可选的取消回调，返回true表示需要取消上传
static Future<Map<String, dynamic>> uploadVideo({
    required File file,
    required String title,
    required Function(double) onProgress,
    String? vid,
    String? filename,
    bool Function()? onCancel,
  }) async {
    // 1. 计算文件MD5（使用流式计算，避免大文件内存溢出）
    final fileMd5 = await _calculateFileMd5(file, onCancel: onCancel);
    final fileSize = await file.length();

    if (onCancel?.call() == true) {
      throw Exception('上传已取消');
    }

    final fileName = filename ?? path.basename(file.path);


    // 2. 检查已上传分片和秒传
    final checkResult = await _checkUploadedChunks(fileMd5, fileSize);
    final uploadedChunks = checkResult['chunks'] as List<int>;
    final instantUpload = checkResult['instantUpload'] as bool;
    final fileID = checkResult['fileID'] as int;

    if (onCancel?.call() == true) {
      throw Exception('上传已取消');
    }

    // 【秒传】文件已存在且转码完成，直接获取视频信息
    if (instantUpload) {
      onProgress(1.0);
      final videoInfo = await _getVideoInfo(fileID: fileID, size: fileSize, title: title, vid: vid);
      return videoInfo;
    }


    // 3. 分片上传
    await _uploadInChunks(
      file: file,
      fileMd5: fileMd5,
      fileName: fileName,
      uploadedChunks: uploadedChunks,
      onProgress: onProgress,
      onCancel: onCancel,
    );


    if (onCancel?.call() == true) {
      throw Exception('上传已取消');
    }

    // 4. 合并分片
    await _mergeChunks(hash: fileMd5, fileID: fileID, size: fileSize);

    if (onCancel?.call() == true) {
      throw Exception('上传已取消');
    }

    // 5. 获取视频信息（参考PC端：有vid时使用不同endpoint）
    final videoInfo = await _getVideoInfo(fileID: fileID, size: fileSize, title: title, vid: vid);

    return videoInfo;
  }

  /// 流式计算文件MD5（避免大文件内存溢出）
  static Future<String> _calculateFileMd5(File file, {bool Function()? onCancel}) async {
    final stream = file.openRead();

    Stream<List<int>> cancelableStream = stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          if (onCancel?.call() == true) {
            sink.close();
            throw Exception('MD5计算已取消');
          }
          sink.add(data);
        },
      ),
    );

    final digest = await md5.bind(cancelableStream).first;
    final md5Hash = digest.toString();

    return md5Hash;
  }

  /// 检查已上传的分片
  /// 返回 { chunks: 已上传分片列表, fileID: 视频文件ID, instantUpload: 是否可秒传 }
  static Future<Map<String, dynamic>> _checkUploadedChunks(String hash, int size) async {
    final response = await _dio.post(
      '/api/v1/upload/checkVideo',
      data: {'hash': hash, 'size': size},
    );

    final data = response.data as Map<String, dynamic>;
    if (data['code'] == 200) {
      final chunks = data['data']['chunks'] as List<dynamic>?;
      final chunkList = chunks?.map((e) => e as int).toList() ?? [];
      final fileID = data['data']['fileID'] as int? ?? 0;

      // 后端返回 [-1] 表示文件已就绪，可以秒传
      if (chunkList.length == 1 && chunkList[0] == -1) {
        return {'chunks': <int>[], 'fileID': fileID, 'instantUpload': true};
      }
      return {'chunks': chunkList, 'fileID': fileID, 'instantUpload': false};
    } else {
      throw Exception(data['msg'] ?? '检查分片失败');
    }
  }

  /// 分片上传
  static Future<void> _uploadInChunks({
    required File file,
    required String fileMd5,
    required String fileName,
    required List<int> uploadedChunks,
    required Function(double) onProgress,
    bool Function()? onCancel,
  }) async {
    const int chunkSize = 5 * 1024 * 1024; // 5MB
    const int maxConcurrent = 5;

    final fileSize = await file.length();
    final totalChunks = (fileSize / chunkSize).ceil();


    final chunksToUpload = <int>[];
    for (int i = 0; i < totalChunks; i++) {
      if (!uploadedChunks.contains(i)) {
        chunksToUpload.add(i);
      }
    }

    if (chunksToUpload.isEmpty) {
      onProgress(1.0);
      return;
    }

    int uploadedCount = uploadedChunks.length;

    for (int i = 0; i < chunksToUpload.length; i += maxConcurrent) {
      if (onCancel?.call() == true) {
        throw Exception('上传已取消');
      }

      final endIndex = (i + maxConcurrent > chunksToUpload.length)
          ? chunksToUpload.length
          : i + maxConcurrent;
      final futures = <Future>[];

      for (int j = i; j < endIndex; j++) {
        final chunkIndex = chunksToUpload[j];
        futures.add(_uploadChunk(
          file: file,
          hash: fileMd5,
          fileName: fileName,
          chunkIndex: chunkIndex,
          totalChunks: totalChunks,
          chunkSize: chunkSize,
          fileSize: fileSize,
        ));
      }

      await Future.wait(futures);

      uploadedCount += futures.length;
      final progress = uploadedCount / totalChunks;
      onProgress(progress);

    }
  }

  /// 上传单个分片
  static Future<void> _uploadChunk({
    required File file,
    required String hash,
    required String fileName,
    required int chunkIndex,
    required int totalChunks,
    required int chunkSize,
    required int fileSize,
  }) async {
    final start = chunkIndex * chunkSize;
    final end = (start + chunkSize > fileSize) ? fileSize : start + chunkSize;

    final randomAccessFile = await file.open();
    await randomAccessFile.setPosition(start);
    final chunkBytes = await randomAccessFile.read(end - start);
    await randomAccessFile.close();

    final formData = FormData.fromMap({
      'hash': hash,
      'name': fileName,
      'chunkIndex': chunkIndex.toString(),
      'totalChunks': totalChunks.toString(),
      'size': fileSize.toString(),
      'video': MultipartFile.fromBytes(
        chunkBytes,
        filename: 'chunk_$chunkIndex',
      ),
    });

    final response = await _dio.post(
      '/api/v1/upload/chunkVideo',
      data: formData,
    );

    final data = response.data as Map<String, dynamic>;
    if (data['code'] != 200) {
      throw Exception(data['msg'] ?? '分片上传失败 (chunk $chunkIndex)');
    }
  }

  /// 合并分片
  static Future<void> _mergeChunks({required String hash, required int fileID, required int size}) async {
    final response = await _dio.post(
      '/api/v1/upload/mergeVideo',
      data: {'hash': hash, 'fileID': fileID, 'size': size},
    );

    final data = response.data as Map<String, dynamic>;
    if (data['code'] != 200) {
      throw Exception(data['msg'] ?? '合并分片失败');
    }
  }

  /// 获取视频信息
static Future<Map<String, dynamic>> _getVideoInfo({required int fileID, required int size, required String title, String? vid}) async {
    final endpoint = vid != null ? '/api/v1/upload/video/$vid' : '/api/v1/upload/video';


    final response = await _dio.post(
      endpoint,
      data: {
        'fileID': fileID,
        'size': size,
        'title': title,
      },
    );

    final data = response.data as Map<String, dynamic>;
    if (data['code'] == 200) {
      return data['data']['resource'] as Map<String, dynamic>;
    } else {
      throw Exception(data['msg'] ?? '获取视频信息失败');
    }
  }

  /// 删除视频资源
  static Future<void> deleteVideoResource(int resourceId) async {
    final response = await _dio.post(
      '/api/v1/upload/video/resource/delete',
      data: {'id': resourceId},
    );

    final data = response.data as Map<String, dynamic>;
    if (data['code'] != 200) {
      throw Exception(data['msg'] ?? '删除视频资源失败');
    }
  }
}
