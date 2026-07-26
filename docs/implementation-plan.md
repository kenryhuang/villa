# Villa 实施计划

> 基于 `docs/detailed-design.md`，分阶段实现从战斗原型到农庄模拟的转换。

## 状态：✅ 全部完成 (2026-07-23)

## 当前状态

**已完成（可直接使用）：**
- `event_bus.gd` — 信号总线，完整
- `grid_system.gd` — 网格系统，完整（185L）
- `farming_system.gd` — 种植系统，完整（135L）
- `season_system.gd` — 季节/时间系统，完整（49L）
- `crop_data.gd`, `crop_instance.gd`, `grid_cell.gd`, `player_state.gd` — 数据类，完整

**需要改造：**
- `player.gd` (83L) — 当前是战斗角色，需改为农耕+工具+体力系统
- `main.gd` (52L) — 当前是战斗场景编排，需改为农庄系统编排
- `hud.gd` (19L) — 当前是战斗 HUD，需改为经营 HUD
- `npc.gd` (78L) — 当前是战斗 NPC，需改为村民
- `game_data.gd` (24L) — 只有作物注册，需扩展为完整数据表
- `world.gd` (22L) — 需添加 GridSystem/Buildings 子节点

**需要删除（Phase 5）：**
- `scripts/combat/projectile.gd`
- `scripts/shared/combat_math.gd`
- `scenes/combat/projectile.tscn`

---

## Phase 1：核心数据 + 背包 + 经济

### 1a. 扩展 game_data.gd
在 `scripts/core/game_data.gd` 中添加完整数据表：
- 物品定义（种子、作物、材料、收集品）— 包含 ID、名称、售价、堆叠上限、分类
- 建筑定义（谷仓、温室、风车、鸡舍、蜂箱、水井、工作台、路灯、围栏）— 占地、造价、功能
- 村民定义（老李、小花、铁匠张、渔夫阿水、学者林）— 名称、角色、日程、对话
- 收集品定义（日记碎片、化石、古代遗物、植物标本等）
- 物品定价表（参照 detailed-design.md §1.6）
- 使用 const Dictionary 硬编码数据，提供 get_item/get_building/get_villager/get_collectible 查询方法

### 1b. 创建 inventory_system.gd
`scripts/systems/inventory_system.gd`：
- InventorySlot 类：item 引用 + quantity
- Inventory 类：slots 数组、max_slots=20、quick_slots=6
- add_item（堆叠逻辑+空槽位）、remove_item、has_item、swap_slots
- 快捷栏映射（对背包槽位的引用，非独立存储）
- use_item 接口（调用 item.on_use）
- 连接 EventBus.item_added 信号

### 1c. 创建 economy_system.gd
`scripts/systems/economy_system.gd`：
- 金币管理：add_gold、spend_gold（从 game_state.gd 迁移金币逻辑）
- 订单系统：Order 数据类、generate_daily_orders（每天 2-3 个随机订单）
- complete_order：消耗物品、获得金币+经验+好感度
- 物品定价查询（委托 game_data）
- 连接 EventBus.day_changed 生成新订单

### 1d. 创建 inventory_ui.gd
`scripts/ui/inventory_ui.gd`：
- 网格布局背包界面（Control + GridContainer）
- 物品槽位显示（图标+数量）
- 拖拽到快捷栏
- 悬停显示物品详情（Tooltip）
- Tab/I 键打开/关闭
- 连接 EventBus.item_added/removed 自动刷新

---

## Phase 2：工具系统 + Player 改造 + 村民基础

### 2a. 创建 tool_system.gd
`scripts/systems/tool_system.gd`：
- Tool 基类：ToolType 枚举（HOE/WATERING_CAN/AXE/PICKAXE/FISHING_ROD 等）、stamina_cost、range、level
- on_use 方法：检查体力→消耗体力→执行工具功能
- HoeTool：开垦荒地（WASTELAND→FARMLAND）
- WateringCanTool：浇水
- AxeTool：砍树/收集木材
- 工具切换逻辑（数字键 1-6）

