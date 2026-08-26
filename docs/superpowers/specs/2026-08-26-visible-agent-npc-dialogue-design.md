# 可见 Agent NPC 绑定与近距离对话设计

日期：2026-08-26  
分支：`feature/painted-production-buildings`

## 1. 目标

把当前三个后台 NPC Agent 绑定到主场景中已有的三个可见 NPC，使玩家接近角色时看到头顶对话图标，并能通过点击图标或 NPC 身体发起真实的流式 Agent 对话。

本次交付包括：

- 将三个可见 NPC 精确绑定到农民阿禾、商人老李和探险家学者林。
- 玩家进入 NPC 水平距离 3 米内时显示头顶对话图标，离开后隐藏。
- 点击对话图标或 NPC 身体均可发起同一条 Agent 对话链路。
- 请求期间以及对话框打开期间抑制重复请求。
- Agent Service 不可用时不回退到固定台词，只在消息面板提示服务不可用。
- 保留现有自主决策调度、真实世界资产变更以及 F8 Agent 原始调试记录。

## 2. 非目标

- 本期不制作三个角色各自独立的人物模型或动画，继续复用现有 NPC 外观。
- 本期不实现靠近后自动开始对话，必须由玩家点击。
- 本期不实现点击远处 NPC 后自动寻路到交互范围。
- 本期不把其余普通村民改造成 Agent。
- 本期不改变 Agent 的角色目标、工具集、记忆、决策频率或行动执行规则。
- 本期不让 NPC 节点直接访问 HTTP、Provider 配置或 Agent Service。

## 3. 方案选择

采用“扩展现有 `npc.tscn`”方案。NPC 场景负责距离感知、图标展示和发出对话意图；现有 `Main → AgentRuntime → AgentGateway → Agent Service` 链路继续负责网络调用和结果处理。

未采用以下方案：

- 新建 `agent_npc.tscn`：会复制当前 NPC 的移动、碰撞和交互能力，在只有三个 Agent 时收益不足。
- 新建集中式交互管理器：适合大量 Agent 的空间查询与图标池化，但当前会引入不必要的全局状态。

## 4. Agent 与场景节点映射

主场景中的三个 NPC 固定映射如下：

| 场景节点 | Agent ID | 显示名 | 角色 |
|---|---|---|---|
| `Actors/Npcs/NpcNorthwest` | `farmer_ahe` | 阿禾 | 农民 |
| `Actors/Npcs/NpcSouth` | `lao_li` | 老李 | 商人 |
| `Actors/Npcs/NpcEast` | `xuezhe_lin` | 学者林 | 探险家 |

`Main._setup_npcs()` 使用以上明确映射，不再按旧村民数组顺序把前三个节点绑定为老李、小花和铁匠张。场景节点的 `villager_id`、Agent Registry 的 `agent_id`、对话 UI 的角色 ID 和 Agent Runtime 请求 ID 必须保持一致。

三个 Agent 的后台自主行动仍然可以在没有视觉动画的情况下修改其农场、库存、市场、建筑、活动和知识资产；可见 NPC 只增加世界中的身份载体与玩家交互入口。

## 5. NPC 场景结构

在 `npc.tscn` 中增加一个独立的头顶交互分支：

```text
Npc (CharacterBody3D)
├── Mesh
├── CollisionShape3D
└── DialoguePrompt (Node3D)
    ├── Icon (Sprite3D)
    └── HitArea (Area3D)
        └── CollisionShape3D
```

### 5.1 图标表现

- `Icon` 使用透明背景、手绘风格的对话气泡 SVG 纹理。
- `Sprite3D` 使用 billboard，使图标始终朝向当前相机。
- 图标位于 NPC 头顶上方，保持足够留白，不遮挡角色头部。
- 图标使用轻量淡入；离开范围、进入 busy 或对话打开时立即进入隐藏状态，避免残留可点击区域。
- 图标不参与角色实体碰撞、导航或受击判定。

### 5.2 点击区域

