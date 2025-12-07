import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 跨平台屏幕常亮管理器
///
/// Android: 使用 FLAG_KEEP_SCREEN_ON
/// iOS: 使用 UIApplication.shared.isIdleTimerDisabled
/// Windows: 使用 SetThreadExecutionState
/// macOS: 使用 IOKit (IOPMAssertion)
class WakelockManager {
  static const MethodChannel _channel = MethodChannel('com.alnitak/wakelock');

  static bool _isEnabled = false;

  /// 启用屏幕常亮
  static Future<void> enable() async {
    if (_isEnabled) return;

    try {
      if (kIsWeb) {
        // Web 平台使用 NoSleep.js 或 Screen Wake Lock API
        debugPrint('🌐 Web 平台暂不支持 wakelock');
        return;
      }

      if (Platform.isAndroid) {
        await _channel.invokeMethod('enableAndroid');
        debugPrint('🤖 [Android] Wakelock 已启用 (FLAG_KEEP_SCREEN_ON)');
      } else if (Platform.isIOS) {
        await _channel.invokeMethod('enableIOS');
        debugPrint('🍎 [iOS] Wakelock 已启用 (isIdleTimerDisabled)');
      } else if (Platform.isWindows) {
        await _channel.invokeMethod('enableWindows');
        debugPrint('🪟 [Windows] Wakelock 已启用 (ES_CONTINUOUS | ES_DISPLAY_REQUIRED)');
      } else if (Platform.isMacOS) {
        await _channel.invokeMethod('enableMacOS');
        debugPrint('🍏 [macOS] Wakelock 已启用 (IOPMAssertion)');
      } else if (Platform.isLinux) {
        await _channel.invokeMethod('enableLinux');
        debugPrint('🐧 [Linux] Wakelock 已启用');
      }

      _isEnabled = true;
    } on PlatformException catch (e) {
      debugPrint('❌ Wakelock 启用失败: ${e.message}');
    } catch (e) {
      debugPrint('❌ Wakelock 启用异常: $e');
    }
  }

  /// 禁用屏幕常亮
  static Future<void> disable() async {
    if (!_isEnabled) return;

    try {
      if (kIsWeb) {
        return;
      }

      if (Platform.isAndroid) {
        await _channel.invokeMethod('disableAndroid');
        debugPrint('🤖 [Android] Wakelock 已禁用');
      } else if (Platform.isIOS) {
        await _channel.invokeMethod('disableIOS');
        debugPrint('🍎 [iOS] Wakelock 已禁用');
      } else if (Platform.isWindows) {
        await _channel.invokeMethod('disableWindows');
        debugPrint('🪟 [Windows] Wakelock 已禁用');
      } else if (Platform.isMacOS) {
        await _channel.invokeMethod('disableMacOS');
        debugPrint('🍏 [macOS] Wakelock 已禁用');
      } else if (Platform.isLinux) {
        await _channel.invokeMethod('disableLinux');
        debugPrint('🐧 [Linux] Wakelock 已禁用');
      }

      _isEnabled = false;
    } on PlatformException catch (e) {
      debugPrint('❌ Wakelock 禁用失败: ${e.message}');
    } catch (e) {
      debugPrint('❌ Wakelock 禁用异常: $e');
    }
  }

  /// 获取当前状态
  static bool get isEnabled => _isEnabled;
}
