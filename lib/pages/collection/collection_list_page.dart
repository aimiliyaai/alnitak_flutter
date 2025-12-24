import 'package:flutter/material.dart';
import '../../models/collection_models.dart';
import '../../services/collection_api_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/time_utils.dart';
import '../../utils/login_guard.dart';
import '../../widgets/cached_image_widget.dart';
import '../../theme/theme_extensions.dart';
import 'collection_detail_page.dart';

/// 收藏夹列表页面
class CollectionListPage extends StatefulWidget {
  const CollectionListPage({super.key});

  @override
  State<CollectionListPage> createState() => _CollectionListPageState();
}

class _CollectionListPageState extends State<CollectionListPage> {
  final CollectionApiService _apiService = CollectionApiService();

  List<CollectionItem> _collections = [];
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _isCheckingLogin = true;

  @override
  void initState() {
    super.initState();
    _checkLoginAndLoad();
  }

  Future<void> _checkLoginAndLoad() async {
    final loggedIn = await LoginGuard.isLoggedIn();
    if (mounted) {
      setState(() {
        _isLoggedIn = loggedIn;
        _isCheckingLogin = false;
      });
      if (loggedIn) {
        _loadData();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final data = await _apiService.getCollectionList();

    if (mounted) {
      setState(() {
        _collections = data;
        _isLoading = false;
      });
    }
  }

  /// 创建收藏夹
  Future<void> _createCollection() async {
    final name = await _showCreateDialog();
    if (name == null || name.isEmpty) return;

    final id = await _apiService.createCollection(name);
    if (!mounted) return;

    if (id != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建成功')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建失败')),
      );
    }
  }

  Future<String?> _showCreateDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建收藏夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: '请输入收藏夹名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              Navigator.pop(context, name);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  /// 编辑收藏夹
  Future<void> _editCollection(CollectionItem collection) async {
    final result = await _showEditDialog(collection);
    if (result == null) return;

    final success = await _apiService.editCollection(
      id: collection.id,
      name: result['name'],
      desc: result['desc'],
      open: result['open'],
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('修改成功')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('修改失败')),
      );
    }
  }

  Future<Map<String, dynamic>?> _showEditDialog(CollectionItem collection) async {
    final nameController = TextEditingController(text: collection.name);
    final descController = TextEditingController(text: collection.desc);
    bool isOpen = collection.open;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑收藏夹'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  maxLength: 150,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '简介',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('公开'),
                  subtitle: const Text('其他用户可以看到此收藏夹'),
                  value: isOpen,
                  onChanged: (value) {
                    setDialogState(() => isOpen = value);
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, {
                  'name': nameController.text.trim(),
                  'desc': descController.text.trim(),
                  'open': isOpen,
                });
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 删除收藏夹
  Future<void> _deleteCollection(CollectionItem collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除收藏夹"${collection.name}"吗？\n删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _apiService.deleteCollection(collection.id);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除成功')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败')),
      );
    }
  }

  void _navigateToDetail(CollectionItem collection) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CollectionDetailPage(
          collectionId: collection.id,
          collectionName: collection.name,
        ),
      ),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_isCheckingLogin) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('收藏夹'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isLoggedIn) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('收藏夹'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_outlined, size: 64, color: colors.iconSecondary),
              const SizedBox(height: 16),
              Text(
                '登录后查看收藏',
                style: TextStyle(fontSize: 16, color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final result = await LoginGuard.navigateToLogin(context);
                  if (result == true) {
                    _checkLoginAndLoad();
                  }
                },
                child: const Text('去登录'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('收藏夹'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createCollection,
            tooltip: '新建收藏夹',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_collections.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_outlined, size: 64, color: colors.iconSecondary),
            const SizedBox(height: 16),
            Text(
              '暂无收藏夹',
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _createCollection,
              icon: const Icon(Icons.add),
              label: const Text('创建收藏夹'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _collections.length,
        itemBuilder: (context, index) {
          return _buildCollectionItem(_collections[index]);
        },
      ),
    );
  }

  Widget _buildCollectionItem(CollectionItem collection) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _navigateToDetail(collection),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 收藏夹封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: collection.cover.isNotEmpty
                    ? CachedImage(
                        imageUrl: ImageUtils.getFullImageUrl(collection.cover),
                        width: 80,
                        height: 60,
                        fit: BoxFit.cover,
                        cacheKey: 'collection_cover_${collection.id}',
                      )
                    : Container(
                        width: 80,
                        height: 60,
                        color: colors.surfaceVariant,
                        child: Icon(
                          Icons.folder,
                          size: 30,
                          color: colors.iconSecondary,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              // 收藏夹信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            collection.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 公开/私密标签
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: collection.open
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            collection.open ? '公开' : '私密',
                            style: TextStyle(
                              fontSize: 11,
                              color: collection.open ? Colors.green : Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (collection.desc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        collection.desc,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '创建于 ${TimeUtils.formatDate(collection.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              // 操作按钮
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: colors.iconSecondary),
                onSelected: (value) {
                  if (value == 'edit') {
                    _editCollection(collection);
                  } else if (value == 'delete') {
                    _deleteCollection(collection);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('编辑'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('删除', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
