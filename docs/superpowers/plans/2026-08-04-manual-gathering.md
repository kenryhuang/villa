# Manual Gathering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现“点击资源后自动靠近、自动换工具、执行一次 1.2 秒动作、获得恰好 1 单位并停止”的手动伐木与露天采矿闭环，并接入现有背包、建造、市场、时间和存档系统。

**Architecture:** 以 `GatheringController` 作为唯一流程编排者，以 `GridPathfinder` 负责现有网格上的 A*，玩家控制器只负责沿路径移动；`ToolSystem` 和 `ResourceNode` 共同提供可预览、可回滚、恰好一次提交的采集事务。表现由独立 `GatheringFeedback` 与 `ToolSwingVisual` 监听状态信号，不参与成功判定。

**Tech Stack:** Godot 4.7.1、GDScript 2.0、AStarGrid2D、现有 SceneTree 自定义测试框架、Godot headless 截图测试。

---

## 实施约束

- 所有功能改动先写失败测试，再写最小实现，再运行目标测试。
- 每个任务完成后更新本计划复选框并单独提交，保持可回退。
- 不改变现有建造、农耕、市场的物品 ID；木材为 `wood`，石材为 `stone`，矿物沿用 `GameData` 目录 ID。
- 不实现矿洞、自动连续采空、动作队列、熔炼或自动生产建筑。
- 复用 `assets/ui/action_icons/axe.png` 与 `assets/ui/action_icons/pickaxe.png` 作为当前胶囊角色的手绘工具表现。

### Task 1: 建立资源目录与 `ResourceNode` v2 状态

**Files:**
- Create: `scripts/world/resource_catalog.gd`
- Modify: `scripts/world/resource_node.gd`
- Modify: `scripts/world/tree_instance.gd`
- Modify: `tests/test_resource_gathering.gd`

- [x] **Step 1: 写资源目录与 v2 状态失败测试**

在 `tests/test_resource_gathering.gd` 增加断言：

```gdscript
assertions.equal(ResourceCatalog.definition("tree").max_units, 5, "tree capacity is five")
assertions.equal(ResourceCatalog.definition("gold_ore").respawn_days, 7, "rare ore respawns in seven days")
assertions.equal(node.preview_reward("pickaxe"), {"copper_ore": 1}, "node yields exactly one visible ore")
assertions.equal(node.to_dict().state_version, 2, "resource state uses schema v2")
```

并覆盖三阶段视觉、采空树桩/碎石仍可见但不可交互、同日刷新幂等、旧 `hits_remaining` 比例迁移。

- [x] **Step 2: 运行资源测试并确认失败**

Run: `godot_console --headless --path . --script res://tests/run_economy_system_tests.gd`

Expected: FAIL，提示 `ResourceCatalog`、`remaining_units` 或 `state_version` 尚不存在。

- [x] **Step 3: 实现不可变资源目录**

`scripts/world/resource_catalog.gd` 暴露：

```gdscript
class_name ResourceCatalog
extends RefCounted

static func definition(resource_type: String) -> Dictionary
static func all_types() -> Array[String]
```

目录精确包含树木、石材、煤、铜、铁、银、金、水晶的 `item_id`、`required_tool`、`max_units`、`respawn_days`、显示名和颜色；每次返回深拷贝，调用者不能修改共享配置。

- [x] **Step 4: 将资源节点升级为 v2**

`ResourceNode` 改用 `resource_type`、`item_id`、`max_units`、`remaining_units`、`respawn_day` 与 `visual_stage`。提供兼容属性或读取路径，使旧测试与旧场景不会因 `hits_remaining` 消失而崩溃；`preview_reward()` 永远只返回 `{item_id: 1}`，删除运行时概率奖励。

`to_dict()` 输出完整 v2 记录；`validate_state_dict()` 和 `from_dict()` 同时接受 v2 与旧记录，但任何失败都不改变节点。视觉在 `remaining_units` 变化时更新，不再用 `visible = false` 隐藏采空节点。

- [x] **Step 5: 配置可采树为 5 单位木材**

`TreeInstance.configure()` 只在数据包含 `gatherable: true` 时加入采集组，配置 `tree/wood/axe/5/3`；装饰树保持碰撞与遮挡，但不暴露采集接口给点击路由。

- [x] **Step 6: 运行资源测试并提交**

Run: `godot_console --headless --path . --script res://tests/run_economy_system_tests.gd`

Expected: PASS。

Commit: `feat: add versioned manual resource catalog`

### Task 2: 生成明确资源区与稳定资源 ID

