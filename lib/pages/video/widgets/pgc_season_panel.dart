import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/pgc_models.dart';
import '../../../services/pgc_api_service.dart';
import '../../../theme/theme_extensions.dart';

class PgcSeasonPanel extends StatefulWidget {
  final int vid;
  final ValueChanged<int> onEpisodeTap;

  const PgcSeasonPanel({
    super.key,
    required this.vid,
    required this.onEpisodeTap,
  });

  @override
  State<PgcSeasonPanel> createState() => PgcSeasonPanelState();
}

class PgcSeasonPanelState extends State<PgcSeasonPanel> {
  bool _autoNext = true;
  bool _loading = true;
  PgcPlayPanel? _panel;
  int _currentPlayIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPanel();
  }

  @override
  void didUpdateWidget(PgcSeasonPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vid != widget.vid) {
      _currentPlayIndex = -1;
      _loadPanel();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoNext = prefs.getBool('video_pgc_auto_next') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('video_pgc_auto_next', _autoNext);
  }

  Future<void> _loadPanel({String? seasonId}) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await PgcApiService.playPanelByVideo(vid: widget.vid, seasonId: seasonId);
      if (!mounted) return;
      setState(() {
        _panel = res;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _panel = null;
        _loading = false;
      });
    }
  }

  void _toggleAutoNext() {
    setState(() => _autoNext = !_autoNext);
    _saveSettings();
  }

  int? getNextVideo() {
    if (!_autoNext) return null;
    final eps = _panel?.episodes ?? const <PgcEpisode>[];
    if (eps.isEmpty) return null;
    final nextIndex = _currentPlayIndex + 1;
    if (nextIndex >= 0 && nextIndex < eps.length) {
      _currentPlayIndex = nextIndex;
      return eps[nextIndex].vid;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final panel = _panel;
    final seasons = panel?.seasons ?? const <PgcItem>[];
    final eps = panel?.episodes ?? const <PgcEpisode>[];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '正片列表',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Row(
                  children: [
                    Text('自动连播', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                    const SizedBox(width: 4),
                    Switch(
                      value: _autoNext,
                      onChanged: (_) => _toggleAutoNext(),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (!_loading && seasons.isNotEmpty)
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: seasons.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final s = seasons[i];
                    final selected = panel?.activeSeasonId == s.pgcId;
                    return ChoiceChip(
                      label: Text(s.title.isNotEmpty ? s.title : '第${i + 1}季'),
                      selected: selected,
                      onSelected: (_) => _loadPanel(seasonId: s.pgcId),
                    );
                  },
                ),
              ),
            if (!_loading && seasons.isNotEmpty) const SizedBox(height: 10),
            if (!_loading && eps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text('暂无剧集', style: TextStyle(color: colors.textSecondary)),
                ),
              ),
            if (!_loading && eps.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < eps.length; i++)
                    _EpChip(
                      ep: eps[i],
                      onTap: () {
                        _currentPlayIndex = i;
                        widget.onEpisodeTap(eps[i].vid);
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EpChip extends StatelessWidget {
  final PgcEpisode ep;
  final VoidCallback onTap;

  const _EpChip({required this.ep, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.inputBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          ep.episodeNumber > 0 ? '${ep.episodeNumber}' : 'EP',
          style: TextStyle(color: colors.textPrimary),
        ),
      ),
    );
  }
}

