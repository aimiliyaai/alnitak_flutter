import '../utils/json_field.dart';

class PgcItem {
  final String pgcId;
  final int pgcType;
  final String title;
  final String cover;
  final String desc;
  final int year;
  final String area;
  final double rating;
  final bool isOngoing;
  final int totalEpisodes;
  final int currentEpisodes;

  final int? latestEpId;
  final int? latestEpNumber;
  final String? latestEpTitle;
  final int? latestVid;

  PgcItem({
    required this.pgcId,
    required this.pgcType,
    required this.title,
    required this.cover,
    required this.desc,
    required this.year,
    required this.area,
    required this.rating,
    required this.isOngoing,
    required this.totalEpisodes,
    required this.currentEpisodes,
    this.latestEpId,
    this.latestEpNumber,
    this.latestEpTitle,
    this.latestVid,
  });

  factory PgcItem.fromJson(Map<String, dynamic> json) {
    return PgcItem(
      pgcId: jsonAsString(json['pgc_id']),
      pgcType: jsonAsInt(json['pgc_type']),
      title: jsonAsString(json['title']),
      cover: jsonAsString(json['cover']),
      desc: jsonAsString(json['desc']),
      year: jsonAsInt(json['year']),
      area: jsonAsString(json['area']),
      rating: (json['rating'] ?? 0).toDouble(),
      isOngoing: json['is_ongoing'] == true,
      totalEpisodes: jsonAsInt(json['total_episodes']),
      currentEpisodes: jsonAsInt(json['current_episodes']),
      latestEpId: json['latest_ep_id'] == null ? null : jsonAsInt(json['latest_ep_id']),
      latestEpNumber:
          json['latest_ep_number'] == null ? null : jsonAsInt(json['latest_ep_number']),
      latestEpTitle: jsonAsStringOrNull(json['latest_ep_title']),
      latestVid: json['latest_vid'] == null ? null : jsonAsInt(json['latest_vid']),
    );
  }
}

class PgcEpisode {
  final int id;
  final int episodeNumber;
  final String title;
  final String vid;
  final String? shortId;  // 分P的shortId

  PgcEpisode({
    required this.id,
    required this.episodeNumber,
    required this.title,
    required this.vid,
    this.shortId,
  });

  factory PgcEpisode.fromJson(Map<String, dynamic> json) {
    return PgcEpisode(
      id: jsonAsInt(json['id'] ?? json['ep_id']),
      episodeNumber: jsonAsInt(json['episode_number']),
      title: jsonAsString(json['title']),
      vid: json['vid']?.toString() ?? '',
      shortId: json['shortId'] as String?,
    );
  }
}

class PgcPlayPanel {
  final PgcItem current;
  final List<PgcItem> seasons;
  final List<PgcEpisode> episodes;
  final String activeSeasonId;

  PgcPlayPanel({
    required this.current,
    required this.seasons,
    required this.episodes,
    required this.activeSeasonId,
  });

  factory PgcPlayPanel.fromJson(Map<String, dynamic> json) {
    return PgcPlayPanel(
      current: PgcItem.fromJson(Map<String, dynamic>.from(json['current'] as Map? ?? {})),
      seasons: (json['seasons'] as List<dynamic>?)
              ?.map((e) => PgcItem.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      episodes: (json['episodes'] as List<dynamic>?)
              ?.map((e) => PgcEpisode.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      activeSeasonId: jsonAsString(json['active_season_id']),
    );
  }
}

String pgcTypeLabel(int pgcType) {
  // 后端类型：1 国创, 2 日创, 3 纪录片, 4 电影, 5 电视剧
  // 产品要求：动画/番剧区分显示：国创=番剧、日创=动画
  switch (pgcType) {
    case 1:
      return '番剧';
    case 2:
      return '动画';
    case 3:
      return '纪录片';
    case 4:
      return '电影';
    case 5:
      return '电视剧';
    default:
      return '影视';
  }
}