**Files:**
- Modify: `scripts/world/world.gd`
- Modify: `scripts/world/vegetation_builder.gd`
- Modify: `scripts/world/tree_scatter.gd`
- Modify: `tests/test_resource_gathering.gd`
- Modify: `tests/test_vegetation_builder.gd`

- [x] **Step 1: 写世界分布失败测试**

验证两次固定种子结果完全相同、ID 唯一，且准确包含：资源林区 10–14 棵可砍树；石材 4、煤 2、铜 2、铁 2；银、金、水晶各 1。验证道路、住宅和农田边缘装饰树不在 `gatherable_resource` 组。

- [x] **Step 2: 运行测试并确认现有概率岩石方案失败**

Run: `godot_console --headless --path . --script res://tests/run_economy_system_tests.gd`

Expected: FAIL，矿物类型数量和可砍树区域不符合新规则。

- [x] **Step 3: 实现确定性定义**

将 `GameWorld.generated_resource_definitions()` 改为按类型生成显式节点，配置示例：

```gdscript
{
    "resource_id": "copper-00",
    "resource_type": "copper_ore",
    "position": Vector3(...),
}
```

资源点避开 `get_blocked_regions()`、道路主轴和主要建造区。资源林数据携带稳定 `tree-resource-00..NN` ID 和 `gatherable: true`；其他树的数据明确为 `false`。

- [x] **Step 4: 让世界统一枚举树木和矿脉存档**

`to_resource_dicts()`、`validate_resource_dicts()`、`restore_resource_dicts()` 和 `advance_resource_day()` 统一遍历所有 v2 可采资源，并按 `resource_id` 排序；读取不得复制节点或随机换位。

- [x] **Step 5: 运行测试并提交**

Run: `godot_console --headless --path . --script res://tests/run_economy_system_tests.gd`

Expected: PASS。

Commit: `feat: generate deterministic gathering zones`

### Task 3: 增加导航修订和网格 A*

**Files:**
- Create: `scripts/systems/grid_pathfinder.gd`
- Modify: `scripts/systems/grid_system.gd`
- Modify: `scripts/systems/building_system.gd`
- Create: `tests/test_grid_pathfinder.gd`
- Modify: `tests/run_grid_system_tests.gd`

- [x] **Step 1: 写 A* 失败测试**

覆盖：绕开水域和建筑、八向行走不穿角、资源格不可走、从目标周围选择最低成本交互格、无解返回空数组、导航修订未变化时不重建、变化后只重建一次。

- [x] **Step 2: 运行并确认失败**

Run: `godot_console --headless --path . --script res://tests/run_grid_system_tests.gd`

Expected: FAIL，`GridPathfinder` 与导航修订 API 尚不存在。

- [x] **Step 3: 为 GridSystem 增加动态阻挡接口**

新增：

```gdscript
signal navigation_changed(revision: int)
func get_navigation_revision() -> int
func set_navigation_blocker(blocker_id: String, cell: Vector2i, active: bool) -> bool
func is_navigation_cell_walkable(cell: Vector2i) -> bool
```

只有阻挡实际改变才增加修订；建筑放置/拆除和资源激活/采空调用统一接口，不污染农田业务状态。

- [x] **Step 4: 实现 GridPathfinder**

使用 `AStarGrid2D` 的现有 36×28 范围；开启对角移动并使用 `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`。实现：

```gdscript
func configure(grid: GridSystem) -> bool
func find_path_to_interaction(start_world: Vector3, target: Node3D, range: float) -> Array[Vector3]
func invalidate() -> void
```

路径结果转为地表世界坐标，终点以实际碰撞体平面距离验证。

- [x] **Step 5: 运行网格测试并提交**

Run: `godot_console --headless --path . --script res://tests/run_grid_system_tests.gd`

Expected: PASS。

Commit: `feat: add grid pathfinding for gathering`

### Task 4: 为玩家增加可取消自动移动

**Files:**
- Modify: `scripts/actors/player.gd`
- Modify: `tests/test_player_logic.gd`
- Modify: `tests/test_player_grid_binding.gd`

- [x] **Step 1: 写自动移动失败测试**

验证 `start_auto_path()` 拒绝空路径、按顺序到达路径点、完成只发一次信号；WASD 先停止自动移动并发 `manual_movement_requested`；阻塞 0.5 秒只发一次 `auto_path_blocked`；停止后速度归零。

- [x] **Step 2: 运行并确认失败**

Run: `godot_console --headless --path . --script res://tests/run_tests.gd`

Expected: FAIL，自动路径 API 与信号尚不存在。

