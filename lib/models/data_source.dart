/// 媒体源类型
enum DataSourceType { network, file, asset }

/// 媒体数据源（参考 pilipala DataSource）
///
/// 统一描述视频和音频的播放源信息
class DataSource {
  /// 视频源（URL 或本地临时文件路径）
  final String videoSource;

  /// 外挂音频源 URL（用于 audio-files 挂载）
  final String? audioSource;

  /// 源类型
  final DataSourceType type;

  /// HTTP 请求头
  final Map<String, String>? httpHeaders;

  const DataSource({
    required this.videoSource,
    this.audioSource,
    this.type = DataSourceType.network,
    this.httpHeaders,
  });
}
