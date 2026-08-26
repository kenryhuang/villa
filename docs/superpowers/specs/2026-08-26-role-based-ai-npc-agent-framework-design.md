# 角色化 AI NPC Agent 框架设计

日期：2026-08-26  
状态：已确认，待实施计划  
目标分支：`feature/painted-production-buildings`

## 1. 文档定位

本文为 `docs/detailed-design.md` 最后一节“AI NPC Agent 系统”的角色化落地设计，并取代尚未实施的 `2026-07-22-ai-npc-agent-system-design.md` 作为后续实现依据。

旧设计中的 Godot 权威、Agent Gateway、调度、工具验证和独立服务方向继续保留；本文补全以下内容：

- 农民、商人、探险家三种首批角色；
- 每个 Agent 独立的目标、Soul、工具集合、实时信息、记忆和初始资源；
- 可配置的真实 Provider；不实现模拟 Provider；
- 按游戏时间和事件驱动的决策周期；
- 不依赖视觉系统、但真实改变世界资产的行为执行；
- Agent Service SQLite 记忆与游戏存档检查点；
- 与现有 NPC、市场、种植、消息及每日经济模拟的兼容方案。

## 2. 目标与非目标

### 2.1 目标

1. Agent 能根据身份、Soul、目标、资源、记忆和实时世界信息进行对话与决策。
2. 不同角色只获得自己的工具集合和信息视图。
3. Provider 产生结构化动作意图；只有 Godot 可以验证并提交世界变化。
4. 农业、交易、探索和抽象建造在没有模型、动画、寻路的情况下也能真实改变权威数据。
5. 实时事件立即进入 Agent 的感知和短期记忆，但 Provider 调用受游戏时间、事件合并和预算控制。
6. 每个 Agent 的记忆相互隔离，可定期提取长期记忆，并随游戏存档恢复。
7. Provider 不可用、返回非法内容或动作过期时，游戏资产保持一致，游戏本身可以继续运行。

### 2.2 首期非目标

- 不为 Agent 行为制作角色动画、手持工具、场景寻路或建筑/作物视觉实例。
- 不让 Provider 直接控制 Node、修改存档或访问不在工具白名单中的世界数据。
- 不依赖 Provider 的远程会话保存记忆。
- 不实现模拟 Provider。自动化测试使用协议级假 HTTP 服务，不作为运行时 Provider。
- 不一次迁移全部现有 NPC；只启用阿禾、老李和学者林。
- 不在首期引入向量数据库；先使用 SQLite 结构化查询与 FTS5，保留 embedding 扩展接口。

## 3. 已有系统约束

- `SeasonSystem.REAL_SECONDS_PER_DAY = 300`，可活动的 18 个游戏小时对应约 300 秒现实时间；一个游戏小时约 16.7 秒。
- `MarketSystem` 已提供报价、原子买卖、库存、价格、历史和结算事件。
- `NpcEconomyState` 已是 NPC 金币与库存的权威数据，不应建立第二套 Agent 账本。
- `NpcEconomySystem` 当前按日驱动现有 NPC 的确定性经济行为。
- `EventBus` 已覆盖时间、市场、农作、库存、村民和探索等事件。
- `HUDMessageBus` 是所有 Agent 行为结果和错误提示的统一消息出口。
- `SaveManager` 已保存村民关系与 NPC 经济状态，需要扩展 Agent 世界数据和记忆检查点。

## 4. 核心原则与权威边界

采用“Godot 世界权威 + Agent Service 大脑”方案。

```text
Godot 时间 / 世界状态 / EventBus
              │
              ▼
WorldProjection + PerceptionInbox + AgentScheduler
              │ DecisionRequest
              ▼
Agent Service
Agent Registry → Context Assembler → Provider Adapter → Tool Runtime
       │                │                    │
       └──────── SQLite Memory ──────────────┘
              │ ActionIntent
              ▼
Godot ActionValidator → DomainExecutor → 权威世界提交
              │
              ├── EventBus / HUDMessageBus
              └── ActionOutcome → Agent Service / Memory
```