### 2b. 改造 player.gd
`scripts/actors/player.gd` 全面改造：
- 移除战斗相关代码（fire_requested、health、combat、projectile）
- 添加体力系统：stamina、max_stamina=100、自然恢复（1/秒）
- 添加工具系统：当前工具槽位、工具切换（数字键）、工具使用（鼠标左键）
- 添加交互系统：鼠标右键/E 键交互（射线检测→GridCell/NPC/建筑）
- 添加奔跑：Shift 键加速+消耗体力
- 保留移动/跳跃/镜头跟随
- 连接 EventBus.stamina_changed

### 2c. 改造 npc.gd → villager 基础
`scripts/actors/npc.gd` 改造为村民：
- 移除战斗相关代码（defeated、combat）
- 添加 villager_id、name、affinity（好感度 0-100）
- 添加日程驱动状态机：IDLE→MOVING_TO_WORK→WORKING→WANDERING→MOVING_TO_HOME→SLEEPING
- 添加基础移动逻辑（move_and_slide 到目标点）
- 添加对话触发（玩家靠近按 E）

### 2d. 创建 villager_system.gd
`scripts/systems/villager_system.gd`：
- 村民注册表（villager_id → VillagerData）
- 好感度管理：add_affinity、get_level（STRANGER/FRIEND/CLOSE/SOULMATE）
- 日程数据驱动（从 game_data 读取每个村民的 schedule）
- 每小时触发日程切换（连接 EventBus.time_changed）
- 对话系统基础：DialogueNode、DialogueChoice
- 连接 EventBus.affinity_changed

---

## Phase 3：建造系统 + 探索 + 收集品 + 故事

### 3a. 创建 building_system.gd
`scripts/systems/building_system.gd`：
- 建造预览模式：半透明 MeshInstance3D 跟随鼠标
- can_place_building：检查 footprint 网格可用性 + 资源
- place_building：消耗资源→标记网格→实例化场景→放置到地形高度
- remove_building：拆除→恢复网格
- 进入/退出建造模式（B 键）
- 射线检测选择网格位置

### 3b. 创建 building_instance.gd
`scripts/buildings/building_instance.gd`：
- BuildingInstance 基类：building_data、位置、footprint
- on_placed 回调
- 碰撞体 + 交互区域（Area3D）
- 各建筑类型特殊效果（谷仓→背包扩容等）

### 3c. 创建 exploration_system.gd
`scripts/systems/exploration_system.gd`：
- 迷雾 Shader（fog_of_war.glshader）：基于探索状态纹理的半透明遮罩
- fog_image：256x256 灰度图，0=未探索，255=已探索
- reveal_area：玩家周围半径 3.0 揭示
- 只在玩家移动超过 0.5 单位时更新迷雾
- RegionManager：区域解锁（溪谷入口、深林、迷雾峰）
- 解锁条件检查（等级、物品、资源、故事进度）

### 3d. 创建 collectible_system.gd
`scripts/systems/collectible_system.gd`：
- CollectiblePickup（Area3D）：浮动动画、玩家进入触发收集
- CollectionBook 图鉴：discovered 字典、分类统计
- 收集后触发 EventBus.collectible_found

### 3e. 创建 story_system.gd
`scripts/systems/story_system.gd`：
- 日记碎片收集：collected_fragments 数组
- 故事里程碑：3/6/9/12 碎片解锁章节
- 每章节解锁对应区域（creek→deep_forest→mist_peak→secret_garden）
- 连接 EventBus.story_fragment_collected

### 3f. 创建 puzzle_system.gd
`scripts/systems/puzzle_system.gd`：
- Puzzle 基类：puzzle_id、reward_items、reward_gold、is_solved
- _solve()：标记完成→发放奖励→触发信号
- PushPuzzle：推石头到目标位置
- OfferingPuzzle：献祭特定物品组合

---

## Phase 4：存档系统 + HUD 重写 + 主场景整合

