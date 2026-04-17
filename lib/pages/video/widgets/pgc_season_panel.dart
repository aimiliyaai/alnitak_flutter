import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/pgc_models.dart';
import '../../../services/pgc_api_service.dart';
import '../../../services/logger_service.dart';
import '../../../theme/theme_extensions.dart';
import 'auto_play_source.dart';

class PgcSeasonPanel extends StatefulWidget {
  final String vid;
  final ValueChanged<String> onEpisodeTap;

  const PgcSeasonPanel({
    super.key,
    required this.vid,
    required this.onEpisodeTap,
  });

  @override
  State<PgcSeasonPanel> createState() => PgcSeasonPanelState();
}

class PgcSeasonPanelState extends State<PgcSeasonPanel> with AutoPlaySource {
  bool _autoNext = true;
  bool _showTitleMode = true;
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
      _showTitleMode = prefs.getBool('video_pgc_show_title') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('video_pgc_auto_next', _autoNext);
    await prefs.setBool('video_pgc_show_title', _showTitleMode);
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
    } catch (e, st) {
      LoggerService.instance.logWarning(
        'PgcSeasonPanel 加载失败 vid=${widget.vid}: $e\n$st',
        tag: 'PgcSeasonPanel',
      );
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

  void _toggleViewMode() {
    setState(() => _showTitleMode = !_showTitleMode);
    _saveSettings();
  }

@override
  String? getNextVideo() {
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

  bool _isCurrentEp(int index) {
    final eps = _panel?.episodes ?? const <PgcEpisode>[];
    if (index < 0 || index >= eps.length) return false;
    return eps[index].vid == widget.vid;
  }

  String _epTitle(PgcEpisode ep, int index) {
    if (ep.title.trim().isNotEmpty) return ep.title.trim();
    if (ep.episodeNumber > 0) return '第${ep.episodeNumber}话';
    return 'EP${index + 1}';
  }

  Widget _buildListMode(List<PgcEpisode> eps, dynamic colors) {
    return Column(
      children: [
        for (int index = 0; index < eps.length; index++) ...[
          if (index > 0) Divider(height: 1, color: colors.divider),
          _buildListTile(index, eps[index], colors),
        ],
      ],
    );
  }

  Widget _buildListTile(int index, PgcEpisode ep, dynamic colors) {
    final isCurrent = _isCurrentEp(index);
    return ListTile(
      selected: isCurrent,
      selectedTileColor: colors.accentColor.withValues(alpha: 0.15),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isCurrent ? colors.accentColor : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isCurrent ? Colors.white : colors.textSecondary,
            ),
          ),
        ),
      ),
      title: Text(
        _epTitle(ep, index),
        style: TextStyle(
          fontSize: 14,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isCurrent ? colors.accentColor : colors.textPrimary,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        ep.episodeNumber > 0 ? '第${ep.episodeNumber}话' : 'EP',
        style: TextStyle(fontSize: 12, color: colors.textSecondary),
      ),
      trailing: isCurrent ? Icon(Icons.play_circle, color: colors.accentColor) : null,
      onTap: () {
        if (!isCurrent) {
          _currentPlayIndex = index;
          widget.onEpisodeTap(ep.vid);
        }
      },
    );
  }

  Widget _buildGridMode(List<PgcEpisode> eps, dynamic colors) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int index = 0; index < eps.length; index++)
          _buildGridItem(index, eps[index], colors),
      ],
    );
  }

  Widget _buildGridItem(int index, PgcEpisode ep, dynamic colors) {
    final isCurrent = _isCurrentEp(index);
    return InkWell(
      onTap: () {
        if (!isCurrent) {
          _currentPlayIndex = index;
          widget.onEpisodeTap(ep.vid);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 32,
        decoration: BoxDecoration(
          color: isCurrent ? colors.accentColor : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: isCurrent ? Border.all(color: colors.accentColor, width: 2) : null,
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isCurrent ? Colors.white : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
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
                Expanded(
                  child: Text(
                    '正片列表 (${eps.where((e) => e.vid == widget.vid).isNotEmpty ? (eps.indexWhere((e) => e.vid == widget.vid) + 1) : 0}/${eps.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                IconButton(
                  icon: Icon(
                    _showTitleMode ? Icons.grid_view : Icons.list,
                    size: 20,
                    color: colors.iconPrimary,
                  ),
                  onPressed: _toggleViewMode,
                  tooltip: _showTitleMode ? '网格视图' : '列表视图',
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
              _showTitleMode
                  ? _buildListMode(eps, colors)
                  : _buildGridMode(eps, colors),
          ],
        ),
      ),
    );
  }
}