- `HitArea` 使用现有鼠标交互碰撞层，使 `PlayerActionController` 的交互射线能够命中。
- 命中图标区域后，现有向父节点查找 `start_dialogue()` 的逻辑最终解析到 NPC。
- 图标隐藏时同步把 `HitArea` 的交互碰撞层设为 `0`，并关闭射线拾取；显示时恢复。
- NPC 身体原有碰撞层继续作为第二个点击入口。

不允许出现“图标不可见但仍阻挡点击”或“图标可见但射线落到地面”的中间状态。

## 6. 距离与交互状态

NPC 持有玩家引用，并以玩家和 NPC 的 XZ 平面距离作为唯一交互距离：

```text
distance = Vector2(player.x, player.z).distance_to(Vector2(npc.x, npc.z))
```

统一交互半径为 `3.0` 米。地形高差不应让玩家在水平距离足够近时失去图标或被拒绝。

NPC 的提示状态由以下条件决定：

```text
prompt_visible = player_in_range
                 and not dialogue_busy
                 and npc_is_interactable
```

规则如下：

- 进入 3 米：图标显示，图标和身体均可点击。
- 超过 3 米：图标隐藏；即使相机射线仍能命中，也不得开始对话。
- 请求已经提交：NPC 进入 `dialogue_busy`，图标隐藏，重复点击不产生第二个请求。
- 对话面板保持打开：继续维持 busy。
- 玩家关闭对话、请求启动失败或流式请求失败：解除 busy；若玩家仍在 3 米内，图标重新显示。

距离变化只控制交互提示，不自动中断已经打开的对话。玩家主动关闭对话时，沿用现有取消 Agent 流的行为。

## 7. 对话数据流

```text
玩家进入 3 米
  → NPC 显示 DialoguePrompt
  → 玩家点击图标或 NPC 身体
  → PlayerActionController.perform_target_interaction(Npc)
  → Npc.start_dialogue() 再次校验距离和 busy
  → Npc 发出 dialogue_started(agent_id)
  → Main 调用 AgentRuntime.trigger_dialogue(agent_id)
  → AgentScheduler 以 dialogue 优先级派发或替换该 Agent 的自主请求
  → AgentGateway 调用 /v1/agents/{agent_id}/decide/stream
  → reasoning_content 进入 F8 Agent 调试窗口
  → content.delta 流式进入 DialogueUI
  → decision.final 完成并执行合法工具动作
  → 玩家关闭 DialogueUI
  → Main 通知对应 NPC 解除 dialogue_busy
```

`Npc` 不知道请求 URL、鉴权 token、SSE 格式或模型响应。它只暴露：

- Agent/村民 ID；
- 当前是否在玩家交互范围；
- 当前是否 busy；
- 设置 busy 的接口；
- `dialogue_started(agent_id)` 信号。

`DialogueUI` 在关闭时发出带角色 ID 的关闭信号，`Main` 据此只解除对应 NPC 的 busy 状态，不影响其他 Agent。

## 8. 服务不可用与错误处理

Agent 管理的 NPC 不允许回退到 `VillagerSystem` 固定台词。

### 8.1 请求未能启动

如果 Agent 客户端未启用、配置无效、Agent Service 不可达，或 `AgentRuntime.trigger_dialogue()` 无法提交请求：

- 不打开固定对话；
- 通过 `HudMessageBus` 在右侧消息面板发布 warning：`Agent 服务不可用，请稍后再试。`；
- 立即解除该 NPC 的 busy 状态；
- 图标根据当前距离恢复，允许玩家稍后重试。

### 8.2 流式请求中途失败

如果已经显示“正在思考”后 SSE 连接超时、断开或服务返回错误：

- 清理对应 `request_id` 的流式对话状态；
- 关闭未完成的 Agent 对话，不注入本地角色台词；
- 在消息面板发布相同的服务不可用提示；
- 解除对应 NPC 的 busy 状态。

### 8.3 重复点击与竞态

- NPC busy 时所有身体/图标点击均被拒绝。
- 一个 Agent 同时最多保留一个对话请求。
- 对话关闭产生的取消事件必须带原 `request_id`，迟到的 stream delta 或 final 不得重新打开 UI。
- 一个 Agent 的完成或失败事件不得解除另一个 NPC 的 busy 状态。

