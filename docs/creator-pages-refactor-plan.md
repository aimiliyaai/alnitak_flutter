# 创作中心/稿件页重复代码修复计划

以下问题已逐项核对，**位置与描述均属实**。按推荐优先级规划修复。

---

## 核实结论摘要

| # | 问题 | 核实结果 | 涉及文件/行号 |
|---|------|----------|----------------|
| 1 | VideoManagePage 与 VideoManuscriptPage 功能重复 | ✅ 存在 | creator_center_page 跳 VideoManagePage；两页同是「视频管理列表+编辑/删除」，API 与数据模型不同 |
| 2 | _getStatusColor 重复 3 次（视频 2+文章 1） | ✅ 存在 | video_manage 458-474；video_manuscript 409-424；article_manuscript 396-407（文章状态码不同） |
| 3 | _getStatusText + _getStatusColor 在 playlist_manage 再重复 | ✅ 存在 | playlist_manage_page 139-161 |
| 4 | 删除确认对话框模式重复 5 次 | ✅ 存在 | 输入标题确认：video_manage 494-587、playlist_manage 40-118；简单确认：video_manuscript 113-158、article_manuscript 109-154、playlist_video 46-78 |
| 5 | 分区选择 _buildPartitionSection 复制粘贴 | ✅ 存在 | video_upload_page 923-1006、article_upload_page 424-507，结构几乎一致 |
| 6 | _showReviewReason 审核原因弹窗重复 | ✅ 存在 | video_manage 161-190、playlist_manage 121-137 |
| 7 | VideoManuscriptPage 与 ArticleManuscriptPage 结构 1:1 复制 | ✅ 存在 | _buildBody、item、loadMore、空/错/加载更多逻辑一致 |
| 8 | video_manage 自带 _formatTime 未用 TimeUtils | ✅ 存在 | video_manage 419-427；TimeUtils.formatDate 可替代 |
| 9 | 加载更多指示器不统一 | ✅ 存在 | video_manuscript/article_manuscript 全尺寸；comment_manage 24×24 strokeWidth:2；video_manage 全尺寸 |

---

## 修复计划（按优先级）

### P1：删除 VideoManagePage，创作中心直接用 VideoManuscriptPage（推荐优先）

**目标**：只保留一套「视频管理列表」实现，消除整页重复。

**步骤**：

1. **creator_center_page.dart**
   - 将「视频管理」入口从 `VideoManagePage` 改为 `VideoManuscriptPage`。
   - import 从 `../creator/video_manage_page` 改为 `../upload/video_manuscript_page`（或按你项目实际路径）。

2. **删除或废弃 video_manage_page**
   - 全局搜索 `VideoManagePage` / `video_manage_page`，确认仅创作中心引用后，删除 `lib/pages/creator/video_manage_page.dart`。
   - 若暂时保留文件，至少从 creator_center 移除引用，避免两套入口并存。

**影响**：P1 完成后，P4（video_manage 的 _formatTime）和 video_manage 内的 _getStatusText/_getStatusColor、加载更多指示器均随页面删除而消失，无需再改。

---

### P2：提取 _buildPartitionSection 为共享 Widget

**目标**：消除 video_upload 与 article_upload 中约 80 行重复分区 UI。

**步骤**：

1. **新建共享 Widget**
   - 路径建议：`lib/widgets/partition_section.dart` 或 `lib/pages/upload/widgets/partition_section.dart`。
   - 入参建议：
     - `parentPartitions`, `subPartitions`, `selectedParentPartition`, `selectedSubPartition`
     - `isLocked`（分区已锁定）
     - `onParentChanged(Partition?)`, `onSubChanged(Partition?)`
     - `validator: String? Function()?`（用于 Form 校验「请选择分区」）
   - 内部只负责：标题行（含锁定提示）、主分区/子分区两个 `DropdownButtonFormField`，逻辑与当前两页一致。

