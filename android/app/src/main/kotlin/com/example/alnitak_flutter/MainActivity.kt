package com.example.alnitak_flutter

import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// 使用 AudioServiceFragmentActivity 以支持 audio_service 后台播放
class MainActivity : AudioServiceFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册原生 Wakelock 插件
        flutterEngine.plugins.add(WakelockPlugin())
    }
}
