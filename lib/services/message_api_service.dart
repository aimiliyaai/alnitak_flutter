import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/message_models.dart';
import '../utils/http_client.dart';
import '../utils/message_read_status.dart';
import '../utils/token_manager.dart';
import 'logger_service.dart';

/// 消息API服务
class MessageApiService {
  final HttpClient _httpClient = HttpClient();
  final TokenManager _tokenManager = TokenManager();

  /// 获取公告列表
  Future<List<AnnounceMessage>> getAnnounceList({
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/message/getAnnounce',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        final list = response.data['data']['announces'] as List<dynamic>? ?? [];
        return list.map((e) => AnnounceMessage.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      LoggerService.instance.logWarning('获取公告列表失败: $e', tag: 'MessageApiService');
      return [];
    }
  }

  /// 获取@消息列表
  Future<List<AtMessage>> getAtMessageList({
    int page = 1,
    int pageSize = 10,
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return [];
    }

    try {
      final response = await _httpClient.dio.get(
        '/api/v1/message/getAtMsg',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        final list = response.data['data']['messages'] as List<dynamic>? ?? [];
        return list.map((e) => AtMessage.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      LoggerService.instance.logWarning('获取@消息列表失败: $e', tag: 'MessageApiService');
      return [];
    }
  }

  /// 获取点赞消息列表
  Future<List<LikeMessage>> getLikeMessageList({
    int page = 1,
    int pageSize = 10,
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return [];
    }

    try {
      final response = await _httpClient.dio.get(
        '/api/v1/message/getLikeMsg',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        final list = response.data['data']['messages'] as List<dynamic>? ?? [];
        return list.map((e) => LikeMessage.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      LoggerService.instance.logWarning('获取点赞消息列表失败: $e', tag: 'MessageApiService');
      return [];
    }
  }

  /// 获取回复消息列表
  Future<List<ReplyMessage>> getReplyMessageList({
    int page = 1,
    int pageSize = 10,
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return [];
    }

    try {
      final response = await _httpClient.dio.get(
        '/api/v1/message/getReplyMsg',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
        },
      );

      if (response.data['code'] == 200) {
        final list = response.data['data']['messages'] as List<dynamic>? ?? [];
        return list.map((e) => ReplyMessage.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      LoggerService.instance.logWarning('获取回复消息列表失败: $e', tag: 'MessageApiService');
      return [];
    }
  }

  /// 获取私信列表
  Future<List<WhisperListItem>> getWhisperList() async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return [];
    }

    try {
      final response = await _httpClient.dio.get(
        '/api/v1/message/getWhisperList',
      );


      if (response.data['code'] == 200) {
        final list = response.data['data']['messages'] as List<dynamic>? ?? [];
        return list.map((e) => WhisperListItem.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      LoggerService.instance.logWarning('获取私信列表失败: $e', tag: 'MessageApiService');
      return [];
    }
  }

  /// 获取私信详情
  Future<List<WhisperDetail>> getWhisperDetails({
    required int fid,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return [];
    }

    try {
      final response = await _httpClient.dio.get(
        '/api/v1/message/getWhisperDetails',
        queryParameters: {
          'fid': fid,
          'page': page,
          'pageSize': pageSize,
        },
      );


      if (response.data['code'] == 200) {
        final data = response.data['data'];
        final list = data['messages'] as List<dynamic>? ?? [];
        return list.map((e) => WhisperDetail.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      LoggerService.instance.logWarning('获取私信详情失败: $e', tag: 'MessageApiService');
      return [];
    }
  }

  /// 发送私信
  Future<bool> sendWhisper({
    required int fid,
    required String content,
  }) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return false;
    }

    try {
      final response = await _httpClient.dio.post(
        '/api/v1/message/sendWhisper',
        data: {
          'fid': fid,
          'content': content,
        },
      );

      return response.data['code'] == 200;
    } catch (e) {
      LoggerService.instance.logWarning('发送私信失败: $e', tag: 'MessageApiService');
      return false;
    }
  }

  /// 获取站内公告/点赞/回复/@ 的已读进度（服务端持久化，清数据后可恢复）
  /// 返回各分类最后已读的消息 ID，无则 0
  Future<Map<String, int>> getReadStatus() async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return {};
    }
    try {
      final response = await _httpClient.dio.get('/api/v1/message/readStatus');
      if (response.data['code'] == 200 && response.data['data'] != null) {
        final data = response.data['data'] as Map<String, dynamic>;
        return {
          MessageReadStatus.announce: (data['announce'] as num?)?.toInt() ?? 0,
          MessageReadStatus.like: (data['like'] as num?)?.toInt() ?? 0,
          MessageReadStatus.reply: (data['reply'] as num?)?.toInt() ?? 0,
          MessageReadStatus.at: (data['at'] as num?)?.toInt() ?? 0,
        };
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MessageApi] getReadStatus failed: $e');
    }
    return {};
  }

  /// 根据当前页 id 列表更新本地已读并上报服务端（公告/点赞/回复/@ 子页用）
  Future<void> markAndSaveReadStatus(String category, Iterable<int> ids) async {
    if (ids.isEmpty) return;
    final readUpToId = ids.reduce((a, b) => a > b ? a : b);
    if (readUpToId <= 0) return;
    await MessageReadStatus.markAsRead(category, readUpToId);
    await saveReadStatus(category, readUpToId);
  }

  /// 上报某分类已读到的消息 ID（服务端持久化）
  Future<void> saveReadStatus(String category, int readUpToId) async {
    if (!_tokenManager.canMakeAuthenticatedRequest || readUpToId <= 0) return;
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/message/readStatus',
        data: {'category': category, 'readUpToId': readUpToId},
      );
      if (response.data['code'] != 200 && kDebugMode) {
        debugPrint('[MessageApi] saveReadStatus $category=$readUpToId code=${response.data['code']} msg=${response.data['msg']} data=${response.data}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MessageApi] saveReadStatus failed: $e');
        if (e is DioException && e.response != null) {
          debugPrint('[MessageApi] saveReadStatus response: ${e.response?.data}');
        }
      }
    }
  }

  /// 标记私信为已读
  /// [fid] 对方用户ID
  Future<bool> readWhisper(int fid) async {
    if (!_tokenManager.canMakeAuthenticatedRequest) {
      return false;
    }

    try {
      final response = await _httpClient.dio.post(
        '/api/v1/message/readWhisper',
        data: {'id': fid},
      );

      return response.data['code'] == 200;
    } catch (e) {
      LoggerService.instance.logWarning('标记私信已读失败: $e', tag: 'MessageApiService');
      return false;
    }
  }
}
