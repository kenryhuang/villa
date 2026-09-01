# 事件溯源式多主体 Agent 经济系统设计

日期：2026-09-01
状态：待用户审阅
目标分支：`feature/painted-production-buildings`

## 1. 背景

当前 NPC Agent 已能定时决策、对话、种植、收获、探索并通过公共市场买卖，但行动空间仍受以下结构限制：

- 每轮虽包含市场快照，市场变化事件却只主动推送给商人老李；
- 上下文没有其他 Agent 和 Player 的公共主体投影；
- `role_id`、目标和工具集合在启动时静态合并，运行中不能改变身份；
- `propose_trade`、`speak` 仍是无权威结果的占位动作；
- Agent 间没有报价、协商、合作、承诺、关系变化或资源锁定；
- 买卖已经能改变公共市场，但私下交易与合作不能形成市场信号；
- 状态散落在 Registry、Runtime、NPC 经济、活动和市场系统中，继续直接扩展会使并发、存档和审计边界越来越模糊。

本设计采用事件溯源式 Agent 世界。Godot 继续拥有全部权威；TypeScript Agent Service 和远程模型只负责读取裁剪后的上下文并提出动作。

## 2. 已确认决策

1. Agent 与 Agent、Agent 与 Player 的交易采用两阶段协议。发起报价不会立即成交，接收方可以接受、拒绝或还价；Player 必须手动确认。
2. Agent 可以提出身份转换，但只能由 Godot 根据确定性条件审核。
3. 私下交易不直接增减公共市场库存，但公开报价、成交价格和成交量会形成供需压力，参与后续价格刷新。
4. Agent 只能看到 Player 的公开身份、位置、关系、公开行为和主动展示的交易资产，不能读取完整背包或金币。
5. Agent 彼此只能看到公共档案、区域、关系、可观察行为和公开交易；私有库存、金币、目标权重和记忆保持隔离。
6. 合作使用正式协议，跟踪参与者、承诺、行动、贡献、阶段、完成条件和收益分配。
7. Agent 始终只有一个当前主身份。转职替换专属目标和工具，但保留 Soul、关系、历史、记忆和通用能力。
8. 所有 Agent 都能看到市场价格、紧缺程度和趋势；商人额外获得成交量、历史、流动性和供需压力。
9. 交易、合作和紧急消息立即唤醒接收者；普通聊天进入收件箱，在下一决策周期处理。

## 3. 目标与非目标

### 3.1 目标

- 为 NPC Agent 和 Player 建立统一但受可见性约束的 Actor 模型。
- 让市场、其他 Agent、Player、关系、报价和合作状态进入 Agent 的实时上下文。
- 提供足够且按身份动态变化的读取工具与命令工具。
- 实现可协商、可过期、可回滚验证的双边交易。
- 实现多人合作协议和可验证的贡献、完成与收益分配。
- 实现受确定性规则约束的身份转换。
- 让 Agent 的公共交易和私下交易信号共同影响市场。
- 通过不可变事件记录获得可重放、可审计和存档安全的 Agent 世界。

### 3.2 非目标

- 不让 LLM 直接修改资产、关系、身份、市场价格或合作进度。
- 不让 Agent 读取其他主体的私有库存、金币、记忆或隐藏目标。
- 不在首期实现自由文本合同；所有交易和合作都必须符合结构化 Schema。
- 不为所有行为补充动画或寻路表现；视觉继续服从现有权威系统。
- 不把整个游戏改造成事件溯源。事件日志只覆盖 Agent 社会、Agent 发起的领域行为和用于感知的世界事实。
- 不实现 Agent 自动控制 Player，也不允许 Agent 代替 Player 接受交易或合作。

## 4. 权威边界与核心不变量

`AgentWorldEventStore` 是 Agent 社会状态的事实来源。现有 `MarketSystem`、Player 背包、NPC 农场和建筑仍是各自游戏领域的权威；Agent 命令只能通过领域事务适配器改变它们，并在同一个逻辑提交中记录已验证事件。

必须始终成立：

