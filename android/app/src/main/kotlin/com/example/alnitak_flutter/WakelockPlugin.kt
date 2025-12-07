package com.example.alnitak_flutter

import android.app.Activity
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android 原生 Wakelock 实现
 *
 * 使用 WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
 * 这是 Android 官方推荐的方式，与 NextPlayer 一致
 */
class WakelockPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.alnitak/wakelock")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "enableAndroid" -> {
                enableWakelock()
                result.success(true)
            }
            "disableAndroid" -> {
                disableWakelock()
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * 启用屏幕常亮
     *
     * 使用 FLAG_KEEP_SCREEN_ON，这个 flag 会：
     * 1. 防止屏幕在视频播放时变暗或关闭
     * 2. 不需要额外的权限（相比 WAKE_LOCK 权限）
     * 3. 当 Activity 失去焦点时自动释放（更安全）
     */
    private fun enableWakelock() {
        activity?.runOnUiThread {
            activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    /**
     * 禁用屏幕常亮
     */
    private fun disableWakelock() {
        activity?.runOnUiThread {
            activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        // 清理时确保禁用 wakelock
        disableWakelock()
        activity = null
    }
}
