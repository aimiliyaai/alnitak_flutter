import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../utils/http_client.dart';
import '../utils/token_manager.dart';

/// 上传API服务 - 参考PC端实现
///
/// Token 刷新机制说明：
/// - 使用 TokenManager 统一管理 token
/// - 当请求返回 code=3000 时自动刷新 token 并重试
/// - 所有涉及认证的请求都会自动处理 token 过期问题
class UploadApiService {
  static String get baseUrl => HttpClient().dio.options.baseUrl;

  /// 获取认证 token（统一使用 TokenManager）
  static String? _getAuthToken() {
    return TokenManager().token;
  }

  /// 刷新 token 并返回新 token
  static Future<String?> _refreshToken() async {
    return await HttpClient().refreshToken();
  }

  /// 发送带 token 刷新机制的 POST 请求
  /// 当收到 code=3000 时自动刷新 token 并重试一次
  static Future<Map<String, dynamic>> _postWithTokenRefresh({
    required String endpoint,
    required Map<String, dynamic> body,
    bool isRetry = false,
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');
    var token = _getAuthToken();

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = token;
    }

    final response = await http.post(
      url,
      headers: headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      // 检测 token 过期 (code=3000)，自动刷新重试
      if (data['code'] == 3000 && !isRetry) {
        print('🔄 检测到 Token 过期 (code=3000)，尝试刷新...');
        final newToken = await _refreshToken();
        if (newToken != null) {
          print('✅ Token 刷新成功，重试请求...');
          return _postWithTokenRefresh(
            endpoint: endpoint,
            body: body,
            isRetry: true,
          );
        } else {
          print('❌ Token 刷新失败');
          throw Exception('登录已过期，请重新登录');
        }
      }

      return data;
    } else {
      throw Exception('请求失败: ${response.statusCode}');
    }
  }