1. Provider 只能提出命令，不能声明命令已经成功。
2. 每个命令先读取当前投影并重新验证具体条件，不校验全局 `world_revision`。
3. 一个命令产生的事件批次要么全部提交并更新投影，要么全部失败。
4. 交易结算必须同时完成双方资产变化；合作结算必须同时完成全部收益分配。
5. LLM 不能直接写 `trust`、角色、能力、市场压力或协议完成状态。
6. 同一 `idempotency_key` 重复执行时返回原结果，不重复产生事件或资产变化。
7. 每个报价、合作与转职聚合拥有独立的 `aggregate_id` 和单调递增 `aggregate_version`。
8. LLM 不需要提供或猜测聚合版本。执行器在当前状态上校验；不满足条件时返回具体领域错误，并等待下一正常周期。
9. 只有成功提交的事件才能进入 EventBus、右侧消息栏和 Agent 长期记忆。
10. 对话内容、模型推理摘要和调试 trace 不是世界事实，不能单独驱动投影。
11. Agent 消息与 Player 文本一律作为不可信内容引用，不能覆盖系统指令、工具权限、可见性或领域规则。
12. Player 参与交易或合作时必须分别手动确认当前版本条款；Agent 不能代替 Player 接受或还价。

## 5. 总体架构

```text
时间 / Player 行为 / 市场 / 世界领域事件
                    │
                    ▼
             AgentWorldEventStore
                    │
           EventProjectorPipeline
          ┌─────────┼──────────────┐
          ▼         ▼              ▼
   ActorProjection  Interaction    MarketPressure
   RoleCapability   Agreement      Relationship
          └─────────┼──────────────┘
                    ▼
             AgentContextProjection
                    │
          AgentRuntime / Scheduler
                    │ DecisionRequest
                    ▼
       TypeScript Agent Service / Provider
                    │ 0–3 commands
                    ▼
            AgentCommandGateway
                    │
     validator → domain transaction adapters
                    │
                    └── committed event batch
```

主要组件：

| 组件 | 职责 |
|---|---|
| `AgentWorldEventStore` | 追加事件批次、分配全局序号、检查幂等键、保存聚合版本、导出与恢复日志 |
| `AgentCommandGateway` | 接收动作，检查当前能力、可见性、参数和前置条件，并协调领域事务与事件提交 |
| `AgentWorldProjector` | 按事件顺序更新全部确定性投影，支持从零重放 |
| `ActorProjection` | 保存 NPC Agent 与 Player 的公共身份、区域和可观察状态 |
| `RoleCapabilityProjection` | 保存当前角色、角色历史、目标、工具、调度策略、审核状态和转职冷却 |
| `InteractionProjection` | 保存消息、交易报价、还价、过期时间、参与者和资产锁定状态 |
| `AgreementProjection` | 保存合作条款、里程碑、承诺、贡献、完成条件和收益分配 |
| `RelationshipProjection` | 从已验证互动事件计算熟悉度、信任与合作记录 |
| `MarketPressureProjection` | 汇总公开报价、私下成交量、成交价格和未满足需求形成的市场信号 |
| `AgentContextProjection` | 依据观察者、角色、区域和可见性生成不可越权的决策上下文 |
| `AgentEventRouter` | 将新事件投递到相关 Agent 收件箱，合并普通事件并决定是否提前唤醒 |

## 6. 事件模型

### 6.1 事件信封

```json
{
  "event_schema_version": 1,
  "event_id": "evt-00001234",
  "global_sequence": 1234,
  "aggregate_type": "trade_offer",
  "aggregate_id": "trade-42",
  "aggregate_version": 3,
  "event_type": "TradeAccepted",
  "actor_id": "farmer_ahe",
  "game_minute": 2840,
  "command_id": "action-7",
  "idempotency_key": "v2:decision-9:action-7",
  "correlation_id": "trade-42",
  "causation_event_id": "evt-00001230",
  "visibility": {
    "scope": "participants",
    "actor_ids": ["farmer_ahe", "lao_li"]
  },
  "payload": {}
}
```

