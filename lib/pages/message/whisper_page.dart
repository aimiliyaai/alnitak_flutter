import 'package:flutter/material.dart';
import '../../models/message_models.dart';
import '../../services/message_api_service.dart';
import '../../utils/time_utils.dart';
import '../../utils/image_utils.dart';
import '../../widgets/cached_image_widget.dart';
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final data = await _apiService.getWhisperList();

    if (mounted) {
      setState(() {
        _whispers = data;
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('私信'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_whispers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '暂无私信',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
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
                          backgroundColor: Colors.grey[200],
                          child: const Icon(Icons.person, size: 28, color: Colors.grey),
                        ),
                  // 未读红点
                  if (!whisper.status)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
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
                              fontWeight: whisper.status ? FontWeight.normal : FontWeight.w600,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          TimeUtils.formatTime(whisper.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      whisper.status ? '点击查看消息' : '有新消息',
                      style: TextStyle(
                        fontSize: 13,
                        color: whisper.status ? Colors.grey[500] : Colors.blue[600],
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
                color: Colors.grey[400],
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
