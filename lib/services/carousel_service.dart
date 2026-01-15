import '../models/carousel_model.dart';
import '../utils/http_client.dart';

/// 轮播图服务
class CarouselService {
  final HttpClient _httpClient = HttpClient();

  /// 获取轮播图列表
  /// [partitionId] 分区ID，默认为0（首页推荐）
  Future<List<CarouselItem>> getCarousel({int partitionId = 0}) async {
    try {
      final response = await _httpClient.dio.get(
        '/api/v1/carousel/getCarousel',
        queryParameters: {'partitionId': partitionId},
      );

      if (response.data['code'] == 200) {
        final list = response.data['data']['carousels'] as List<dynamic>? ?? [];
        return list.map((e) => CarouselItem.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('获取轮播图失败: $e');
      return [];
    }
  }
}