`global_sequence` 只用于稳定排序与重放，不用于拒绝正常动作。并发保护只作用于被修改的聚合和领域资源。

### 6.2 首期事件类别

- 主体：`ActorObserved`、`ActorRegionChanged`、`PublicStatusChanged`。
- 消息：`MessageSent`、`MessageDelivered`、`MessageAcknowledged`。
- 交易：`TradeProposed`、`TradeCountered`、`TradeAccepted`、`TradeRejected`、`TradeExpired`、`TradeCancelled`、`TradeSettled`。
- 资源：`AssetReserved`、`AssetReservationReleased`、`AssetTransferred`、`PublicMarketTradeExecuted`。
- 合作：`AgreementProposed`、`AgreementCountered`、`AgreementActivated`、`ContributionCommitted`、`ContributionVerified`、`MilestoneCompleted`、`AgreementCompleted`、`AgreementFailed`、`AgreementCancelled`。
- 身份：`RoleChangeProposed`、`RoleChangeApproved`、`RoleChangeRejected`、`RoleChanged`。
- 关系：`TrustAdjusted`、`FamiliarityAdjusted`。数值由规则产生，事件必须引用原因事件。
- 市场：`MarketQuoteObserved`、`MarketPressureRecorded`、`MarketPressureSettled`。
- 世界动作：沿用耕作、收获、探索、建造等结果事件，并附加参与协议和可见性信息。

### 6.3 批次提交

每个命令对应一个原子事件批次。例如接受并结算交易：

```text
TradeAccepted
AssetTransferred × N
AssetReservationReleased
TradeSettled
MarketPressureRecorded
TrustAdjusted
```

执行步骤：

1. 用当前投影验证命令和权限；
2. 在领域适配器中预检双方资产、容量、报价状态和整数溢出；
3. 创建候选事件批次；
4. 暂存 NPC、Player、市场和事件存储的事务状态；
5. 应用领域变化并追加事件；
6. 更新投影；
7. 任一步失败则恢复所有暂存状态，不发送成功通知。

Godot 主线程负责串行提交。异步 Provider 响应只进入命令队列，不能并行写世界。

## 7. Actor、身份与能力模型

### 7.1 Actor

NPC Agent 和 Player 使用统一公共标识：

```text
actor_id, actor_type(player|npc_agent), display_name,
public_role, region_id, observable_status, reputation_tags
```

Player 不是自治 Agent，不进入定时调度，也没有 Provider 会话；它只作为可感知主体、消息接收者、交易参与者和合作参与者存在。

### 7.2 动态身份

每个 Agent 始终只有一个 `active_role_id`。角色定义包含：

```text
goals, command_tools, read_tools, subscriptions,
schedule_policy, eligibility_rules, cooldown_hours,
public_title, retained_general_capabilities
```

Soul、个人记忆、关系、历史事件和通用工具在转职后保留。旧角色专属目标、工具、订阅和节奏立即失效。

### 7.3 转职流程

1. Agent 使用 `propose_role_change(target_role_id, motivation)`；
2. Godot 从当前投影读取目标角色规则；
3. 确定性检查资源、建筑、经验事件、关系、进行中的协议和冷却；
4. 通过时在一个批次中写入 `RoleChangeProposed`、`RoleChangeApproved`、`RoleChanged`；
5. 不通过时写入提议与带机器错误码的拒绝事件，不消耗资产；
6. 下一个请求使用新角色的目标、工具、订阅与调度策略。

进行中的旧角色决策如果在转职后到达，执行时按当前能力重新验证。失去权限的动作返回 `role_capability_changed`，不自动重试。

首期可转换角色仍为 `farmer`、`merchant`、`explorer`。资格规则使用配置文件，不写死在提示词中。

## 8. 感知、可见性与上下文

### 8.1 公共主体投影

每次请求包含 `known_actors`。Agent 可以看到其他主体的：

- 显示名称、公开身份和区域；
- 双方关系、共同协议和公开声誉标签；
- 可观察状态和近期公开行为；
- 已公开的交易与合作；
- 对方在当前报价中明确声明并锁定的资产。

