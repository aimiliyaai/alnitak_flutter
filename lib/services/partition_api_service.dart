import 'package:dio/dio.dart';
import '../models/partition.dart';
import '../utils/http_client.dart';

/// 分区API服务
class PartitionApiService {
  static final Dio _dio = HttpClient().dio;

  /// 获取视频分区列表
  static Future<List<Partition>> getVideoPartitions() async {
    try {
      final response = await _dio.get(
        '/api/v1/partition/getPartitionList',
        queryParameters: {'type': 0},
      );

      if (response.data['code'] == 200) {
        final partitionResponse = PartitionResponse.fromJson(response.data);
        return partitionResponse.partitions;
      } else {
        throw Exception(response.data['msg'] ?? '获取视频分区失败');
      }
    } catch (e) {
      throw Exception('获取失败: $e');
    }
  }

  /// 获取文章分区列表
  static Future<List<Partition>> getArticlePartitions() async {
    try {
      final response = await _dio.get(
        '/api/v1/partition/getPartitionList',
        queryParameters: {'type': 1},
      );

      if (response.data['code'] == 200) {
        final partitionResponse = PartitionResponse.fromJson(response.data);
        return partitionResponse.partitions;
      } else {
        throw Exception(response.data['msg'] ?? '获取文章分区失败');
      }
    } catch (e) {
      throw Exception('获取失败: $e');
    }
  }

  /// 获取父分区列表（一级分区）
  static List<Partition> getParentPartitions(List<Partition> allPartitions) {
    return allPartitions.where((p) => p.parentId == null).toList();
  }

  /// 获取子分区列表
  static List<Partition> getSubPartitions(List<Partition> allPartitions, int parentId) {
    return allPartitions.where((p) => p.parentId == parentId).toList();
  }

  /// 根据ID查找分区
  static Partition? findPartitionById(List<Partition> allPartitions, int id) {
    try {
      return allPartitions.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }
}
