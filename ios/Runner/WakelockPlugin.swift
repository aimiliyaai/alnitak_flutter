import Flutter
import UIKit

/**
 * iOS 原生 Wakelock 实现
 *
 * 使用 UIApplication.shared.isIdleTimerDisabled
 * 这是 iOS 官方推荐的防止屏幕休眠的方式
 */
public class WakelockPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.alnitak/wakelock", binaryMessenger: registrar.messenger())
        let instance = WakelockPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enableIOS":
            enableWakelock()
            result(true)
        case "disableIOS":
            disableWakelock()
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /**
     * 启用屏幕常亮
     *
     * UIApplication.shared.isIdleTimerDisabled = true 会：
     * 1. 防止设备在无操作时进入休眠状态
     * 2. 保持屏幕常亮，适用于视频播放场景
     * 3. 需要在主线程调用
     */
    private func enableWakelock() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    /**
     * 禁用屏幕常亮
     *
     * 恢复系统默认的空闲计时器行为
     */
    private func disableWakelock() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