必须始终成立的不变量：

1. Godot 与游戏存档是土地、库存、金币、市场、建筑和探索知识的唯一事实源。
2. Provider 与 Agent Service 只能提出动作，不能直接写世界资产。
3. HUD 的成功消息只能在领域事务成功提交后发布。
4. 每次命令携带 `world_revision` 和 `idempotency_key`。
5. 同一幂等键重复到达时返回原结果，不再次扣款、播种或收获。
6. 视觉系统以后只表现权威数据，视觉失败不回滚或重复业务结果。

## 5. 主要组件

### 5.1 Godot 侧

| 组件 | 职责 |
|---|---|
| `AgentRegistry` | 加载 Agent 配置，建立 NPC 与 Agent 的映射和启用状态 |
| `AgentScheduler` | 根据绝对游戏分钟、角色节奏、事件优先级和并发限制派发决策 |
| `AgentGateway` | 调用 Agent Service，处理超时、取消、健康状态和协议错误 |
| `WorldProjectionBuilder` | 构建带 `world_revision` 的角色可见快照 |
| `AgentPerceptionInbox` | 订阅 EventBus，按角色过滤、合并并保存尚未消费的事件 |
| `AgentActionValidator` | 验证工具权限、Schema、revision、资源所有权和领域前置条件 |
| `AgentActionExecutorRouter` | 将动作路由到农业、市场、探索、建造或交互执行器 |
| `NpcActivitySystem` | 保存和推进旅行、建造等耗时活动，在完成分钟提交最终结果 |
| `AgentCheckpointCoordinator` | 在存档/读档时协调世界状态和 Agent Service 记忆检查点 |

### 5.2 Agent Service 侧

| 组件 | 职责 |
|---|---|
| `Agent Registry` | 加载 RoleDefinition 与 AgentProfile，维护版本和工具权限 |
| `Context Assembler` | 组合身份、目标、自身状态、全局投影、事件增量、记忆和预算 |
| `Provider Adapter` | 统一真实 Provider 的请求、结构化输出、工具调用、超时和用量 |
| `Tool Registry` | 注册带版本的只读工具和命令工具 Schema |
| `Agent Runtime` | 执行有限轮次的读取工具循环，并产生至多一个命令意图 |
| `Memory Service` | SQLite 分 Agent 存储事件、长期记忆、检索索引和检查点 |
| `Trace Store` | 记录决策 ID、延迟、用量、工具、结果和错误，不记录密钥 |

## 6. 角色与 Agent 数据模型

角色能力与具体人物分离：

- `RoleDefinition`：可复用的目标框架、工具白名单、信息订阅、节奏、资源类型和权限。
- `AgentProfile`：人物身份、Soul、个人目标权重、初始资源引用、关系、记忆命名空间和当前状态。

建议配置结构：

```json
{
  "agent_id": "farmer_ahe",
  "npc_id": "farmer_ahe",
  "role_id": "farmer",
  "display_name": "阿禾",
  "soul": {
    "traits": ["踏实", "耐心", "略保守"],
    "values": ["土地可持续", "粮食储备", "稳定收益"],
    "speech_style": "朴素、友善、简洁",
    "risk_tolerance": 0.3
  },
  "goal_weights": {
    "basic_reserve": 1.0,
    "crop_health": 0.9,
    "stable_profit": 0.7,
    "experiment": 0.3
  },
  "tool_collection_id": "farmer.v1",
  "schedule_policy_id": "farmer.v1",
  "resource_ledger_id": "farmer_ahe",
  "memory_namespace": "farmer_ahe"
}
```

### 6.1 农民：阿禾（新增）

- Soul：踏实耐心、略保守，重视土地和粮食储备，不盲目追逐短期高价。
- 目标优先级：基本储备 → 作物健康 → 稳定收益 → 高价值作物试验。
- 初始资源：500 金币；12 格专属抽象农田；谷物种子 8、胡萝卜种子 6、土豆种子 6；基础农作知识。
- 工具：查看地块、开垦、播种、收获、建造、购买、出售、交谈、等待。

