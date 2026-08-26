# Agent 流式决策、对话与调试会话设计

日期：2026-08-26  
分支：`feature/painted-production-buildings`

## 1. 目标

将当前必须等待完整 `/chat/completions` 响应的 Agent 调用改为端到端流式处理，让玩家和开发者能够立即看到请求已经开始，并在 Provider 生成期间持续获得反馈。

本次交付包括：

- 新增向后兼容的流式决策接口，不移除现有同步接口。
- 在独立 Agent 调试窗口中实时展示 Provider 的原始 `input`、`reasoning_content` 和 `output` 记录。
- Agent 对话文本增量进入对话框，避免等待完整响应时界面无反馈。
- 完整工具调用仍须在流结束后通过协议、角色权限、参数和世界 revision 校验，才允许修改世界资产。
- 调试记录默认只保存在内存；显式配置后，以 NDJSON 实时追加到本地文件。

## 2. 非目标与安全边界

- 不将 reasoning 展示在普通 HUD、右侧消息面板或玩家对话框中。
- 不根据半完成的工具名或参数提前执行动作。
- 不让 Godot 直接解析不同 Provider 的私有 SSE 格式。
- 不将调试 trace 混入 NPC 长期记忆、SQLite Agent 记忆或游戏存档。
- 不记录或传输 Provider API Key、Authorization 请求头等凭证。
- 本期不实现流断点续传；中断后必须使用新 `request_id` 发起新决策。

## 3. 方案选择

### 3.1 选择 SSE

采用 Server-Sent Events，而不是 NDJSON 分块响应或 WebSocket：

- SSE 是 OpenAI-compatible 流式响应的事实标准，TypeScript 侧转换成本最低。
- 当前链路只有服务端向 Godot 持续输出，WebSocket 的双向常连接能力没有必要。
- SSE 有明确的事件类型、事件 ID 和 heartbeat 约定，比裸 NDJSON 更容易诊断代理缓冲与断线问题。

Godot 内置 `HTTPRequest` 只在请求结束后交付完整正文，因此新增基于 `HTTPClient` 的增量客户端。远程 Provider 协议只在本地 TypeScript 服务内处理；Godot 只消费项目定义的稳定 SSE 事件。

### 3.2 兼容策略

保留现有：

```http
POST /v1/agents/{agent_id}/decide
```

新增：

```http
POST /v1/agents/{agent_id}/decide/stream
Accept: text/event-stream
Content-Type: application/json
```

两条接口共享相同的请求校验、上下文构建、Provider adapter、最终 ActionIntent 解析、幂等存储和记忆写入逻辑。旧接口可以内部收集同一个流式 Provider 结果后一次性返回，避免维护两套决策实现。

## 4. 端到端架构

```text
Godot AgentRuntime
    ↓ POST /v1/agents/:id/decide/stream
TypeScript Agent Service
    ↓ OpenAI-compatible request, stream: true
Remote Provider
    ↓ Provider-specific SSE chunks
Provider stream decoder + AgentStreamAssembler
    ↓ project-owned SSE events
Godot AgentStreamClient
    ├─ input/reasoning/output → AgentDebugWindow
    ├─ content.delta → DialogueUI（仅 dialogue trigger）
    └─ decision.final → validator → executor → world mutation
```

职责边界：

- `OpenAICompatibleProvider` 只负责远程 HTTP、Provider SSE 解码和 Provider 字段兼容。
- `AgentStreamAssembler` 负责按 tool-call index 重组 reasoning、content、工具名和参数，并生成最终 Provider 输出记录。
- Service 路由负责项目 SSE envelope、连接生命周期、幂等和记忆提交。
- `AgentStreamClient.gd` 负责连接、逐帧读取、项目 SSE 解析、sequence 校验、取消和静默超时。
- `AgentRuntime` 负责把流事件路由给调试 trace、对话 UI 和最终动作执行器。
- `AgentSessionTrace.gd` 负责内存上限和可选本地 NDJSON。
- `AgentDebugWindow` 与 `DialogueUI` 只负责展示，不执行世界写入。

## 5. Provider 流解析

远程请求设置：

```json
{
  "stream": true,
  "tool_choice": "auto"
}
```

`tool_choice` 保持 `auto`，兼容不允许 thinking mode 使用 `required` 的 OpenAI-compatible Provider。本地最终校验仍要求一个且只能有一个角色允许的工具调用，因此 Provider 的自动选择不会放松世界写入权限。