## 9. 与现有系统的边界

### `npc.gd`

负责玩家距离检测、提示图标状态、二次距离校验、busy 防重入和对话意图信号，不负责网络调用。

### `main.gd`

负责三个场景节点与 Agent ID 的映射，维护 Agent ID 到 NPC 节点的路由，并协调 NPC、Agent Runtime、Dialogue UI 和消息面板的状态变化。

### `PlayerActionController`

继续使用现有碰撞射线和向父节点解析交互目标的逻辑。身体和图标点击均走 `perform_target_interaction()`，不增加 Agent 专用射线分支。

### `AgentRuntime` 与 `AgentGateway`

继续负责服务启用状态、调度优先级、SSE 生命周期、Provider 调用、动作校验、真实世界资产变更和 outcome 上报。本功能不改变自主行动的调度周期。

### `DialogueUI`

继续负责 Agent 文本流展示；补充明确的关闭/失败生命周期信号，使 `Main` 能可靠解除对应 NPC 的 busy 状态。

### `HudMessageBus`

统一承载 Agent Service 不可用提示，避免错误文字重新散落到 HUD 顶部。

## 10. 测试策略

实现遵循测试先行，至少覆盖以下自动化契约。

### 10.1 NPC 单元测试

- 水平距离小于或等于 3 米时显示图标。
- 水平距离超过 3 米时隐藏图标。
- Y 轴高差不改变范围判断。
- busy 时隐藏图标并拒绝重复对话。
- 图标隐藏时点击 Area 的碰撞层与射线拾取关闭。
- 出范围时直接调用 `start_dialogue()` 不发出信号。
- 进入范围并点击时只发出一次正确 Agent ID。
- 解除 busy 且玩家仍在范围时恢复图标。

### 10.2 场景与 Main 集成测试

- 三个场景节点精确绑定 `farmer_ahe`、`lao_li`、`xuezhe_lin`。
- 点击 NPC 身体可以到达同一 `start_dialogue()` 入口。
- 点击图标 Area 可以解析到同一个 NPC。
- Agent 请求成功启动后设置对应 NPC busy。
- 对话关闭、启动失败和流失败分别解除正确 NPC 的 busy。
- 服务不可用时不调用固定 `DialogueUI.start_dialogue()`，只发布 warning。
- 其他两个 NPC 不受当前 Agent 的对话生命周期影响。

### 10.3 回归测试

- 三个 Agent 仍按照角色周期产生自主决策。
- 玩家对话仍能替换同一 Agent 的在途自主请求。
- reasoning 只出现在 F8 Agent 调试窗口。
- 合法 tool call 仍通过 validator 后真实修改世界资产。
- 建筑、资源和作物的现有鼠标交互不受新增图标碰撞层影响。

## 11. 手工验收

1. 启动配置好的本地 Agent Service，再启动游戏。
2. 分别接近阿禾、老李和学者林，确认 3 米内出现头顶气泡，离开后消失。
3. 分别点击 NPC 身体和头顶图标，确认两种入口都能打开流式 Agent 对话。
4. 请求生成期间重复点击，确认没有第二次请求。
5. 打开 F8 Agent 调试窗口，确认能看到该对话的 input、reasoning 和 output 原始事件。
6. 关闭对话，确认对应 NPC 的图标在仍处于范围内时恢复。
7. 停止 Agent Service 后再次点击，确认不显示固定台词，只在消息面板提示 `Agent 服务不可用，请稍后再试。`。
8. 观察或推进游戏时间，确认三个 Agent 的后台自主动作仍能执行并修改其资产。

## 12. 完成标准

- 主场景三个可见 NPC 与三个 Agent 身份一一对应。
- 3 米范围、图标显隐、身体/图标双入口和 busy 防重入行为符合本设计。
- 成功对话端到端使用现有流式 Agent 链路。
- 服务不可用或流失败时没有固定对话回退，错误只进入统一消息面板。
- 所有新增自动测试与相关回归测试通过。
- 手工验收中不存在不可见点击区域、重复请求、错误 NPC 解锁或遗留对话图标。