默认不可见：完整库存、金币、隐藏目标、风险参数、私有记忆、未公开消息和内部决策摘要。

Player 额外遵守最小披露原则：只暴露位置、公开身份、关系、公开行为，以及 Player 在当前交互中主动填写的物品和金币上限。

### 8.2 市场投影

所有角色获得：

- 当前买价、卖价；
- 库存正常、偏低、紧缺或过剩状态；
- 近期价格方向和变化比例；
- 与自身持有物、目标、报价和合作相关的显著行情。

商人额外获得：

- 最近成交量与价格历史；
- 目标库存、每日流动性和可成交深度；
- 当前需求压力、供给压力、私下成交价格信号；
- 公开大宗报价、紧缺持续时间和商队信息。

### 8.3 上下文结构

```text
identity_and_soul
active_role_and_goals
current_capabilities
self_private_state
known_actors
relationships
market_view
active_offers
active_agreements
world_domain_view
recent_visible_events
relevant_long_term_memories
dialogue_input
```

`AgentContextProjection` 先执行可见性裁剪，再把结果发送给 Agent Service。Agent Service 不能通过读取工具绕过裁剪。

### 8.4 事件投递与唤醒

- 立即唤醒：报价、还价、合作请求、紧急求助、转职审核结果。
- 可提前唤醒：协议失败、承诺到期、重大行情变化、关键资源短缺。
- 下一周期处理：普通消息、公开行为、小幅行情变化。

同一商品、主体或协议的普通事件按最新状态合并。单 Agent 仍只允许一个在途 Provider 请求；新紧急事件设置 `pending_urgent`，当前请求结束后最多补发一次汇总请求。

## 9. 工具体系

工具分为 Agent Service 本地读取工具和 Godot 权威命令工具。

### 9.1 读取工具

读取工具只查询当前请求携带的不可变、已裁剪上下文：

- `inspect_market_item(item_id)`
- `compare_market_items(item_ids)`
- `inspect_known_actor(actor_id)`
- `inspect_relationship(actor_id)`
- `inspect_trade_offer(offer_id)`
- `inspect_agreement(agreement_id)`
- `inspect_role_option(role_id)`
- `inspect_self_resources(item_ids)`
- 农民：`inspect_farm_plots()`、`inspect_crop_options()`
- 商人：`inspect_market_depth(item_id)`、`inspect_price_history(item_id)`
- 探险家：`inspect_region(region_id)`、`inspect_known_discoveries()`

一次 Provider 决策最多执行 6 次读取工具调用。读取工具不产生 Godot 动作，不占最终 0–3 个动作名额，也不能读取上下文之外的数据。

### 9.2 通用命令工具

- `send_message(target_actor_id, text, urgency)`
- `propose_trade(target_actor_id, give, receive, expires_in_minutes, note)`
- `counter_trade(offer_id, give, receive, expires_in_minutes, note)`
- `accept_trade(offer_id)`
- `reject_trade(offer_id, reason_code)`
- `cancel_trade(offer_id)`
- `propose_cooperation(participants, objective_id, milestones, commitments, reward_split, deadline, note)`
- `counter_cooperation(agreement_id, revised_terms, note)`
- `accept_cooperation(agreement_id)`
- `reject_cooperation(agreement_id, reason_code)`
- `commit_contribution(agreement_id, contribution_id)`
- `cancel_cooperation(agreement_id, reason_code)`
- `propose_role_change(target_role_id, motivation)`
- `speak(target_actor_id, text)`
- `wait(reason)`

`speak` 表示同一区域内可观察的即时公开发言；`send_message` 表示进入指定接收者收件箱的异步消息。两者的文本都按不可信数据处理，不能携带新的工具权限或系统指令。

### 9.3 角色命令工具

- 农民：`till`、`plant`、`harvest`、`build`，以及通用买卖和协作工具。
- 商人：`buy`、`sell`、交易协商、合作组织和市场相关消息工具。
- 探险家：`prepare_supplies`、`travel`、`survey`、`collect_sample`、`register_discovery`、`sell`，以及通用协作工具。