### 6.2 商人：老李（复用）

- Soul：精明健谈、风险适中，追求利润但不愿让村庄关键商品断货。
- 目标优先级：保持偿付能力 → 获取利润 → 维持关键库存 → 经营关系。
- 初始资源：沿用现有 `NpcEconomyState`：800 金币、盐 8、谷物种子 6，以及现有储备和销售目标。
- 工具：市场快照、价格历史、查看库存、报价、购买、出售、提出交易、交谈、等待。

### 6.3 探险家：学者林（复用）

- Soul：好奇严谨、重视证据，愿意分享可靠发现，面对危险先准备。
- 目标优先级：保证安全 → 发现未知 → 验证样本 → 发布知识和交换成果。
- 初始资源：沿用现有 900 金币、金矿 2、水晶 1、蜂蜜蛋糕 1；新增绳索 2、面包 2，以及村庄、住所和溪流三个已知区域与私人发现日志。
- 工具：查看地图知识、准备补给、前往区域、勘察、采集样本、登记发现、出售标本、交谈、等待。

## 7. 信息投影与上下文

Agent 不接收完整场景树或全量内部状态。`WorldProjectionBuilder` 生成白名单投影，并按角色裁剪：

- 公共信息：绝对游戏时间、季节、天气、公开发现、公共事件、市场摘要。
- 自身信息：位置或抽象区域、忙碌状态、金币、库存、地块、建筑、关系、当前目标。
- 实时增量：上次成功决策后与该 Agent 相关的市场、农田、库存和探索事件。
- 角色信息：农民得到作物与地块，商人得到市场深度与价格历史，探险家得到已知区域、传闻和补给风险。

每次 Provider 上下文按以下顺序组装：

1. Identity / Soul；
2. 角色目标和个人目标权重；
3. 自身权威状态；
4. 全局公开投影；
5. 实时事件增量；
6. 与当前目标相关的私有记忆；
7. 当前角色可用的工具清单；
8. 轮次、超时、token 预算和 `world_revision`。

Provider 不承担持久会话。每次上下文都由 Agent Service 从权威快照与 SQLite 重新构建。

## 8. Provider 配置

运行时只接入真实 Provider，不提供模拟 Provider。首个适配器采用现有详细设计约定的 OpenAI-compatible 结构化工具调用协议；其他协议以后通过相同接口增加适配器。配置至少包括：

```json
{
  "provider": {
    "base_url": "https://provider.example/v1",
    "api_key": "replace-with-your-key",
    "model": "replace-with-your-model",
    "timeout_ms": 10000,
    "temperature": 0.4,
    "max_output_tokens": 1200
  }
}
```

约束：

- 服务从被 Git 忽略的 `services/agent-service/config/agent-service.local.json` 读取 Provider 配置，也可以通过 `--config` 指定其他 JSON 文件；不兼容环境变量配置。
- API key 只存在于 TypeScript 服务的本地配置文件中，不进入 Godot、仓库、存档、日志、trace 或 SQLite。
- 适配器必须返回统一结构化结果和用量信息。
- Provider 超时、限流、拒绝、无效 JSON 或非法工具调用均不得产生世界写入。
- 自动测试使用可编程的假 HTTP 端点验证协议、超时和错误处理；它不是运行时 Provider 实现。

## 9. 工具模型与协议

### 9.1 ToolDefinition

每个工具至少定义：

```text
name, version, kind(read|command), allowed_roles,
description, parameter_schema, result_schema,
preconditions, timeout, required_capabilities
```

工具分两类：

- `read`：可在一次决策中多次调用，仅查询 `DecisionRequest` 携带的不可变快照或 SQLite 记忆。首期不建立 Agent Service 反向调用 Godot 的 HTTP 接口；快照必须一次性包含该角色本周期可能查询的全部权威数据。
- `command`：产生 `ActionIntent`，本次决策立即结束；每个决策周期最多一个命令。

