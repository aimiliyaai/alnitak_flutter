# 播放相关逻辑与组件状态审查

## 1. 撤销说明

已按你的要求撤销「仅从 0 起播时启用 B 方案」的修改，恢复为：无论 seekTo 是否为 0，都走同一套「open(play: false) → 等缓冲达标 → 280ms 后 play」逻辑。

---

## 2. 播放流程概览

- **从 0 起播**：`_startPlayback(part, null)` → `MediaPlayerWidget` 收到 `resourceId` + `initialPosition: null` → `initialize(resourceId, null)` → `setDataSource(..., seekTo: Duration.zero, autoPlay: true)` → open(play: false) → 等缓冲 + 280ms → play()。
- **带进度恢复**：`_startPlayback(part, progress)` → `initialPosition: progress` → `setDataSource(..., seekTo: progress, autoPlay: true)` → open(play: false) → 等缓冲 + 280ms → play()。
- **登录后恢复**：不重新 open。`_onAuthStateChanged` → `fetchAndRestoreProgress()` → 若与当前 position 差 > 3s 则 `seek(targetPos)`，无重新 setDataSource，因此不会触发「从 0 起播」那条路径，也不会出现你描述的双音。

---

## 3. 组件状态与逻辑结论

### 3.1 MediaPlayerWidget 与 resourceId / initialPosition

- **didUpdateWidget** 仅在 `oldWidget.resourceId != widget.resourceId` 时调用 `_initializePlayer()`，**不会**在仅 `initialPosition` 变化时重新初始化。
- 当前产品行为是：
  - 首次进入：`_loadVideoData` → `_fetchProgressAndRestore` → `_startPlayback(part, position)` 一次性设置 `_currentResourceId` 和 `_currentInitialPosition`，MediaPlayerWidget 收到后执行一次 initialize。
  - 登录后：只调 `fetchAndRestoreProgress()` 做 seek，不再次 setState 更新 `_currentInitialPosition`，因此不会、也不需要 didUpdateWidget 再初始化。
- **结论**：在现有设计下，不根据 `initialPosition` 单独变化而 re-initialize 是合理的，未发现逻辑错误。

### 3.2 首次 build 时 resourceId 为 null

- 第一次 build 时 `_currentResourceId`、`_currentInitialPosition` 仍为 null（在 `_fetchProgressAndRestore` 完成并调用 `_startPlayback` 之前）。
- MediaPlayerWidget 的 `_initializePlayer()` 中有 `if (widget.resourceId == null) return;`，因此不会在 resourceId 为 null 时初始化。
- `_startPlayback` 在 setState 里设置 `_currentResourceId`、`_currentInitialPosition`，触发 didUpdateWidget，此时才执行 `_initializePlayer()` 并传入正确的 initialPosition。
- **结论**：顺序正确，无「未带进度就初始化」的问题。

### 3.3 hasEverPlayed / isBuffering / isPlayerInitialized

- **hasEverPlayed**：在 position 流中当 `position > Duration.zero` 时置 true，用于区分「首帧前加载」与「播放中缓冲」；恢复进度时若 open 的 start 为非 0，首次上报的 position 通常已 > 0，hasEverPlayed 会很快变为 true，语义正确。
- **isBuffering**：由 buffering 流 + 1500ms 持续判定更新；setDataSource 时显式置为 false，与 removeListeners 等配合一致。
- **isPlayerInitialized**：在 setDataSource 中 open 完成后置 true；UI 用其控制是否展示 Video 与加载层，逻辑一致。
- **结论**：三个状态与当前注释（如「方案七：未初始化显示加载；已初始化且 hasEverPlayed 且持续缓冲才显示缓冲加载」）一致，未发现错误。

### 3.4 方案 B：_pendingStablePlay 与竞态

- `_schedulePlayWhenStable()` 入口处即置 `_pendingStablePlay = false` 并取消兜底定时器，后续再调用会因 `!_pendingStablePlay` 直接 return。
- buffer 与 buffering 两路都可能触发，但只会真正执行一次「280ms 后 play」。
- **结论**：无重复 play 的竞态问题。

### 3.5 快速切换资源时的 initialize 竞态

- `initialize()` 中有「若正在初始化且 _currentResourceId == resourceId 则 return」。
- 若先初始化 resource A，再在未完成时收到 resource B，会再进入一次 initialize(B)，此时 `_currentResourceId` 会被设为 B，A 的异步完成后在 setDataSource 前有 `if (_currentResourceId != resourceId) return`（resourceId 为 A），会直接 return，不会用 A 覆盖 B。
- **结论**：快速切换资源时由 _currentResourceId 保证只生效最后一次请求，逻辑正确。

### 3.6 dispose 与延迟 play

- `_schedulePlayWhenStable()` 里在 `Future.delayed(280ms)` 的回调中先判断 `if (_isDisposed || _player == null) return` 再执行 `play()`。
- **结论**：dispose 后不会误执行 play，安全。

---

## 4. 小结

- 播放链路、登录后恢复（仅 seek、不重新 open）与「从 0 起播 / 带进度起播」的差异与当前实现一致，未发现明显逻辑错误或状态不一致。
- MediaPlayerWidget 仅在 resourceId 变化时重新初始化、不随 initialPosition 单独变化而重新初始化，与当前产品行为（登录后仅 fetchAndRestoreProgress + seek）匹配。
- 若后续希望「登录后用服务端进度重新 open 而不是 seek」，则需要：要么在登录后也更新 `_currentInitialPosition` 并让 MediaPlayerWidget 在「同一 resourceId、仅 initialPosition 变化」时也 re-initialize，要么在 controller 内提供「按新 position 重新 setDataSource」的接口并由页面在登录后调用；当前实现未按此设计，审查中未发现因此导致的 bug。
