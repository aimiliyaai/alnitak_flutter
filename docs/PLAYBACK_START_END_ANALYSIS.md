# 播放起始位置与结束时间问题分析

## 现象

- **起始位置非绝对 0**：期望从 0 或指定 `initialPosition` 开始播，实际从其它位置开始。
- **结束时间非绝对结束**：进度条或“播放结束”触发时机与真实结尾不一致（提前或延后）。

## 当前实现要点

- **起始**：`initialize()` 里 `seekTo = initialPosition > 0 ? Duration(seconds: initialPosition.toInt()) : Duration.zero`，在 `setDataSource(..., seekTo)` 里通过 `player.open(Media(url, start: seekTo), play: false)` 传给 media_kit/mpv。
- **进度**：`position` / `duration` 完全来自 `player.stream.position` / `player.state.duration`（mpv 解析流/文件得到）。
- **结束**：依赖 `player.stream.completed`；并用 `progress = position/duration >= 0.9` 判定“真结束”，避免断网导致的假完成。

## 可能原因区分

### 1. 起始位置不对

| 可能来源 | 说明 |
|---------|------|
| **播放器/media_kit** | Android 上存在 [issue #1298](https://github.com/media-kit/media-kit/issues/1298)：`Media.start` 在某些情况下不生效；或 mpv 将 start 对齐到关键帧/切片起点，导致与传入秒数有偏差。 |
| **我们自己的逻辑** | `initialPosition.toInt()` 会截断小数；若历史/服务端给的是带小数的秒，会有精度损失。一般不会导致“从 0 开始却从别处起播”。 |
| **流/切片** | HLS/DASH 切片边界不是整秒，mpv 可能从最近关键帧或 segment 起点开始，看起来像“没从 0 开始”。 |

**如何判断**：

- 用**本地已知时长的单文件**（如 60 秒的 mp4）测试：`open(Media(path, start: Duration.zero))` 后看首帧/首秒是否在 0。
- 在 Debug 下看日志：我们已在对 `_hasPlaybackStarted` 首次置 true 时打一条「首帧 position / duration」（见 controller 内注释），若此时 position 明显不是 0 且未做 seek，多半是 **播放器或流对齐** 问题。
- 若同一资源在 Web 或其它播放器上从 0 正常，而在本端不从 0 开始，则更倾向 **media_kit/Android** 或 **平台实现** 问题。

### 2. 结束时间不对

| 可能来源 | 说明 |
|---------|------|
| **转码/封装** | 视频或 DASH/HLS 的 duration 元数据不准确（略短或略长），mpv 用该 duration 做进度和 completed，就会“提前结束”或“到不了 100%”。 |
| **流/切片** | 最后一个切片时长或 EXT-X-ENDLIST 等标记有误，导致 completed 触发时机与真实最后一帧不一致。 |
| **播放器** | completed 触发略早/略晚于最后一帧；或 duration 在流未完全加载时为估算值，后续会变。 |

**如何判断**：

- 对比**后端/接口返回的 duration**（如 `currentResource.duration`）与**稳定播放后** `player.state.duration`：若差异大（如差数秒），多半是 **转码或流元数据** 问题。
- 同一资源在其它播放器或 ffprobe 下看到的 duration 与当前 app 是否一致；若一致而只有我们不对，再怀疑 **播放器侧**。

## 结论与建议

- **起始非 0**：更可能来自 **播放器/平台**（Media.start 未生效或关键帧对齐）或 **流切片**；可通过本地文件 + 首帧日志区分。
- **结束非绝对**：更可能来自 **转码/流元数据**（duration 或结尾切片不准）；可用后端 duration 与 player duration 对比、以及其它播放器对比来确认。

**代码侧已做/可选**：

- 已用 `Media(..., start: seekTo)` 传起始；已用 90% 比例防假完成。
- 可选加固：若确认 Android 上 `Media.start` 不生效，可在 `open` 成功后、`play` 前对「期望从 0 开始」的情况做一次显式 `seek(Duration.zero)`（可能带来轻微闪跳，需实机权衡）。
- 已在对 `_hasPlaybackStarted` 首次为 true 时打 Debug 日志（首帧 position/duration），便于区分是播放器还是源问题。