首期默认限制为最多 3 个 Provider 推理轮次、6 次只读工具调用、1 个命令工具。这样避免在同一旧快照上生成长动作链。命令结果会作为新事件进入下一次决策。

### 9.2 主要消息

`DecisionRequest`：

```text
session_id, agent_id, trigger, game_time, world_revision,
snapshot, event_delta, budget, dialogue_input?
```

`ActionIntent`：

```text
decision_id, agent_id, tool_name, tool_version, arguments,
expected_revision, idempotency_key, speech?, decision_summary
```

`ActionOutcome`：

```text
decision_id, idempotency_key, status(accepted|in_progress|completed|rejected|failed), failure_code,
committed_revision, changed_entities, resource_delta,
hud_message, game_time
```

`decision_summary` 只保存简短可审计理由，不要求或存储隐藏推理过程。

## 10. 调度与实时事件

### 10.1 时间模型

调度使用绝对游戏分钟而非现实计时器，以支持暂停、倍速、调试推进、存档和读档。

| Agent | 常规决策 | 事件提前唤醒 |
|---|---|---|
| 阿禾 | 清醒时每游戏小时 | 成熟、灾害、种子不足、库存不足、季节变化 |
| 老李 | 每 1–2 游戏小时，按市场活跃度调整 | 显著价格变化、关键短缺、交易结算 |
| 学者林 | 每 2–4 游戏小时，按任务阶段调整 | 新传闻、区域开放、补给危险、待验证发现 |
| 对话 | 立即，最高优先级 | 玩家点击 NPC |

### 10.2 事件收件箱

`AgentPerceptionInbox` 订阅 EventBus，并执行：

1. 按 Agent 角色和可见性过滤；
2. 附加事件来源、游戏时间与 `world_revision`；
3. 同商品、同地块和同区域事件合并；
4. 计算紧急度与显著变化；
5. 将事件追加到 Agent Service 短期事件表；
6. 到达节奏或事件阈值时唤醒 Agent。

市场小幅波动只进入下一次上下文；不会每个价格信号调用一次 Provider。

### 10.3 并发、时间跳跃与过期

- 单 Agent 同时最多一个请求；请求期间的新事件设置 `pending`，完成后再决定是否补发。
- 全局 Provider 并发数可配置，默认 2。
- 睡觉或调试推进跨过多个周期时，每个 Agent 只执行一次汇总补算，不补发所有漏掉的小时。
- 动作 revision 过期时拒绝写入；可恢复错误使用新快照重新排队。
- Provider 失败时不运行旧版随机动作，也不修改资产；Agent 暂停到下一个允许周期。

## 11. 独立记忆系统

### 11.1 存储层级

每个 Agent 在 SQLite 中使用独立命名空间：

1. `raw_events`：对话、动作结果、资源、市场、发现和失败的不可变原始事件。
2. `memory_candidates`：经确定性重要度规则选出的候选事件。
3. `long_term_memories`：Provider 从候选事件压缩出的结构化长期记忆。
4. `memory_links`：长期记忆与原始事件、人物、商品、地块、区域和目标之间的关联。

### 11.2 重要度与提取

规则评分考虑：

- 对当前目标的影响；
- 资源变化幅度；
- 关系变化；
- 新发现和新颖度；
- 风险、失败及异常；
- 与已有事件的重复度。

达到以下任一条件时请求 Provider 压缩：

- 游戏日结束；
- 某 Agent 累计 20 条候选重要事件。

Provider 失败时保留原始事件和候选队列，下次继续，不丢失记忆来源。

长期记忆结构包含：

```text
summary, facts, confidence, impact, importance,
entities, tags, source_event_ids, validity,
created_game_time, supersedes?
```

长期记忆必须引用原始事件。新事实纠正旧认知时，将旧记忆标为 `superseded`，不直接删除，以保留认知变化轨迹。

