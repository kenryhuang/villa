# Agent v2 紧凑上下文设计

## 目标

将 Agent 决策请求收敛为无兼容负担的纯 v2 协议，删除重复的旧版世界快照，并按角色向模型提供确定性的市场摘要。完整市场明细仍可通过只读工具按需查询，确保压缩上下文不会削弱 Agent 的真实决策能力。

本次范围只调整请求上下文和本地只读查询，不改变动作批量协议、世界资产结算、事件溯源、角色权限或远程 Provider 配置。

## 已确认问题

真实 Runtime 请求约为 254–257 KB。主要重复来自：

- `snapshot` 约 109 KB，内部重复包含角色、农场、建筑、市场和事件投影；
- `event_delta` 与 `own_event_delta` 各约 51 KB，内容相同；
- 市场数据同时出现在 `snapshot.market`、`snapshot.market_view` 和顶层 `market_view`；
- 公共世界、公共事件和已知角色同时出现在旧快照和 v2 投影中。

TypeScript Provider 只使用 v2 投影构造 `AgentContext`，不读取 `snapshot` 或 `event_delta`。旧字段没有决策价值。

## 协议调整

`DecisionRequest` v2 保留以下字段：

- 请求身份：`protocol_version`、`request_id`、`session_id`、`session_epoch`、`agent_id`；
- 触发与并发信息：`trigger`、`game_minute`、`world_revision`；
- 投影信息：`projection_schema_version`、`actor_context`、`active_role`、`goals`、`allowed_read_tools`、`allowed_command_tools`；
- 世界信息：`public_world_state`、`global_public_events`、`known_actors`、`own_event_delta`；
- 交互信息：`market_summary`、`market_view`、`interaction_view`、`agreement_view`；
- 对话请求可选字段：`dialogue_input`。

删除 `snapshot` 和 `event_delta`。Godot 不再生成或发送这两个字段，TypeScript 类型、解析器、共享 fixture 和测试同步删除。服务端发现这两个旧字段时返回 `legacy_request_fields`，不提供旧客户端兼容。

`own_event_delta` 是唯一的增量事件字段，其冻结、失败释放和成功确认语义保持不变。

## 市场上下文分层

每个请求同时包含两种市场表示：

### `market_summary`

这是发送给远程模型的紧凑、角色相关信息，由 Godot 根据权威市场状态确定性生成，不增加额外模型调用。

结构为：

```json
{
  "schema_version": 1,
  "role_id": "farmer",
  "generated_game_minute": 480,
  "overview": {
    "item_count": 72,
    "shortage_count": 4,
    "surplus_count": 3,
    "rising_count": 6,
    "falling_count": 2
  },
  "signals": [
    {
      "item_id": "carrot",
      "mid_price": 15,
      "base_price": 14,
      "stock_ratio_bps": 7200,
      "price_change_bps": 714,
      "reason_codes": ["owned_item", "crop_output", "shortage"]
    }
  ]
}
```

所有比例使用整数 basis points，避免浮点序列化差异。每条 signal 只携带决策所需的标量，不携带完整历史、深度结构或冗长描述。

### `market_view`

这是当前请求对应的完整、不可变市场明细，只保留在本地 Agent Service 的 `AgentContext` 中。它不进入远程模型的初始 user message。

以下读取工具继续查询完整 `market_view`：

- `inspect_market_item(item_id)`；
- `compare_market_items(item_ids)`；
- `inspect_market_depth(item_id)`；
- `inspect_price_history(item_id)`。

模型先依据 `market_summary` 判断关注对象，再通过读取工具获取精确状态。工具结果只返回请求商品，不回传整个市场。

## 摘要生成规则

摘要生成器接收 `agent_id`、`active_role`、NPC 当前资产、农场状态和完整市场快照，输出稳定排序的有限 signals。

公共计算规则：

