# 缓冲逻辑判断 — 可选方案

## 当前逻辑简述（已采用方案七）

- **数据源**：`VideoPlayerController` 监听 `_player!.stream.buffering`；**持续 1.5 秒**才把 `isBuffering.value = true`，`false` 立即回写。
- **hasEverPlayed**：position 首次 > 0 时置 true，切资源时重置；用于区分「首帧前」与「播放中缓冲」。
- **UI 显示**：未初始化 → 全屏加载；已初始化且 **hasEverPlayed 且 isBuffering** 才显示缓冲加载（无 2 秒宽限、无 _playerInitializedAt）。

问题本质：mpv 的 `buffering` 会频繁 true/false，若直接驱动 UI 就会「闪两次」或抖动，需要**过滤/延迟/条件**策略。

---

## 方案一：UI 层「初始化后 2 秒内不显示缓冲」（已废弃）

- **做法**：在 MediaPlayerWidget 里用 `_playerInitializedAt`，2 秒内不显示缓冲加载。**已删除，现用方案七。**
- **优点**：逻辑简单，controller 干净。
- **缺点**：依赖 2 秒魔法数；首帧很慢时 2 秒内无加载反馈。

---

## 方案二：Controller 层「初始化后 N 秒内不对外报缓冲」

- **做法**：在 `video_player_controller.dart` 里，setDataSource 完成后记下时间；在 `buffering.listen` 里，若「距初始化 < N 秒」则收到 `buffering=true` 时不执行 `isBuffering.value = true`，只在该时间之后或 `buffering=false` 时正常更新。
- **优点**：所有「是否算缓冲」的逻辑集中在 controller，UI 只消费 `isBuffering`，无需 `_playerInitializedAt` 和 2 秒判断。
- **缺点**：controller 要维护时间和（可选）Timer，与之前方案 A 类似。

---

## 方案三：延迟显示 — 「缓冲持续超过 M 秒才显示」

- **做法**：收到 `buffering=true` 时**不立刻**显示加载，而是启动一个 M 秒（如 1.0～1.5）的 Timer；只有**持续** buffering 超过 M 秒才把「可显示缓冲」设为 true；若中途变为 false 则取消 Timer 并隐藏。可在 UI 层做（MediaPlayerWidget 或 CustomPlayerUI），也可在 controller 里做（例如对外暴露 `shouldShowBufferingUI` 而非原始 `isBuffering`）。
- **优点**：短暂抖动（几百毫秒）不会触发加载动画，只有真正卡住才显示。
- **缺点**：真正卡顿时用户要等 M 秒才看到提示；实现要管 Timer 和状态。

---

## 方案四：用「是否已经播过」区分 — hasEverPlayed

- **做法**：在 controller 增加 `ValueNotifier<bool> hasEverPlayed`，在 position 第一次 > 0（或第一次收到 duration 且 position > 0）时设为 true。UI 显示缓冲的条件改为：`isBuffering && hasEverPlayed`。即**未开始播放前的 buffering 一律不显示**。
- **优点**：语义清晰——「首帧前的算加载/初始化，之后才算缓冲」；不依赖固定秒数。
- **缺点**：需在 controller 维护一个状态并在 position 流里写一次判断。

---

## 方案五：用缓冲量过滤 — 只有「缓冲不足」且 buffering 才显示

- **做法**：不仅看 `buffering` 布尔，还看 `buffer`（或 `bufferedSeconds`）。例如：只有 `buffering == true` **且** `buffer < 3 秒`（或 `buffer == 0`）时才认为「需要显示加载」；缓冲已有几秒则只当「卡顿」处理（或配合方案三延迟显示）。
- **优点**：能区分「正在补一点点缓冲」和「真的卡住没数据」，减少无意义闪烁。
- **缺点**：要定阈值（几秒）；和 mpv 的 buffer 含义要对应好（DASH 可能用 demuxer-cache-state）。

---

## 方案六：防抖 — buffering 为 true 时延迟再置 true，false 立即置 false

- **做法**：在 controller 的 `buffering.listen` 里：若 `buffering == true`，先启动一个 300～500ms 的 Timer，到点再设 `isBuffering.value = true`；若在这之前收到 `buffering == false`，取消 Timer 并设 `isBuffering.value = false`。这样短脉冲不会触发显示。
- **优点**：实现简单，对「闪一下又恢复」的抖动很有效。
- **缺点**：真正卡顿时会有几百毫秒延迟才出现提示；若 500ms 内 true→false→true 可能仍会闪。

---

## 方案七：组合 — 「已播过」+ 「持续 N 秒才显示」

- **做法**：方案四 + 方案三：只有 `hasEverPlayed && isBuffering` 且「本次 buffering 已持续 ≥ M 秒」才显示加载。即首帧前不显示、首帧后只有持续卡顿才显示。
- **优点**：既避免首帧闪加载，又避免短暂抖动触发加载。
- **缺点**：实现稍复杂，要维护 hasEverPlayed 和「本次 buffering 开始时间」或 Timer。

---

## 对比小结

| 方案 | 改动位置 | 复杂度 | 适用场景 |
|------|----------|--------|----------|
| 一（已废弃） | 仅 UI | 低 | 已由方案七替代 |
| 二 | 仅 Controller | 中 | 希望逻辑集中、UI 只认 isBuffering |
| 三 | Controller 或 UI | 中 | 不想为短暂抖动显示加载 |
| 四 | Controller + UI | 中 | 语义清晰：首帧前不算缓冲 |
| 五 | Controller | 中高 | 有缓冲数据、想按「缓冲不足」判断 |
| 六 | Controller | 低 | 快速防抖、少改 UI |
| 七（当前） | Controller + UI | 高 | 既要首帧不闪又要持续卡顿才提示 |

当前采用 **方案七**（hasEverPlayed + 持续 1.5 秒才显示缓冲）。若后续调整，可考虑单独 **方案四** 或加 **方案六（防抖）**。
