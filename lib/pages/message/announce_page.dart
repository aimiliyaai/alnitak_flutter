import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/message_models.dart';
import '../../services/message_api_service.dart';
import '../../utils/time_utils.dart';

/// 站内公告页面
class AnnouncePage extends StatefulWidget {
  const AnnouncePage({super.key});

  @override
  State<AnnouncePage> createState() => _AnnouncePageState();
}

class _AnnouncePageState extends State<AnnouncePage> {
  final MessageApiService _apiService = MessageApiService();
  final ScrollController _scrollController = ScrollController();

  List<AnnounceMessage> _announces = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _page = 1;
    });

    final data = await _apiService.getAnnounceList(
      page: _page,
      pageSize: _pageSize,
    );

    if (mounted) {
      setState(() {
        _announces = data;
        _isLoading = false;
        _hasMore = data.length >= _pageSize;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    _page++;

    final data = await _apiService.getAnnounceList(
      page: _page,
      pageSize: _pageSize,
    );

    if (mounted) {
      setState(() {
        _announces.addAll(data);
        _isLoadingMore = false;
        _hasMore = data.length >= _pageSize;
      });
    }
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('站内公告'),
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

    if (_announces.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '暂无公告',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _announces.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _announces.length) {
            return _buildLoadingMore();
          }
          return _buildAnnounceItem(_announces[index]);
        },
      ),
    );
  }

  Widget _buildAnnounceItem(AnnounceMessage announce) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: announce.url.isNotEmpty ? () => _openUrl(announce.url) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '公告',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    TimeUtils.formatTime(announce.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                announce.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (announce.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  announce.content,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                ),
              ],
              if (announce.url.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '查看详情',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[600],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: Colors.blue[600],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingMore() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: _isLoadingMore
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const SizedBox.shrink(),
    );
  }
}
