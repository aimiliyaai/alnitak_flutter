import 'package:flutter/material.dart';
import '../../theme/theme_extensions.dart';
import '../user/user_space_page.dart';
import 'video_page_controller.dart';
import 'widgets/media_player_widget.dart';
import 'widgets/fullscreen_player_page.dart';
import 'widgets/author_card.dart';
import 'widgets/video_info_card.dart';
import 'widgets/video_action_buttons.dart';
import 'widgets/collection_list.dart';
import 'widgets/recommend_list.dart';
import 'widgets/comment_preview_card.dart';
import 'widgets/pgc_recommend_list.dart';
import 'widgets/pgc_season_panel.dart';
import '../../widgets/danmaku_overlay.dart';
import '../../services/pgc_api_service.dart';
import '../../services/logger_service.dart';
import '../../models/pgc_models.dart';
import '../../utils/video_route.dart';

/// 视频播放页面（纯 UI 层，业务逻辑委托给 VideoPageController）
class VideoPlayPage extends StatefulWidget {
  /// 路由/API 层视频标识：数字 id 或 shortId（与后端 ParseVideoID 一致）
  final String videoRef;
  final bool pgcMode;
  final int? epId;
  final int? initialPart;

  const VideoPlayPage({
    super.key,
    required this.videoRef,
    this.pgcMode = false,
    this.epId,
    this.initialPart,
  });

  @override
  State<VideoPlayPage> createState() => _VideoPlayPageState();
}

class _VideoPlayPageState extends State<VideoPlayPage> with WidgetsBindingObserver {
  late final VideoPageController _controller;
  final ScrollController _scrollController = ScrollController();
  late final GlobalKey _playerKey;

  // 自动连播 GlobalKey
  final GlobalKey<CollectionListState> _collectionListKey = GlobalKey<CollectionListState>();
  final GlobalKey<RecommendListState> _recommendListKey = GlobalKey<RecommendListState>();
  final GlobalKey<PgcSeasonPanelState> _pgcSeasonKey = GlobalKey<PgcSeasonPanelState>();
  final GlobalKey<PgcRecommendListState> _pgcRecommendKey = GlobalKey<PgcRecommendListState>();

  PgcPlayPanel? _pgcPanel;
  // 预留：后续可用于顶部信息展示/缓存，当前未使用

  bool get _isPGCMode => widget.pgcMode || isPgcVideoPlayRef(widget.videoRef);

  String get _resolvedVideoRef => resolveVideoRefForPlayback(widget.videoRef);

  @override
  void initState() {
    super.initState();
    _playerKey = GlobalKey(debugLabel: 'player_stable');
    _controller = VideoPageController();
    _controller.setAutoPlayKeys(
      collectionListKey: _isPGCMode ? _pgcSeasonKey : _collectionListKey,
      recommendListKey: _isPGCMode ? _pgcRecommendKey : _recommendListKey,
    );
    _controller.addListener(_onControllerChanged);
    _controller.init(_resolvedVideoRef, initialPart: widget.initialPart);
    WidgetsBinding.instance.addObserver(this);

    LoggerService.instance.reportEvent(
      '进入播放页',
      {'videoRef': _resolvedVideoRef, 'pgcMode': _isPGCMode, 'epId': widget.epId, 'initialPart': widget.initialPart},
    );
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
    if (_isPGCMode && _controller.currentVid > 0 && _pgcPanel == null) {
      _loadPgcMeta(_controller.currentVid);
    }
  }

