# fMP4 DASH 播放 PTS 回溯问题分析与修复

## 问题描述

在使用 DASH 模式（fMP4 SegmentBase）播放视频时，mpv 日志出现 PTS（Presentation Timestamp）回溯错误：

```
Invalid video timestamp: 95.033333 -> 90.000000
```

**用户现象**：画面一开始正常同步，播放一段时间后突然回溯一下再重新对齐，伴随短暂画面跳变。

---

## 根因分析

问题由 **服务端编码** 和 **客户端 demuxer** 两层因素叠加导致。

### 1. 服务端：nvenc GPU 编码忽略 `-sc_threshold 0`

**背景**：服务端使用 NVIDIA GPU（nvenc）进行硬件加速转码，FFmpeg 命令中设置了 `-sc_threshold 0` 来禁用场景检测，期望获得严格的固定 GOP（2秒）。

**问题**：`-sc_threshold 0` 是 **libx264 专属参数**，nvenc 编码器直接忽略该参数。导致实际输出的关键帧间距不规则（4.3s、2s、5s 混合），破坏了 fMP4 fragment 对齐。

**修复**：使用 nvenc 专属参数替代：

```go
// 旧代码（无效）
"-sc_threshold", "0",

// 新代码（nvenc 专属）
"-no-scenecut", "1",    // 禁用 nvenc 场景检测
"-forced-idr", "1",     // 强制所有关键帧为 IDR 帧
```

修复后通过 `ffprobe -show_frames` 验证，关键帧严格按 2 秒间隔对齐。

### 2. 客户端：mpv lavf demuxer 在 fragment 边界回退读取

即使关键帧完全对齐，mpv 的 lavf demuxer 仍会在 fMP4 fragment 边界处回退读取旧 fragment 的数据，导致 PTS 出现短暂倒退。

**修复**：

```dart
await nativePlayer.setProperty('demuxer-max-back-bytes', '0');
```

禁止 demuxer 回退读取，彻底消除 PTS 回溯。

### 3. 排除的错误方案

在排查过程中尝试过以下方案，均不适用于 fMP4：

| 方案 | 效果 | 原因 |
|------|------|------|
| `fflags=+genpts` | seek 后 PTS 从 0 重计 | genpts 对 fMP4 分段容器重新生成 PTS，seek 后上下文丢失导致重置 |
| `linearize-timestamps=yes` | video PTS 全部为 0 | 该选项设计用于连接多个独立文件，对单文件 fMP4 直接将 video PTS 清零 |

最终采用的客户端配置：

```dart
// fMP4 容错：只保留 discardcorrupt（丢弃损坏帧）
await nativePlayer.setProperty('demuxer-lavf-o', 'fflags=+discardcorrupt');
// 禁止 demuxer 回退读取
await nativePlayer.setProperty('demuxer-max-back-bytes', '0');
```

---

## fMP4 容器结构对比：我们 vs B站 vs YouTube

### 通用 fMP4 SegmentBase 结构

三家均使用相同的 box 结构：

```
ftyp → moov → sidx → [moof + mdat] × N
```

| Box | 作用 |
|-----|------|
| `ftyp` | 文件类型标识 |
| `moov` | 轨道元数据（codec、分辨率等），`empty_moov` 模式下不含 sample 表 |
| `sidx` | Segment Index，记录每个 fragment 的时间范围和字节偏移，支持 HTTP Range 精确 seek |
| `moof` | Fragment 级别的 sample 表（时间戳、大小、关键帧标记） |
| `mdat` | 实际的音视频数据 |

### 编码参数对比

| 维度 | 我们 | B站 | YouTube |
|------|------|-----|---------|
| **编码器** | H.264 nvenc (GPU) | H.264 (CPU) | AV1 |
| **GOP 策略** | 固定 2s (`-g gopSize`) | 固定 5s | 场景自适应 (0.5-5s) |
| **Fragment 时长** | 2s (`-frag_duration 2000000`) | 5s | 不规则 |
| **ftyp brand** | `iso5` | `isom` | `dash` |
| **B 帧** | 禁用 (`-bf 0`) | 使用 | 不适用 (AV1) |
| **音视频** | 分离文件 (video.m4s + audio.m4s) | 分离文件 | 分离文件 |
| **sidx** | 有 (`global_sidx`) | 有 | 有 |

### 关键差异

1. **B站**：固定 5 秒 GOP + CPU 编码，关键帧完美对齐，PiliPlus 用纯 mpv 默认配置即可流畅播放。
2. **YouTube**：AV1 编码 + 场景自适应关键帧（不规则 0.5-5s），但 sidx/fragment 对齐完善，播放器侧无需特殊配置。
3. **我们**：GPU 编码（nvenc）需要专属参数控制关键帧，且 B 帧在 fMP4 fragment 边界会导致非单调 PTS，因此必须 `-bf 0` 禁用。

