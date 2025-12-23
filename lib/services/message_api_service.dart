import '../models/message_models.dart';
import '../utils/http_client.dart';

/// 消息API服务
class MessageApiService {
  final HttpClient _httpClient = HttpClient();

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
      print('获取公告列表失败: $e');
      return [];
    }
  }

  /// 获取@消息列表
  Future<List<AtMessage>> getAtMessageList({
    int page = 1,
    int pageSize = 10,
  }) async {
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
      print('获取@消息列表失败: $e');
      return [];
    }
  }

  /// 获取点赞消息列表
  Future<List<LikeMessage>> getLikeMessageList({
    int page = 1,
    int pageSize = 10,
  }) async {
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
      print('获取点赞消息列表失败: $e');
      return [];
    }
  }

  /// 获取回复消息列表
  Future<List<ReplyMessage>> getReplyMessageList({
    int page = 1,
    int pageSize = 10,
  }) async {
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
      print('获取回复消息列表失败: $e');
      return [];
    }
  }

  /// 获取私信列表
  Future<List<WhisperListItem>> getWhisperList() async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/message/getWhisperList',
      );

      print('私信列表响应: ${response.data}');

      if (response.data['code'] == 200) {
        final list = response.data['data']['messages'] as List<dynamic>? ?? [];
        print('私信列表长度: ${list.length}');
        return list.map((e) => WhisperListItem.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('获取私信列表失败: $e');
      return [];
    }
  }

  /// 获取私信详情
  Future<List<WhisperDetail>> getWhisperDetails({
    required int fid,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/message/getWhisperDetails',
        queryParameters: {
          'fid': fid,
          'page': page,
          'pageSize': pageSize,
        },
      );

      print('私信详情响应: ${response.data}');

      if (response.data['code'] == 200) {
        final data = response.data['data'];
        print('私信详情data: $data');
        final list = data['messages'] as List<dynamic>? ?? [];
        print('私信详情列表长度: ${list.length}');
        return list.map((e) => WhisperDetail.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('获取私信详情失败: $e');
      return [];
    }
  }

  /// 发送私信
  Future<bool> sendWhisper({
    required int fid,
    required String content,
  }) async {
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
      print('发送私信失败: $e');
      return false;
    }
  }

  /// 标记私信为已读
  Future<bool> readWhisper(int id) async {
    try {
      final response = await _httpClient.dio.post(
        '/api/v1/message/readWhisper',
        data: {'id': id},
      );

      return response.data['code'] == 200;
    } catch (e) {
      print('标记已读失败: $e');
      return false;
    }
  }
}