  Future<void> _loadPgcMeta(int vid) async {
    try {
      final panel = await PgcApiService.playPanelByVideo(vid: vid);
      final rec = await PgcApiService.recommendByVideo(vid: vid);
      if (!mounted) return;
      setState(() {
        _pgcPanel = panel;
        // 由 PgcRecommendList 自行拉取；这里仅做预留缓存位
        // ignore: unused_local_variable
        final _ = rec;
      });
    } catch (e, st) {
      LoggerService.instance.logWarning(
        'PGC 元数据加载失败 vid=$vid: $e\n$st',
        tag: 'VideoPlayPage',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _controller.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// 进入全屏
  void _openFullscreen() {
    if (_controller.playerController == null || !mounted || _controller.videoDetail == null) return;
    final c = _controller;
    final currentResource = c.videoDetail!.resources[c.currentPart - 1];
    final title = c.videoDetail!.resources.length > 1
        ? currentResource.title
        : c.videoDetail!.title;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, _, __) => FullscreenPlayerPage(
          controller: c.playerController!,
          title: title,
          danmakuController: c.danmakuController,
          onlineCount: c.onlineWebSocketService.onlineCount,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        left: false,
        right: false,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.isLoading) {
      return Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.transparent,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(),
                    ),
                    SizedBox(height: 12),
                    Text('加载中...', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      );
    }

    if (_controller.errorMessage != null) {
      return Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.white70),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _controller.errorMessage!,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _controller.loadVideoData,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      );
    }

