import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';

/// 跨平台屏幕常亮管理器
///
/// Android: 使用 FLAG_KEEP_SCREEN_ON
/// iOS: 使用 UIApplication.shared.isIdleTimerDisabled
/// Windows: 使用 SetThreadExecutionState
/// macOS: 使用 IOKit (IOPMAssertion)
class WakelockManager {
  static const MethodChannel _channel = MethodChannel('com.alnitak/wakelock');
  static final LoggerService _logger = LoggerService.instance;
  static bool _isEnabled = false;

  /// 启用屏幕常亮
  static Future<void> enable() async {
    if (_isEnabled) return;

    try {
      if (kIsWeb) {
        // Web 平台使用 NoSleep.js 或 Screen Wake Lock API
        _logger.logDebug('[Wakelock] Web 平台暂不支持 wakelock', tag: 'Wakelock');
        return;
      }

      if (Platform.isAndroid) {
        await _channel.invokeMethod('enableAndroid');
        _logger.logDebug('[Wakelock] Android Wakelock 已启用', tag: 'Wakelock');
      } else if (Platform.isIOS) {
        await _channel.invokeMethod('enableIOS');
        _logger.logDebug('[Wakelock] iOS Wakelock 已启用', tag: 'Wakelock');
      } else if (Platform.isWindows) {
        await _channel.invokeMethod('enableWindows');
        _logger.logDebug('[Wakelock] Windows Wakelock 已启用', tag: 'Wakelock');
      } else if (Platform.isMacOS) {
        await _channel.invokeMethod('enableMacOS');
        _logger.logDebug('[Wakelock] macOS Wakelock 已启用', tag: 'Wakelock');
      } else if (Platform.isLinux) {
        await _channel.invokeMethod('enableLinux');
        _logger.logDebug('[Wakelock] Linux Wakelock 已启用', tag: 'Wakelock');
      }

      _isEnabled = true;
    } on PlatformException catch (e) {
      await _logger.logError(message: '[Wakelock] Wakelock 启用失败: ${e.message}');
    } catch (e) {
      await _logger.logError(message: '[Wakelock] Wakelock 启用异常: $e');
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
        _logger.logDebug('[Wakelock] Android Wakelock 已禁用');
      } else if (Platform.isIOS) {
        await _channel.invokeMethod('disableIOS');
        _logger.logDebug('[Wakelock] iOS Wakelock 已禁用');
      } else if (Platform.isWindows) {
        await _channel.invokeMethod('disableWindows');
        _logger.logDebug('[Wakelock] Windows Wakelock 已禁用');
      } else if (Platform.isMacOS) {
        await _channel.invokeMethod('disableMacOS');
        _logger.logDebug('[Wakelock] macOS Wakelock 已禁用');
      } else if (Platform.isLinux) {
        await _channel.invokeMethod('disableLinux');
        _logger.logDebug('[Wakelock] Linux Wakelock 已禁用');
      }

      _isEnabled = false;
    } on PlatformException catch (e) {
      await _logger.logError(message: '[Wakelock] Wakelock 禁用失败: ${e.message}');
    } catch (e) {
      await _logger.logError(message: '[Wakelock] Wakelock 禁用异常: $e');
    }
  }

  /// 获取当前状态
  static bool get isEnabled => _isEnabled;
}
