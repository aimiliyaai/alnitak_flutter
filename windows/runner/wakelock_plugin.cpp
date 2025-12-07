#include "wakelock_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <windows.h>

namespace wakelock_plugin {

// 定义执行状态标志
// ES_CONTINUOUS: 告诉系统该设置持续有效直到下次调用且使用 ES_CONTINUOUS
// ES_DISPLAY_REQUIRED: 强制显示器保持开启
// ES_SYSTEM_REQUIRED: 防止系统自动进入睡眠模式
static bool is_wakelock_enabled = false;

// static
void WakelockPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.alnitak/wakelock",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<WakelockPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

WakelockPlugin::WakelockPlugin() {}

WakelockPlugin::~WakelockPlugin() {
  // 析构时确保禁用 wakelock
  DisableWakelock();
}

void WakelockPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("enableWindows") == 0) {
    EnableWakelock();
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name().compare("disableWindows") == 0) {
    DisableWakelock();
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

void WakelockPlugin::EnableWakelock() {
  if (!is_wakelock_enabled) {
    // SetThreadExecutionState 会阻止系统进入睡眠模式并保持显示器开启
    // ES_CONTINUOUS: 持续有效
    // ES_DISPLAY_REQUIRED: 强制显示器保持开启
    // ES_SYSTEM_REQUIRED: 防止系统自动睡眠
    SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED);
    is_wakelock_enabled = true;
  }
}

void WakelockPlugin::DisableWakelock() {
  if (is_wakelock_enabled) {
    // 恢复默认行为，允许系统进入睡眠模式
    SetThreadExecutionState(ES_CONTINUOUS);
    is_wakelock_enabled = false;
  }
}

}  // namespace wakelock_plugin