### B 帧问题（`-bf 0` 的必要性）

fMP4 的每个 fragment 是独立解码单元。B 帧的参考帧可能跨越 fragment 边界，导致：

- Fragment 边界处出现非单调递增的 PTS
- mpv demuxer 发出 `Invalid video timestamp` 警告
- 画面短暂回溯后重新对齐

禁用 B 帧后，每帧只依赖前向参考帧，PTS 严格单调递增。

---

## 服务端 FFmpeg 编码关键参数

```bash
# GPU 编码（nvenc）
-c:v h264_nvenc
-no-scenecut 1          # 禁用场景检测（nvenc 专属）
-forced-idr 1           # 强制 IDR 关键帧（nvenc 专属）
-g <gopSize>            # GOP 大小（帧数 = fps * 2，即 2 秒）
-bf 0                   # 禁用 B 帧
-movflags +frag_keyframe+empty_moov+default_base_moof+dash+global_sidx
-frag_duration 2000000  # Fragment 时长 2 秒

# CPU 编码（libx264，备用）
-c:v libx264
-sc_threshold 0         # 禁用场景检测（libx264 专属）
-g <gopSize>
-bf 0
# ... 其余相同
```

### `movflags` 各标志作用

| 标志 | 作用 |
|------|------|
| `frag_keyframe` | 每个关键帧开始新 fragment（`global_sidx` 依赖此标志生成 segment 索引） |
| `empty_moov` | moov 不含 sample 表，所有数据在 moof+mdat 中 |
| `default_base_moof` | moof 使用 default-base-is-moof 标记，DASH 规范要求 |
| `dash` | 启用 DASH 兼容模式 |
| `global_sidx` | 在文件头生成全局 sidx，支持 HTTP Range seek |

---

## PiliPlus 参考对比

PiliPlus（B站第三方客户端）播放 B站 fMP4 时使用纯 mpv 默认配置，无任何 demuxer 参数覆盖。能正常工作的原因：

1. B站 fMP4 使用 CPU 编码 + 固定 5s GOP，关键帧完美对齐
2. B站 fMP4 使用 B 帧但 GOP 较长（5s），fragment 边界上的 B 帧跨越问题在 5s 粒度上不明显
3. mpv 默认的 `demuxer-max-back-bytes`（非零）对 B站的优质 fMP4 无副作用

我们的场景差异：
- GPU 编码需要特殊参数控制关键帧
- 2s 短 fragment + 禁用 B 帧的组合下，demuxer 回退读取反而触发 PTS 回溯
- 因此需要 `demuxer-max-back-bytes=0` + `fflags=+discardcorrupt` 的组合

---

## 音视频 PTS 绝对对齐（后端 + App）

为便于 DASH 双流（video.m4s + audio.m4s）在播放器内对齐，服务端转码已做：

- **视频**：`[0:v]setpts=PTS-STARTPTS`（首帧 PTS 归零）+ `-avoid_negative_ts make_zero`（时间戳从 0 开始，与 YouTube 对齐）
- **音频**：`[0:a]asetpts=PTS-STARTPTS`（首采样 PTS 归零）

理论上两端均从 0 起，音画绝对对齐。若某资源 ffprobe 显示 video `start_time` 非 0（如 0.1），多为该资源在加入上述参数**之前**转码的，**重新转码**即可；新转码产物应与音频对齐。

---

## 最终解决方案总结

### 服务端
- **PTS 从 0 起**：视频 `setpts=PTS-STARTPTS` + `-avoid_negative_ts make_zero`，音频 `asetpts=PTS-STARTPTS`
- nvenc 编码：`-no-scenecut 1 -forced-idr 1`（替代无效的 `-sc_threshold 0`）
- 禁用 B 帧：`-bf 0`（文档建议；当前实现若为 `-bf 3` 则与文档不一致，需权衡 PTS 稳定性与画质）
- GOP 与 fragment 对齐：`-g gopSize` + `-frag_duration 2000000`

### 客户端
- `demuxer-lavf-o=fflags=+discardcorrupt`（容错，不用 genpts）
- `demuxer-max-back-bytes=0`（禁止 demuxer 回退读取）
- `hr-seek=yes`（双独立流精确 seek）
- 不使用 `linearize-timestamps`（会清零 video PTS）
- 不使用 `genpts`（seek 后 PTS 重置）

---

*文档更新: 2026-03-06*
