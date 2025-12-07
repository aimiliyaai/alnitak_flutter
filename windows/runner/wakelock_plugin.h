#ifndef FLUTTER_PLUGIN_WAKELOCK_PLUGIN_H_
#define FLUTTER_PLUGIN_WAKELOCK_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace wakelock_plugin {

/**
 * Windows 原生 Wakelock 实现
 *
 * 使用 SetThreadExecutionState API
 * ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED
 *
 * 这是 Windows 官方推荐的防止系统休眠和保持显示器开启的方式
 */
class WakelockPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  WakelockPlugin();

  virtual ~WakelockPlugin();

  // Disallow copy and assign.
  WakelockPlugin(const WakelockPlugin&) = delete;
  WakelockPlugin& operator=(const WakelockPlugin&) = delete;

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // 启用 wakelock
  void EnableWakelock();

  // 禁用 wakelock
  void DisableWakelock();
};

}  // namespace wakelock_plugin

#endif  // FLUTTER_PLUGIN_WAKELOCK_PLUGIN_H_
