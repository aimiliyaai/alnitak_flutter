# 消息已读状态服务端 API（公告/点赞/回复/@）

客户端已读状态原先只存本地（SharedPreferences），清数据或换设备后红点会复现。需要服务端持久化以下两个接口，供客户端同步。

## 1. 获取已读进度（拉取，用于清数据后恢复）

- **方法/路径**: `GET /api/v1/message/readStatus`
- **鉴权**: 需要登录（与现有消息接口一致）
- **响应**（示例）:
```json
{
  "code": 200,
  "data": {
    "announce": 123,
    "like": 456,
    "reply": 789,
    "at": 100
  }
}
```
- 含义: 各分类「最后已读到的消息 ID」。未读过可省略该 key 或传 0。
- 分类与现有接口对应: announce=公告, like=点赞消息, reply=回复消息, at=@消息。

## 2. 上报已读进度（写入）

- **方法/路径**: `POST /api/v1/message/readStatus`
- **鉴权**: 需要登录
- **请求体**:
```json
{
  "category": "announce",
  "readUpToId": 123
}
```
- `category`: 仅限 `"announce"` | `"like"` | `"reply"` | `"at"`。
- `readUpToId`: 该分类下用户已读到的最大消息 ID（客户端用当前列表页 max(id) 上报）。
- **响应**: `code: 200` 表示成功；服务端按用户维度持久化各 category 的 readUpToId（覆盖式更新即可）。

## 客户端行为简述

- 用户点开公告/点赞/回复/@ 列表并加载成功后，客户端会先写本地再调用 **POST readStatus** 上报当前页的 max(id)。
- 每次进入消息中心检查红点时，会先调 **GET readStatus**，若某分类服务端返回的 id 大于本地，则用服务端值更新本地，再算未读。这样清数据或换设备后，红点不会错误复现。

## 排查说明

- **服务端看不到「消息已读」相关日志**  
  客户端通过 `POST /api/v1/client/log` 上报，请求体含 `level`、`message`、`context`、`timestamp`。消息已读类日志使用 **level: "warn"**。请确认：  
  1) 服务端已注册并实现 `POST /api/v1/client/log`；  
  2) 处理该接口时会把内容打到日志（若 zap 等只打 Error，需改为至少打 Warn）。  
  Debug 包下若上报失败会在控制台打印 `[LoggerService] POST /api/v1/client/log failed: ...`。

- **清理数据后红点再次出现**  
  说明已读状态未在服务端持久化。必须实现上述 **GET** 与 **POST** `/api/v1/message/readStatus`，并按当前用户读写。未实现时 Debug 包会打印 `[MessageApi] getReadStatus failed` 或 `saveReadStatus failed`。
