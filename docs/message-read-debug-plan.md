# 消息已读小红点问题：日志与方案（先不改逻辑）

## 一、当前已读链路（客户端 vs 服务端）

| 类型 | 服务端 | 客户端 |
|------|--------|--------|
| **私信** | 有：`POST /message/readWhisper`，表 `msg_whisper.status`；列表接口带 `status` | 进详情调 `readWhisper(fid)`，列表用 `!item.status` 判未读 → **一致，正常** |
| **公告/点赞/回复/@** | 无已读接口、无已读字段 | 本地 `MessageReadStatus`：key=`msg_read_{category}`，存 `lastReadId`；未读 = `latestId > lastReadId` |

公告/点赞/回复/@ 的「已读」只存在客户端 SharedPreferences，依赖两处写入：

1. **消息中心**：点入口时 `_navigateToAndMarkRead` 用 `_latestIds[category]` 调 `markAsRead(category, latestId)`（若 `latestId > 0`）。
2. **子页**：进入公告/点赞/回复/@ 列表后，`_loadData` 里用当前页 `data` 的 **max(id)** 调 `markAsRead(category, readUpToId)`。

消息中心用的 `latestId` 来自：`getXxxList(page:1, pageSize:1)` 的 **first.id**（依赖服务端按 id 倒序，公告已加 `Order("id DESC")`）。

---

## 二、可能原因（为何除私信外都有小红点）

1. **消息中心拿到的 latestId 和子页拿到的 id 不一致**  
   例如：中心用「第一条 id」，子页用「当前页 max(id)」；若接口排序或分页不一致，或子页拿到的第一页并不是「全局最新」，则 `lastReadId` 会小于真实的 `latestId`，hasUnread 一直为 true。

2. **进入子页时未写入或写入的 id 偏小**  
   子页 `_loadData` 里若 `data.isEmpty` 不会 mark；若服务端返回顺序不是「最新在前」，`data.map(id).reduce(max)` 仍是「当前页最大 id」，可能小于消息中心用的 latestId。

3. **_latestIds 尚未就绪就点了入口**  
   `_checkUnreadStatus()` 异步，若用户很快点击「公告/点赞/回复/@」，`_latestIds[category]` 可能仍为 0，`_navigateToAndMarkRead` 里不会 mark，只依赖子页 mark；若子页也因上面原因写入了更小的 id，红点不消。

4. **本地 key 或 category 不一致**  
   理论上只有一处 `MessageReadStatus` 和固定 category，但若某处拼错 key 或用了不同常量，会导致读写的不是同一条 lastReadId。

---

## 三、建议日志点（最少、不重复）

只在一处用同一前缀（如 `[Read]`），便于过滤；每点只打一条，带关键参数即可。

| 位置 | 日志内容（示例） |
|------|------------------|
| **MessageReadStatus.markAsRead** | `[Read] markAsRead category=$category latestId=$latestId` |
| **MessageReadStatus.hasUnread** | `[Read] hasUnread category=$category latestId=$latestId lastReadId=$lastReadId result=$result`（在 hasUnread 内先 getLastReadId 再算 result，打一条） |
| **message_center_page _checkUnreadStatus** | 在拿到四个 latestId 后打一条：`[Read] center latestIds announce=$announceLatestId like=$likeLatestId reply=$replyLatestId at=$atLatestId` |
| **message_center_page _navigateToAndMarkRead** | 在 `if (latestId > 0)` 分支内 mark 之后打：`[Read] center markOnTap category=$category latestId=$latestId`（若 latestId==0 可打一条 `[Read] center markOnTap category=$category latestId=0 skip`） |
| **announce_page _loadData**（同理 like/reply/at 各一处） | 在 `if (data.isNotEmpty)` 里 mark 之后打：`[Read] subpage category=announce readUpToId=$readUpToId listLen=${data.length}`（like/reply/at 仅改 category 与 readUpToId 变量名） |

不重复：hasUnread 只在一个方法里打；center 只打「汇总 latestIds」和「点击时是否 mark」；子页只打「本次写入的 readUpToId」。

---

## 四、根据日志怎么分析

1. **看 center latestIds**  
   进入消息中心后，公告/点赞/回复/@ 的 latestId 是否都 >0。若为 0，说明接口没返回或 first 为空。

2. **看点入口时是否 mark**  
   点「站内公告」等时，是否有 `[Read] center markOnTap ... latestId=xxx`。若频繁出现 `latestId=0 skip`，说明点得太早，`_latestIds` 还没被 _checkUnreadStatus 填上。

3. **看 hasUnread 的入参与结果**  
   `latestId`、`lastReadId`、`result`。若某 category 一直 `lastReadId=0` 且 `latestId>0`，说明从没写过或写错 key；若 `lastReadId` 有值但始终小于 `latestId`，说明写入的 id 比消息中心用的「最新 id」小（顺序/接口不一致或只写了子页一页的 max）。

4. **看子页 mark**  
   进入公告/点赞/回复/@ 列表后，是否有 `[Read] subpage category=xxx readUpToId=xxx`，且该 `readUpToId` 是否 ≥ 消息中心里同 category 的 latestId。若子页的 readUpToId 一直小于 center 的 latestId，就是「子页拿到的列表不是最新」或「排序不一致」导致。

---

## 五、后续改代码方向（看完日志再动）

- 若多为 **latestId=0 skip**：在消息中心等 _checkUnreadStatus 完成再允许点入口，或子页 mark 时用「当前页 max(id) 与 center 的 latestId 取 max」再写入（需把 center 的 latestId 能传到子页或通过共享状态）。
- 若 **lastReadId 一直小于 latestId**：统一「最新 id」来源——例如消息中心与子页都只用「getXxxList(1,1) 的 first.id」作为该 category 的 latestId，子页进入时用该值 mark（或子页首屏加载后用接口返回的 first.id 与 center 一致）；并确认服务端公告/点赞/回复/@ 列表均为 `Order("id DESC")` 且无缓存导致顺序不一致。
- 若 **lastReadId 从未变**：检查 markAsRead 的 key 是否与 hasUnread 一致，以及是否真的走到 markAsRead（无异常吞掉）。

先按第三节加日志，跑一遍「清数据 → 登录 → 进消息中心 → 依次点公告/点赞/回复/@ 并进入列表」，把 `[Read]` 相关日志抓出来再对照第四节分析，确定是哪一类问题后再改代码。