- [x] **Step 3: 实现路径跟随**

在 `PlayerController` 增加设计约定的三个信号和三个方法。自动移动走普通 `speed`，不消耗冲刺；终点容差固定并可测试；手动输入优先于同帧自动移动。

- [x] **Step 4: 运行核心测试并提交**

Run: `godot_console --headless --path . --script res://tests/run_tests.gd`

Expected: PASS。

Commit: `feat: add cancellable player auto movement`

### Task 5: 实现动作时钟拥有者锁

**Files:**
- Modify: `scripts/systems/season_system.gd`
- Modify: `tests/test_season_system.gd`

- [x] **Step 1: 写时钟锁失败测试**

覆盖同一拥有者重复锁拒绝、不同拥有者可同时持有、任一有效锁存在时 `_process` 不推进、释放最后一把锁后恢复、失效对象被清理，以及成功动作只推进精确 10 分钟。

- [x] **Step 2: 运行并确认失败**

Run: `godot_console --headless --path . --script res://tests/run_tests.gd`

Expected: FAIL，动作锁 API 尚不存在。

- [x] **Step 3: 实现锁并保护场景切换**

用实例 ID 到 `WeakRef` 的字典保存拥有者；`_process()` 开始时清理失效锁，锁非空则返回。释放必须幂等且不能释放其他拥有者的锁；`advance_game_minutes(10)` 仍允许显式调用。

- [x] **Step 4: 运行核心测试并提交**

Run: `godot_console --headless --path . --script res://tests/run_tests.gd`

Expected: PASS。

Commit: `feat: add owned gathering clock locks`

### Task 6: 将 ToolSystem 采集改为可预览的原子事务

**Files:**
- Modify: `scripts/systems/tool_system.gd`
- Modify: `tests/test_tool_action_transaction.gd`
- Modify: `tests/test_resource_gathering.gd`

- [x] **Step 1: 写预览与提交失败测试**

验证 `preview_gather_unit()` 的所有返回字段；错误原因区分目标、工具损坏、体力、容量和距离；`commit_gather_unit()` 恰好增加 1 个物品、扣 1 耐久和对应体力。逐步注入背包写入失败、资源提交不一致和同步重入，确认全量回滚且没有部分事件。

- [x] **Step 2: 运行并确认失败**

Run: `godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`

Expected: FAIL，新接口和结构化错误尚不存在。

- [x] **Step 3: 实现工具映射与预览**

增加字符串/枚举双向映射并允许控制器自动选择 `axe` 或 `pickaxe`。预览只读，不改变当前工具、背包、体力、耐久或资源。

- [x] **Step 4: 实现恰好一次提交**

提交使用 `_active_gather_transactions` 防重入；快照包括背包映射、资源 v2 状态、玩家体力、当前工具和耐久。所有变更成功后才解除事件阻塞并发送一次提交事件；任何失败按逆序完整恢复。

- [x] **Step 5: 保持旧入口兼容并提交**

`use_tool_on()` 的斧头/镐分支委托 `commit_gather_unit()`，锄头、浇水和鱼竿行为不变。

Run: `godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`

Expected: PASS。

Commit: `feat: make gathering transactions atomic`

### Task 7: 实现 GatheringController 状态机

**Files:**
- Create: `scripts/systems/gathering_controller.gd`
- Create: `tests/test_gathering_controller.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

- [x] **Step 1: 写状态机失败测试**

用玩家、寻路、工具、季节和动画替身验证完整状态序列；最新点击覆盖；WASD、地面、模式、Esc 取消；到达后二次校验；只允许一次重寻路；动作取消不提交；成功提交后推进 10 分钟并停止。

- [x] **Step 2: 运行并确认失败**

Run: `godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`

Expected: FAIL，控制器尚不存在。

- [x] **Step 3: 实现依赖注入和状态信号**

提供：

```gdscript
signal state_changed(state: int, context: Dictionary)
signal gather_started(target: Node, preview: Dictionary)
signal gather_progress(target: Node, progress: float)
signal gather_completed(target: Node, result: Dictionary)
signal gather_failed(target: Node, reason: String)
signal gather_cancelled(reason: String)