Provider decoder 使用流式 `TextDecoder`，正确处理 UTF-8 字符跨 TCP chunk 拆分。它识别 SSE `data:` 行和 `[DONE]`，支持以下 delta：

- `delta.reasoning_content`：原样追加到 reasoning。
- `delta.content`：原样追加到 output content。
- `delta.tool_calls[index].id`。
- `delta.tool_calls[index].function.name`。
- `delta.tool_calls[index].function.arguments`。
- `finish_reason` 和最终 usage（Provider 提供时）。

空 reasoning 是合法情况。未知的非关键字段被忽略，不影响协议。非法 JSON、多个 choice、多个最终 tool call、工具参数无法解析或普通文本替代工具调用均产生稳定错误，不生成 ActionIntent。

## 6. 项目 SSE 协议

每个 JSON data envelope 都包含：

```text
protocol_version, stream_id, request_id, agent_id, sequence, timestamp_msec, payload
```

`sequence` 从 1 开始严格递增。事件按以下顺序发送：

1. `stream.started`：本地服务接受并验证请求。
2. `provider.input`：实际发送给 Provider 的 JSON body，不包含 HTTP 凭证。
3. `reasoning.delta`：Provider reasoning 原始文本增量，可出现多次。
4. `content.delta`：Provider 普通文本增量，可出现多次。
5. `tool_call.delta`：工具调用原始增量，可出现多次。
6. `provider.output`：重组后的原始 assistant message、finish reason 和 usage。
7. `decision.final`：通过服务端严格协议校验的 ActionIntent。
8. `stream.completed`：正常结束标记。

`reasoning.delta`、`content.delta` 和 `tool_call.delta` 可按 Provider 原始顺序交错，但 `provider.output` 必须在所有 delta 后，`decision.final` 只能出现一次。

流开始后的错误通过以下事件表达：

```text
event: stream.error
data: {"code":"provider_timeout","message":"...","retryable":true}
```

随后服务端关闭连接，并且不得发送 `decision.final`。响应头发送前的请求校验错误仍使用普通 HTTP JSON 错误。

等待 Provider 期间，服务端定期发送 SSE comment heartbeat。Godot 的 `timeout_seconds` 表示流静默超时；Provider 的总超时仍由服务端 `provider.timeout_ms` 控制。

## 7. 幂等、提交与取消

- 完成过的 `request_id` 请求流式接口时，服务端重放 `decision.final` 和 `stream.completed`，不再次调用 Provider。
- 同一 `request_id` 正在执行时，重复调用返回冲突，不附着到现有半完成流。
- 只有完整 Provider 输出成功转换为合法 ActionIntent 后，服务端才写入决策幂等记录和 Agent 记忆。
- Godot 只有收到 `decision.final`，并通过现有 `AgentActionValidator` 的角色权限、参数、revision 校验后，才调用 executor 修改世界。
- 流断开、Provider 错误、解析错误、超时、取消或 stale epoch 不产生世界写入。
- 切换存档、退出游戏、关闭当前 Agent 对话、同一 Agent 发起新请求时取消旧流。
- Godot 断开本地 SSE 连接时，TypeScript 使用 `AbortController` 中止对应远程 Provider fetch。

自主请求的 content 只进入 Agent 调试窗口；完成后的 speech 仍可沿用现有 `dialogue_ready` 行为。只有 `trigger == dialogue` 的 content delta 实时进入当前对话框。

## 8. Agent 调试窗口

窗口通过两种入口打开：

- `F8` 快捷键。
- 现有调试面板中的“Agent 调试”按钮。

窗口独立于右侧 HUD 消息流。左侧是最近请求列表，至少展示 Agent、trigger、开始时间、耗时和状态；右侧展示选中请求的三个原始区域：

- `Input`：完整 Provider 请求 JSON，不含 Authorization/API Key。
- `Reasoning`：实时追加的 `reasoning_content`。
- `Output`：普通 content、原始工具调用及最终 ActionIntent。

窗口支持实时追加、自动滚动、选择历史请求和清空当前内存记录。关闭调试窗口不会取消 Agent 请求，也不会清空 trace。内存最多保留最近 100 个 Agent 请求，超出后从最旧请求开始淘汰。

## 9. 对话流式体验

玩家发起 Agent 对话后立即打开现有对话框并显示等待状态。首个 `content.delta` 到达时移除等待状态，之后直接增量追加原始 content。reasoning 和工具参数永远不进入玩家对话。