工具白名单由 `RoleCapabilityProjection` 在每次请求中给出，Godot 执行时再次按当前角色检查。Agent Service 使用本地角色目录与 Godot 声明能力的交集，避免配置漂移放宽权限。

### 9.4 对话触发

对话仍然流式返回文字，但不再强制禁用全部工具。对话轮只开放交互型命令子集，可附带最多一个 `send_message`、交易或合作命令；不能在对话中顺手执行耕作、旅行、收获或市场投机。

最终自主决策继续返回 0–3 个有序命令。每个命令单独原子提交；失败或进入 `in_progress` 后停止执行后续命令，已成功的前序命令不回滚。

## 10. 双边交易

### 10.1 报价结构

```text
offer_id, proposer_id, recipient_id,
proposer_gives(items, gold), proposer_receives(items, gold),
status, created_game_minute, expires_game_minute,
parent_offer_id, reservation_ids, public_visibility
```

不允许同一边同时给予和接收同一种物品，不允许空报价、负数、零数量、未知物品、超过安全上限或自己与自己交易。

### 10.2 资源锁定

- 创建报价时锁定发起方承诺给出的 NPC 资产，避免重复报价或消费。
- 接收方资产在接受时验证并原子扣除，不提前锁定。
- Player 只在界面中主动声明可给出的资产；接受按钮点击时才验证并扣除。
- 还价会关闭旧报价、释放旧锁定，再为还价方创建新报价和锁定。
- 拒绝、取消、过期、读档回滚或参与者失效都会确定性释放锁定。

### 10.3 成交与市场影响

公共市场买卖继续即时改变市场库存和报价基础。

私下成交不改变公共库存，但会产生：

- 已成交品种与数量；
- 实际单位价格或以公共中间价折算的易货价值；
- 成交时公共参考价；
- 报价持续时间；
- 未满足的公开买入或卖出意向。

`MarketPressureProjection` 分别维护需求压力、供给压力、私下成交量和价格发现偏差。市场在现有刷新节点应用有上限的平滑影响：高于参考价成交推动价格上行，低于参考价成交推动价格下行；资产已锁定且仍有效的未成交买单增加需求压力，已锁定的未成交卖单增加供给压力。撤销、拒绝或过期会移除未成交压力。单个 Agent、单笔报价和单位游戏日都有影响上限，避免模型通过刷报价操纵市场。

## 11. 合作协议

### 11.1 协议结构

```text
agreement_id, objective_id, participants,
milestones, commitments, reward_split,
deadline, status, aggregate_version
```

`objective_id` 必须引用 Godot 配置中的合作模板，例如联合种植、批量供货、探索采样、材料筹集或建筑建设。LLM 可以选择模板和参数，不能发明完成判定代码。

### 11.2 生命周期

```text
proposed → negotiating → active → completed
                    └──→ failed / cancelled
```

- 所有参与者接受同一版本条款后才能激活。
- Player 是参与者时必须在结构化交互卡中手动接受当前条款版本；文本回复不能视为接受。
- 激活时锁定明确承诺的物品或金币；行动型承诺只记录责任，不预先伪造完成。
- 农作、交易、探索和建造结果可携带 `agreement_id`，投影器据此验证贡献。
- 里程碑和最终完成由确定性规则判断。
- 收益在完成事件批次中按整数规则分配；余数去向由模板明确指定。
- 到期、成员无法继续或关键承诺失败时，模板决定退款、部分结算或失败，无权由模型临时改写。

### 11.3 关系影响

关系由事件规则调整：履约、合理还价和成功合作提高信任；取消、到期不响应、承诺失败和恶意低价降低信任。每类事件有每日变化上限。Soul 可以影响 Agent 如何解释关系，但不能直接修改数值。

## 12. 身份转换规则

角色资格配置至少支持：

- 最低金币和必要物品；
- 必要建筑、区域知识或已验证事件；
- 最低关系、声誉或已完成协议数量；
- 不允许存在的冲突活动；
- 转职成本；
- 游戏时间冷却。

