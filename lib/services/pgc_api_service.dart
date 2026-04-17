import 'package:dio/dio.dart';
import '../models/pgc_models.dart';
import '../utils/http_client.dart';

class PgcApiService {
  static final Dio _dio = HttpClient().dio;

  static Future<List<PgcItem>> recommend({
    int page = 1,
    int pageSize = 12,
    int? pgcType,
    String? seedPgcId,
    String scene = 'home',
  }) async {
    final resp = await _dio.get(
      '/api/v1/pgc/recommend',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (pgcType != null) 'pgc_type': pgcType,
        if (seedPgcId != null && seedPgcId.isNotEmpty) 'seed_pgc_id': seedPgcId,
        'scene': scene,
      },
    );
    if (resp.data['code'] != 200) return [];
    final data = resp.data['data'] as Map<String, dynamic>? ?? {};
    final list = data['list'] as List<dynamic>? ?? [];
    return list.map((e) => PgcItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<List<PgcItem>> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
    int? pgcType,
  }) async {
    final resp = await _dio.get(
      '/api/v1/pgc/search',
      queryParameters: {
        'keyword': keyword,
        'page': page,
        'page_size': pageSize,
        if (pgcType != null) 'pgc_type': pgcType,
      },
    );
    if (resp.data['code'] != 200) return [];
    final data = resp.data['data'] as Map<String, dynamic>? ?? {};
    final list = data['list'] as List<dynamic>? ?? [];
    return list.map((e) => PgcItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

static Future<PgcPlayPanel?> playPanelByVideo({
    required String vid,
    String? seasonId,
  }) async {
    final resp = await _dio.get(
      '/api/v1/pgc/play-panel-by-video',
      queryParameters: {
        'vid': vid,
        if (seasonId != null && seasonId.isNotEmpty) 'season_id': seasonId,
      },
    );
    if (resp.data['code'] != 200) return null;
    final data = resp.data['data'] as Map<String, dynamic>? ?? {};
    if (data['current'] == null) return null;
    return PgcPlayPanel.fromJson(data);
  }

static Future<String?> resolveVidByEpisodeId(int epId) async {
    final resp = await _dio.get(
      '/api/v1/pgc/episode-detail',
      queryParameters: {'ep_id': epId},
    );
    if (resp.data['code'] != 200) return null;
    final data = resp.data['data'] as Map<String, dynamic>? ?? {};
    final ep = data['episode'] as Map<String, dynamic>? ?? {};
    final vid = ep['vid'];
    if (vid == null) return null;
    if (vid is String) return vid;
    if (vid is int) return vid.toString();
    if (vid is num) return vid.toString();
    return null;
  }

static Future<List<PgcItem>> recommendByVideo({
    required String vid,
    int page = 1,
    int pageSize = 12,
  }) async {
    final resp = await _dio.get(
      '/api/v1/pgc/recommend-by-video',
      queryParameters: {'vid': vid, 'page': page, 'page_size': pageSize},
    );
    if (resp.data['code'] != 200) return [];
    final data = resp.data['data'] as Map<String, dynamic>? ?? {};
    final list = data['list'] as List<dynamic>? ?? [];
    return list.map((e) => PgcItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}