    if (_controller.videoDetail == null) {
      return Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const Center(
                    child: Text('视频加载失败', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      );
    }

    final c = _controller;
    final currentResource = c.videoDetail!.resources[c.currentPart - 1];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 900;
        if (isWideScreen) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: _buildMainContent(currentResource),
              ),
              SizedBox(
                width: 350,
                child: _buildSidebar(),
              ),
            ],
          );
        } else {
          return _buildMainContent(currentResource);
        }
      },
    );
  }

  Widget _buildMainContent(dynamic currentResource) {
    final c = _controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final playerHeight = constraints.maxWidth * 9 / 16;
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: playerHeight,
              child: MediaPlayerWidget(
                key: _playerKey,
                resourceId: c.currentResourceId,
                initialPosition: c.currentInitialPosition,
                duration: currentResource.duration,
                onVideoEnd: c.onVideoEnded,
                onProgressUpdate: c.onProgressUpdate,
                onControllerReady: (controller) {
                  c.playerController = controller;
                  controller.setVideoContext(vid: c.currentVid, part: c.currentPart);
                  controller.onReplayAfterCompletion = () {
                    if (!mounted) return;
                    c.onReplayFromEnd();
                  };
                },
                title: c.videoDetail!.resources.length > 1
                    ? currentResource.title
                    : c.videoDetail!.title,
                author: c.videoDetail!.author.name,
                coverUrl: c.videoDetail!.cover,
                totalParts: c.videoDetail!.resources.length,
                currentPart: c.currentPart,
                onPartChange: (part) => c.changePart(part, onComplete: _scrollToTop),
                danmakuController: c.danmakuController,
                onPlayingStateChanged: c.onPlayingStateChanged,
                onlineCount: c.onlineWebSocketService.onlineCount,
                isFullscreen: false,
                onFullscreenToggle: _openFullscreen,
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  _buildDanmakuInputBar(),
                  if (_isPGCMode && _pgcPanel?.current != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _PgcInfoCard(item: _pgcPanel!.current),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: VideoInfoCard(
                      videoDetail: c.videoDetail!,
                      videoStat: c.videoStat!,
                      currentPart: c.currentPart,
                      onlineCount: c.onlineWebSocketService.onlineCount,
                      danmakuCount: c.danmakuCountNotifier,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: VideoActionButtons(
                      vid: c.currentVid,
                      currentPart: c.currentPart,
                      shortId: c.videoDetail!.shortId,
                      initialStat: c.videoStat!,
                      initialHasLiked: c.actionStatus!.hasLiked,
                      initialHasCollected: c.actionStatus!.hasCollected,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_isPGCMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AuthorCard(
                        author: c.videoDetail!.author,
                        initialRelationStatus: c.actionStatus!.relationStatus,
                        onAvatarTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserSpacePage(userId: c.videoDetail!.author.uid),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (MediaQuery.of(context).size.width <= 900)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _isPGCMode
                          ? PgcSeasonPanel(
                              key: _pgcSeasonKey,
                              vid: c.currentVid,
                              onEpisodeTap: (vid) => c.switchToVideo(vid, onComplete: _scrollToTop),
                            )
                          : CollectionList(
                              key: _collectionListKey,
                              vid: c.currentVid,
                              currentPart: c.currentPart,
                              onVideoTap: (vid, {int? part}) =>
                                  c.switchToVideo(vid, part: part, onComplete: _scrollToTop),
                              onPartTap: (part) => c.changePart(part, onComplete: _scrollToTop),
                            ),
                    ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: CommentPreviewCard(
                      vid: c.currentVid,
                      totalComments: c.totalComments,
                      latestComment: c.latestComment,
                      onSeek: (seconds) {
                        c.playerController?.seek(Duration(seconds: seconds));
                      },
                      onCommentPosted: c.refreshCommentPreview,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (MediaQuery.of(context).size.width <= 900)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _isPGCMode
                          ? PgcRecommendList(
                              key: _pgcRecommendKey,
                              vid: c.currentVid,
                              onPgcTap: (item) async {
                                final epId = item.latestEpId;
                                if (epId == null || epId <= 0) return;
                                final vid = await PgcApiService.resolveVidByEpisodeId(epId);
                                if (vid == null || vid <= 0) return;
                                c.switchToVideo(vid, onComplete: _scrollToTop);
                              },
                            )
                          : RecommendList(
                              key: _recommendListKey,
                              vid: c.currentVid,
                              onVideoTap: (vid) => c.switchToVideo(vid, onComplete: _scrollToTop),
                            ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSidebar() {
    final c = _controller;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (!_isPGCMode)
              AuthorCard(
                author: c.videoDetail!.author,
                initialRelationStatus: c.actionStatus!.relationStatus,
                onAvatarTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserSpacePage(userId: c.videoDetail!.author.uid),
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            _isPGCMode
                ? PgcSeasonPanel(
                    key: _pgcSeasonKey,
                    vid: c.currentVid,
                    onEpisodeTap: (vid) => c.switchToVideo(vid, onComplete: _scrollToTop),
                  )
                : CollectionList(
                    key: _collectionListKey,
                    vid: c.currentVid,
                    currentPart: c.currentPart,
                    onVideoTap: (vid, {int? part}) => c.switchToVideo(vid, part: part, onComplete: _scrollToTop),
                    onPartTap: (part) => c.changePart(part, onComplete: _scrollToTop),
                  ),
            const SizedBox(height: 16),
            _isPGCMode
                ? PgcRecommendList(
                    key: _pgcRecommendKey,
                    vid: c.currentVid,
                    onPgcTap: (item) async {
                      final epId = item.latestEpId;
                      if (epId == null || epId <= 0) return;
                      final vid = await PgcApiService.resolveVidByEpisodeId(epId);
                      if (vid == null || vid <= 0) return;
                      c.switchToVideo(vid, onComplete: _scrollToTop);
                    },
                  )
                : RecommendList(
                    key: _recommendListKey,
                    vid: c.currentVid,
                    onVideoTap: (vid) => c.switchToVideo(vid, onComplete: _scrollToTop),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildDanmakuInputBar() {
    final colors = context.colors;
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              color: colors.card,
              child: SafeArea(
                top: false,
                child: DanmakuSendBar(
                  controller: _controller.danmakuController,
                  onSendEnd: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border(
            bottom: BorderSide(color: colors.divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.inputBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '发一条弹幕...',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PgcInfoCard extends StatelessWidget {
  final PgcItem item;
  const _PgcInfoCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 90,
              height: 120,
              child: Image.network(item.cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  [
                    if (item.year > 0) '${item.year}',
                    if (item.area.isNotEmpty) item.area,
                    if (item.currentEpisodes > 0) '全${item.currentEpisodes}话',
                  ].join(' · '),
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                if (item.rating > 0) ...[
                  const SizedBox(height: 6),
                  Text('评分 ${item.rating}', style: TextStyle(color: colors.accentColor, fontSize: 13)),
                ],
                const SizedBox(height: 6),
                Text(
                  item.desc.isNotEmpty ? item.desc : '暂无简介',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
