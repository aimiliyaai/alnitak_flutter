import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart';
import 'profile_page.dart';
import '../services/hls_service.dart';
import '../services/logger_service.dart';
import '../widgets/cached_image_widget.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final LoggerService _logger = LoggerService.instance;
  int _currentIndex = 0;
  final HlsService _hlsService = HlsService();
  bool _hasCleaned = false; // 是否已清理过缓存
  bool _clearCacheOnExit = false; // 退出即清设置
  DateTime? _lastBackPressTime;

  static const String _clearCacheOnExitKey = 'clear_cache_on_exit';

  final List<Widget> _pages = [
    const HomePage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 加载退出即清设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _clearCacheOnExit = prefs.getBool(_clearCacheOnExitKey) ?? false;
  }

  /// 处理返回键按下事件
  /// 第一次返回：根据设置决定是否清理缓存并提示
  /// 第二次返回（2秒内）：退出应用
  Future<void> _onWillPop() async {
    final now = DateTime.now();

    // 检查是否在2秒内再次按返回
    if (_lastBackPressTime != null &&
        now.difference(_lastBackPressTime!) <= const Duration(seconds: 2)) {
      // 2秒内再次按返回，直接退出应用（不返回，直接终止进程）
      _exitApp();
      return;
    }

    // 第一次按返回或超过2秒后再按
    _lastBackPressTime = now;

    // 如果开启了"退出即清"且还没清理过缓存，执行清理
    if (_clearCacheOnExit && !_hasCleaned) {
      _hasCleaned = true;

      // 显示清理提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在清理缓存...再按一次退出'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // 异步执行缓存清理（不阻塞）
      _cleanupCache();
    } else {
      // 未开启退出即清或已清理过，只显示退出提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('再按一次退出应用'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 仅清理缓存（不退出）
  Future<void> _cleanupCache() async {
    try {
      // 1. 清理 Flutter 内存中的图片缓存（同步操作，立即执行）
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 2. 清理图片磁盘缓存（cached_network_image 使用的缓存）
      await DefaultCacheManager().emptyCache();
      // 【新增】清理自定义智能缓存管理器
      await SmartCacheManager().emptyCache();

      // 3. 清理所有播放器缓存（HLS缓存目录 + MPV缓存）
      // 【修复】使用 clearAllCache 替代 cleanupAllTempCache，确保完整清理
      await _hlsService.clearAllCache();

      // 4. 清理临时目录
      try {
        final tempDir = await getTemporaryDirectory();
        await for (final entity in tempDir.list(followLinks: false)) {
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
      } catch (e) {
        _logger.logWarning('[MainPage] 清理临时目录失败: $e', tag: 'MainPage');
      }

      // 5. 清理日志文件
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final logFile = File('${docDir.path}/error_log.txt');
        if (await logFile.exists()) {
          await logFile.delete();
        }
        final logsDir = Directory('${docDir.path}/logs');
        if (await logsDir.exists()) {
          await logsDir.delete(recursive: true);
        }
      } catch (e) {
        _logger.logWarning('[MainPage] 清理日志文件失败: $e', tag: 'MainPage');
      }

      _logger.logDebug('[MainPage] 缓存清理完成', tag: 'MainPage');
    } catch (e) {
      _logger.logWarning('[MainPage] 缓存清理异常: $e', tag: 'MainPage');
    }
  }

  /// 退出应用
  Future<void> _exitApp() async {
    _logger.logDebug('[MainPage] 退出应用', tag: 'MainPage');
    // 彻底退出应用（使用 exit(0) 确保进程终止）
    if (Platform.isAndroid || Platform.isIOS) {
      exit(0);
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 直接调用处理函数，退出逻辑在内部处理
        _onWillPop();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
