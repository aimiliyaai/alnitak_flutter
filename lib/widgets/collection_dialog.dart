import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/collection_models.dart';
import '../services/collection_api_service.dart';

/// 收藏到收藏夹弹窗
class CollectionDialog extends StatefulWidget {
  final int vid;
  final VoidCallback? onCollected;

  const CollectionDialog({
    super.key,
    required this.vid,
    this.onCollected,
  });

  /// 显示收藏弹窗
  static Future<bool?> show(BuildContext context, int vid, {VoidCallback? onCollected}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CollectionDialog(vid: vid, onCollected: onCollected),
    );
  }

  @override
  State<CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<CollectionDialog> {
  final CollectionApiService _apiService = CollectionApiService();
  final TextEditingController _newNameController = TextEditingController();

  List<CollectionItem> _collections = [];
  List<int> _originalCheckedIds = []; // 原始选中的收藏夹ID
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showCreateInput = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _newNameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // 并行加载收藏夹列表和视频的收藏信息
    final results = await Future.wait([
      _apiService.getCollectionList(),
      _apiService.getVideoCollectInfo(widget.vid),
    ]);

    if (mounted) {
      final collections = results[0] as List<CollectionItem>;
      final checkedIds = results[1] as List<int>;

      // 标记已收藏的收藏夹
      for (var collection in collections) {
        collection.checked = checkedIds.contains(collection.id);
      }

      setState(() {
        _collections = collections;
        _originalCheckedIds = List.from(checkedIds);
        _isLoading = false;
      });
    }
  }

  /// 创建新收藏夹
  Future<void> _createCollection() async {
    final name = _newNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入收藏夹名称')),
      );
      return;
    }

    if (name.length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称不能超过20个字符')),
      );
      return;
    }

    final id = await _apiService.createCollection(name);
    if (!mounted) return;

    if (id != null) {
      _newNameController.clear();
      setState(() => _showCreateInput = false);
      // 重新加载列表
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建失败')),
      );
    }
  }

  /// 保存收藏更改
  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    // 计算新增和移除的收藏夹
    final currentCheckedIds = _collections
        .where((c) => c.checked)
        .map((c) => c.id)
        .toList();

    final addList = currentCheckedIds
        .where((id) => !_originalCheckedIds.contains(id))
        .toList();
    final cancelList = _originalCheckedIds
        .where((id) => !currentCheckedIds.contains(id))
        .toList();

    // 如果没有变化，直接关闭
    if (addList.isEmpty && cancelList.isEmpty) {
      Navigator.pop(context, false);
      return;
    }

    final success = await _apiService.collectVideo(
      CollectVideoParams(
        vid: widget.vid,
        addList: addList,
        cancelList: cancelList,
      ),
    );

    if (mounted) {
      setState(() => _isSaving = false);

      if (success) {
        widget.onCollected?.call();
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4.h,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '添加到收藏夹',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _isSaving ? null : _saveChanges,
                  child: _isSaving
                      ? SizedBox(
width: 20.w,
                  height: 20.h,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('完成'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 收藏夹列表
          Flexible(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      shrinkWrap: true,
      children: [
        // 新建收藏夹
        if (_showCreateInput)
          _buildCreateInput()
        else
          _buildCreateButton(),

        const Divider(height: 1),

        // 收藏夹列表
        if (_collections.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                '暂无收藏夹，点击上方创建',
                style: TextStyle(color: Colors.grey[500]),
              ),
            ),
          )
        else
          ...List.generate(_collections.length, (index) {
            return _buildCollectionItem(_collections[index]);
          }),

        // 底部安全区域
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ],
    );
  }

  Widget _buildCreateButton() {
    return InkWell(
      onTap: () => setState(() => _showCreateInput = true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add, color: Colors.blue),
            ),
            const SizedBox(width: 14),
            Text(
              '新建收藏夹',
              style: TextStyle(
                fontSize: 15.sp,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateInput() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _newNameController,
              autofocus: true,
              maxLength: 20,
              decoration: InputDecoration(
                hintText: '输入收藏夹名称',
                border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8.r),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12.w,
                  vertical: 10.h,
                ),
                counterText: '',
              ),
              onSubmitted: (_) => _createCollection(),
            ),
          ),
          SizedBox(width: 12.w),
          TextButton(
            onPressed: () {
              _newNameController.clear();
              setState(() => _showCreateInput = false);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: _createCollection,
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionItem(CollectionItem collection) {
    return InkWell(
      onTap: () {
        setState(() {
          collection.checked = !collection.checked;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 封面
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.folder,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(width: 14),
            // 名称
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.name,
                    style: TextStyle(
fontSize: 15.sp,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (collection.desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      collection.desc,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey[500],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // 选中状态
            Checkbox(
              value: collection.checked,
              onChanged: (value) {
                setState(() {
                  collection.checked = value ?? false;
                });
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4.r),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