### 11.3 检索

首期使用 SQLite 结构化过滤与 FTS5，按目标相关性、实体、标签、近期性、重要度和可信度排序。只向上下文提供少量最相关记忆。

私有记忆默认不可被其他 Agent 直接检索。需要共享的发现先由 Godot 验证并写入全局知识，再通过公共投影传播。

## 12. 无视觉的真实世界执行

所有命令遵循：

```text
权限与 Schema 校验
→ revision / 资源 / 前置条件校验
→ 领域事务提交
→ EventBus
→ HUD 成功消息
→ ActionOutcome
→ Agent 记忆
```

### 12.1 农民领域执行

- 开垦：将阿禾专属抽象地块从未开垦更新为可种植。
- 播种：真实扣除种子，写入作物类型、播种时间和成熟时间。
- 收获：只允许成熟作物；清空地块，将产物加入阿禾的 `NpcEconomyState.inventory`。
- 建造：扣除所需资源，在 `NpcBuildingRegistry` 登记建筑，不实例化视觉模型。
- 买卖：复用 `MarketSystem` 原子接口购买种子、出售作物。

### 12.2 商人领域执行

- 报价和价格历史为只读工具，不锁定价格。
- 买卖复用 `MarketSystem` 原子事务，直接更新老李的现有金币和库存。
- 交易提议建立 `pending interaction`；玩家明确接受后才允许修改玩家资产。
- 每次成交同步市场库存、价格历史、EventBus 与双方记忆。

### 12.3 探险家领域执行

- 前往区域：创建带目标区域和 `complete_at_game_minute` 的耗时活动，不要求寻路；到期时由 `NpcActivitySystem` 提交当前位置变化并发布完成结果。
- 勘察：由 Godot 世界种子、区域定义和确定性规则产生结果；模型不能编造可获得资产。
- 采集样本：验证区域资源后加入学者林的 NPC 库存。
- 私人发现：先写入 `ExplorerKnowledgeRegistry` 的个人知识。
- 登记发现：验证后写入全局知识，供其他 Agent 和系统感知。

旅行和建造属于耗时命令：首次提交返回 `in_progress`，保存已消耗或预留的资源和完成分钟；`NpcActivitySystem` 到期后在新事务中返回 `completed` 或 `failed`。Agent 忙碌期间仍可对话，但不能开始冲突的命令。播种、收获和市场交易为即时命令。

### 12.4 新增权威数据

- `NpcFarmRegistry`：NPC 农场、地块和作物状态。
- `NpcBuildingRegistry`：NPC 抽象建筑记录和效果状态。
- `ExplorerKnowledgeRegistry`：私人发现、验证状态和公共知识。
- `NpcActivitySystem` 状态：进行中的耗时活动、资源预留、完成分钟和最终结果。

这些数据全部由 Godot 保存。NPC 金币和库存继续复用 `NpcEconomyState`。

## 13. 对话与交互

玩家点击启用 Agent 的 NPC 时：

1. 创建最高优先级对话请求；
2. 注入玩家输入、Soul、目标、关系、相关记忆和最新世界状态；
3. Provider 返回 `speech`，必要时附带一个安全的命令意图；
4. 对话文字显示在现有对话界面；真实动作结果显示在右侧消息面板；
5. 对话及其结果写入该 Agent 的事件和记忆。

需要玩家同意的交易、赠予或任务只能创建 `pending interaction`，不能由模型直接扣除玩家资产。玩家文本视为不可信输入，不能修改工具白名单、系统目标或安全规则。

未启用 Agent 的 NPC 继续使用现有对话逻辑。Agent Service 不可用时，启用 Agent 的 NPC 显示简短不可用提示，不执行资产动作。

## 14. HTTP API

首期服务接口：