首期示例：

- 转为农民：拥有或获准使用农地，持有基础种子与农具能力。
- 转为商人：达到资本门槛，并至少完成若干真实交易。
- 转为探险家：拥有基础补给，解锁至少一个可前往区域。

通过审核后原子扣除转职成本并写入角色事件。公开身份立刻变化，旧身份相关的未激活报价或合作提议按规则重新校验；已经激活的合作不会自动取消，但 Agent 必须仍能履约，否则走协议失败流程。

## 13. 协议与 Agent Service

Godot 与 Agent Service 保持现有 Agent Protocol v2 的批量结果原则：最终允许 0–3 个有序动作，不兼容旧单动作格式。本次不再进行破坏性数据库清空。

DecisionRequest 增加或规范以下 v2 字段：

```text
projection_schema_version
actor_context
active_role
goals
allowed_read_tools
allowed_command_tools
market_view
interaction_view
agreement_view
recent_visible_events
```

Agent Service 的静态 profile 只保存 Soul 和稳定人物信息。当前角色、目标和能力以 Godot 请求为准，并与本地角色目录取权限交集。

Provider 循环分两阶段：

1. 最多 6 次本地读取工具调用；
2. 输出文字、简短 `decision_summary` 和 0–3 个 Godot 命令。

读取工具结果只来自本轮不可变上下文。对话采用同一上下文，但最终最多一个交互型命令。`reasoning_content` 只进入可选调试 trace，不进入事件日志或长期记忆。

## 14. 存档、重放与迁移

Agent Runtime 存档升级为下一版本并包含：

```text
event_schema_version
next_global_sequence
events
projection_checkpoint
checkpoint_sequence
idempotency_outcomes
```

- 事件永久按全局序号保存，检查点只用于加快加载，不能替代事件事实。
- 每 256 个事件或每个游戏日生成一次确定性投影检查点。
- 加载时验证事件 ID、序号、聚合版本、Schema、引用关系和检查点哈希；验证失败时整个存档加载失败，不部分应用。
- 正常加载从检查点恢复投影，再重放后续事件；测试必须能从零重放全部事件并得到相同状态。
- 旧 Agent Runtime v2/v3 存档通过一次 `AgentWorldBootstrapped` 迁移事件导入现有角色、NPC 资产、农场、建筑、活动和知识，不清空玩家存档或 Agent 记忆数据库。
- SQLite 记忆继续沿用现有检查点机制。新增世界事件以 `event_id` 写入记忆，重复上报不会产生重复记忆。

事件数量设置安全上限，超过配置阈值时禁止继续保存并给出明确错误；不静默截断历史。初期三个 Agent 的事件量可直接保留完整日志，后续再设计归档格式。

## 15. 错误处理

- Provider 不可用、超时或返回非法动作：不写事件、不修改世界，等待下一轮。
- 当前角色无工具权限：`role_capability_changed`。
- 报价已关闭或过期：`offer_not_open`。
- 发起方锁定资产不足：创建报价失败，不产生半成品报价。
- 接收方接受时资产不足：`recipient_resources_changed`，报价保持打开或按模板关闭；首期保持打开直到到期。
- Player 未确认：永远不结算 Player 资产。
- 合作版本已被还价替换：`agreement_terms_changed`。
- 贡献不符合模板：`contribution_not_applicable`。
- 转职条件不足：返回具体资格错误码并记录审核拒绝事件。
- 市场压力异常或超过上限：裁剪到配置上限并记录诊断事件，不允许直接设置价格。
- 投影器处理未知事件或重放不一致：停止加载或提交，不跳过事件。

领域失败不自动重试模型。事件进入下一次上下文，由 Agent 在正常调度、事件唤醒或对话中自行决定后续行动。

## 16. UI 与玩家交互