2. **video_upload_page / article_upload_page**
   - 删除各自 `_buildPartitionSection` 实现，改为使用上述 Widget，传入当前 state 与 `PartitionApiService.getSubPartitions` 结果。
   - 保持两页对 `_isPartitionLocked`、`_selectedParentPartition`、`_selectedSubPartition` 等状态的管理不变，仅把 UI 抽成共享组件。

**注意**：若两页对「分区锁定」或 API 来源有细微差异，在共享 Widget 上用参数区分，避免再复制粘贴。

---

### P3：提取视频状态文本/颜色为工具类

**目标**：视频状态码（100/200/300/500/2000/3000/0）的文案与颜色只维护一处。

**步骤**：

1. **新建 `lib/utils/video_status_utils.dart`**（或 `status_utils.dart` 内分视频/文章）
   - `static String? getStatusText(int? status)`：与当前 video_manage / video_manuscript 的映射一致（转码中/待审核/审核不通过/处理失败等）。
   - `static Color getStatusColor(int? status)`：与当前两页一致（orange/blue/red/green）。

2. **替换引用**
   - **video_manuscript_page**：删除 `_getStatusColor`，改用 `VideoStatusUtils.getStatusText` / `getStatusColor`。
   - **playlist_manage_page**：删除 `_getStatusText`、`_getStatusColor`，改用同上（合集与视频状态码一致 0/500/2000）。
   - **article_manuscript_page**：保留自身 `_getStatusColor`（文章状态 1/2/3 不同），不混用视频工具类；若希望统一风格，可另建 `ArticleStatusUtils`。

3. **video_manage_page**：若 P1 已删除该页，则无需再改。

---

### P4：video_manage_page 的 _formatTime → TimeUtils（P1 后自动消失）

若未删 VideoManagePage，再单独做：

- 删除 `_formatTime`（419-427），所有展示「日期」的地方改为 `TimeUtils.formatDate(time)`（或 `formatDateTime` 视需求）。
- P1 已删该页则跳过。

---

### P5：统一加载更多指示器为 24×24

**目标**：列表底部「加载更多」统一为小圆，与 comment_manage 一致。

**步骤**：

1. **定义统一组件**
   - 方式 A：在公共 widgets 中新增 `LoadingMoreIndicator`（例如 `lib/widgets/loading_more_indicator.dart`），内部为：`Padding(padding: 16, child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))`。
   - 方式 B：或在现有 `theme`/通用组件中提供同名 Widget，保证全项目只一处定义。

2. **替换使用处**
   - **video_manuscript_page**（约 280-285）：底部加载更多改为 `LoadingMoreIndicator`。
   - **article_manuscript_page**（约 275-280）：同上。
   - **comment_manage_page**：已有 24×24，可改为使用同一 `LoadingMoreIndicator`，避免重复定义。
   - **video_manage_page**：若 P1 已删除则无需改。

---

## 未纳入本轮的优化（可后续做）

- **删除确认对话框**：5 处模式不同（输入标题 vs 简单确认），可后续抽象为「需输入标题的确认」与「简单确认」两个通用 Dialog，减少重复。
- **_showReviewReason**：video_manage（将删）/ playlist_manage 两处结构一致，可抽成共享「审核原因弹窗」Widget。
- **VideoManuscriptPage 与 ArticleManuscriptPage**：若希望进一步收口，可考虑共用「稿件列表」通用组件（传入 itemBuilder、loadMore、空/错状态），需较大重构，建议单独排期。

---

## 建议执行顺序

1. **P1**：先做创作中心改用 VideoManuscriptPage 并删除 VideoManagePage，减少后续改动面。
2. **P2**：分区区块抽成共享 Widget，改动集中、收益明确。
3. **P3**：视频状态工具类，改 2～3 个文件即可。
4. **P5**：统一加载更多指示器，改 3～4 处引用。

完成以上后，再视需要做删除确认弹窗、审核原因弹窗的抽取以及稿件列表的通用化。
