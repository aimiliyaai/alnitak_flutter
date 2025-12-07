import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 注册原生 Wakelock 插件
    let controller = window?.rootViewController as! FlutterViewController
    WakelockPlugin.register(with: registrar(forPlugin: "WakelockPlugin")!)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
