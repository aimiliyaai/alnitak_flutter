import 'package:flutter/material.dart';
import '../../models/message_models.dart';
import '../../services/message_api_service.dart';
import '../../utils/time_utils.dart';
import '../../utils/image_utils.dart';
import '../../widgets/cached_image_widget.dart';

/// 私信详情页面
class WhisperDetailPage extends StatefulWidget {
  final int userId;
  final String userName;
  final String userAvatar;

  const WhisperDetailPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userAvatar,
  });

  @override
  State<WhisperDetailPage> createState() => _WhisperDetailPageState();
}

class _WhisperDetailPageState extends State<WhisperDetailPage> {
  final MessageApiService _apiService = MessageApiService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<WhisperDetail> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    final data = await _apiService.getWhisperDetails(
      fid: widget.userId,
      pageSize: 50,
    );

    if (mounted) {
      setState(() {
        _messages = data.reversed.toList(); // 倒序显示，最新的在下面
        _isLoading = false;
      });

      // 滚动到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final content = _inputController.text.trim();
    if (content.isEmpty || _isSending) return;

    if (content.length > 255) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('消息内容不能超过255字')),
      );
      return;
    }

    setState(() => _isSending = true);

    final success = await _apiService.sendWhisper(
      fid: widget.userId,
      content: content,
    );

    if (mounted) {
      if (success) {
        _inputController.clear();
        _loadMessages(); // 刷新消息列表
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('发送失败，请重试')),
        );
      }
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Row(
          children: [
            widget.userAvatar.isNotEmpty
                ? CachedCircleAvatar(
                    imageUrl: ImageUtils.getFullImageUrl(widget.userAvatar),
                    radius: 16,
                    cacheKey: 'user_avatar_${widget.userId}',
                  )
                : CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey[200],
                    child: const Icon(Icons.person, size: 18, color: Colors.grey),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.userName,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: _buildMessageList(),
          ),
          // 输入框
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '暂无消息记录',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            Text(
              '发送第一条消息吧',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.fromId != widget.userId;
        return _buildMessageBubble(message, isMe);
      },
    );
  }

  Widget _buildMessageBubble(WhisperDetail message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            widget.userAvatar.isNotEmpty
                ? CachedCircleAvatar(
                    imageUrl: ImageUtils.getFullImageUrl(widget.userAvatar),
                    radius: 18,
                    cacheKey: 'user_avatar_${widget.userId}',
                  )
                : CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey[200],
                    child: const Icon(Icons.person, size: 20, color: Colors.grey),
                  ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.65,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.blue[500] : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 15,
                      color: isMe ? Colors.white : Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  TimeUtils.formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blue[100],
              child: Icon(Icons.person, size: 20, color: Colors.blue[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _focusNode,
              maxLines: null,
              maxLength: 255,
              decoration: InputDecoration(
                hintText: '输入消息...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                counterText: '',
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSending ? null : _sendMessage,
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                backgroundColor: Colors.blue[500],
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send, size: 22, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