- NPC 名称和公开身份来自 `ActorProjection`，转职后实时刷新。
- 对话框保留流式文本和历史滚动。
- NPC 向 Player 发起交易或合作时，对话框显示结构化交互卡，列出双方资产、期限、合作条款和接受、拒绝、还价按钮。
- Player 只有点击确认后才提交命令；关闭对话框不会默认接受。
- 待处理交互在再次打开对话时仍可见，过期后显示已过期但不可操作。
- 交易完成、合作激活、贡献完成、转职和重大市场影响进入右侧消息面板。
- Agent 原始 input、流式 `reasoning_content`、output、命令和事件批次继续只显示在 Agent 调试窗口。

## 17. 实施阶段

本设计作为一个总体规格，实施按顺序拆成六个可独立验证阶段：

1. 事件存储、投影框架、幂等结果、存档和旧状态迁移。
2. Actor、关系、分层市场和多 Agent 事件路由。
3. 读取工具循环、动态能力上下文和 Agent Service 协议扩展。
4. 双边交易、资源锁定、Player 确认 UI 和市场压力。
5. 合作协议、贡献验证和收益结算。
6. 身份审核、动态工具切换、调度切换和完整重放验证。

每个阶段都必须保持可运行，不允许先写入无法重放的临时状态。

## 18. 测试与验收

### 18.1 Godot 单元测试

- 原子追加、批次回滚、幂等、聚合版本和全局顺序；
- 从零重放与检查点恢复结果完全一致；
- Actor 可见性矩阵不会泄漏 Player 或其他 Agent 的私有资产；
- 市场信息按普通角色和商人角色正确裁剪；
- 普通事件合并，紧急交互只补发一次唤醒；
- 报价创建、锁定、接受、拒绝、还价、取消、过期和释放；
- NPC↔NPC、NPC↔Player 交易资产原子性；
- 私下交易不改变公共库存，但能产生有上限的市场压力；
- 合作协商、激活、贡献、里程碑、完成、失败和收益分配；
- 转职成功、资格失败、冷却、工具失效和旧角色决策拒绝；
- v2/v3 旧 Agent 状态迁移且不丢失既有资产。

### 18.2 TypeScript 测试

- 动态角色、目标和工具上下文正确组装；
- 本地读取工具只能访问已裁剪快照；
- 最多 6 次读取调用，最终仍为 0–3 个命令；
- 对话最多返回一个交互型命令；
- 本地与 Godot 工具白名单取交集；
- 事件按可见性写入正确 Agent 的短期与长期记忆；
- 重复 `event_id` 不重复存储；
- Provider 失败不会缓存虚假动作或事实。

### 18.3 集成验收场景

1. 阿禾观察到种子涨价，向老李提出私下购买；老李被立即唤醒并还价；双方接受后资产正确转移，公共库存不变，市场产生价格信号。
2. 老李向 Player 报价；在 Player 点击确认前任何资产都不改变，确认后双方原子结算。
3. 阿禾与学者林建立新作物探索合作，分别提交种植资源与样本调查，完成后按条款分配收益并提高关系。
4. 学者林满足条件后提出转为商人；Godot 审核、扣除成本、切换目标和工具，旧探险专属动作被拒绝。
5. 保存游戏、重启、加载，从检查点和事件尾部恢复相同报价、锁定、合作、关系、角色、市场压力和幂等结果。
6. Agent Service 停止时游戏继续运行；重新启动后用当前投影恢复决策，不重放已经提交的动作。

## 19. 完成标准

- 三个 NPC Agent 的上下文都包含当前市场、其他可见 Agent 和 Player 公共信息。
- Agent 能真实发送消息、协商交易、建立合作并改变双方权威资产。
- Player 的私有资产不会因感知或未确认报价泄漏、锁定或扣除。
- Agent 可以在确定性规则下改变身份，目标、工具和调度随之变化。
- 公共市场交易和私下成交信号都能以受限、可解释方式影响价格。
- 所有 Agent 社会状态可从事件日志确定性重放，并随游戏存档安全恢复。
- 没有全局 revision 过期重试；失败使用具体领域条件解释，并等待下一轮。
- 所有提交事件、资产变化、UI 通知和 Agent 记忆保持一致。
