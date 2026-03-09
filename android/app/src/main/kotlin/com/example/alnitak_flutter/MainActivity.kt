package com.example.alnitak_flutter

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 使用 AudioServiceFragmentActivity 以支持 audio_service 后台播放
class MainActivity : AudioServiceFragmentActivity() {
    private val CHANNEL = "com.example.alnitak_flutter/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册原生 Wakelock 插件
        flutterEngine.plugins.add(WakelockPlugin())

        // 电池优化设置通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openBatteryOptimizationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        // 部分机型（如 Android 14/16 等）无弹窗，改为打开本应用设置页，用户可进入「电池」设为无限制
                        try {
                            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(fallback)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("UNAVAILABLE", "无法打开设置", null)
                        }
                    }
                }
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                else -> result.notImplemented()
            }
        }
    }
}
