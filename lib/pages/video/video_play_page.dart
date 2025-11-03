import 'package:flutter/material.dart';
import '../../models/video_detail.dart';
import '../../services/video_service.dart';
import '../../services/hls_service.dart';
import 'widgets/media_player_widget.dart';
import 'widgets/author_card.dart';
import 'widgets/video_info_card.dart';
import 'widgets/video_action_buttons.dart';
import 'widgets/part_list.dart';
import 'widgets/recommend_list.dart';

/// 视频播放页面
class VideoPlayPage extends StatefulWidget {
  final int vid;
  final int? initialPart;

  const VideoPlayPage({
    super.key,
    required this.vid,
    this.initialPart,
  });

  @override
  State<VideoPlayPage> createState() => _VideoPlayPageState();
}

class _VideoPlayPageState extends State<VideoPlayPage> {
  final VideoService _videoService = VideoService();
  final HlsService _hlsService = HlsService();
  final ScrollController _scrollController = ScrollController();

  // 使用稳定的 GlobalKey 保持播放器状态
  late final GlobalKey _playerKey;

  VideoDetail? _videoDetail;
  VideoStat? _videoStat;
  UserActionStatus? _actionStatus;
  bool _isLoading = true;
  String? _errorMessage;

  late int _currentPart;
  double? _initialProgress; // 改为 double 类型（秒）

  @override
  void initState() {
    super.initState();
    _currentPart = widget.initialPart ?? 1;
    // 为播放器创建稳定的 GlobalKey，使用 vid 和 part 作为标识
    _playerKey = GlobalKey(debugLabel: 'player_${widget.vid}_$_currentPart');
    _loadVideoData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // 清理临时 m3u8 文件
    _hlsService.cleanupTempFiles();
    super.dispose();
  }

  /// 加载视频数据
  Future<void> _loadVideoData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 并发请求多个接口
      final results = await Future.wait([
        _videoService.getVideoDetail(widget.vid),
        _videoService.getVideoStat(widget.vid),
        _videoService.getPlayProgress(widget.vid, _currentPart),
      ]);

      final videoDetail = results[0] as VideoDetail?;
      final videoStat = results[1] as VideoStat?;
      final progress = results[2] as int?; // 进度单位为秒

      if (videoDetail == null) {
        setState(() {
          _errorMessage = '视频不存在或已被删除';
          _isLoading = false;
        });
        return;
      }

      // 获取用户操作状态
      final actionStatus = await _videoService.getUserActionStatus(
        widget.vid,
        videoDetail.author.uid,
      );

      setState(() {
        _videoDetail = videoDetail;
        _videoStat = videoStat ?? VideoStat(like: 0, collect: 0, share: 0);
        _actionStatus = actionStatus ?? UserActionStatus(
          hasLiked: false,
          hasCollected: false,
          relationStatus: 0,
        );
        _initialProgress = progress?.toDouble(); // 转换为 double
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 切换分P
  Future<void> _changePart(int part) async {
    if (_videoDetail == null || part == _currentPart) return;

    // 检查分P是否存在
    if (part < 1 || part > _videoDetail!.resources.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该分集不存在')),
      );
      return;
    }

    // 获取新分P的播放进度
    final progress = await _videoService.getPlayProgress(widget.vid, part);

    setState(() {
      _currentPart = part;
      _initialProgress = progress?.toDouble();
      // 切换分P时更新播放器 key
      _playerKey = GlobalKey(debugLabel: 'player_${widget.vid}_$part');
    });

    // 滚动到顶部
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// 跳转到其他视频
  void _navigateToVideo(int vid) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayPage(vid: vid),
      ),
    );
  }

  /// 播放进度更新回调（每秒触发一次）
  void _onProgressUpdate(Duration position) {
    final seconds = position.inSeconds;
    // 每5秒上报一次播放进度，减少请求频率
    if (seconds % 5 == 0) {
      _videoService.reportPlayProgress(widget.vid, _currentPart, seconds);
    }
  }

  /// 播放结束回调
  void _onVideoEnded() {
    // 上报最终播放进度
    final currentResource = _videoDetail?.resources[_currentPart - 1];
    if (currentResource != null) {
      _videoService.reportPlayProgress(
        widget.vid,
        _currentPart,
        currentResource.duration.toInt(),
      );
    }

    // 检查是否有下一P，并自动播放
    if (_videoDetail != null && _currentPart < _videoDetail!.resources.length) {
      // 延迟2秒后自动播放下一P
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _changePart(_currentPart + 1);
        }
      });
    }
  }

