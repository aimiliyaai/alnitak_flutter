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
import '../services/theme_service.dart';
import '../controllers/video_player_controller.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../widgets/cached_image_widget.dart';
import '../config/api_config.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _authService = AuthService();
  final HlsService _hlsService = HlsService();
  final ThemeService _themeService = ThemeService();

  bool _backgroundPlayEnabled = false;
  bool _httpsEnabled = false;
  bool _isLoggedIn = false;
  PackageInfo? _packageInfo;

  // 缓存相关
  String _cacheSize = '计算中...';
  bool _isCleaningCache = false;
  int _maxCacheSizeMB = 500; // 默认最大缓存 500MB
  bool _clearCacheOnExit = false; // 退出即清选项
  static const String _maxCacheSizeKey = 'max_cache_size_mb';
  static const String _clearCacheOnExitKey = 'clear_cache_on_exit';

  // 解码模式：'no' = 软解码，'auto-copy' = 硬解码
  String _decodeMode = 'no';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPackageInfo();
    _checkLoginStatus();
    _calculateCacheSize();
    _loadMaxCacheSetting();
    _loadDecodeModeSetting();
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
      _httpsEnabled = ApiConfig.httpsEnabled;
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

  /// 保存 HTTPS 设置
  Future<void> _saveHttpsSetting(bool value) async {
    await ApiConfig.setHttpsEnabled(value);
    setState(() {
      _httpsEnabled = value;
    });
    // 提示用户需要重启应用
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('HTTPS 设置已更改，重启应用后生效'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 加载最大缓存设置
  Future<void> _loadMaxCacheSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _maxCacheSizeMB = prefs.getInt(_maxCacheSizeKey) ?? 500;
        _clearCacheOnExit = prefs.getBool(_clearCacheOnExitKey) ?? false;
      });
    }
  }

  /// 保存退出即清设置
  Future<void> _saveClearCacheOnExitSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_clearCacheOnExitKey, value);
    setState(() {
      _clearCacheOnExit = value;
    });
  }

  /// 加载解码模式设置
  Future<void> _loadDecodeModeSetting() async {
    final mode = await VideoPlayerController.getDecodeMode();
    if (mounted) {
      setState(() {
        _decodeMode = mode;
      });
    }
  }

  /// 保存解码模式设置
  Future<void> _saveDecodeModeSetting(String mode) async {
    await VideoPlayerController.setDecodeMode(mode);
    setState(() {
      _decodeMode = mode;
    });
    // 提示用户需要重新打开视频
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('解码模式已更改，重新打开视频后生效'),
          duration: Duration(seconds: 2),
        ),
      );
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
                  ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
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

  /// 显示主题选择对话框
  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('外观模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppThemeMode.values.map((mode) {
            final isSelected = mode == _themeService.themeMode;
            return ListTile(
              leading: Icon(
                _themeService.getThemeModeIcon(mode),
                color: isSelected ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(_themeService.getThemeModeName(mode)),
              trailing: isSelected
                  ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _themeService.setThemeMode(mode);
                setState(() {}); // 刷新UI显示当前选项
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

  /// 显示解码模式选择对话框
  void _showDecodeModeDialog() {
    // 解码模式选项：软解码(no)、硬解码(auto-copy)
    final options = [
      {'value': 'no', 'label': '软解码', 'desc': 'CPU解码，兼容性好（推荐）'},
      {'value': 'auto-copy', 'label': '硬解码', 'desc': 'GPU加速，性能更好'},
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解码模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            final isSelected = option['value'] == _decodeMode;
            return ListTile(
              title: Text(option['label']!),
              subtitle: Text(
                option['desc']!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              trailing: isSelected
                  ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                Navigator.pop(context);
                if (option['value'] != _decodeMode) {
                  _saveDecodeModeSetting(option['value']!);
                }
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

  /// 判断当前是否为深色模式
  bool get _isDarkMode => _themeService.isDarkMode(context);

  /// 获取当前主题的颜色
  dynamic get _colors => _isDarkMode ? AppColors.dark : AppColors.light;

  @override
  Widget build(BuildContext context) {
    final colors = _colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),

          // 外观设置
          _buildSectionHeader('外观设置', colors),
          _buildSettingsGroup([
            _buildTappableTile(
              icon: _themeService.getThemeModeIcon(_themeService.themeMode),
              title: '外观模式',
              value: _themeService.getThemeModeName(_themeService.themeMode),
              onTap: _showThemeDialog,
              colors: colors,
            ),
          ], colors),

          const SizedBox(height: 12),

          // 偏好设置
          _buildSectionHeader('偏好设置', colors),
          _buildSettingsGroup([
            _buildSwitchTile(
              icon: Icons.play_circle_outline,
              title: '后台播放',
              subtitle: '退到后台时继续播放视频',
              value: _backgroundPlayEnabled,
              onChanged: _saveBackgroundPlaySetting,
              colors: colors,
            ),
            _buildDivider(colors),
            _buildTappableTile(
              icon: Icons.memory_outlined,
              title: '解码模式',
              value: VideoPlayerController.getDecodeModeDisplayName(_decodeMode),
              onTap: _showDecodeModeDialog,
              colors: colors,
            ),
          ], colors),

          const SizedBox(height: 12),

          // 网络设置
          _buildSectionHeader('网络设置', colors),
          _buildSettingsGroup([
            _buildSwitchTile(
              icon: Icons.lock_outline,
              title: '启用 HTTPS',
              subtitle: '使用加密连接访问服务器（重启后生效）',
              value: _httpsEnabled,
              onChanged: _saveHttpsSetting,
              colors: colors,
            ),
          ], colors),

          const SizedBox(height: 12),

          // 存储管理
          _buildSectionHeader('存储管理', colors),
          _buildSettingsGroup([
            _buildTappableTile(
              icon: Icons.cleaning_services_outlined,
              title: '清理缓存',
              value: _isCleaningCache ? '清理中...' : _cacheSize,
              onTap: _isCleaningCache ? () {} : _clearAllCache,
              colors: colors,
            ),
            _buildDivider(colors),
            _buildTappableTile(
              icon: Icons.storage_outlined,
              title: '最大缓存',
              value: _maxCacheSizeMB >= 1000
                  ? '${_maxCacheSizeMB ~/ 1000} GB'
                  : '$_maxCacheSizeMB MB',
              onTap: _showMaxCacheDialog,
              colors: colors,
            ),
            _buildDivider(colors),
            _buildSwitchTile(
              icon: Icons.exit_to_app_outlined,
              title: '退出即清',
              subtitle: '退出应用时自动清理缓存',
              value: _clearCacheOnExit,
              onChanged: _saveClearCacheOnExitSetting,
              colors: colors,
            ),
          ], colors),

          const SizedBox(height: 12),

          // 账号安全（仅登录后显示）
          if (_isLoggedIn) ...[
            _buildSectionHeader('账号安全', colors),
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
                colors: colors,
              ),
            ], colors),
            const SizedBox(height: 12),
          ],

          // 关于
          _buildSectionHeader('关于', colors),
          _buildSettingsGroup([
            _buildInfoTile(
              icon: Icons.info_outline,
              title: 'App 版本',
              value: _packageInfo?.version ?? '加载中...',
              colors: colors,
            ),
            _buildDivider(colors),
            _buildInfoTile(
              icon: Icons.calendar_today_outlined,
              title: '构建日期',
              value: _packageInfo?.buildNumber ?? '加载中...',
              colors: colors,
            ),
            _buildDivider(colors),
            _buildTappableTile(
              icon: Icons.email_outlined,
              title: '开发者邮箱',
              value: 'ayypd@foxmail.com',
              onTap: () => _launchUrl('mailto:ayypd@foxmail.com'),
              colors: colors,
            ),
            _buildDivider(colors),
            _buildTappableTile(
              icon: Icons.code_outlined,
              title: '开源地址',
              value: 'GitHub',
              onTap: () => _launchUrl('https://github.com/your-repo/alnitak_flutter'),
              colors: colors,
            ),
          ], colors),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 构建分组标题
  Widget _buildSectionHeader(String title, dynamic colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          color: colors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 构建设置组
  Widget _buildSettingsGroup(List<Widget> children, dynamic colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.card,
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
    required dynamic colors,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 24, color: colors.iconPrimary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
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
    required dynamic colors,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 24, color: colors.iconPrimary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
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
    required dynamic colors,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 24, color: colors.iconPrimary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: colors.iconSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建分割线
  Widget _buildDivider(dynamic colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: colors.divider,
      ),
    );
  }
}