对话关闭时取消该 dialogue stream。流失败、超时或被取消时，不把半截 content 作为正式对话记录；如果对话框仍打开，显示稳定的本地回退文案。最终工具动作仍等待 `decision.final` 后执行。

## 10. 客户端配置与本地会话日志

Godot 客户端配置增加字段：

```json
{
  "enabled": true,
  "service_url": "http://127.0.0.1:8787",
  "token": "",
  "timeout_seconds": 10,
  "store_agent_session": false
}
```

`store_agent_session` 必须是 bool，缺省值为 `false`。示例配置和本地配置都包含该字段，旧配置缺少该字段时按 `false` 迁移，不导致 Agent 服务禁用。

当值为 `false`：

- trace 只存在于当前 Godot 进程内存。
- 退出游戏后清空。

当值为 `true`：

- Godot 将每个已解析的项目 SSE 事件立即追加到 `user://agent_sessions/<session-id>-<timestamp>.ndjson`。
- 每行是一个完整 JSON 事件；每次 append 后刷新，使异常退出前已收到的事件尽量保留。
- 自动保留最近 20 个游戏会话文件并删除更旧文件。
- 文件名只使用安全化 session ID 和时间戳，不接受服务端路径。

磁盘 trace 不进入 Git、世界存档、Agent SQLite 或 NPC 记忆。API Key 和 Authorization 永不写入；由于 input 可能包含玩家对话和世界快照，该开关只用于本地调试。

## 11. 错误处理与资源限制

- Provider 在本地 SSE 响应头发送前失败时返回普通 HTTP 错误；之后失败使用 `stream.error`。
- Godot 拒绝未知事件、缺失 envelope 字段、sequence 回退、重复 final 和 completed 后继续发送数据。
- UTF-8、SSE 行和 JSON 可以跨网络 chunk，解析器必须保留未完成缓冲区。
- 单个事件、单次 reasoning、完整 output 和总请求设置明确大小上限；超限使用稳定错误关闭流。
- 调试 UI 每帧合并文本更新，避免每个 token 都触发布局重建。
- heartbeat 只更新连接活跃时间，不进入调试记录或 NDJSON。
- 磁盘写入失败只关闭本地 trace 持久化并发布一次调试警告，不取消 Agent 决策或影响世界存档。

## 12. 测试与验收

### TypeScript

- 可编程假 Provider 分块发送中文 UTF-8、reasoning/content 交错、工具名和参数拆分。
- 验证 `[DONE]`、finish reason、usage、heartbeat 和严格事件顺序。
- 验证非法 JSON、半截参数、多个工具、普通文本命令、Provider 4xx/5xx、超时和客户端断开。
- 验证断开会触发 AbortController，失败不会写幂等结果或 Agent 记忆。
- 验证旧 `/decide` 行为保持兼容。

### Godot

- 使用本地假 SSE 服务验证跨帧、跨 UTF-8 字符和跨行解析。
- 验证 sequence、未知事件、重复 final、静默超时和取消。
- 验证切换存档、退出、关闭对话和同 Agent 新请求会取消旧流。
- 验证只有 final ActionIntent 进入 validator/executor。
- 验证 F8 和调试面板按钮、请求列表、三个原始记录区和自动滚动。
- 验证 dialogue content 增量显示，reasoning 不进入对话框。
- 验证默认不落盘、开启后实时 NDJSON、无凭证、只保留最近 20 个会话文件。

### 真实 Provider 验收

使用本地配置的真实 OpenAI-compatible Provider：

- 请求开始后立即收到 `stream.started` 和 `provider.input`。
- Provider 生成时，调试窗口持续显示 reasoning；若 Provider 不提供 reasoning，流仍能正常完成。
- Agent 对话 content 逐步出现，主线程没有同步等待造成的卡顿。
- 工具调用完整重组并只执行一次；结果真实修改 Godot 权威世界资产。
- 取消对话或切换存档后，不再接受旧流 final，也不产生世界写入。

## 13. 完成标准

- 现有同步接口和测试保持可用。
- 新流式接口使用稳定、版本化、可测试的 SSE envelope。
- Agent 调试窗口可实时查看 input、reasoning 和 output 原始记录。
- 对话可以流式显示 content，不泄露 reasoning。
- 默认 trace 仅内存；配置开启后实时保存 NDJSON，并最多保留 20 个会话文件。
- 任意流式失败、取消或非法输出都不能修改世界资产。
- 自动测试和一次真实 Provider 流式验收均通过。
