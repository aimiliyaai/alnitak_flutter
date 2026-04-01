import 'package:flutter/material.dart';
import '../../../models/pgc_models.dart';
import '../../../services/pgc_api_service.dart';
import '../../../theme/theme_extensions.dart';
import '../../../widgets/cached_image_widget.dart';

class PgcRecommendList extends StatefulWidget {
  final int vid;
  final void Function(PgcItem) onPgcTap;

  const PgcRecommendList({
    super.key,
    required this.vid,
    required this.onPgcTap,
  });

  @override
  State<PgcRecommendList> createState() => PgcRecommendListState();
}

class PgcRecommendListState extends State<PgcRecommendList> {
  bool _loading = true;
  List<PgcItem> _list = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(PgcRecommendList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vid != widget.vid) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final list = await PgcApiService.recommendByVideo(vid: widget.vid, page: 1, pageSize: 12);
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _list = [];
        _loading = false;
      });
    }
  }

  // 推荐区不参与自动连播：只保留一个开关（放在正片列表里）
  int? getNextVideo() => null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('相关推荐', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (!_loading && _list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text('暂无推荐', style: TextStyle(color: colors.textSecondary)),
                ),
              ),
            if (!_loading && _list.isNotEmpty)
              Column(
                children: [
                  for (final item in _list) ...[
                    _PgcRecommendRow(item: item, onTap: () => widget.onPgcTap(item)),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PgcRecommendRow extends StatelessWidget {
  final PgcItem item;
  final VoidCallback onTap;

  const _PgcRecommendRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subtitle = item.latestEpTitle?.isNotEmpty == true ? item.latestEpTitle! : item.desc;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 160,
              height: 90,
              child: CachedImage(imageUrl: item.cover, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle.isNotEmpty ? subtitle : '暂无简介',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  pgcTypeLabel(item.pgcType),
                  style: TextStyle(fontSize: 12, color: colors.accentColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