| 方法 | 路径 | 用途 |
|---|---|---|
| `GET` | `/health` | 服务、数据库和 Provider 配置健康状态 |
| `POST` | `/v1/sessions/sync` | 创建或恢复会话，声明世界 revision 与 Agent 配置版本 |
| `POST` | `/v1/agents/:id/decide` | 常规、事件或对话决策 |
| `POST` | `/v1/agents/:id/outcomes` | 回传验证/执行结果并写入记忆 |
| `POST` | `/v1/checkpoints/export` | 生成与世界 revision 对应的 SQLite 在线备份 |
| `POST` | `/v1/checkpoints/import` | 读档时恢复记忆检查点 |

协议使用共享 JSON Schema 版本。未知字段可忽略，缺少必填字段或主版本不兼容必须显式拒绝。

## 15. 存档、读档与迁移

### 15.1 存档

1. 暂停派发新决策；
2. 增加 `session_epoch`，在超时内等待或取消在途请求；旧 epoch 的迟到响应一律丢弃；
3. 固定当前 `world_revision`；
4. 请求 Agent Service 使用 SQLite 在线备份导出 sidecar；
5. 在游戏存档中写入 checkpoint ID、revision、schema version 和校验和；
6. 将世界存档、记忆 sidecar 和 manifest 写入新的存档 generation，校验成功后只原子切换 slot manifest 指针，再恢复调度。

记忆检查点失败不应破坏世界存档。保留上一次成功检查点，HUD 给出记忆可能回退的警告。

### 15.2 读档

先恢复 Godot 世界，再导入相应记忆检查点并发送最新世界同步。检查点缺失、损坏或版本不可迁移时：

- 不阻止世界读档；
- 为各 Agent 创建空记忆库；
- 从当前世界重新开始感知；
- 发布清晰警告并记录 trace。

旧存档首次升级时，以 Agent ID 和迁移标记幂等创建新增资源，避免重复发放金币、种子或地块。

## 16. 与现有经济和 NPC 的兼容

- 老李和学者林标记为 `agent_managed` 后，跳过当前 `NpcEconomySystem.simulate_day()` 中的自主购买、生产和出售，避免被两套系统重复操作。现有系统尚无独立的被动日常消耗阶段；以后增加该阶段时，可以继续对 Agent-managed NPC 生效。
- 二者继续复用原 `NpcEconomyState`，并正常参与市场结算和公共需求变化。
- 阿禾新增独立的 `NpcEconomyState`、NPC 配置和农田数据。
- 其他 NPC 保持现有确定性每日经济逻辑。
- `npc.gd` 的可视移动和日程首期保持原样；Agent 的抽象状态是业务状态，后续视觉层再订阅并表现。
- 对启用 Agent 的 NPC，现有点击对话入口改路由到 Agent；其他 NPC 不变。

## 17. 一致性、降级与安全

| 情况 | 行为 |
|---|---|
| 重复 `idempotency_key` | 返回原结果，不重复执行 |
| revision 过期 | 拒绝写入，必要时刷新快照后重排 |
| 资源不足或前置条件失效 | 返回结构化领域失败，不产生部分变化 |
| 事务中途失败 | 回滚，不发布成功 HUD |
| Provider 无合适动作 | 合法返回 `wait` 或仅 `speech` |
| Provider 超时或结构错误 | 不写世界，记录错误并等待下周期 |
| Agent Service 离线 | Agent 暂停；游戏、市场和非 Agent NPC 继续运行 |

额外安全要求：

- 所有输入按 JSON Schema 严格验证；
- 工具权限由服务与 Godot 双重检查；
- 参数限制数量、价格、目标 ID 和字符串长度；
- Provider 密钥和 Authorization 头不记录；
- trace 对玩家文本和 Provider 原文应用可配置脱敏与保留期；
- 设置每 Agent、每游戏日和全局调用预算。

## 18. 工程落点

