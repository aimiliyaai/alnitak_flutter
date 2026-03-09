# Android 构建注意事项

## NDK abiFilters 与 Flutter splits 冲突

**现象**：在 `android/app/build.gradle.kts` 的 `defaultConfig` 里设置 `ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }` 后，构建报错：

```text
Conflicting configuration : '...' in ndk abiFilters cannot be present when splits abi filters are set
```

**原因**：Flutter Gradle 插件会自行配置 `splits.abi`（如 armeabi-v7a, x86_64, arm64-v8a），与手动设置的 `ndk.abiFilters` 不能同时存在。

**做法**：
- 不要在手写配置里再设 `ndk.abiFilters`。
- 若只要 arm 架构、减小单 APK 体积，用 Flutter 命令行指定平台即可：
  ```bash
  flutter build apk --release --target-platform android-arm,android-arm64
  ```