### 4a. 创建 save_manager.gd
`scripts/core/save_manager.gd`：
- 存档格式：JSON（user://villa_save_<slot>.json）
- 保存内容：gold、player_state（stamina/level/exp）、current_season/day/hour/minute、grid_cells（状态+作物）、inventory、buildings、collected_fragments、discovered_collectibles、villager_affinity、fog_image（base64）、total_days
- save_game(slot)、load_game(slot)、get_save_slots()
- 自动存档：每天结束时触发
- 连接 EventBus 监听关键状态变化

### 4b. 重写 hud.gd
`scripts/ui/hud.gd` 完整重写：
- 顶部栏：体力条（ProgressBar）、金币（Label）、等级+经验条、季节/日期、游戏内时间
- 底部栏：快捷栏（6 格，HBoxContainer + TextureRect）
- 小地图（右上角，TextureRect 显示简化地形+玩家标记）
- 连接所有 EventBus 信号自动更新
- 只在数据变化时刷新（不每帧更新）

### 4c. 创建 dialogue_ui.gd
`scripts/ui/dialogue_ui.gd`：
- 对话框面板（Panel + Label + VBoxContainer）
- 显示 NPC 名称和对话文本
- 选项按钮（DialogueChoice）
- 打字机效果文本显示

### 4d. 创建 build_ui.gd
`scripts/ui/build_ui.gd`：
- 建筑选择面板（GridContainer + 建筑卡片）
- 每个卡片显示：建筑名称、图标、造价
- 点击后进入建造预览模式

### 4e. 创建 map_ui.gd
`scripts/ui/map_ui.gd`：
- 全屏地图（M 键打开/关闭）
- 显示已探索区域（基于 fog_image）
- 标记玩家位置、建筑位置、NPC 位置

### 4f. 创建 shop_ui.gd
`scripts/ui/shop_ui.gd`：
- 商店界面（购买种子、材料）
- 物品列表 + 价格 + 购买按钮
- 连接 economy_system 检查金币

### 4g. 重写 main.gd + 主场景整合
`scripts/main.gd` 全面重写：
- 编排所有系统初始化顺序
- 注册 Autoload 引用（EventBus、GameData、GameState、SaveManager）
- 初始化 GridSystem→FarmingSystem→SeasonSystem→EconomySystem→InventorySystem→BuildingSystem→VillagerSystem→ExplorationSystem→CollectibleSystem→StorySystem→ToolSystem
- 连接系统间依赖
- 初始化村民位置和日程
- 处理场景切换（HUD 打开/关闭时暂停逻辑）
- 移除所有战斗相关代码（projectiles、fire、combat）

### 4h. 更新 world.gd
`scripts/world/world.gd`：
- 添加 GridSystem 和 Buildings 子节点
- 提供 get_bounds() 方法
- 保持现有 terrain/road/tree 逻辑不变

### 4i. 更新 project.godot
- 添加 Autoload 注册：EventBus、GameData、GameState、SaveManager
- 添加 Input Map：interact、sprint、inventory、map、tool_1~tool_6、build_mode
- 移除 combat 相关 input action

### 4j. 清理战斗代码
- 删除 `scripts/combat/projectile.gd`
- 删除 `scripts/shared/combat_math.gd`
- 删除 `scenes/combat/projectile.tscn`
- 从 main.tscn 中移除 Projectiles 节点

---

## 实施规则

1. **遵循 detailed-design.md** 中的所有设计规范、接口定义和数据结构
2. **GDScript 规范**：Godot 4.7 语法、类型注解、class_name、信号优先于直接调用
3. **数据驱动**：所有游戏数据（作物、建筑、物品、村民）集中在 game_data.gd
4. **信号解耦**：系统间通过 EventBus 通信，不直接引用
5. **保留已有代码**：grid_system、farming_system、season_system 已经完整，不要重写
6. **场景文件**：.tscn 文件的修改需谨慎，优先通过代码动态添加节点
7. **测试**：每个系统创建后在 tests/ 目录下添加基础测试脚本
