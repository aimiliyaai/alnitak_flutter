# APK 体积与依赖对比（alnitak_flutter vs pili_plus）

## 当前单 ABI APK 体积构成（app-armeabi-v7a-release.apk ≈ 35.3 MB）

| 内容 | 大小（约） | 说明 |
|------|------------|------|
| **lib/**（原生 .so 合计） | **~33 MB** | 见下表 |
| assets、res、dex 等 | ~2 MB | 资源与代码 |
| **合计** | **35.3 MB** | |

### lib/ 内各 .so 占比（armeabi-v7a）

| 文件 | 大小（约） | 来源 |
|------|------------|------|
| libapp.so | **14.1 MB** | Dart AOT 编译产物（业务 + 依赖 Dart 代码） |
| libmpv.so | **11.5 MB** | media_kit_libs_video（libmpv 解码/渲染） |
| libflutter.so | **7.9 MB** | Flutter 引擎 |
| libmediakitandroidhelper.so | 280 KB | media_kit Android 桥接 |
| 其他 | &lt;10 KB | 插件原生库 |

**结论**：约 **33 MB / 35 MB ≈ 94%** 来自 `lib/`，其中 **libmpv + libflutter + libapp** 占绝大部分；**media_kit（libmpv）单库约 11.5 MB**，与 Flutter 引擎、Dart AOT 同量级。

---

## 依赖包与打包体积关系

### 对体积影响大的依赖（两项目共有）

| 依赖 | 影响方式 | 大致体积贡献 |
|------|----------|--------------|
| **media_kit** + **media_kit_libs_video** | 引入 libmpv.so（每 ABI 一份） | **~11.5 MB / ABI** |
| **flutter**（引擎） | libflutter.so | **~8 MB / ABI** |
| **audio_service** | 少量原生 + 与 media 共用部分 | 与现有 so 合并，增量小 |
| **Dart 依赖整体** | 编译进 libapp.so | 业务越多、依赖越多，libapp 越大 |

### alnitak_flutter 直接依赖（约 30 个）

- 视频/媒体：media_kit, media_kit_video, media_kit_libs_video  
- 网络/存储：dio, http, path_provider, shared_preferences, cached_network_image, flutter_cache_manager  
- UI/能力：flutter_screenutil, qr_flutter, emoji_picker_flutter, flutter_widget_from_html  
- 系统/设备：audio_service, audio_session, wakelock_plus, screen_brightness, volume_controller, connectivity_plus, share_plus, url_launcher, package_info_plus, image_picker, file_picker  
- 工具：intl, uuid, web_socket_channel, crypto, path, xml  

**无大块资源**：未声明 `assets`，仅 uses-material-design（图标已 tree-shake）。

### pili_plus 直接依赖（约 70+ 个）

- 同样包含：media_kit, media_kit_libs_video, audio_service, audio_session 等 → **原生体积（libmpv + 引擎）与 alnitak 一致**。
- 额外大量依赖：getx, hive, flutter_inappwebview, permission_handler_*, font_awesome_flutter, material_design_icons_flutter, 弹幕/画中画/窗口/图表/WebDAV 等 → **libapp.so 会更大**。
- 大量 **assets**：多目录图片、字体、shaders 等 → **APK 中 assets 明显更大**。

**综合**：  
- **单 ABI（如 armeabi-v7a）**：alnitak 约 35 MB 是“引擎 + libmpv + 当前 Dart 体量”下的正常水平。  
- pili_plus 若打 **同一 ABI**，通常 ≥ 35 MB（Dart 更多、资源更多），可能 40 MB+。  
- 若 pili_plus 平时看的是 **split-per-abi** 的其中一个 APK，或 **app bundle** 安装后按设备只下一种 ABI，看到的“安装体积”会接近我们单 ABI 的 35 MB 量级，甚至更大。

---

## 综合计算与结论

1. **35 MB 主要来自**：  
   - **libmpv（media_kit）~11.5 MB**（两项目相同）  
   - **Flutter 引擎 ~8 MB**（两项目相同）  
   - **libapp（Dart）~14 MB**（我们已 minify/shrinkResources，体积正常）

2. **和 pili_plus 比**：  
   - 原生层（libmpv + 引擎）一致，**不是我们更大的原因**。  
   - 我们依赖更少、无大 assets，单 ABI 35 MB 应 ≤ 或 接近 pili_plus 同 ABI 的包。

3. **若想再减体积**（需权衡功能）：  
   - 换掉 media_kit（如改用 ExoPlayer/官方 video_player）可省约 **11.5 MB**，但需重写播放与可能的功能取舍。  
   - 继续用 media_kit 时，35 MB 单 ABI 已属该技术栈下的正常范围。

---

## 建议的构建方式（兼顾体积与兼容）

- 发应用商店或按设备分发：  
  `flutter build appbundle --release`  
  用户按设备只下载对应 ABI，体积等价于单 ABI。
- 直接发 APK（仅 arm）：  
  `flutter build apk --release --target-platform android-arm,android-arm64`  
  得到两个 APK，每个约 35 MB 量级（arm64 略大一点属正常）。