- `stock_ratio_bps = stock * 10000 / target_stock`；
- `price_change_bps = (mid_price - base_price) * 10000 / base_price`；
- `stock_ratio_bps < 7500` 记为 `shortage`；
- `stock_ratio_bps > 12500` 记为 `surplus`；
- `price_change_bps >= 500` 记为 `rising`；
- `price_change_bps <= -500` 记为 `falling`；
- 信号按角色相关优先级、异常幅度绝对值、`item_id` 依次排序，确保相同世界状态产生相同摘要。

角色规则：

- 农民：优先背包中的种子和作物、已种植作物对应产物、当前可播种作物；再补充异常幅度最大的农业商品，总计最多 12 条。
- 商人：优先自身持仓、短缺、过剩、涨跌和 Agent 市场压力显著的商品；各类信号合并去重后最多 20 条。
- 探险家：优先背包补给、鱼类、稀有资源、样本及发现相关商品；再补充异常幅度最大的相关商品，总计最多 10 条。

若角色发生转换，立即按 `active_role` 使用新规则；不依赖 Agent 初始身份。空市场生成合法的零计数 overview 和空 signals。

## Provider 数据流

1. Godot Runtime 构造纯 v2 请求、完整 `market_view` 和角色化 `market_summary`。
2. Agent Service 校验两种市场字段并构造完整 `AgentContext`。
3. Provider 构造初始 user message 时复制上下文，但排除 `market_view`，只包含 `market_summary`。
4. 模型可调用市场只读工具；工具在服务进程内查询完整 `market_view`。
5. 工具仅将匹配结果追加到后续消息；最终动作仍按现有 0–3 个批量动作协议返回。

调试窗口中的 `provider.input` 因此展示实际发送给远程 API 的紧凑摘要，而非完整市场。Agent session trace 继续按一次完整 input/response 保存，不恢复 delta 级持久化。

## 大小和安全边界

- 删除旧字段后，当前积压场景的本地请求预计从约 250 KB 降至约 90 KB；
- 成功确认事件后，常态本地请求预计约 40 KB；
- `market_summary.signals` 有严格角色上限，不随商品目录无限增长；
- 完整 `market_view` 仍受 Agent Service 的 1 MiB 总请求上限保护；
- API key 只存在于 Agent Service 配置和 Authorization header，不进入任何摘要、trace 或工具结果。

本次不改变 `own_event_delta` 的事件压缩策略。若事件积压仍使请求持续增长，后续单独设计事件字节预算与确定性摘要，避免在本次协议清理中混入另一种可靠性语义。

## 错误处理

- 请求包含 `snapshot` 或 `event_delta`：HTTP 400，`legacy_request_fields`；
- 缺少或非法 `market_summary`：HTTP 400，`invalid_market_summary`；
- 缺少或非法 `market_view`：HTTP 400，`invalid_market_view`；
- 未知角色：沿用 `Unknown role` 拒绝；
- 市场工具查询摘要未覆盖的商品：允许，只要商品存在于完整 `market_view`；
- 查询不存在商品：返回 `{ "found": false }`，不允许模型捏造行情。

## 测试与验收

Godot 测试覆盖：

- `make_decision_request` 不再生成旧字段；
- Runtime 请求包含 `market_summary` 和完整 `market_view`；
- 三种角色在同一市场状态下产生不同且稳定的 signals；
- 转职后摘要立即切换规则；
- 空市场和零库存不会除零或产生非法数值；
- 实际 Runtime 请求显著小于删除前的约 250 KB。

TypeScript 测试覆盖：

- 纯 v2 fixture 可解析；
- 旧字段被明确拒绝；
- 缺少/错误摘要被拒绝；
- Provider 初始 input 包含 `market_summary` 且不包含 `market_view`；
- 四个市场读取工具仍能查询完整市场数据；
- Runtime 尺寸请求继续低于服务请求上限。

连接验收继续使用真实 Runtime 集成测试，验证 Godot → Gateway → Agent Service → OpenAI-compatible Provider → v2 intent 完整链路。