```text
scripts/ai_agent/
  agent_registry.gd
  agent_scheduler.gd
  agent_gateway.gd
  world_projection_builder.gd
  agent_perception_inbox.gd
  agent_action_validator.gd
  agent_action_executor_router.gd
  agent_checkpoint_coordinator.gd

scripts/systems/
  npc_activity_system.gd
  npc_farm_registry.gd
  npc_building_registry.gd
  explorer_knowledge_registry.gd

data/agents/
  roles/
  profiles/
  tool_collections/
  schedule_policies/

services/agent-service/
  src/api/
  src/agents/
  src/context/
  src/providers/
  src/tools/
  src/memory/
  src/checkpoints/
  src/tracing/
  tests/
```

## 19. 实施切片

所有切片共同构成首个可交付版本；其中行为结果必须真实写入权威世界，只是暂不表现视觉。

### Slice 1：协议与服务基础

- 共享 Schema；
- Agent Service HTTP 服务；
- 可配置真实 Provider adapter；
- Agent Registry 和 Tool Registry；
- SQLite 原始事件与基础记忆；
- 健康检查、trace 和假 HTTP 协议测试。

### Slice 2：Godot Agent 主循环

- 三名 Agent 配置；
- Gateway、Scheduler、PerceptionInbox、WorldProjection；
- 角色节奏、事件合并、并发和降级；
- 启用 Agent 的对话路由；
- HUD 行为与错误消息。

### Slice 3：无视觉真实行为

- 农田、建筑和探索知识权威数据；
- 农业、市场、探索和建造执行器；
- 事务、幂等、revision 与 ActionOutcome；
- `agent_managed` 经济隔离；
- 真实资产变化集成测试。

### Slice 4：长期记忆与存档

- 规则重要度与 Provider 压缩；
- FTS5 检索和认知修正；
- SQLite sidecar 检查点；
- 存档迁移、恢复和损坏降级；
- 长时间运行与时间跳跃验证。

## 20. 测试与验收

### 20.1 自动化测试

- 共享 Schema 和序列化契约测试；
- Provider adapter 使用假 HTTP 服务测试成功、超时、限流、非法 JSON 和非法工具；
- Scheduler 的周期、事件防抖、优先级、单 Agent 串行和时间跳跃测试；
- Validator 的权限、参数、revision、资源和前置条件测试；
- Executor 的原子提交、回滚和幂等测试；
- Memory 的评分、压缩队列、来源追溯、检索、superseded 和隔离测试；
- checkpoint 导出、导入、校验和、损坏及旧存档迁移测试；
- Agent-managed NPC 不再运行旧日结自主行为的回归测试。

### 20.2 必须通过的端到端场景

1. 阿禾购买或消耗种子、开垦、播种、成熟、收获入 NPC 库存，再出售并改变市场。
2. 老李感知价格或短缺，完成交易后金币、库存和市场状态原子一致。
3. 学者林准备补给、抽象旅行、勘察、采样并把验证发现发布到全局知识。
4. 三名 Agent 的对话符合 Soul、目标和个人记忆，且不泄露他人私有记忆。
5. Provider 超时、非法输出、重复请求、资源不足和过期 revision 均不产生错误资产变化。
6. 调试时间跳跃只触发一次汇总决策；存档/读档恢复匹配的世界与记忆检查点。
7. HUD 只在提交成功后显示成功动作，例如“阿禾收获胡萝卜 ×4，已进入库存”。
8. 日志能关联 decision、tool、outcome、延迟和用量，且不包含密钥或敏感头。

真实 Provider smoke test 必须显式配置和启动，不作为默认 CI 前提。

## 21. 已确认的关键决策

1. 使用可配置真实 Provider，不实现模拟 Provider。
2. 老李作为商人、学者林作为探险家，新增农民阿禾。
3. 记忆由 Agent Service 的 SQLite 分 Agent 存储，并随游戏存档检查点恢复。
4. 记忆先由规则筛选，再由 Provider 定期压缩；失败保留原始重要事件。
5. 调度采用角色分级周期与事件提前唤醒。
6. Godot 是唯一世界权威。
7. 行为不要求调用视觉系统，但结果必须真实改变世界资产。
8. Provider 每周期最多提出一个命令，命令由 Godot 验证并原子执行。