func configure(player, pathfinder, tools, season) -> bool
func request_gather(target: Node) -> bool
func cancel_current(reason: String) -> void
```

每个请求使用单调递增 token，任何 await 恢复后先检查 token，防止旧协程提交。

- [x] **Step 4: 实现动作锁和最终提交**

到达后重新预览并验证距离；1.2 秒动作期间持锁并逐帧发进度。成功时先调用事务提交，成功才 `advance_game_minutes(10)`；失败和取消只释放锁。

- [x] **Step 5: 运行状态机测试并提交**

Run: `godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`

Expected: PASS。

Commit: `feat: orchestrate single-unit gathering actions`

### Task 8: 实现工具动作、资源阶段与采集反馈

**Files:**
- Create: `scripts/visual/tool_swing_visual.gd`
- Create: `scripts/ui/gathering_feedback.gd`
- Create: `scenes/ui/gathering_feedback.tscn`
- Modify: `scripts/world/resource_node.gd`
- Modify: `scripts/world/tree_instance.gd`
- Create: `tests/test_gathering_visuals.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

- [x] **Step 1: 写视觉结构失败测试**

验证工具句柄末端为旋转圆心、1.2 秒分段时序、斧头/镐图标路径；目标环、路径、无刻度圆形进度、剩余量、自动装备提示、`+1` 飘字和错误文字节点齐全；树木/矿脉四个视觉阶段可切换。

- [x] **Step 2: 运行并确认失败**

Run: `godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`

Expected: FAIL，视觉节点和脚本尚不存在。

- [x] **Step 3: 实现 ToolSwingVisual**

复用现有手绘工具 PNG，在角色朝向目标的一侧创建 `Sprite3D`；工具柄末端作为父节点原点。按 0.25/0.30/0.15/0.50 秒执行预备、下挥、命中停顿和回收；取消时立即进入短回收且不发命中提交。

- [x] **Step 4: 实现资源阶段表现**

树木保留树冠/树干并叠加斧痕，0 单位替换为树桩；矿石根据比例缩放并叠加裂纹，0 单位显示碎石底座。采空时关闭交互/实体阻挡但保留可见残骸。

- [x] **Step 5: 实现 GatheringFeedback**

目标环和虚线路径使用世界空间轻量几何；进度圆通过 `Control._draw()` 画透明底圆和无刻度扇形；文字使用高对比描边并同时带图标和文案。所有表现只响应控制器信号。

- [x] **Step 6: 运行视觉结构测试并提交**

Run: `godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`

Expected: PASS。

Commit: `feat: add gathering action and feedback visuals`

### Task 9: 接入主场景、点击路由和取消规则

**Files:**
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `scripts/main.gd`
- Modify: `scenes/main.tscn`
- Modify: `scenes/actors/player.tscn`
- Modify: `scripts/ui/hud.gd`
- Modify: `tests/test_player_action_controller.gd`
- Modify: `tests/test_main_pointer_farming.gd`
- Create: `tests/test_main_gathering_integration.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

- [x] **Step 1: 写真实主场景失败测试**

实例化 `scenes/main.tscn`，点击远处资源，验证自动换工具、绕行、动作一次后停止；WASD、地面、建造模式和 Esc 取消。确认装饰树不会进入采集流程，现有农耕/建造点击仍正常。

- [x] **Step 2: 运行并确认失败**

Run: `godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`

Expected: FAIL，主场景尚未创建或连接采集控制器。

- [x] **Step 3: 主场景编排依赖**

`main.gd` 在网格、工具和玩家完成配置后创建 `GridPathfinder`、`GatheringController` 与反馈层，并连接资源阻挡。加载完成、场景退出和调试重置前统一取消当前采集并清理时钟锁。

- [x] **Step 4: 修改点击与模式路由**

普通工具模式点击 `gatherable_resource` 时将目标交给控制器，不再要求点击瞬间已在 2.5 米内。农耕和建造模式保持优先级；点击地面或其他目标先取消旧采集。HUD 自动高亮实际切换的工具。

- [x] **Step 5: 运行集成测试并提交**

Run: `godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`

Expected: PASS。

Commit: `feat: integrate click-to-gather gameplay`

### Task 10: 完成资源存档迁移与原子加载

**Files:**
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/world/world.gd`
- Modify: `tests/test_resource_gathering.gd`
- Modify: `tests/test_economy_save_integration.gd`

- [x] **Step 1: 写迁移和回滚失败测试**

覆盖 v2 往返；旧满/半满/0 命中按比例向上取整；旧概率奖励丢弃；旧存档缺少新资源时补目录默认值；非法单条资源、重复 ID、错误刷新日均导致整个资源/背包/时间/工具快照不变。

- [x] **Step 2: 运行并确认失败**

Run: `godot_console --headless --path . --script res://tests/run_economy_system_tests.gd`

Expected: FAIL，旧记录尚不能升级为完整 v2 世界快照。

- [x] **Step 3: 在资源世界中标准化存档**

