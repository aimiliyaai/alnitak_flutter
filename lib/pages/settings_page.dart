import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'reset_password_page.dart';
import '../services/auth_service.dart';
import '../services/hls_service.dart';
import '../widgets/cached_image_widget.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _authService = AuthService();
  final HlsService _hlsService = HlsService();

  bool _backgroundPlayEnabled = false;
  bool _isLoggedIn = false;
  PackageInfo? _packageInfo;

  // 缓存相关
  String _cacheSize = '计算中...';
  bool _isCleaningCache = false;
  int _maxCacheSizeMB = 500; // 默认最大缓存 500MB
  static const String _maxCacheSizeKey = 'max_cache_size_mb';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPackageInfo();
    _checkLoginStatus();
    _calculateCacheSize();
    _loadMaxCacheSetting();
  }

  /// 检查登录状态
  Future<void> _checkLoginStatus() async {
    final isLoggedIn = await _authService.isLoggedIn();
    if (mounted) {
      setState(() {
        _isLoggedIn = isLoggedIn;
      });
    }
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backgroundPlayEnabled = prefs.getBool('background_play_enabled') ?? false;
    });
  }

  /// 加载应用信息
  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
  }

  /// 保存后台播放设置
  Future<void> _saveBackgroundPlaySetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_play_enabled', value);
    setState(() {
      _backgroundPlayEnabled = value;
    });
  }

  /// 加载最大缓存设置
  Future<void> _loadMaxCacheSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _maxCacheSizeMB = prefs.getInt(_maxCacheSizeKey) ?? 500;
      });
    }
  }

  /// 保存最大缓存设置
  Future<void> _saveMaxCacheSetting(int sizeMB) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxCacheSizeKey, sizeMB);
    setState(() {
      _maxCacheSizeMB = sizeMB;
    });
    // 检查是否需要自动清理
    await _checkAndAutoCleanCache();
  }

  /// 计算缓存大小
  Future<void> _calculateCacheSize() async {
    try {
      int totalSize = 0;

      // 1. 计算临时目录大小
      final tempDir = await getTemporaryDirectory();
      totalSize += await _getDirectorySize(tempDir);

      // 2. 计算应用缓存目录大小
      try {
        final cacheDir = await getApplicationCacheDirectory();
        totalSize += await _getDirectorySize(cacheDir);
      } catch (e) {
        // 某些平台可能不支持
      }

      if (mounted) {
        setState(() {
          if (totalSize < 1024) {
            _cacheSize = '$totalSize B';
          } else if (totalSize < 1024 * 1024) {
            _cacheSize = '${(totalSize / 1024).toStringAsFixed(1)} KB';
          } else if (totalSize < 1024 * 1024 * 1024) {
            _cacheSize = '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
          } else {
            _cacheSize = '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cacheSize = '计算失败';
        });
      }
    }
  }

  /// 获取目录大小
  Future<int> _getDirectorySize(Directory dir) async {
    int size = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              size += await entity.length();
            } catch (e) {
              // 文件可能正在使用或已删除
            }
          }
        }
      }
    } catch (e) {
      // 目录访问失败
    }
    return size;
  }

  /// 清理所有缓存
  Future<void> _clearAllCache() async {
    if (_isCleaningCache) return;

    setState(() {
      _isCleaningCache = true;
    });

    try {
      // 1. 清理 Flutter 内存中的图片缓存
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 2. 清理图片磁盘缓存（cached_network_image 使用的缓存）
      await DefaultCacheManager().emptyCache();
      // 【新增】清理自定义智能缓存管理器
      await SmartCacheManager().emptyCache();

      // 3. 清理 HLS 和 MPV 缓存
      await _hlsService.clearAllCache();

      // 4. 清理临时目录中的其他缓存文件
      final tempDir = await getTemporaryDirectory();
      await _cleanDirectory(tempDir);

      // 5. 清理应用缓存目录
      try {
        final cacheDir = await getApplicationCacheDirectory();
        await _cleanDirectory(cacheDir);
      } catch (e) {
        // 某些平台可能不支持
      }

      // 6. 【新增】清理日志文件（减少用户数据占用）
      try {
        final docDir = await getApplicationDocumentsDirectory();
        // 清理日志文件
        final logFile = File('${docDir.path}/error_log.txt');
        if (await logFile.exists()) {
          await logFile.delete();
          debugPrint('🗑️ 已删除日志文件');
        }
        // 清理归档日志目录
        final logsDir = Directory('${docDir.path}/logs');
        if (await logsDir.exists()) {
          await logsDir.delete(recursive: true);
          debugPrint('🗑️ 已删除归档日志目录');
        }
      } catch (e) {
        debugPrint('⚠️ 清理日志文件失败: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('缓存清理完成'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // 重新计算缓存大小
      await _calculateCacheSize();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('清理缓存失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCleaningCache = false;
        });
      }
    }
  }

  /// 清理目录中的文件
  Future<void> _cleanDirectory(Directory dir) async {
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (e) {
            // 文件可能正在使用，跳过
          }
        }
      }
    } catch (e) {
      // 目录访问失败
    }
  }

  /// 检查并自动清理缓存（达到设定值时）
  Future<void> _checkAndAutoCleanCache() async {
    try {
      int totalSize = 0;

      final tempDir = await getTemporaryDirectory();
      totalSize += await _getDirectorySize(tempDir);

      try {
        final cacheDir = await getApplicationCacheDirectory();
        totalSize += await _getDirectorySize(cacheDir);
      } catch (e) {
        // 某些平台可能不支持
      }

      final maxSizeBytes = _maxCacheSizeMB * 1024 * 1024;

      if (totalSize > maxSizeBytes) {
        debugPrint('缓存超过限制 (${(totalSize / (1024 * 1024)).toStringAsFixed(1)}MB > ${_maxCacheSizeMB}MB)，自动清理...');
        await _clearAllCache();
      }
    } catch (e) {
      debugPrint('自动清理缓存失败: $e');
    }
  }

  /// 显示最大缓存设置对话框
  void _showMaxCacheDialog() {
    final options = [100, 200, 500, 1000, 2000];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最大缓存大小'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((size) {
            final isSelected = size == _maxCacheSizeMB;
            return ListTile(
              title: Text(size >= 1000 ? '${size ~/ 1000} GB' : '$size MB'),
              trailing: isSelected
                  ? const Icon(Icons.check, color: Colors.blue)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _saveMaxCacheSetting(size);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 打开 URL
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),

          // 偏好设置
          _buildSectionHeader('偏好设置'),
          _buildSettingsGroup([
            _buildSwitchTile(
              icon: Icons.play_circle_outline,
              title: '后台播放',
              subtitle: '退到后台时继续播放视频',
              value: _backgroundPlayEnabled,
              onChanged: _saveBackgroundPlaySetting,
            ),
          ]),

          const SizedBox(height: 12),

          // 存储管理
          _buildSectionHeader('存储管理'),
          _buildSettingsGroup([
            _buildTappableTile(
              icon: Icons.cleaning_services_outlined,
              title: '清理缓存',
              value: _isCleaningCache ? '清理中...' : _cacheSize,
              onTap: _isCleaningCache ? () {} : _clearAllCache,
            ),
            _buildDivider(),
            _buildTappableTile(
              icon: Icons.storage_outlined,
              title: '最大缓存',
              value: _maxCacheSizeMB >= 1000
                  ? '${_maxCacheSizeMB ~/ 1000} GB'
                  : '$_maxCacheSizeMB MB',
              onTap: _showMaxCacheDialog,
            ),
          ]),

          const SizedBox(height: 12),

          // 账号安全（仅登录后显示）
          if (_isLoggedIn) ...[
            _buildSectionHeader('账号安全'),
            _buildSettingsGroup([
              _buildTappableTile(
                icon: Icons.lock_outline,
                title: '修改密码',
                value: '',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ResetPasswordPage()),
                  );
                },
              ),
            ]),
            const SizedBox(height: 12),
          ],

          // 关于
          _buildSectionHeader('关于'),
          _buildSettingsGroup([
            _buildInfoTile(
              icon: Icons.info_outline,
              title: 'App 版本',
              value: _packageInfo?.version ?? '加载中...',
            ),
            _buildDivider(),
            _buildInfoTile(
              icon: Icons.calendar_today_outlined,
              title: '构建日期',
              value: _packageInfo?.buildNumber ?? '加载中...',
            ),
            _buildDivider(),
            _buildTappableTile(
              icon: Icons.email_outlined,
              title: '开发者邮箱',
              value: 'ayypd@foxmail.com',
              onTap: () => _launchUrl('mailto:ayypd@foxmail.com'),
            ),
            _buildDivider(),
            _buildTappableTile(
              icon: Icons.code_outlined,
              title: '开源地址',
              value: 'GitHub',
              onTap: () => _launchUrl('https://github.com/your-repo/alnitak_flutter'),
            ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 构建分组标题
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[600],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 构建设置组
  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  /// 构建开关项
  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 24, color: Colors.grey[700]),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /// 构建信息项
  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 24, color: Colors.grey[700]),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建可点击项
  Widget _buildTappableTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Colors.grey[700]),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue[600],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建分割线
  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey[100],
      ),
    );
  }
}