  /// 发送带 token 刷新机制的 Multipart 请求（用于文件上传）
  /// [buildRequest] 回调函数接收当前 token，返回构建好的 MultipartRequest
  static Future<Map<String, dynamic>> _multipartWithTokenRefresh({
    required String endpoint,
    required Future<http.MultipartRequest> Function(String? token) buildRequest,
    bool isRetry = false,
  }) async {
    var token = _getAuthToken();

    final request = await buildRequest(token);
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      // 检测 token 过期 (code=3000)，自动刷新重试
      if (data['code'] == 3000 && !isRetry) {
        print('🔄 检测到 Token 过期 (code=3000)，尝试刷新...');
        final newToken = await _refreshToken();
        if (newToken != null) {
          print('✅ Token 刷新成功，重试请求...');
          return _multipartWithTokenRefresh(
            endpoint: endpoint,
            buildRequest: buildRequest,
            isRetry: true,
          );
        } else {
          print('❌ Token 刷新失败');
          throw Exception('登录已过期，请重新登录');
        }
      }

      return data;
    } else {
      throw Exception('请求失败: ${response.statusCode}, ${response.body}');
    }
  }

  /// 上传图片
  /// 返回图片URL（带 token 刷新机制）
  static Future<String> uploadImage(File file) async {
    print('📤 ========== 开始上传封面图片 ==========');
    print('📁 文件路径: ${file.path}');
    print('📝 文件名: ${path.basename(file.path)}');

    final fileSize = await file.length();
    print('📦 文件大小: ${(fileSize / 1024).toStringAsFixed(2)} KB');

    final data = await _multipartWithTokenRefresh(
      endpoint: '/api/v1/upload/image',
      buildRequest: (token) async {
        final url = Uri.parse('$baseUrl/api/v1/upload/image');
        final request = http.MultipartRequest('POST', url);

        // 添加 Authorization header
        if (token != null) {
          request.headers['Authorization'] = token;
        }

        // 添加文件（参考PC端：字段名使用 "image"）
        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            file.path,
            filename: path.basename(file.path),
          ),
        );

        return request;
      },
    );

    if (data['code'] == 200) {
      final imageUrl = data['data']['url'] as String;
      print('✅ 图片上传成功！');
      print('🖼️ 图片URL: $imageUrl');
      print('📤 ========== 封面上传完成 ==========\n');
      return imageUrl;
    } else {
      print('❌ 服务器返回错误: code=${data['code']}, msg=${data['msg']}');
      print('📤 ========== 封面上传失败 ==========\n');
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
    int? vid,
    String? filename,
    bool Function()? onCancel, // 新增：取消检查回调
  }) async {
    // 1. 计算文件MD5（使用流式计算，避免大文件内存溢出）
    final fileMd5 = await _calculateFileMd5(file, onCancel: onCancel);

    // 检查是否已取消
    if (onCancel?.call() == true) {
      print('❌ 上传已取消（MD5计算后）');
      throw Exception('上传已取消');
    }

    final fileName = filename ?? path.basename(file.path);

    print('📹 准备上传视频: $fileName (MD5: $fileMd5)${vid != null ? ' (添加到VID: $vid)' : ''}');

    // 2. 检查已上传分片和秒传
    final checkResult = await _checkUploadedChunks(fileMd5);
    final uploadedChunks = checkResult['chunks'] as List<int>;
    final instantUpload = checkResult['instantUpload'] as bool;

    // 检查是否已取消
    if (onCancel?.call() == true) {
      print('❌ 上传已取消（检查分片后）');
      throw Exception('上传已取消');
    }

    // 【秒传】文件已存在且转码完成，直接获取视频信息
    if (instantUpload) {
      print('⚡ 【秒传】文件已存在，跳过上传直接完成');
      onProgress(1.0);
      final videoInfo = await _getVideoInfo(fileMd5, title: title, vid: vid);
      print('✅ 秒传成功，资源ID: ${videoInfo['id']}');
      return videoInfo;
    }

    print('✅ 已上传分片: ${uploadedChunks.length}');

    // 3. 分片上传
    await _uploadInChunks(
      file: file,
      fileMd5: fileMd5,
      fileName: fileName,
      uploadedChunks: uploadedChunks,
      onProgress: onProgress,
      onCancel: onCancel, // 传递取消回调
    );

    print('✅ 分片上传完成');

    // 检查是否已取消
    if (onCancel?.call() == true) {
      print('❌ 上传已取消（分片上传后）');
      throw Exception('上传已取消');
    }

    // 4. 合并分片
    await _mergeChunks(fileMd5);
    print('✅ 分片合并完成');

    // 检查是否已取消
    if (onCancel?.call() == true) {
      print('❌ 上传已取消（合并分片后）');
      throw Exception('上传已取消');
    }

    // 5. 获取视频信息（参考PC端：有vid时使用不同endpoint）
    final videoInfo = await _getVideoInfo(fileMd5, title: title, vid: vid);
    print('✅ 视频上传成功，资源ID: ${videoInfo['id']}');

    return videoInfo;
  }

  /// 流式计算文件MD5（避免大文件内存溢出）
  static Future<String> _calculateFileMd5(File file, {bool Function()? onCancel}) async {
    final fileSize = await file.length();
    print('📊 开始计算MD5: 文件大小 ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB');

    // 使用流式读取，默认每次读取64KB，不会占用大量内存
    final stream = file.openRead();

    // 定期检查取消标志
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

    print('✅ MD5计算完成: $md5Hash');
    return md5Hash;
  }

  /// 检查已上传的分片（带 token 刷新机制）
  /// 返回 { chunks: 已上传分片列表, instantUpload: 是否可秒传 }
  static Future<Map<String, dynamic>> _checkUploadedChunks(String hash) async {
    final data = await _postWithTokenRefresh(
      endpoint: '/api/v1/upload/checkVideo',
      body: {'hash': hash},
    );

    if (data['code'] == 200) {
      final chunks = data['data']['chunks'] as List<dynamic>?;
      final chunkList = chunks?.map((e) => e as int).toList() ?? [];

      // 后端返回 [-1] 表示文件已就绪，可以秒传
      if (chunkList.length == 1 && chunkList[0] == -1) {
        return {'chunks': <int>[], 'instantUpload': true};
      }
      return {'chunks': chunkList, 'instantUpload': false};
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
    bool Function()? onCancel, // 新增：取消检查回调
  }) async {
    const int chunkSize = 5 * 1024 * 1024; // 5MB
    const int maxConcurrent = 5; // 最大并发数

    final fileSize = await file.length();
    final totalChunks = (fileSize / chunkSize).ceil();

    print('📦 总分片数: $totalChunks, 已上传: ${uploadedChunks.length}');

    // 过滤出未上传的分片
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

    // 分批并发上传
    for (int i = 0; i < chunksToUpload.length; i += maxConcurrent) {
      // 每批上传前检查是否取消
      if (onCancel?.call() == true) {
        print('❌ 分片上传已取消（批次 ${i ~/ maxConcurrent + 1}）');
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

      print('📊 上传进度: ${(progress * 100).toStringAsFixed(1)}% ($uploadedCount/$totalChunks)');
    }
  }

  /// 上传单个分片（带 token 刷新机制）
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

    final data = await _multipartWithTokenRefresh(
      endpoint: '/api/v1/upload/chunkVideo',
      buildRequest: (token) async {
        final url = Uri.parse('$baseUrl/api/v1/upload/chunkVideo');
        final request = http.MultipartRequest('POST', url);

        // 添加 Authorization header
        if (token != null) {
          request.headers['Authorization'] = token;
        }

        // 添加表单字段
        request.fields['hash'] = hash;
        request.fields['name'] = fileName;
        request.fields['chunkIndex'] = chunkIndex.toString();
        request.fields['totalChunks'] = totalChunks.toString();

        // 添加文件
        request.files.add(
          http.MultipartFile.fromBytes(
            'video',
            chunkBytes,
            filename: 'chunk_$chunkIndex',
          ),
        );

        return request;
      },
    );

    if (data['code'] != 200) {
      throw Exception(data['msg'] ?? '分片上传失败 (chunk $chunkIndex)');
    }
  }

  /// 合并分片（带 token 刷新机制）
  static Future<void> _mergeChunks(String hash) async {
    final data = await _postWithTokenRefresh(
      endpoint: '/api/v1/upload/mergeVideo',
      body: {'hash': hash},
    );

    if (data['code'] != 200) {
      throw Exception(data['msg'] ?? '合并分片失败');
    }
  }

  /// 获取视频信息（带 token 刷新机制）
  static Future<Map<String, dynamic>> _getVideoInfo(String hash, {required String title, int? vid}) async {
    final endpoint = vid != null ? '/api/v1/upload/video/$vid' : '/api/v1/upload/video';

    print('📡 获取视频信息: $endpoint');
    print('📝 视频标题: $title');

    final data = await _postWithTokenRefresh(
      endpoint: endpoint,
      body: {
        'hash': hash,
        'title': title,
      },
    );

    if (data['code'] == 200) {
      return data['data']['resource'] as Map<String, dynamic>;
    } else {
      throw Exception(data['msg'] ?? '获取视频信息失败');
    }
  }

  /// 删除视频资源（带 token 刷新机制）
  static Future<void> deleteVideoResource(int resourceId) async {
    final data = await _postWithTokenRefresh(
      endpoint: '/api/v1/upload/video/resource/delete',
      body: {'id': resourceId},
    );

    if (data['code'] != 200) {
      throw Exception(data['msg'] ?? '删除视频资源失败');
    }
  }
}