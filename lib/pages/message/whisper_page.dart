import 'package:flutter/material.dart';
import '../../models/message_models.dart';
import '../../services/message_api_service.dart';
import '../../utils/time_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/whisper_read_status.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';
import 'whisper_detail_page.dart';

/// 私信列表页面
class WhisperPage extends StatefulWidget {
  const WhisperPage({super.key});

  @override
  State<WhisperPage> createState() => _WhisperPageState();
}

class _WhisperPageState extends State<WhisperPage> {
  final MessageApiService _apiService = MessageApiService();

  List<WhisperListItem> _whispers = [];
  Map<int, bool> _unreadStatus = {}; // 本地未读状态缓存
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final data = await _apiService.getWhisperList();

    // 检查每个会话的本地已读状态
    final unreadMap = <int, bool>{};
    for (final whisper in data) {
      final hasUnread = await WhisperReadStatus.hasUnread(
        whisper.user.uid,
        whisper.createdAt,
      );
      unreadMap[whisper.user.uid] = hasUnread;
    }

    if (mounted) {
      setState(() {
        _whispers = data;
        _unreadStatus = unreadMap;
        _isLoading = false;
      });
    }
  }

  void _navigateToDetail(WhisperListItem whisper) async {
    print('跳转私信详情页, userId: ${whisper.user.uid}, userName: ${whisper.user.name}');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WhisperDetailPage(
          userId: whisper.user.uid,
          userName: whisper.user.name,
          userAvatar: whisper.user.avatar,
        ),
      ),
    );
    // 返回后刷新列表
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('私信'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_whispers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline, size: 64, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Text(
              '暂无私信',
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _whispers.length,
        itemBuilder: (context, index) {
          return _buildWhisperItem(_whispers[index]);
        },
      ),
    );
  }

  Widget _buildWhisperItem(WhisperListItem whisper) {
    final colors = context.colors;
    // 使用本地已读状态判断是否有未读消息
    final hasUnread = _unreadStatus[whisper.user.uid] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _navigateToDetail(whisper),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 用户头像（带未读标记）
              Stack(
                children: [
                  whisper.user.avatar.isNotEmpty
                      ? CachedCircleAvatar(
                          imageUrl: ImageUtils.getFullImageUrl(whisper.user.avatar),
                          radius: 24,
                          cacheKey: 'user_avatar_${whisper.user.uid}',
                        )
                      : CircleAvatar(
                          radius: 24,
                          backgroundColor: colors.surfaceVariant,
                          child: Icon(Icons.person, size: 28, color: colors.iconSecondary),
                        ),
                  // 未读红点（使用本地状态）
                  if (hasUnread)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.card, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // 用户信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            whisper.user.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          TimeUtils.formatTime(whisper.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasUnread ? '有新消息' : '点击查看消息',
                      style: TextStyle(
                        fontSize: 13,
                        color: hasUnread ? Colors.blue[600] : colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: colors.iconSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
