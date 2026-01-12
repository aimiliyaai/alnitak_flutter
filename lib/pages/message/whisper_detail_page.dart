import 'package:flutter/material.dart';
import '../../models/message_models.dart';
import '../../services/message_api_service.dart';
import '../../services/user_service.dart';
import '../../utils/time_utils.dart';
import '../../utils/image_utils.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';

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
  final UserService _userService = UserService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<WhisperDetail> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String _myAvatar = '';
  int _myUid = 0; // 【新增】当前用户ID，用于头像缓存key

  @override
  void initState() {
    super.initState();
    _loadMyInfo();
    _loadMessages();
  }

  Future<void> _loadMyInfo() async {
    final userInfo = await _userService.getUserInfo();
    if (mounted && userInfo != null) {
      setState(() {
        _myAvatar = userInfo.userInfo.avatar;
        _myUid = userInfo.userInfo.uid; // 【新增】保存用户ID
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({int retryCount = 0}) async {
    setState(() => _isLoading = true);

    print('正在加载私信详情, userId(fid): ${widget.userId}');

    final data = await _apiService.getWhisperDetails(
      fid: widget.userId,
      pageSize: 20,
    );

    print('私信详情加载完成, 消息数量: ${data.length}');

    // 如果返回空且是首次请求，可能是速率限制，稍后重试
    if (data.isEmpty && retryCount < 2) {
      print('私信详情为空，${retryCount + 1}秒后重试...');
      await Future.delayed(Duration(seconds: retryCount + 1));
      if (mounted) {
        _loadMessages(retryCount: retryCount + 1);
      }
      return;
    }

    if (mounted) {
      setState(() {
        // API返回的是按时间升序（旧的在前），直接使用即可，最新的在下面
        _messages = data;
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
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
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
                    backgroundColor: colors.surfaceVariant,
                    child: Icon(Icons.person, size: 18, color: colors.iconSecondary),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.userName,
                style: TextStyle(fontSize: 16, color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: colors.card,
        foregroundColor: colors.textPrimary,
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
    final colors = context.colors;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Text(
              '暂无消息记录',
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '发送第一条消息吧',
              style: TextStyle(fontSize: 14, color: colors.textTertiary),
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
    final colors = context.colors;
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
                    backgroundColor: colors.surfaceVariant,
                    child: Icon(Icons.person, size: 20, color: colors.iconSecondary),
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
                    color: isMe ? colors.accentColor : colors.card,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 15,
                      color: isMe ? Colors.white : colors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  TimeUtils.formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 10),
            _myAvatar.isNotEmpty
                ? CachedCircleAvatar(
                    imageUrl: ImageUtils.getFullImageUrl(_myAvatar),
                    radius: 18,
                    cacheKey: 'user_avatar_$_myUid', // 【修复】使用用户ID作为缓存key，避免切换账号后显示旧头像
                  )
                : CircleAvatar(
                    radius: 18,
                    backgroundColor: colors.accentColor.withValues(alpha: 0.2),
                    child: Icon(Icons.person, size: 20, color: colors.accentColor),
                  ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: colors.card,
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
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
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: '输入消息...',
                hintStyle: TextStyle(color: colors.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colors.inputBackground,
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
                backgroundColor: colors.accentColor,
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