增加纯函数式标准化步骤，先把传入数组复制并迁移为按当前目录排序的完整 v2 记录，再统一验证，最后才逐节点应用。运行时加载更早日期时同步每日游标。

- [x] **Step 4: 让 SaveManager 在提交前取消动作**

保存只收集最后一次成功提交状态；加载前通过主场景回调取消路径/动画并释放锁。既有经济系统回滚顺序保持不变，资源迁移失败必须触发全局快照回滚。

- [x] **Step 5: 运行存档测试并提交**

Run: `godot_console --headless --path . --script res://tests/run_economy_system_tests.gd`

Expected: PASS。

Commit: `feat: migrate gathering resources to save schema v2`

### Task 11: 证明产业链接入与边界行为

**Files:**
- Modify: `tests/test_resource_gathering.gd`
- Modify: `tests/test_building_economy_effects.gd`
- Modify: `tests/test_market_system.gd`
- Modify: `tests/test_main_gathering_integration.gd`

- [ ] **Step 1: 写端到端失败测试**

从真实资源节点采 1 木材/石材/矿石，验证建造诊断立即减少缺口，市场库存不自动变化，玩家主动出售矿石后才改变金钱和市场库存。再覆盖背包已满、体力不足、工具损坏、不可达、目标失效、快速双击和动作跨日。

- [ ] **Step 2: 运行并修复任何接线缺口**

Run: `godot_console --headless --path . --script res://tests/run_economy_system_tests.gd`

Run: `godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`

Expected: 两个测试入口均 PASS；若失败，只修复触发失败的边界，不扩大本期范围。

- [ ] **Step 3: 提交产业链接入**

Commit: `test: verify manual gathering economy chain`

### Task 12: 视觉验收、全量验证与文档收尾

**Files:**
- Create: `tests/capture_manual_gathering.gd`
- Create: `docs/validation/manual-gathering-validation.md`
- Modify: `docs/superpowers/plans/2026-08-04-manual-gathering.md`

- [ ] **Step 1: 创建确定性视觉捕获场景**

捕获树木目标与路径、伐木进度、`+1` 飘字、树桩、矿脉完整/受损/碎石、背包已满和不可达。在 1280×720、1920×1080、3000×2000 下保存到临时验证目录，避免提交运行产物。

- [ ] **Step 2: 运行视觉捕获并逐图检查**

Run: `godot_console --path . --script res://tests/capture_manual_gathering.gd`

Expected: 进程退出码 0，无裁切、重叠、工具轴心错误或不可读文字。

- [ ] **Step 3: 运行全量自动测试**

Run: `godot_console --headless --path . --script res://tests/run_tests.gd`

Run: `godot_console --headless --path . --script res://tests/run_grid_system_tests.gd`

Run: `godot_console --headless --path . --script res://tests/run_farming_system_tests.gd`

Run: `godot_console --headless --path . --script res://tests/run_building_system_tests.gd`

Run: `godot_console --headless --path . --script res://tests/run_economy_system_tests.gd`

Run: `godot_console --headless --path . --script res://tests/run_economy_ui_tests.gd`

Run: `godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`

Expected: 所有入口 PASS，Godot 输出没有新的解析错误、无效节点、孤立信号或时间锁告警。

- [ ] **Step 4: 静态检查和计划收尾**

Run: `git diff --check`

Run: `rg -n "TODO|TBD|placeholder|待定|占位" scripts scenes tests docs/validation/manual-gathering-validation.md`

Expected: `git diff --check` 无输出；搜索结果没有本功能遗留项。

在 `docs/validation/manual-gathering-validation.md` 记录每个命令的实际 PASS 数、截图尺寸和人工检查结论；将本计划全部复选框改为完成。

- [ ] **Step 5: 最终提交**

Commit: `docs: validate manual gathering system`

## 完成定义

- 玩家点击可采树木或矿脉后会自动找到可达交互格并移动过去。
- 系统自动选择正确且未损坏的工具，1.2 秒后只获得 1 单位并停止。
- 成功动作只扣一次体力和 1 耐久，只推进精确 10 分钟；任何取消或失败均不产生部分变更。
- 资源容量、视觉阶段、树桩/碎石和刷新日符合正式设计。
- 装饰树不可采，矿脉所见即所得，稳定 ID 和 v2 存档迁移可复现且原子。
- 木材/石材立即可用于建造，矿石可主动出售，资源不会自动进入市场。
- 目标、路径、自动装备、环形进度、剩余量、产出和错误反馈在三种目标分辨率下清晰可读。
- 全量测试通过，工作树无未审查改动。