///头部
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // 只在顶部添加安全区域，适配刘海、挖孔、水滴屏
        top: true,
        bottom: false,
        left: false,
        right: false,
        child: _buildBody(),
      ),
    );
  }

  /// 构建页面主体
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadVideoData,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_videoDetail == null) {
      return const Center(
        child: Text('视频加载失败', style: TextStyle(color: Colors.grey)),
      );
    }

    // 获取当前分P的视频URL
    final currentResource = _videoDetail!.resources[_currentPart - 1];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 900;

        if (isWideScreen) {
          // 宽屏布局：左右两栏
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧主内容区
              Expanded(
                flex: 7,
                child: _buildMainContent(currentResource),
              ),

              // 右侧边栏
              SizedBox(
                width: 350,
                child: _buildSidebar(),
              ),
            ],
          );
        } else {
          // 窄屏布局：单栏
          return _buildMainContent(currentResource);
        }
      },
    );
  }

  /// 构建主内容区
  Widget _buildMainContent(VideoResource currentResource) {
    // 计算播放器高度（16:9 比例）
    final screenWidth = MediaQuery.of(context).size.width;
    final playerHeight = screenWidth * 9 / 16;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 固定播放器区域
        SliverAppBar(
          pinned: true,
          expandedHeight: playerHeight,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.black,
          flexibleSpace: FlexibleSpaceBar(
            background: MediaPlayerWidget(
              key: _playerKey,
              resourceId: currentResource.id,
              initialPosition: _initialProgress,
              onVideoEnd: _onVideoEnded,
              onProgressUpdate: _onProgressUpdate,
            ),
          ),
        ),

        // 可滚动内容区域
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 视频标题和信息
                VideoInfoCard(
                  videoDetail: _videoDetail!,
                  videoStat: _videoStat!,
                  currentPart: _currentPart,
                ),
                const SizedBox(height: 16),

                // 操作按钮
                VideoActionButtons(
                  vid: widget.vid,
                  initialStat: _videoStat!,
                  initialHasLiked: _actionStatus!.hasLiked,
                  initialHasCollected: _actionStatus!.hasCollected,
                ),
                const SizedBox(height: 16),

                // 作者信息
                AuthorCard(
                  author: _videoDetail!.author,
                  initialRelationStatus: _actionStatus!.relationStatus,
                  onAvatarTap: () {
                    // TODO: 跳转到用户主页
                  },
                ),
                const SizedBox(height: 16),

                // 分P列表（手机端）
                if (MediaQuery.of(context).size.width <= 900)
                  PartList(
                    resources: _videoDetail!.resources,
                    currentPart: _currentPart,
                    onPartChange: _changePart,
                  ),

                const SizedBox(height: 16),

                // 推荐视频（手机端）
                if (MediaQuery.of(context).size.width <= 900)
                  RecommendList(
                    vid: widget.vid,
                    onVideoTap: _navigateToVideo,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建侧边栏（宽屏）
  Widget _buildSidebar() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 作者信息
            AuthorCard(
              author: _videoDetail!.author,
              initialRelationStatus: _actionStatus!.relationStatus,
              onAvatarTap: () {
                // TODO: 跳转到用户主页
              },
            ),
            const SizedBox(height: 16),

            // 分P列表
            if (_videoDetail!.resources.length > 1)
              PartList(
                resources: _videoDetail!.resources,
                currentPart: _currentPart,
                onPartChange: _changePart,
              ),

            const SizedBox(height: 16),

            // 推荐视频
            RecommendList(
              vid: widget.vid,
              onVideoTap: _navigateToVideo,
            ),
          ],
        ),
      ),
    );
  }
}
