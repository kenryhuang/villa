# Villa 详细技术设计文档

> 基于 `docs/game-design.md` 策划案，为 Godot 4.7 + GDScript 项目提供可执行的技术设计。

---

## 目录

1. [系统架构设计](#1-系统架构设计)
2. [数据结构定义](#2-数据结构定义)
3. [信号与事件总线](#3-信号与事件总线)
4. [场景节点树](#4-场景节点树)
5. [现有系统改造方案](#5-现有系统改造方案)
6. [存档系统设计](#6-存档系统设计)
7. [UI 布局详细设计](#7-ui-布局详细设计)
8. [性能考虑](#8-性能考虑)
9. [AI NPC Agent 系统](#9-ai-npc-agent-系统)

---

## 1. 系统架构设计

### 1.1 全局 Autoload 注册

项目新增以下 Autoload 单例（`项目设置 → Autoload`）：

| 单例名 | 脚本路径 | 职责 |
|--------|----------|------|
| `EventBus` | `res://scripts/core/event_bus.gd` | 全局信号总线，系统间解耦 |
| `GameData` | `res://scripts/core/game_data.gd` | 静态数据表（作物、建筑、物品、村民、收集品定义） |
| `GameState` | `res://scripts/core/game_state.gd` | 运行时全局状态（金币、季节、时间、等级、已解锁区域） |
| `SaveManager` | `res://scripts/core/save_manager.gd` | 存档读写、自动存档触发 |

**设计决策**：核心数据（作物定义、建筑定义等）使用 `GameData` 集中管理，而非散落在各系统脚本中。这样 Phase 1 就能建立清晰的数据驱动架构，后续添加新作物/建筑只需修改数据表。

---

### 1.2 GridSystem（地块网格系统）

**文件**：`scripts/systems/grid_system.gd`

#### 节点结构

```
GridSystem (Node3D)
├── GridOverlay (MeshInstance3D)      — 网格线可视化（可选）
├── GridCells (Node3D)                — 运行时单元格标记容器
│   └── CellMarker_* (MeshInstance3D) — 高亮/预览标记
└── GridData (Node)                   — 纯数据节点（无视觉）
```

#### 网格规格

- 世界尺寸：`36.0 × 28.0`（与 TerrainBuilder.WORLD_SIZE 一致）
- 网格单元：`1.0 × 1.0` 世界单位
- 总网格数：`36 × 28 = 1008` 格
- 网格原点：世界坐标 `(-18.0, -14.0)` 对应网格 `(0, 0)`
- 坐标转换：
  - `world_to_grid(wx, wz) → (gx, gz)`：`gx = floor(wx + 18.0)`, `gz = floor(wz + 14.0)`
  - `grid_to_world(gx, gz) → (wx, wz)`：`wx = gx - 17.5`, `wz = gz - 13.5`（返回格子中心）

#### GridCell 状态机

```
WASTELAND（荒地）
    │  使用锄头开垦
    ▼
FARMLAND（农田）
    │  种植种子
    ▼
PLANTED（已种植）
    │  作物成熟后收获
    ▼
FARMLAND（回到农田，可再次种植）
```

其他状态（由建筑系统设置）：
- `BUILDING` — 被建筑占用
- `ROAD` — 道路（与现有道路系统重叠区域）
- `WATER` — 水域
- `DECORATION` — 装饰物

#### 坡度判定

利用现有 `TerrainBuilder.sample_height()` 计算坡度：

```gdscript
# 计算网格 (gx, gz) 处的坡度
func get_slope_at(gx: int, gz: int) -> float:
    var wx := float(gx) - 17.5
    var wz := float(gz) - 13.5
    var h_center := terrain.get_height_at(wx, wz)
    var h_right := terrain.get_height_at(wx + 0.5, wz)
    var h_forward := terrain.get_height_at(wx, wz + 0.5)
    var slope_x := absf(h_right - h_center) / 0.5
    var slope_z := absf(h_forward - h_center) / 0.5
    return sqrt(slope_x * slope_x + slope_z * slope_z)
```

坡度阈值：`> 0.35` 不可开垦为农田。

#### 核心接口

```gdscript
class_name GridSystem extends Node3D

# 查询
func get_cell(gx: int, gz: int) -> GridCell
func get_cell_at_world(wx: float, wz: float) -> GridCell
func get_cells_in_rect(gx: int, gz: int, w: int, h: int) -> Array[GridCell]
func is_cell_available(gx: int, gz: int, required_state: GridCell.State) -> bool

# 修改
func set_cell_state(gx: int, gz: int, state: GridCell.State) -> void
func plant_crop(gx: int, gz: int, crop_data: CropData) -> CropInstance
func harvest_crop(gx: int, gz: int) -> Dictionary  # {items: [...], exp: int}
func water_cell(gx: int, gz: int) -> void

# 地形查询
func get_terrain_height_at_cell(gx: int, gz: int) -> float
func get_slope_at_cell(gx: int, gz: int) -> float
func can_farm_at(gx: int, gz: int) -> bool  # 坡度 + 非水域 + 非建筑

# 可视化
func highlight_cell(gx: int, gz: int, color: Color) -> void
func clear_highlights() -> void
```

#### 数据存储

`GridSystem` 内部使用一维字典存储，key 为 `gx * 1000 + gz`：

```gdscript
var _cells: Dictionary = {}  # int_key → GridCell
```

初始化时只创建农庄区域内的网格（约 60% 地形），其他区域按需创建。

---

### 1.3 FarmingSystem（种植系统）

**文件**：`scripts/systems/farming_system.gd`

#### 生长驱动机制

生长由游戏内时间驱动，而非实时计时。每天结束时（`EventBus.day_changed`），`FarmingSystem` 遍历所有已种植网格，推进生长阶段。

```
每日更新流程：
1. 接收 EventBus.day_changed 信号
2. 遍历所有 PLANTED 状态的 GridCell
3. 对每个 CropInstance：
   a. 检查季节是否允许生长
   b. 检查是否浇水 → 决定生长速度
   c. 推进 growth_days
   d. 如果 growth_days >= crop_data.growth_days → 标记为成熟
   e. 更新视觉表现（Sprite3D 切换）
```

#### 作物视觉表现

每种作物使用 Sprite3D Billboard，每个生长阶段一张图：

```
CropVisual (Sprite3D)
├── stage_0_seed.png
├── stage_1_sprout.png
├── stage_2_growing.png
└── stage_3_mature.png
```

阶段切换时替换 `texture` 属性。Phase 1 先用简单色块 MeshInstance3D 占位，后续替换为美术资源。

#### 浇水机制

- 每个 GridCell 有 `watered: bool` 标志
- 使用浇水壶工具时设置 `watered = true`
- 每天结束时重置所有 `watered = false`
- 浇水时生长速度 × 1.5
- 未浇水时正常速度生长（不会死亡，只是慢）

#### 季节过滤

```gdscript
func _can_crop_grow_in_season(crop_data: CropData, season: Season) -> bool:
    if crop_data.seasons.is_empty():
        return true  # 无季节限制
    return season in crop_data.seasons
```

温室建筑内的作物忽略季节过滤。

#### 核心接口

```gdscript
class_name FarmingSystem extends Node

func plant(grid_cell: GridCell, seed_item: SeedItem) -> CropInstance
func harvest(grid_cell: GridCell) -> Dictionary  # {items: [...], exp: int}
func water(grid_cell: GridCell) -> void
func on_day_changed(new_day: int) -> void  # 推进所有作物生长
func get_all_planted_cells() -> Array[GridCell]
```

---

### 1.4 BuildingSystem（建造系统）

**文件**：`scripts/systems/building_system.gd`

#### 建造预览

使用半透明的 MeshInstance3D 作为预览：

```gdscript
# 预览节点结构
BuildingPreview (Node3D)
├── PreviewMesh (MeshInstance3D)  # 半透明，绿色=可放置，红色=不可放置
└── FootprintMarkers (Node3D)     # 占用网格的角标标记
```

预览跟随鼠标射线检测到的网格位置移动。鼠标移动时：
1. 射线检测 → 获取世界坐标
2. 转换为网格坐标
3. 检查所有占用网格是否可用
4. 更新预览颜色（绿/红）

#### 建造验证

```gdscript
func can_place_building(building_data: BuildingData, gx: int, gz: int) -> bool:
    for dx in building_data.footprint_x:
        for dz in building_data.footprint_z:
            var cell := grid_system.get_cell(gx + dx, gz + dz)
            if cell == null or cell.state != GridCell.State.FARMLAND:
                if cell == null or cell.state != GridCell.State.WASTELAND:
                    return false
    # 检查资源是否足够
    return economy_system.has_resources(building_data.cost)
```

#### 建筑放置

```gdscript
func place_building(building_data: BuildingData, gx: int, gz: int) -> BuildingInstance:
    # 1. 消耗资源
    economy_system.spend_resources(building_data.cost)
    
    # 2. 标记网格
    for dx in building_data.footprint_x:
        for dz in building_data.footprint_z:
            grid_system.set_cell_state(gx + dx, gz + dz, GridCell.State.BUILDING)
    
    # 3. 实例化建筑场景
    var instance := building_data.scene.instantiate() as BuildingInstance
    instance.configure(building_data, gx, gz)
    var wy := grid_system.get_terrain_height_at_cell(gx, gz)
    instance.global_position = Vector3(
        grid_system.grid_to_world(gx, gz).x,
        wy,
        grid_system.grid_to_world(gx, gz).y
    )
    buildings_container.add_child(instance)
    
    # 4. 触发效果（如谷仓增加背包容量）
    building_data.on_placed.emit(instance)
    
    return instance
```

#### 主游戏操作模式与连续建造

主游戏由 `PlayerActionController` 统一管理种植和建造两种操作模式。HUD 只呈现控制器状态，并将数字键或鼠标按钮选择转发给同一个 `select_mode_slot()` 接口，不保存第二份选择状态。

| 模式 | 切换键 | 数字键 | 固定顺序 |
|---|---|---|---|
| 种植 | `P` | `1–6` | 锄头、浇水壶、斧头、镐、鱼竿、谷物种子 |
| 建造 | `B` | `1–9` | 谷仓、温室、风车、鸡舍、蜂箱、水井、工作台、路灯、围栏 |

- 首次进入种植模式默认锄头，首次进入建造模式默认谷仓。
- 两种模式分别记忆最后一次有效选择；切换回来时恢复各自选择。
- `Esc` 清除当前选择、单格阴影或建筑预览，但不改变当前模式和记忆项。
- 种植模式由鼠标地面射线显示单格绿/红阴影，左键执行翻地、浇水、播种或收获。
- 建造模式调用 `BuildingSystem` 的现有完成态模型和 footprint 预览；可建造为绿色，不可建造为红色。
- 红色位置点击不扣资源、不修改网格、不创建建筑。
- 绿色位置点击创建 `FOUNDATION` 阶段的建筑；成功后立即恢复同类预览，允许连续建造。
- 任一时刻只允许显示一种世界预览。模式切换和取消操作必须先清理旧预览。

#### 建筑场景结构

每种建筑有独立 `.tscn` 场景：

```
Barn (Node3D) — BuildingInstance
├── Mesh (MeshInstance3D)        — 建筑外观
├── Collision (StaticBody3D)     — 碰撞体
│   └── CollisionShape3D
└── InteractionArea (Area3D)     — 交互区域（点击进入建筑内部菜单）
    └── CollisionShape3D
```

#### 核心接口

```gdscript
class_name BuildingSystem extends Node3D

func enter_preview_mode(building_data: BuildingData) -> void
func exit_preview_mode() -> void
func can_place(building_data: BuildingData, gx: int, gz: int) -> bool
func place_building(building_data: BuildingData, gx: int, gz: int) -> BuildingInstance
func remove_building(instance: BuildingInstance) -> void  # 拆除
func get_all_buildings() -> Array[BuildingInstance]
func get_buildings_of_type(type: String) -> Array[BuildingInstance]
```

---

### 1.5 InventorySystem（背包系统）

**文件**：`scripts/systems/inventory_system.gd`

#### 背包容器

```gdscript
class_name Inventory extends Node

var slots: Array[InventorySlot] = []
var max_slots: int = 20
var quick_slots: Array[InventorySlot] = []  # 6格快捷栏

func add_item(item: Item, quantity: int = 1) -> bool:
    # 1. 尝试堆叠到已有槽位
    for slot in slots:
        if slot.item != null and slot.item.can_stack_with(item):
            var added := mini(quantity, slot.item.max_stack - slot.quantity)
            slot.quantity += added
            quantity -= added
            if quantity <= 0:
                EventBus.item_added.emit(item)
                return true
    # 2. 放入空槽位
    if slots.size() < max_slots:
        var new_slot := InventorySlot.new()
        new_slot.item = item
        new_slot.quantity = quantity
        slots.append(new_slot)
        EventBus.item_added.emit(item)
        return true
    return false  # 背包已满

func remove_item(item_id: String, quantity: int = 1) -> bool
func has_item(item_id: String, quantity: int = 1) -> bool
func get_item_count(item_id: String) -> int
func swap_slots(from_index: int, to_index: int) -> void
func set_quick_slot(slot_index: int, quick_index: int) -> void
```

#### 快捷栏同步

快捷栏不持有独立物品，而是对背包槽位的引用：

```gdscript
# quick_slots[i] 指向 slots[quick_slot_mappings[i]]
var quick_slot_mappings: Array[int] = [-1, -1, -1, -1, -1, -1]

func get_quick_item(index: int) -> Item:
    var slot_idx := quick_slot_mappings[index]
    if slot_idx >= 0 and slot_idx < slots.size():
        return slots[slot_idx].item
    return null
```

#### 物品使用

```gdscript
func use_item(slot_index: int, target: Variant = null) -> bool:
    var slot := slots[slot_index]
    if slot.item == null:
        return false
    var result := slot.item.on_use(target)
    if result and slot.item.consumable:
        slot.quantity -= 1
        if slot.quantity <= 0:
            slots.erase(slot)
    return result
```

---

### 1.6 EconomySystem（经济系统）

**文件**：`scripts/systems/economy_system.gd`

#### 金币管理

```gdscript
class_name EconomySystem extends Node

var gold: int = 100  # 初始金币

func add_gold(amount: int) -> void:
    gold += amount
    EventBus.gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
    if gold >= amount:
        gold -= amount
        EventBus.gold_changed.emit(gold)
        return true
    return false
```

#### 订单系统

```gdscript
# 订单生成
func generate_daily_orders() -> Array[Order]:
    var orders: Array[Order] = []
    var count := randi_range(2, 3)
    for i in count:
        var order := Order.new()
        order.item_id = _random_order_item()
        order.quantity = randi_range(1, 5)
        order.reward_gold = _calculate_reward(order.item_id, order.quantity)
        order.reward_exp = order.reward_gold / 2
        order.days_remaining = 3
        order.villager_id = _random_villager()
        orders.append(order)
    return orders

# 订单完成
func complete_order(order: Order) -> bool:
    if not inventory.has_item(order.item_id, order.quantity):
        return false
    inventory.remove_item(order.item_id, order.quantity)
    add_gold(order.reward_gold)
    EventBus.exp_gained.emit(order.reward_exp)
    EventBus.order_completed.emit(order)
    # 提升对应村民好感度
    var villager := villager_system.get_villager(order.villager_id)
    if villager:
        villager_system.add_affinity(villager, 10)
    return true
```

#### 物品定价表

定价在 `GameData` 中定义：

```gdscript
# game_data.gd 中的定价
const ITEM_PRICES := {
    # 蔬菜
    "tomato": {"buy": 5, "sell": 8},
    "carrot": {"buy": 4, "sell": 7},
    "potato": {"buy": 3, "sell": 6},
    # 水果
    "strawberry": {"buy": 10, "sell": 15},
    "blueberry": {"buy": 12, "sell": 18},
    "watermelon": {"buy": 15, "sell": 25},
    # 花卉
    "sunflower": {"buy": 8, "sell": 12},
    "rose": {"buy": 10, "sell": 16},
    "lavender": {"buy": 8, "sell": 14},
    # 稀有
    "moonflower": {"buy": 0, "sell": 50},
    "stardust_fruit": {"buy": 0, "sell": 80},
    # 材料
    "wood": {"buy": 2, "sell": 1},
    "stone": {"buy": 3, "sell": 1},
    "iron": {"buy": 8, "sell": 3},
    "fiber": {"buy": 1, "sell": 0},
    "glass": {"buy": 5, "sell": 2},
}
```

---

### 1.7 SeasonSystem（季节系统）

**文件**：`scripts/systems/season_system.gd`

#### 时间驱动

```gdscript
class_name SeasonSystem extends Node

enum Season { SPRING, SUMMER, AUTUMN, WINTER }
const SEASON_NAMES := ["春", "夏", "秋", "冬"]
const DAYS_PER_SEASON := 7

var current_season: Season = Season.SPRING
var current_day: int = 1        # 当前季节内的天数 (1-7)
var total_days: int = 1         # 总天数
var hour: int = 6               # 游戏内小时 (0-23)
var minute: int = 0             # 游戏内分钟

# 可游玩时段为 06:00 到次日 06:00，共 1080 游戏分钟。
# 300 现实秒推进一个完整游戏日。
const REAL_SECONDS_PER_DAY := 300.0
const GAME_MINUTES_PER_DAY := 18.0 * 60.0
const MINUTES_PER_REAL_SECOND := GAME_MINUTES_PER_DAY / REAL_SECONDS_PER_DAY

var _accumulator := 0.0

func _process(delta: float) -> void:
    _accumulator += delta * MINUTES_PER_REAL_SECOND
    var whole_minutes := int(_accumulator)
    if whole_minutes > 0:
        _accumulator -= whole_minutes
        advance_game_minutes(whole_minutes)

func _advance_day() -> void:
    hour = 6
    current_day += 1
    total_days += 1
    if current_day > DAYS_PER_SEASON:
        current_day = 1
        current_season = (current_season + 1) % 4 as Season
        EventBus.season_changed.emit(current_season)
    EventBus.day_changed.emit(total_days)

# 调试构建中按 N 调用，复用正常时间和日期事件链。
func advance_to_next_day() -> void:
    var minutes_until_next_day := (24 - hour) * 60 - minute
    advance_game_minutes(maxi(1, minutes_until_next_day))
```

主场景只在调试构建中响应 `N`。未浇水作物每天增加 `1.0`
生长进度，当天浇水则增加 `1.5`；加速生长允许跳过一个中间外观阶段。

#### 季节视觉切换

季节切换时修改环境参数和地形材质：

```gdscript
func _apply_season_visuals(season: Season) -> void:
    var config := SEASON_CONFIGS[season]
    # 地形材质
    terrain_material.albedo_texture = load(config.terrain_texture)
    terrain_material.albedo_color = config.terrain_tint
    # 环境光
    environment.ambient_light_color = config.ambient_color
    environment.ambient_light_energy = config.ambient_energy
    # 太阳光
    sun.light_color = config.sun_color
    sun.light_energy = config.sun_energy
    # 天空
    environment.background_color = config.sky_color
    # 天气粒子（冬季雪花等）
    _update_weather_particles(season)
```

```gdscript
const SEASON_CONFIGS := {
    Season.SPRING: {
        terrain_texture = "res://assets/terrain/grass-seamless-blended.png",
        terrain_tint = Color(0.85, 1.0, 0.8),
        ambient_color = Color(0.8, 0.9, 1.0),
        ambient_energy = 0.35,
        sun_color = Color(1.0, 0.97, 0.9),
        sun_energy = 0.75,
        sky_color = Color(0.5, 0.72, 0.9),
    },
    Season.SUMMER: {
        terrain_texture = "res://assets/terrain/grass-seamless-blended.png",
        terrain_tint = Color(0.7, 0.9, 0.6),
        ambient_color = Color(0.9, 0.95, 1.0),
        ambient_energy = 0.4,
        sun_color = Color(1.0, 1.0, 0.85),
        sun_energy = 0.85,
        sky_color = Color(0.4, 0.65, 0.95),
    },
    Season.AUTUMN: {
        terrain_texture = "res://assets/terrain/grass-seamless-blended.png",
        terrain_tint = Color(1.0, 0.85, 0.55),
        ambient_color = Color(1.0, 0.85, 0.7),
        ambient_energy = 0.3,
        sun_color = Color(1.0, 0.9, 0.7),
        sun_energy = 0.65,
        sky_color = Color(0.55, 0.6, 0.8),
    },
    Season.WINTER: {
        terrain_texture = "res://assets/terrain/grass-seamless-blended.png",
        terrain_tint = Color(0.9, 0.92, 0.95),
        ambient_color = Color(0.7, 0.75, 0.85),
        ambient_energy = 0.25,
        sun_color = Color(0.9, 0.92, 0.95),
        sun_energy = 0.5,
        sky_color = Color(0.6, 0.65, 0.75),
    },
}
```

#### 树木季节外观

`VegetationBuilder` 扩展：每种树木纹理有季节变体（Phase 5 实现），季节切换时批量替换：

```gdscript
func update_tree_season(season: Season) -> void:
    for tree in get_children():
        if tree is Sprite3D:
            var variant := _get_tree_variant_name(tree)
            var texture_path := _season_texture_path(variant, season)
            tree.texture = load(texture_path) as Texture2D
```

---

### 1.8 VillagerSystem（村民系统）

**文件**：`scripts/systems/villager_system.gd`

#### 村民 AI 状态机

```
IDLE（空闲）
    │  到达日程时间
    ▼
MOVING_TO_WORK（前往工作地点）
    │  到达目的地
    ▼
WORKING（工作）
    │  到达下班时间
    ▼
MOVING_TO_WANDER（散步）
    │  到达目的地
    ▼
WANDERING（散步）
    │  到达回家时间
    ▼
MOVING_TO_HOME（回家）
    │  到达家
    ▼
SLEEPING（睡觉）
    │  第二天早上
    ▼
IDLE
```

#### 日程定义

每个村民的日程用数据驱动：

```gdscript
# VillagerData 中的日程
schedule = [
    {"hour_start": 6, "hour_end": 8, "state": "IDLE", "position": "home"},
    {"hour_start": 8, "hour_end": 12, "state": "WORKING", "position": "shop"},
    {"hour_start": 12, "hour_end": 13, "state": "IDLE", "position": "shop"},
    {"hour_start": 13, "hour_end": 17, "state": "WORKING", "position": "shop"},
    {"hour_start": 17, "hour_end": 19, "state": "WANDERING", "position": "random_waypoint"},
    {"hour_start": 19, "hour_end": 21, "state": "MOVING_TO_HOME", "position": "home"},
    {"hour_start": 21, "hour_end": 6, "state": "SLEEPING", "position": "home"},
]
```

#### 对话系统

对话数据使用简单的节点树结构：

```gdscript
class_name DialogueNode extends Resource

var text: String = ""
var choices: Array[DialogueChoice] = []
var next_node: String = ""  # 默认下一节点ID
var conditions: Dictionary = {}  # 触发条件（如好感度等级）
var effects: Dictionary = {}  # 对话效果（如好感度+5）

class_name DialogueChoice extends Resource
var text: String = ""
var next_node: String = ""
```

对话文件存储为 `.tres` 资源，每个村民一个对话树。

#### 好感度系统

```gdscript
class_name VillagerAffinity extends Resource

var villager_id: String = ""
var value: int = 0  # 0-100

enum Level { STRANGER, FRIEND, CLOSE, SOULMATE }

func get_level() -> Level:
    if value <= 20: return Level.STRANGER
    if value <= 50: return Level.FRIEND
    if value <= 80: return Level.CLOSE
    return Level.SOULMATE

func add(amount: int) -> void:
    var old_level := get_level()
    value = clampi(value + amount, 0, 100)
    var new_level := get_level()
    EventBus.affinity_changed.emit(villager_id, value)
    if new_level != old_level:
        EventBus.affinity_level_up.emit(villager_id, new_level)
        _grant_level_reward(new_level)
```

---

### 1.9 ExplorationSystem（探索系统）

**文件**：`scripts/systems/exploration_system.gd`

#### 迷雾实现

使用 Shader 实现区域迷雾：

```glsl
// fog_of_war.gdshader
shader_type spatial;
render_mode unshaded, depth_draw_never;

uniform sampler2D fog_texture;  // 探索状态纹理（白色=已探索，黑色=未探索）
uniform vec2 world_size = vec2(36.0, 28.0);
uniform vec2 world_offset = vec2(-18.0, -14.0);

void fragment() {
    vec2 uv = (WORLD_POS.xz - world_offset) / world_size;
    float fog = texture(fog_texture, uv).r;
    ALPHA = 1.0 - fog;
    ALBEDO = vec3(0.1, 0.12, 0.15);
}
```

迷雾层是一个覆盖整个世界的平面 MeshInstance3D，使用上述 Shader。探索状态存储在一个 `Image` 中：

```gdscript
var fog_image: Image  # 256x256 灰度图，0=未探索，255=已探索

func reveal_area(center_x: float, center_z: float, radius: float) -> void:
    var img_w := fog_image.get_width()
    var img_h := fog_image.get_height()
    var uv_x := (center_x + 18.0) / 36.0
    var uv_z := (center_z + 14.0) / 28.0
    var pixel_cx := int(uv_x * img_w)
    var pixel_cz := int(uv_z * img_h)
    var pixel_radius := int(radius / 36.0 * img_w)
    for dz in range(-pixel_radius, pixel_radius + 1):
        for dx in range(-pixel_radius, pixel_radius + 1):
            if dx * dx + dz * dz <= pixel_radius * pixel_radius:
                var px := clampi(pixel_cx + dx, 0, img_w - 1)
                var py := clampi(pixel_cz + dz, 0, img_h - 1)
                fog_image.set_pixel(px, py, Color.WHITE)
    fog_texture.update(fog_image)
```

玩家每帧检查位置，自动揭示周围区域（半径 3.0）。

#### 区域解锁

```gdscript
class_name RegionManager extends Node

var regions: Dictionary = {}  # region_id → RegionData

func is_unlocked(region_id: String) -> bool:
    var region: RegionData = regions.get(region_id)
    return region != null and region.unlocked

func unlock_region(region_id: String) -> bool:
    var region: RegionData = regions.get(region_id)
    if region == null:
        return false
    # 检查解锁条件
    if not _check_unlock_conditions(region):
        return false
    region.unlocked = true
    EventBus.region_unlocked.emit(region)
    # 移除该区域的物理障碍/迷雾
    _activate_region(region)
    return true

func _check_unlock_conditions(region: RegionData) -> bool:
    for condition in region.unlock_conditions:
        match condition.type:
            "level":
                if GameState.player_level < condition.value:
                    return false
            "item":
                if not InventorySystem.has_item(condition.item_id):
                    return false
            "resource":
                if not EconomySystem.has_resources(condition.resources):
                    return false
            "story_progress":
                if StorySystem.fragment_count < condition.value:
                    return false
    return true
```

---

### 1.10 CollectibleSystem（收集品系统）

**文件**：`scripts/systems/collectible_system.gd`

#### 收集品在世界中的放置

收集品使用场景节点 + 数据驱动混合方式：

- 每个收集品在场景中是一个 `CollectiblePickup` (Area3D) 节点
- 节点通过 `collectible_id` 关联到 `GameData` 中的定义
- 玩家进入 Area3D 范围时触发收集

```gdscript
class_name CollectiblePickup extends Area3D

@export var collectible_id: String = ""
@export var float_amplitude: float = 0.15
@export var float_speed: float = 2.0

var _collected := false

func _ready() -> void:
    body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
    if not _collected:
        position.y += sin(Time.get_ticks_msec() / 1000.0 * float_speed) * float_amplitude * delta

func _on_body_entered(body: Node3D) -> void:
    if _collected or not body is PlayerController:
        return
    _collected = true
    var data := GameData.get_collectible(collectible_id)
    if data:
        CollectibleSystem.collect(data)
        EventBus.collectible_found.emit(data)
    queue_free()
```

#### 图鉴系统

```gdscript
class_name CollectionBook extends Node

var discovered: Dictionary = {}  # collectible_id → true
var categories: Dictionary = {}  # category → {total: int, found: int}

func discover(collectible_id: String) -> void:
    if discovered.has(collectible_id):
        return
    discovered[collectible_id] = true
    var data := GameData.get_collectible(collectible_id)
    if data:
        var cat := categories.get(data.category, {"total": 0, "found": 0})
        cat.found += 1
        categories[data.category] = cat
        if cat.found >= cat.total:
            EventBus.category_completed.emit(data.category)
```

---

### 1.11 PuzzleSystem（解谜系统）

**文件**：`scripts/systems/puzzle_system.gd`

#### 谜题基类

```gdscript
class_name Puzzle extends Node3D

signal puzzle_solved(puzzle_id: String)

@export var puzzle_id: String = ""
@export var reward_items: Array[String] = []
@export var reward_gold: int = 0

var is_solved: bool = false

func _solve() -> void:
    if is_solved:
        return
    is_solved = true
    _grant_rewards()
    puzzle_solved.emit(puzzle_id)
    EventBus.puzzle_solved.emit(puzzle_id)

func _grant_rewards() -> void:
    for item_id in reward_items:
        InventorySystem.add_item(item_id)
    if reward_gold > 0:
        EconomySystem.add_gold(reward_gold)

func reset() -> void:
    is_solved = false
    _reset_visuals()
```

#### 具体谜题实现

**推石头谜题（PushPuzzle）**：

```gdscript
class_name PushPuzzle extends Puzzle

@export var target_positions: Array[Vector3] = []
@export var stones: Array[Node3D] = []

func _physics_process(_delta: float) -> void:
    if is_solved:
        return
    var all_on_target := true
    for target in target_positions:
        var found := false
        for stone in stones:
            if stone.global_position.distance_to(target) < 0.5:
                found = true
                break
        if not found:
            all_on_target = false
            break
    if all_on_target:
        _solve()
```

**献祭台谜题（OfferingPuzzle）**：

```gdscript
class_name OfferingPuzzle extends Puzzle

@export var required_items: Dictionary = {}  # item_id → quantity
@export var offering_slots: Array[Node3D] = []

func check_offering() -> void:
    for item_id in required_items:
        var needed: int = required_items[item_id]
        if InventorySystem.get_item_count(item_id) < needed:
            return
    # 消耗物品
    for item_id in required_items:
        InventorySystem.remove_item(item_id, required_items[item_id])
    _solve()
```

---

### 1.12 StorySystem（故事系统）

**文件**：`scripts/systems/story_system.gd`

```gdscript
class_name StorySystem extends Node

var collected_fragments: Array[String] = []
var story_revealed_up_to: int = 0  # 已揭示的故事章节

const STORY_MILESTONES := [
    {"fragments_needed": 3, "chapter": 1, "text_key": "story_chapter_1"},
    {"fragments_needed": 6, "chapter": 2, "text_key": "story_chapter_2"},
    {"fragments_needed": 9, "chapter": 3, "text_key": "story_chapter_3"},
    {"fragments_needed": 12, "chapter": 4, "text_key": "story_chapter_4"},
]

func collect_fragment(fragment_id: String) -> void:
    if fragment_id in collected_fragments:
        return
    collected_fragments.append(fragment_id)
    EventBus.story_fragment_collected.emit(fragment_id)
    _check_story_progress()

func _check_story_progress() -> void:
    var count := collected_fragments.size()
    for milestone in STORY_MILESTONES:
        if count >= milestone.fragments_needed and story_revealed_up_to < milestone.chapter:
            story_revealed_up_to = milestone.chapter
            _reveal_chapter(milestone)
            EventBus.story_chapter_revealed.emit(milestone.chapter)

func _reveal_chapter(milestone: Dictionary) -> void:
    # 显示故事文本（通过 DialogueUI）
    var text := GameData.get_story_text(milestone.text_key)
    EventBus.story_text_display.emit(text)
    # 解锁对应区域或功能
    match milestone.chapter:
        1: RegionManager.unlock_region("creek")
        2: RegionManager.unlock_region("deep_forest")
        3: RegionManager.unlock_region("mist_peak")
        4: RegionManager.unlock_region("secret_garden")
```

---

### 1.13 ToolSystem（工具系统）

**文件**：`scripts/systems/tool_system.gd`

#### 工具基类

```gdscript
class_name Tool extends Item

enum ToolType { HOE, WATERING_CAN, AXE, PICKAXE, LANTERN, GLIDER, ROPE, COMPASS, DIVING_MASK, FISHING_ROD }

@export var tool_type: ToolType = ToolType.HOE
@export var stamina_cost: int = 5
@export var range: float = 2.0
@export var level: int = 1  # 工具等级，影响效率

func on_use(target: Variant) -> bool:
    # 检查体力
    if PlayerState.stamina < stamina_cost:
        return false
    PlayerState.stamina -= stamina_cost
    EventBus.stamina_changed.emit(PlayerState.stamina)
    # 执行工具功能
    _execute_tool_action(target)
    return false  # 工具不消耗（consumable = false）

func _execute_tool_action(target: Variant) -> void:
    pass  # 子类实现
```

#### 具体工具

```gdscript
class_name HoeTool extends Tool

func _execute_tool_action(target: Variant) -> void:
    if target is GridCell:
        if target.state == GridCell.State.WASTELAND:
            target.state = GridCell.State.FARMLAND
            EventBus.cell_state_changed.emit(target)

class_name WateringCanTool extends Tool

func _execute_tool_action(target: Variant) -> void:
    if target is GridCell:
        if target.state == GridCell.State.PLANTED:
            target.watered = true
            EventBus.cell_watered.emit(target)

class_name AxeTool extends Tool

func _execute_tool_action(target: Variant) -> void:
    if target is TreeInstance:
        target.take_damage(level)  # 树木有"耐久"，砍伐多次后倒下
```

#### 工具切换

```gdscript
# PlayerController 中
var current_tool: Tool = null
var tool_index: int = 0

func _unhandled_input(event: InputEvent) -> void:
    # 数字键切换工具
    if event is InputEventKey and event.pressed:
        if event.keycode >= KEY_1 and event.keycode <= KEY_6:
            tool_index = event.keycode - KEY_1
            current_tool = InventorySystem.get_quick_item(tool_index) as Tool
            EventBus.tool_changed.emit(current_tool)
    
    # 鼠标左键使用工具
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if current_tool:
            var target := _get_tool_target()
            current_tool.on_use(target)
```

---

## 2. 数据结构定义

### 2.1 GridCell

```gdscript
class_name GridCell extends RefCounted

enum State { WASTELAND, FARMLAND, PLANTED, BUILDING, ROAD, WATER, DECORATION }

var gx: int = 0
var gz: int = 0
var state: State = State.WASTELAND
var watered: bool = false
var crop_instance: CropInstance = null
var building_instance: Node = null
var terrain_height: float = 0.0
var slope: float = 0.0

func world_position() -> Vector2:
    return Vector2(float(gx) - 17.5, float(gz) - 13.5)

func world_position_3d() -> Vector3:
    var wp := world_position()
    return Vector3(wp.x, terrain_height, wp.y)
```

### 2.2 CropData

```gdscript
class_name CropData extends Resource

@export var crop_id: String = ""
@export var crop_name: String = ""
@export var category: String = ""  # "vegetable", "fruit", "flower", "rare", "aquatic"
@export var growth_days: int = 3
@export var seasons: Array[int] = []  # SeasonSystem.Season 枚举值
@export var seed_price: int = 5
@export var sell_price: int = 8
@export var exp_reward: int = 5
@export var seed_drop_chance: float = 0.2  # 收获时额外掉落种子概率
@export var stage_textures: Array[String] = []  # 各阶段纹理路径
@export var water_required: bool = false  # 是否必须浇水才能生长
```

### 2.3 CropInstance

```gdscript
class_name CropInstance extends RefCounted

var crop_data: CropData
var growth_days: int = 0
var is_watered_today: bool = false
var is_mature: bool = false
var cell: GridCell = null

func advance_growth() -> void:
    if is_mature:
        return
    var speed := 1.5 if is_watered_today else 1.0
    growth_days += int(speed)
    is_watered_today = false  # 重置浇水状态
    if growth_days >= crop_data.growth_days:
        is_mature = true

func get_current_stage() -> int:
    if is_mature:
        return crop_data.stage_textures.size() - 1
    var progress := float(growth_days) / float(crop_data.growth_days)
    return mini(int(progress * crop_data.stage_textures.size()), crop_data.stage_textures.size() - 2)
```

### 2.4 BuildingData

```gdscript
class_name BuildingData extends Resource

@export var building_id: String = ""
@export var building_name: String = ""
@export var scene_path: String = ""
@export var footprint: Vector2i = Vector2i(1, 1)  # 占用网格尺寸
@export var cost: Dictionary = {}  # {"wood": 100, "stone": 50}
@export var unlock_level: int = 1
@export var description: String = ""
@export var effect_type: String = ""  # "inventory_expand", "crafting", "animal_housing"
@export var effect_value: int = 0
```

### 2.5 BuildingInstance

```gdscript
class_name BuildingInstance extends Node3D

var building_data: BuildingData
var grid_x: int = 0
var grid_z: int = 0
var occupied_cells: Array[GridCell] = []

func configure(data: BuildingData, gx: int, gz: int) -> void:
    building_data = data
    grid_x = gx
    grid_z = gz

func get_interaction_area() -> Area3D:
    return get_node_or_null("InteractionArea") as Area3D
```

### 2.6 Item 基类与子类

```gdscript
class_name Item extends Resource

enum ItemType { TOOL, SEED, CROP, MATERIAL, COLLECTIBLE, FOOD, FISH }

@export var item_id: String = ""
@export var item_name: String = ""
@export var item_type: ItemType = ItemType.MATERIAL
@export var icon_path: String = ""
@export var description: String = ""
@export var max_stack: int = 99
@export var consumable: bool = false
@export var sell_price: int = 0

func can_stack_with(other: Item) -> bool:
    return item_id == other.item_id

func on_use(target: Variant) -> bool:
    return false

class_name SeedItem extends Item
@export var crop_id: String = ""

class_name CropItem extends Item
@export var crop_data: CropData

class_name MaterialItem extends Item
@export var material_type: String = ""  # "wood", "stone", "iron", "fiber", "glass"

class_name FoodItem extends Item
@export var stamina_restore: int = 30
func on_use(target: Variant) -> bool:
    PlayerState.stamina = mini(PlayerState.stamina + stamina_restore, PlayerState.max_stamina)
    EventBus.stamina_changed.emit(PlayerState.stamina)
    return true  # 消耗品

class_name ToolItem extends Item
@export var tool_type: int = 0  # Tool.ToolType
@export var tool_level: int = 1
@export var stamina_cost: int = 5
```

### 2.7 InventorySlot

```gdscript
class_name InventorySlot extends RefCounted

var item: Item = null
var quantity: int = 0

func is_empty() -> bool:
    return item == null or quantity <= 0

func clear() -> void:
    item = null
    quantity = 0
```

### 2.8 Order

```gdscript
class_name Order extends Resource

@export var order_id: String = ""
@export var item_id: String = ""
@export var quantity: int = 1
@export var reward_gold: int = 0
@export var reward_exp: int = 0
@export var days_remaining: int = 3
@export var villager_id: String = ""
@export var is_active: bool = true

func is_expired() -> bool:
    return days_remaining <= 0

func can_complete() -> bool:
    return is_active and not is_expired() and InventorySystem.has_item(item_id, quantity)
```

### 2.9 VillagerData

```gdscript
class_name VillagerData extends Resource

@export var villager_id: String = ""
@export var villager_name: String = ""
@export var role: String = ""  # "shopkeeper", "florist", "blacksmith", "fisherman", "scholar", "traveler"
@export var scene_path: String = ""
@export var home_position: Vector3 = Vector3.ZERO
@export var work_position: Vector3 = Vector3.ZERO
@export var schedule: Array[Dictionary] = []
@export var dialogue_tree_path: String = ""
@export var affinity_rewards: Dictionary = {}  # level → reward_item_id
@export var unlock_condition: Dictionary = {}  # 村民解锁条件
```

### 2.10 DialogueNode

```gdscript
class_name DialogueNode extends Resource

@export var node_id: String = ""
@export var speaker: String = ""
@export var text: String = ""
@export var choices: Array[DialogueChoice] = []
@export var default_next: String = ""
@export var condition: Dictionary = {}  # {"affinity_min": 20, "has_item": "xxx"}
@export var effects: Dictionary = {}  # {"affinity": 5, "give_item": "xxx"}

class_name DialogueChoice extends Resource
@export var text: String = ""
@export var next_node: String = ""
@export var condition: Dictionary = {}
```

### 2.11 CollectibleData

```gdscript
class_name CollectibleData extends Resource

enum Category { DIARY_FRAGMENT, RARE_SEED, FOSSIL, ARTIFACT, PLANT_SPECIMEN, ANIMAL_TRACK, MESSAGE_BOTTLE, MINERAL }

@export var collectible_id: String = ""
@export var collectible_name: String = ""
@export var category: Category = Category.DIARY_FRAGMENT
@export var icon_path: String = ""
@export var description: String = ""
@export var region_id: String = ""  # 所在区域
@export var world_position: Vector3 = Vector3.ZERO
@export var sell_price: int = 0
@export var is_story_fragment: bool = false
```

### 2.12 PuzzleData

```gdscript
class_name PuzzleData extends Resource

enum PuzzleType { PUSH, PATH_CONNECT, LIGHT_REFLECTION, OFFERING, SEASON_LOCKED, TIME_LOCKED, STONE_CIPHER, ANCIENT_MECHANISM }

@export var puzzle_id: String = ""
@export var puzzle_type: PuzzleType = PuzzleType.PUSH
@export var scene_path: String = ""
@export var region_id: String = ""
@export var reward_items: Array[String] = []
@export var reward_gold: int = 0
@export var unlock_region: String = ""  # 解谜后解锁的区域
@export var description: String = ""
```

### 2.13 RegionData

```gdscript
class_name RegionData extends Resource

@export var region_id: String = ""
@export var region_name: String = ""
@export var unlocked: bool = false
@export var unlock_conditions: Array[Dictionary] = []
# [{"type": "level", "value": 3}, {"type": "item", "item_id": "lantern"}]
@export var bounds: Rect2 = Rect2()
@export var scene_path: String = ""
@export var stamina_drain_multiplier: float = 1.0
```

### 2.14 StoryFragment

```gdscript
class_name StoryFragment extends Resource

@export var fragment_id: String = ""
@export var chapter: int = 0
@export var text: String = ""
@export var collectible_id: String = ""  # 关联的收集品ID
```

### 2.15 SeasonConfig

```gdscript
class_name SeasonConfig extends Resource

@export var season: int = 0  # SeasonSystem.Season
@export var season_name: String = ""
@export var terrain_tint: Color = Color.WHITE
@export var ambient_color: Color = Color.WHITE
@export var ambient_energy: float = 0.3
@export var sun_color: Color = Color.WHITE
@export var sun_energy: float = 0.7
@export var sky_color: Color = Color(0.5, 0.7, 0.9)
@export var allowed_crops: Array[String] = []  # 可种植的作物ID列表
@export var special_event: String = ""
```

### 2.16 PlayerState

```gdscript
class_name PlayerState extends RefCounted

var position: Vector3 = Vector3.ZERO
var stamina: int = 100
var max_stamina: int = 100
var level: int = 1
var exp: int = 0
var exp_to_next_level: int = 100

# 等级经验表
const LEVEL_EXP := [0, 100, 250, 500, 850, 1300, 1900, 2600, 3500, 4600, 6000]

func add_exp(amount: int) -> bool:
    exp += amount
    var leveled_up := false
    while level < LEVEL_EXP.size() - 1 and exp >= LEVEL_EXP[level + 1]:
        level += 1
        leveled_up = true
        EventBus.level_changed.emit(level)
    if leveled_up:
        EventBus.exp_gained.emit(amount)
    return leveled_up

func get_exp_progress() -> float:
    if level >= LEVEL_EXP.size() - 1:
        return 1.0
    var current_req := LEVEL_EXP[level]
    var next_req := LEVEL_EXP[level + 1]
    return clampf(float(exp - current_req) / float(next_req - current_req), 0.0, 1.0)
```

### 2.17 SaveData

```gdscript
class_name SaveData extends Resource

# 玩家
var player_position: Vector3 = Vector3.ZERO
var player_stamina: int = 100
var player_level: int = 1
var player_exp: int = 0

# 世界
var current_season: int = 0
var current_day: int = 1
var total_days: int = 1
var hour: int = 6
var minute: int = 0
var gold: int = 100

# 背包
var inventory_slots: Array[Dictionary] = []
var quick_slot_mappings: Array[int] = []

# 网格
var grid_cells: Array[Dictionary] = []
# [{"gx": 5, "gz": 10, "state": 2, "watered": true, "crop_id": "tomato", "growth_days": 2}]

# 建筑
var buildings: Array[Dictionary] = []
# [{"building_id": "barn", "gx": 3, "gz": 5}]

# 探索
var explored_regions: Array[String] = []
var fog_image_data: PackedByteArray = []
var collected_collectibles: Array[String] = []
var solved_puzzles: Array[String] = []

# 故事
var story_fragments: Array[String] = []
var story_chapter: int = 0

# 村民
var villager_affinity: Dictionary = {}  # villager_id → affinity_value
var active_orders: Array[Dictionary] = []

# 元数据
var save_version: int = 1
var save_timestamp: int = 0
var play_time_seconds: float = 0.0
```

---

## 3. 信号与事件总线

**文件**：`scripts/core/event_bus.gd`

```gdscript
class_name EventBusClass extends Node

# ═══════════════════════════════════════════
# 农庄相关
# ═══════════════════════════════════════════
signal cell_state_changed(cell: GridCell)
signal cell_watered(cell: GridCell)
signal crop_planted(cell: GridCell, crop_data: CropData)
signal crop_grew(cell: GridCell, new_stage: int)
signal crop_matured(cell: GridCell, crop_data: CropData)
signal crop_harvested(cell: GridCell, crop_data: CropData, items: Array)
signal building_placed(building: BuildingInstance)
signal building_removed(building: BuildingInstance)
signal building_preview_moved(gx: int, gz: int, can_place: bool)
signal item_added(item: Item)
signal item_removed(item: Item, quantity: int)
signal item_used(item: Item)
signal item_sold(item: Item, quantity: int, gold_earned: int)
signal order_generated(order: Order)
signal order_completed(order: Order)
signal order_expired(order: Order)
signal gold_changed(new_gold: int)

# ═══════════════════════════════════════════
# 探索相关
# ═══════════════════════════════════════════
signal region_unlocked(region: RegionData)
signal area_revealed(center_x: float, center_z: float, radius: float)
signal collectible_found(data: CollectibleData)
signal collectible_category_completed(category: int)
signal puzzle_solved(puzzle_id: String)
signal story_fragment_collected(fragment_id: String)
signal story_chapter_revealed(chapter: int)
signal story_text_display(text: String)
signal tool_equipped(tool: Tool)
signal tool_changed(tool: Tool)
signal fishing_started(spot_id: String)
signal fishing_caught(fish_id: String)

# ═══════════════════════════════════════════
# 季节/时间
# ═══════════════════════════════════════════
signal season_changed(new_season: int)
signal day_changed(total_day: int)
signal time_changed(hour: int, minute: int)
signal weather_changed(weather_type: String)

# ═══════════════════════════════════════════
# 玩家
# ═══════════════════════════════════════════
signal stamina_changed(value: int)
signal stamina_depleted()
signal level_changed(new_level: int)
signal exp_gained(amount: int)
signal player_position_changed(position: Vector3)

# ═══════════════════════════════════════════
# 村民
# ═══════════════════════════════════════════
signal villager_greeting(villager_id: String)
signal affinity_changed(villager_id: String, new_value: int)
signal affinity_level_up(villager_id: String, new_level: int)
signal dialogue_started(villager_id: String, dialogue_node: DialogueNode)
signal dialogue_ended(villager_id: String)
signal villager_moved(villager_id: String, new_position: Vector3)

# ═══════════════════════════════════════════
# UI
# ═══════════════════════════════════════════
signal inventory_opened()
signal inventory_closed()
signal build_mode_entered()
signal build_mode_exited()
signal map_opened()
signal map_closed()
signal notification_show(text: String, icon_path: String)

# ═══════════════════════════════════════════
# 存档
# ═══════════════════════════════════════════
signal game_saved()
signal game_loaded()
```

---

## 4. 场景节点树

### 4.1 完整主场景

```
Main (Node3D) — scripts/main.gd
│
├── WorldEnvironment                  — 环境设置（天空、光照）
├── Sun (DirectionalLight3D)          — 定向光（已有）
│
├── World (Node3D) — scripts/world/world.gd
│   ├── Terrain (Node3D) — scripts/world/terrain_builder.gd [已有]
│   │   ├── TerrainMesh (MeshInstance3D)
│   │   └── TerrainBody (StaticBody3D)
│   │       └── CollisionShape3D (HeightMapShape3D)
│   ├── Road (Node3D) — scripts/world/road_builder.gd [已有]
│   │   └── RoadMesh (MeshInstance3D)
│   ├── Vegetation (Node3D) — scripts/world/vegetation_builder.gd [已有，扩展]
│   │   └── TreeInstance_* (Node3D) [改造：从 Sprite3D 升级为 TreeInstance]
│   │       ├── Sprite3D
│   │       ├── TrunkBody (StaticBody3D)
│   │       └── CameraOccluder (Area3D)
│   ├── GridOverlay (MeshInstance3D)  [新增：网格线可视化]
│   ├── Buildings (Node3D)            [新增：建筑容器]
│   │   └── BuildingInstance_* (Node3D)
│   ├── FogOfWar (MeshInstance3D)     [新增：迷雾层]
│   └── Regions (Node3D)              [新增：区域标记]
│       ├── RegionMarker_Farm (Area3D)
│       ├── RegionMarker_Creek (Area3D)
│       ├── RegionMarker_Forest (Area3D)
│       └── RegionMarker_Peak (Area3D)
│
├── Actors (Node3D)
│   ├── Player (CharacterBody3D) — scripts/actors/player.gd [已有，扩展]
│   │   ├── Mesh (MeshInstance3D)
│   │   └── CollisionShape3D
│   ├── Villagers (Node3D)            [新增：村民容器]
│   │   └── Villager_* (CharacterBody3D)
│   │       ├── Mesh (MeshInstance3D)
│   │       ├── CollisionShape3D
│   │       └── InteractionArea (Area3D)
│   └── Animals (Node3D)              [新增：动物容器]
│       └── Animal_* (CharacterBody3D)
│
├── Systems (Node)                    [新增：系统容器]
│   ├── GridSystem (Node3D) — scripts/systems/grid_system.gd
│   ├── FarmingSystem (Node) — scripts/systems/farming_system.gd
│   ├── BuildingSystem (Node3D) — scripts/systems/building_system.gd
│   │   └── BuildingPreview (Node3D)
│   ├── EconomySystem (Node) — scripts/systems/economy_system.gd
│   ├── SeasonSystem (Node) — scripts/systems/season_system.gd
│   ├── InventorySystem (Node) — scripts/systems/inventory_system.gd
│   ├── ExplorationSystem (Node) — scripts/systems/exploration_system.gd
│   ├── PuzzleSystem (Node) — scripts/systems/puzzle_system.gd
│   ├── StorySystem (Node) — scripts/systems/story_system.gd
│   ├── ToolSystem (Node) — scripts/systems/tool_system.gd
│   ├── VillagerSystem (Node) — scripts/systems/villager_system.gd
│   └── CollectibleSystem (Node) — scripts/systems/collectible_system.gd
│
├── Projectiles (Node3D)              [已有，Phase 1 后移除]
│
├── CameraRig (Node3D) — scripts/camera/camera_rig.gd [已有]
│   └── Camera3D
│
├── UI (CanvasLayer)
│   ├── HUD (CanvasLayer) — scripts/ui/hud.gd [已有，重构]
│   │   ├── TopBar (Control)
│   │   │   ├── StaminaBar (TextureProgressBar)
│   │   │   ├── GoldLabel (Label)
│   │   │   ├── LevelBar (Control)
│   │   │   ├── SeasonDateLabel (Label)
│   │   │   └── TimeLabel (Label)
│   │   ├── BottomBar (Control)
│   │   │   ├── QuickBar (HBoxContainer)
│   │   │   │   └── QuickSlot_* (TextureRect)
│   │   │   └── MiniMap (SubViewportContainer)
│   │   └── NotificationPanel (Control)
│   ├── InventoryUI (Control)         [新增]
│   ├── BuildUI (Control)             [新增]
│   ├── MapUI (Control)               [新增]
│   ├── DialogueUI (Control)          [新增]
│   └── ShopUI (Control)              [新增]
│
└── AudioManager (Node)               [新增]
    ├── MusicPlayer (AudioStreamPlayer)
    ├── SfxPlayer (AudioStreamPlayer)
    └── AmbientPlayer (AudioStreamPlayer3D)
```

### 4.2 各子场景文件

```
scenes/
├── main.tscn                         [已有，扩展]
├── world/
│   ├── world.tscn                    [已有，扩展]
│   ├── terrain.tscn                  [已有]
│   ├── road.tscn                     [已有]
│   ├── vegetation.tscn               [已有，扩展]
│   ├── grid_overlay.tscn             [新增]
│   └── fog_of_war.tscn              [新增]
├── actors/
│   ├── player.tscn                   [已有，扩展]
│   ├── npc.tscn                      [已有，Phase 1 后移除]
│   ├── villager.tscn                 [新增]
│   └── animal.tscn                   [新增]
├── buildings/                        [新增]
│   ├── barn.tscn
│   ├── greenhouse.tscn
│   ├── windmill.tscn
│   ├── chicken_coop.tscn
│   ├── beehive.tscn
│   ├── well.tscn
│   ├── workbench.tscn
│   ├── lamppost.tscn
│   └── fence.tscn
├── camera/
│   └── camera_rig.tscn               [已有]
├── combat/
│   └── projectile.tscn               [已有，Phase 1 后移除]
├── collectibles/                     [新增]
│   └── collectible_pickup.tscn
├── puzzles/                          [新增]
│   ├── push_puzzle.tscn
│   ├── path_puzzle.tscn
│   ├── light_puzzle.tscn
│   └── offering_puzzle.tscn
└── ui/
    ├── hud.tscn                      [已有，重构]
    ├── inventory_ui.tscn             [新增]
    ├── build_ui.tscn                 [新增]
    ├── map_ui.tscn                   [新增]
    ├── dialogue_ui.tscn             [新增]
    ├── shop_ui.tscn                  [新增]
    └── notification.tscn             [新增]
```

---

## 5. 现有系统改造方案

### 5.1 Player（scripts/actors/player.gd）

**保留**：
- `movement_from_input()` 静态方法 — 镜头相对移动逻辑完全保留
- WASD 移动、跳跃、重力、`_clamp_to_world()` — 全部保留
- `configure()` 方法 — 保留并扩展

**移除**：
- `fire_requested` 信号
- `health_changed` 信号
- `health` 变量
- `cooldown_remaining` / `fire_cooldown`
- `CombatMathScript` preload
- `_request_fire()` 方法
- `take_damage()` 方法
- `_unhandled_input()` 中的鼠标左键射击逻辑
- `scenes/combat/projectile.tscn` preload

**新增**：
```gdscript
# 体力系统
var stamina: int = 100
var max_stamina: int = 100

# 工具系统
var current_tool: Tool = null
var tool_quick_slots: Array[Tool] = [null, null, null, null, null, null]

# 奔跑
var is_sprinting: bool = false
const SPRINT_MULTIPLIER := 1.8
const SPRINT_STAMINA_DRAIN := 5.0  # 每秒消耗

# 交互射线
const INTERACT_RANGE := 2.5

func _physics_process(delta: float) -> void:
    # ... 保留现有移动逻辑 ...
    
    # 体力自然恢复
    if not is_sprinting and is_on_floor():
        stamina = mini(stamina + 1 * delta, max_stamina)
    
    # 奔跑消耗体力
    if is_sprinting and is_on_floor():
        stamina -= SPRINT_STAMINA_DRAIN * delta
        if stamina <= 0:
            stamina = 0
            is_sprinting = false
            EventBus.stamina_depleted.emit()
    
    EventBus.stamina_changed.emit(int(stamina))

func _unhandled_input(event: InputEvent) -> void:
    # 奔跑
    if event is InputEventKey:
        if event.keycode == KEY_SHIFT:
            is_sprinting = event.pressed and stamina > 0
    
    # 工具使用（鼠标左键）
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _use_current_tool()
    
    # 交互（鼠标右键 / E键）
    if event is InputEventKey and event.keycode == KEY_E and event.pressed:
        _interact()
    
    # 工具切换（数字键）
    if event is InputEventKey and event.pressed:
        if event.keycode >= KEY_1 and event.keycode <= KEY_6:
            _switch_tool(event.keycode - KEY_1)
    
    # UI快捷键
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_TAB, KEY_I:
                EventBus.inventory_opened.emit()
            KEY_M:
                EventBus.map_opened.emit()

func _use_current_tool() -> void:
    if current_tool == null:
        return
    var target := _raycast_for_tool_target()
    current_tool.on_use(target)

func _raycast_for_tool_target() -> Variant:
    var camera := get_viewport().get_camera_3d()
    if camera == null:
        return null
    var mouse_pos := get_viewport().get_mouse_position()
    var ray_origin := camera.project_ray_origin(mouse_pos)
    var ray_dir := camera.project_ray_normal(mouse_pos)
    var query := PhysicsRayQueryParameters3D.create(
        ray_origin, ray_origin + ray_dir * INTERACT_RANGE, 1
    )
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        var collider = hit.get("collider")
        if collider and collider.has_method("get_grid_cell"):
            return collider.get_grid_cell()
    # 回退：返回射线命中的网格坐标
    var hit_pos: Variant = hit.get("position")
    if hit_pos:
        return GridSystem.get_cell_at_world(hit_pos.x, hit_pos.z)
    return null

func _interact() -> void:
    # 检查附近的可交互对象（村民、建筑、收集品）
    var nearby := _find_nearby_interactables(2.0)
    if nearby.size() > 0:
        var target = nearby[0]
        if target.has_method("interact"):
            target.interact(self)

func _switch_tool(index: int) -> void:
    current_tool = InventorySystem.get_quick_item(index) as Tool
    EventBus.tool_changed.emit(current_tool)
```

### 5.2 NPC → Villager（scripts/actors/npc.gd）

**完全重写**。现有 `VillaNpc` 是敌人 AI（追踪玩家、受击、击退、死亡），需要改为和平村民。

**保留**：
- `CharacterBody3D` 基类
- 重力逻辑
- `rotation.y` 朝向逻辑

**移除**：
- `defeated` 信号
- `health` / `max_health` / `contact_damage`
- `CombatMathScript`
- `take_hit()` 方法
- `_try_contact_damage()` 方法
- `_hit_flash_remaining` / `_update_hit_flash()`
- `knockback_velocity`
- 追踪玩家的 chase 逻辑

**新增**：
```gdscript
class_name Villager extends CharacterBody3D

signal interaction_requested(villager: Villager)

@export var villager_data: VillagerData

var current_state: String = "IDLE"
var target_position: Vector3 = Vector3.ZERO
var move_speed: float = 1.5
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta
    
    match current_state:
        "MOVING_TO_WORK", "MOVING_TO_HOME", "MOVING_TO_WANDER":
            _move_toward_target(delta)
        "WORKING":
            _do_work(delta)
        "WANDERING":
            _wander(delta)
        "SLEEPING":
            velocity = Vector3.ZERO
        "IDLE":
            velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
            velocity.z = move_toward(velocity.z, 0.0, speed * 8.0 * delta)
    
    move_and_slide()

func _move_toward_target(delta: float) -> void:
    var dir := target_position - global_position
    dir.y = 0.0
    if dir.length_squared() < 0.25:
        _on_arrived()
        return
    dir = dir.normalized()
    velocity.x = dir.x * move_speed
    velocity.z = dir.z * move_speed
    rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-8.0 * delta))

func update_schedule(hour: int) -> void:
    var entry := _get_schedule_entry(hour)
    if entry == null:
        return
    match entry.state:
        "WORKING":
            target_position = villager_data.work_position
            current_state = "MOVING_TO_WORK"
        "WANDERING":
            target_position = _random_waypoint_near(villager_data.work_position, 5.0)
            current_state = "MOVING_TO_WANDER"
        "SLEEPING":
            target_position = villager_data.home_position
            current_state = "MOVING_TO_HOME"

func interact(player: Node3D) -> void:
    interaction_requested.emit(self)
    EventBus.dialogue_started.emit(villager_data.villager_id, null)
```

### 5.3 Projectile → ToolInteraction（scripts/combat/projectile.gd）

**Phase 1 后完全移除**。投射物系统不再需要。

工具交互改为射线检测 + 直接调用，不需要物理投射物。

`scenes/combat/projectile.tscn` 和 `scripts/combat/projectile.gd` 删除。
`scripts/shared/combat_math.gd` 删除（无战斗后不再需要）。

### 5.4 HUD（scripts/ui/hud.gd, scenes/ui/hud.tscn）

HUD 已重构为经营状态栏和上下文操作栏。底部左侧模式按钮是种植/建造入口；悬停时菜单向上展开，右侧按钮行根据模式动态生成六个工具/种子按钮或九个建筑按钮。

**过渡方案**（Phase 1）：
```gdscript
class_name VillaHud extends CanvasLayer

@onready var stamina_bar: TextureProgressBar = $TopBar/StaminaBar
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var level_label: Label = $TopBar/LevelLabel
@onready var season_label: Label = $TopBar/SeasonLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var mode_button: Button = $BottomBar/ActionRow/ModeButton
@onready var quick_bar: HBoxContainer = $BottomBar/ActionRow/QuickBar

func configure_action_bar(
    controller: PlayerActionController,
    inventory: InventorySystem,
    economy: EconomySystem
) -> void:
    # 监听 mode_changed / palette_changed，并按权威状态重建按钮。
    pass

func rebuild_action_palette() -> void:
    # FARMING 创建 6 项，BUILDING 创建 9 项。
    # 每个按钮调用 controller.select_mode_slot(index)。
    pass

func set_stamina(value: int, max_value: int) -> void:
    stamina_bar.max_value = max_value
    stamina_bar.value = value

func set_gold(amount: int) -> void:
    gold_label.text = "💰 %d" % amount

func set_level(level: int, exp_progress: float) -> void:
    level_label.text = "Lv.%d" % level

func set_season_date(season: int, day: int) -> void:
    var names := ["春", "夏", "秋", "冬"]
    season_label.text = "%s %d/7" % [names[season], day]

func set_time(hour: int, minute: int) -> void:
    time_label.text = "%02d:%02d" % [hour, minute]
```

### 5.5 Vegetation（scripts/world/vegetation_builder.gd）

**扩展而非重写**。

**保留**：
- `TEXTURES` 字典
- `vertical_scale_for()` 方法
- `build()` 的基本流程

**修改**：
将 `Sprite3D` 升级为 `TreeInstance` 节点（已有 tree-collision-camera-occlusion 设计中的改造）：

```gdscript
func build(terrain: TerrainBuilder, route: Array[Dictionary]) -> int:
    var placements := TreeScatterScript.generate(route)
    for tree in placements:
        # 改造：使用 TreeInstance 而非裸 Sprite3D
        var instance := TreeInstance.new()
        instance.name = str(tree.id)
        instance.configure(tree, load(TEXTURES[tree.variant]) as Texture2D, terrain)
        add_child(instance)
    return get_child_count()
```

**Phase 2 扩展**：部分树木标记为"果树"，可以收获果实：

```gdscript
# TreeInstance 新增字段
var is_fruit_tree: bool = false
var fruit_crop_id: String = ""
var has_fruit: bool = false
var fruit_respawn_days: int = 7
```

### 5.6 Main（scripts/main.gd）

**重写 `_ready()`**，连接新系统：

```gdscript
func _ready() -> void:
    # 初始化世界（保留）
    world.build()
    
    # 放置玩家
    _place_on_terrain(player, Vector2(0.0, 0.0))
    player.configure(camera_rig, world)
    camera_rig.set_target(player)
    
    # 初始化系统
    grid_system.initialize(world.terrain)
    season_system.start()
    inventory_system.initialize()
    
    # 连接信号
    EventBus.stamina_changed.connect(hud.set_stamina)
    EventBus.gold_changed.connect(hud.set_gold)
    EventBus.season_changed.connect(season_system._apply_season_visuals)
    EventBus.day_changed.connect(farming_system.on_day_changed)
    
    # 初始化村民
    for villager in villagers.get_children():
        if villager is Villager:
            villager.interaction_requested.connect(_on_villager_interaction)
    
    # 加载存档（如果有）
    if SaveManager.has_save():
        SaveManager.load_game()
```

**移除**：
- NPC 生成/追踪逻辑
- 投射物生成 (`_on_fire_requested`)
- 战斗相关 HUD 更新

---

## 6. 存档系统设计

### 6.1 JSON 结构

```json
{
  "version": 1,
  "timestamp": 1721548800,
  "play_time": 3600.0,
  
  "player": {
    "position": {"x": 0.0, "y": 0.5, "z": 0.0},
    "stamina": 85,
    "max_stamina": 100,
    "level": 3,
    "exp": 450
  },
  
  "world": {
    "season": 0,
    "day_in_season": 4,
    "total_days": 4,
    "hour": 14,
    "minute": 30,
    "gold": 250
  },
  
  "inventory": {
    "max_slots": 20,
    "slots": [
      {"item_id": "hoe_basic", "quantity": 1, "slot": 0},
      {"item_id": "watering_can", "quantity": 1, "slot": 1},
      {"item_id": "tomato_seed", "quantity": 5, "slot": 2},
      {"item_id": "wood", "quantity": 30, "slot": 3}
    ],
    "quick_slots": [0, 1, 2, -1, -1, -1]
  },
  
  "grid": {
    "cells": [
      {"gx": 5, "gz": 10, "state": "FARMLAND", "watered": true},
      {"gx": 5, "gz": 11, "state": "PLANTED", "watered": false, "crop": {"id": "tomato", "growth_days": 2}},
      {"gx": 3, "gz": 5, "state": "BUILDING", "building": {"id": "barn"}}
    ]
  },
  
  "buildings": [
    {"id": "barn", "gx": 3, "gz": 5}
  ],
  
  "exploration": {
    "unlocked_regions": ["farm", "creek"],
    "fog_data": "<base64 encoded 256x256 grayscale image>",
    "collected": ["diary_001", "plant_specimen_003", "fossil_002"],
    "solved_puzzles": ["push_puzzle_001"]
  },
  
  "story": {
    "fragments": ["fragment_001", "fragment_003"],
    "chapter": 1
  },
  
  "villagers": {
    "affinity": {
      "old_li": 35,
      "xiao_hua": 15
    },
    "orders": [
      {"id": "order_001", "item_id": "tomato", "quantity": 3, "reward_gold": 20, "days_left": 2, "villager": "old_li"}
    ]
  }
}
```

### 6.2 SaveManager

**文件**：`scripts/core/save_manager.gd`

```gdscript
class_name SaveManagerClass extends Node

const SAVE_PATH := "user://villa_save.json"
const AUTO_SAVE_INTERVAL_DAYS := 1

func save_game() -> void:
    var data := _collect_save_data()
    var json_string := JSON.stringify(data, "\t")
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file:
        file.store_string(json_string)
        file.close()
        EventBus.game_saved.emit()
        print("[SaveManager] Game saved successfully")
    else:
        push_error("[SaveManager] Failed to save game: %s" % FileAccess.get_open_error())

func load_game() -> bool:
    if not FileAccess.file_exists(SAVE_PATH):
        return false
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if not file:
        return false
    var json_string := file.get_as_text()
    file.close()
    var json := JSON.new()
    var error := json.parse(json_string)
    if error != OK:
        push_error("[SaveManager] Failed to parse save file")
        return false
    var data: Dictionary = json.data
    _apply_save_data(data)
    EventBus.game_loaded.emit()
    print("[SaveManager] Game loaded successfully")
    return true

func has_save() -> bool:
    return FileAccess.file_exists(SAVE_PATH)

func _collect_save_data() -> Dictionary:
    var data := {}
    data.version = 1
    data.timestamp = Time.get_unix_time_from_system()
    data.play_time = GameState.play_time
    
    # Player
    data.player = {
        "position": {"x": Player.global_position.x, "y": Player.global_position.y, "z": Player.global_position.z},
        "stamina": PlayerState.stamina,
        "max_stamina": PlayerState.max_stamina,
        "level": PlayerState.level,
        "exp": PlayerState.exp,
    }
    
    # World
    data.world = {
        "season": SeasonSystem.current_season,
        "day_in_season": SeasonSystem.current_day,
        "total_days": SeasonSystem.total_days,
        "hour": SeasonSystem.hour,
        "minute": SeasonSystem.minute,
        "gold": GameState.gold,
    }
    
    # Inventory
    data.inventory = InventorySystem.to_dict()
    
    # Grid
    data.grid = GridSystem.to_dict()
    
    # Buildings
    data.buildings = BuildingSystem.to_dict()
    
    # Exploration
    data.exploration = ExplorationSystem.to_dict()
    
    # Story
    data.story = StorySystem.to_dict()
    
    # Villagers
    data.villagers = VillagerSystem.to_dict()
    
    return data

func _apply_save_data(data: Dictionary) -> void:
    # 按相反顺序恢复数据
    var player_data: Dictionary = data.player
    Player.global_position = Vector3(player_data.position.x, player_data.position.y, player_data.position.z)
    PlayerState.stamina = player_data.stamina
    PlayerState.level = player_data.level
    PlayerState.exp = player_data.exp
    
    SeasonSystem.current_season = data.world.season
    SeasonSystem.current_day = data.world.day_in_season
    SeasonSystem.total_days = data.world.total_days
    SeasonSystem.hour = data.world.hour
    SeasonSystem.minute = data.world.minute
    GameState.gold = data.world.gold
    
    InventorySystem.from_dict(data.inventory)
    GridSystem.from_dict(data.grid)
    BuildingSystem.from_dict(data.buildings)
    ExplorationSystem.from_dict(data.exploration)
    StorySystem.from_dict(data.story)
    VillagerSystem.from_dict(data.villagers)
    
    # 应用季节视觉
    SeasonSystem._apply_season_visuals(SeasonSystem.current_season)
```

JSON 解析得到的是无类型 `Array`，不能直接赋给
`InventorySystem.slots: Array[Dictionary]` 或
`quick_slot_mappings: Array[int]`。存档恢复必须通过
`InventorySystem.restore_state()`：逐项复制合法字典、把槽位补齐到
`max_slots`、把快捷映射转换为整数并将越界索引归一化为 `-1`。这样旧版
JSON 存档也不会在主场景启动时触发类型赋值错误。

### 6.3 自动存档触发点

```gdscript
# 在 Main.gd 中
func _ready() -> void:
    EventBus.day_changed.connect(_on_day_changed_auto_save)
    EventBus.region_unlocked.connect(_on_region_unlocked_auto_save)

func _on_day_changed_auto_save(_day: int) -> void:
    SaveManager.save_game()

func _on_region_unlocked_auto_save(_region: RegionData) -> void:
    SaveManager.save_game()
```

---

## 7. UI 布局详细设计

### 7.1 HUD（scenes/ui/hud.tscn）

```
HUD (CanvasLayer) — scripts/ui/hud.gd
│
├── TopBar (Control)                  — 顶部栏
│   │   anchors: top=0, left=0, right=1, height=48
│   │   layout: HFlowContainer
│   │
│   ├── StaminaPanel (PanelContainer)
│   │   └── StaminaBar (TextureProgressBar)
│   │       min=0, max=100, value=100
│   │       tint_progress: green → red (value < 30)
│   │
│   ├── GoldPanel (PanelContainer)
│   │   └── GoldLabel (Label)
│   │       text="💰 100"
│   │
│   ├── LevelPanel (PanelContainer)
│   │   ├── LevelLabel (Label)
│   │   │   text="Lv.1"
│   │   └── ExpBar (TextureProgressBar)
│   │       min=0, max=100, value=0
│   │
│   ├── SeasonPanel (PanelContainer)
│   │   └── SeasonLabel (Label)
│   │       text="春 1/7"
│   │
│   └── TimePanel (PanelContainer)
│       └── TimeLabel (Label)
│           text="06:00"
│
├── BottomBar (Control)               — 底部栏
│   │   anchors: bottom=1, left=0, right=1
│   │
│   ├── ToolLabel (Label)              — 当前动作说明
│   ├── ModeMenu (PopupPanel)          — 模式按钮上方的悬停菜单
│   │   └── VBox
│   │       ├── FarmingModeButton      — 种植模式（P）
│   │       └── BuildingModeButton     — 建造模式（B）
│   └── ActionRow (HBoxContainer)
│       ├── ModeButton (Button)        — 当前模式图像和名称
│       └── QuickBar (HBoxContainer)   — 动态生成 6 或 9 个 Button
```

操作按钮包含手绘图像、数字和短名称。种植按钮最小宽度 `72px`，建造按钮最小宽度 `64px`、间距 `4px`，完整建造栏在 `1280 × 720` 下保持单行显示。模式菜单和所有按钮拦截鼠标输入，避免点击穿透到世界。

种植工具图标来自 `assets/ui/action_icons/`，种子复用谷物幼苗图；建筑按钮复用 `assets/buildings/painted/<id>/<id>_back.png`，因为该图层包含可辨识的完整建筑轮廓。

#### 数据绑定

```gdscript
class_name VillaHud extends CanvasLayer

func _ready() -> void:
    # 连接事件总线
    EventBus.stamina_changed.connect(_on_stamina_changed)
    EventBus.gold_changed.connect(_on_gold_changed)
    EventBus.level_changed.connect(_on_level_changed)
    EventBus.season_changed.connect(_on_season_changed)
    EventBus.day_changed.connect(_on_day_changed)
    EventBus.time_changed.connect(_on_time_changed)
    action_controller.mode_changed.connect(_on_action_mode_changed)
    action_controller.palette_changed.connect(_on_action_palette_changed)
    rebuild_action_palette()

func _on_stamina_changed(value: int) -> void:
    stamina_bar.value = value
    if value < 30:
        stamina_bar.tint_progress = Color(1.0, 0.2, 0.2, 1.0)
    else:
        stamina_bar.tint_progress = Color(0.2, 0.8, 0.2, 1.0)

func _on_gold_changed(amount: int) -> void:
    gold_label.text = "💰 %d" % amount

func _on_time_changed(hour: int, minute: int) -> void:
    time_label.text = "%02d:%02d" % [hour, minute]

func _on_action_mode_changed(_mode: PlayerActionController.ActionMode) -> void:
    rebuild_action_palette()

func _on_action_palette_changed(
    _mode: PlayerActionController.ActionMode,
    selected_index: int
) -> void:
    for i in quick_bar.get_child_count():
        (quick_bar.get_child(i) as Button).button_pressed = i == selected_index
```

### 7.2 背包界面（scenes/ui/inventory_ui.tscn）

```
InventoryUI (Control) — scripts/ui/inventory_ui.gd
│   visible = false (默认隐藏)
│   anchors: full screen
│   │
│   ├── Background (ColorRect)         — 半透明背景
│   │   color: (0, 0, 0, 0.5)
│   │
│   └── Panel (PanelContainer)        — 主面板
│       anchors: center, 600x400
│       │
│       ├── Header (HBoxContainer)
│       │   ├── TitleLabel (Label)    — "背包"
│       │   └── CloseButton (Button)  — "X"
│       │
│       ├── Tabs (TabContainer)       — 分类标签
│       │   ├── 全部
│       │   ├── 工具
│       │   ├── 种子
│       │   ├── 作物
│       │   ├── 材料
│       │   └── 收集品
│       │
│       └── Grid (GridContainer)      — 物品网格
│           columns: 5
│           └── ItemSlot_* (TextureRect)  — 20个槽位
│               size: 64x64
│               每个槽位:
│               ├── ItemIcon (TextureRect)
│               ├── QuantityLabel (Label)  — 右下角堆叠数量
│               └── Highlight (ColorRect)  — 选中高亮
```

#### 交互逻辑

```gdscript
class_name InventoryUI extends Control

var _dragging_slot: InventorySlot = null
var _dragging_from_quick: bool = false

func _ready() -> void:
    EventBus.inventory_opened.connect(show)
    EventBus.inventory_closed.connect(hide)
    visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed() -> void:
    if visible:
        _refresh_grid()
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _refresh_grid() -> void:
    var slots := InventorySystem.slots
    for i in grid.get_child_count():
        var slot_ui: TextureRect = grid.get_child(i)
        if i < slots.size() and not slots[i].is_empty():
            slot_ui.texture = load(slots[i].item.icon_path)
            slot_ui.get_node("QuantityLabel").text = str(slots[i].quantity)
        else:
            slot_ui.texture = null
            slot_ui.get_node("QuantityLabel").text = ""

func _gui_input(event: InputEvent) -> void:
    # 拖拽物品
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _start_drag(_get_slot_at_mouse(event.position))
        else:
            _end_drag(_get_slot_at_mouse(event.position))
    
    # ESC关闭
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        hide()
        EventBus.inventory_closed.emit()
```

### 7.3 建造界面（scenes/ui/build_ui.tscn）

`BuildUI` 作为兼容场景保留，供独立验证或后续建筑详情面板使用。主游戏把
`keyboard_shortcut_enabled` 设为 `false`，全局 `B` 由
`PlayerActionController` 切换底部建造模式，避免两个入口同时响应。

```
BuildUI (Control) — scripts/ui/build_ui.gd
│   visible = false
│   anchors: left panel, 250 width
│   │
│   ├── BuildingList (ItemList)       — 建筑列表
│   │   每项显示: 建筑名称 + 图标 + 造价
│   │   不可建造的建筑灰色显示
│   │
│   ├── DetailPanel (PanelContainer)  — 建筑详情
│   │   ├── BuildingName (Label)
│   │   ├── BuildingDesc (Label)
│   │   ├── CostList (VBoxContainer)
│   │   │   └── CostItem (HBoxContainer)
│   │   │       ├── ResourceIcon (TextureRect)
│   │   │       └── ResourceLabel (Label)
│   │   └── PlaceButton (Button)      — "放置"
│   │
│   └── CancelButton (Button)         — "取消建造"
```

#### 交互流程

```gdscript
class_name BuildUI extends Control

var selected_building: BuildingData = null

func _on_building_selected(index: int) -> void:
    var building_id := building_list.get_item_metadata(index)
    selected_building = GameData.get_building(building_id)
    _update_detail_panel()
    
    # 进入预览模式
    BuildingSystem.enter_preview_mode(selected_building)
    EventBus.build_mode_entered.emit()

func _on_place_button_pressed() -> void:
    if selected_building == null:
        return
    # 放置由 BuildingSystem 处理（鼠标左键确认放置位置）
    # 这里只是切换到放置确认模式
    BuildingSystem.set_placing(true)

func _on_cancel_button_pressed() -> void:
    BuildingSystem.exit_preview_mode()
    selected_building = null
    EventBus.build_mode_exited.emit()
```

### 7.4 地图界面（scenes/ui/map_ui.tscn）

```
MapUI (Control) — scripts/ui/map_ui.gd
│   visible = false
│   anchors: full screen
│   │
│   ├── Background (ColorRect)
│   │
│   └── MapPanel (PanelContainer)
│       anchors: center, 800x500
│       │
│       ├── MapViewport (SubViewportContainer)
│       │   └── SubViewport
│       │       ├── TerrainTexture (Sprite2D)    — 地形俯视图
│       │       ├── FogOverlay (TextureRect)     — 迷雾叠加
│       │       ├── Markers (Node2D)             — 标记点
│       │       │   ├── PlayerMarker (Sprite2D)
│       │       │   ├── BuildingMarkers
│       │       │   └── CollectibleMarkers
│       │       └── MapCamera (Camera2D)
│       │
│       └── Legend (VBoxContainer)    — 图例
│           ├── FarmIcon + "农庄"
│           ├── CreekIcon + "溪谷"
│           ├── ForestIcon + "深林"
│           └── PeakIcon + "迷雾峰"
```

### 7.5 对话界面（scenes/ui/dialogue_ui.tscn）

```
DialogueUI (Control) — scripts/ui/dialogue_ui.gd
│   visible = false
│   anchors: bottom panel, height=200
│   │
│   ├── DialoguePanel (PanelContainer)
│   │   │
│   │   ├── SpeakerRow (HBoxContainer)
│   │   │   ├── SpeakerPortrait (TextureRect)  — 村民头像
│   │   │   └── SpeakerName (Label)            — 村民名字
│   │   │
│   │   ├── TextContainer (RichTextLabel)      — 对话文本
│   │   │   bbcode_enabled = true
│   │   │   打字机效果
│   │   │
│   │   └── ChoicesContainer (VBoxContainer)   — 选项
│   │       ├── ChoiceButton_0 (Button)
│   │       ├── ChoiceButton_1 (Button)
│   │       └── ChoiceButton_2 (Button)
│   │
│   └── ContinueHint (Label)                   — "点击继续"
```

---

## 8. 性能考虑

### 8.1 网格系统优化

**问题**：1008 个网格，如果每个都有 MeshInstance3D，会造成渲染压力。

**方案**：
- 网格线使用**单个** `MeshInstance3D`（`ImmediateMesh` 或 `ArrayMesh`），一次性绘制所有网格线
- 单元格高亮使用 `ImmediateMesh` 动态绘制，不为每个格子创建独立节点
- 网格数据存储在内存字典中（`_cells: Dictionary`），不创建对应场景节点
- 只有**有内容的网格**（种植了作物、有建筑）才创建视觉节点

```gdscript
# 网格线一次性绘制
func _build_grid_lines() -> void:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_LINES)
    for gx in 37:  # 36格 = 37条线
        var wx := float(gx) - 18.0
        surface.add_vertex(Vector3(wx, 0.01, -14.0))
        surface.add_vertex(Vector3(wx, 0.01, 14.0))
    for gz in 29:  # 28格 = 29条线
        var wz := float(gz) - 14.0
        surface.add_vertex(Vector3(-18.0, 0.01, wz))
        surface.add_vertex(Vector3(18.0, 0.01, wz))
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = surface.commit()
    mesh_instance.material_override = _grid_line_material
    add_child(mesh_instance)
```

### 8.2 植被 LOD

**当前**：28 棵 Sprite3D Billboard，已经非常轻量。

**扩展后**：可能达到 60-80 棵树（深林区域）。

**方案**：
- Sprite3D 本身已经很高效，不需要传统 LOD
- 远处的树使用 `visibility_range_end` 裁剪（Godot 4 的可见性范围）
- 深林区域的密集树木使用 `MultiMeshInstance3D` 批量渲染

```gdscript
# 深林区域使用 MultiMesh
func build_dense_forest() -> void:
    var multi_mesh := MultiMesh.new()
    multi_mesh.mesh = tree_billboard_mesh
    multi_mesh.instance_count = forest_tree_count
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
    for i in forest_tree_count:
        multi_mesh.set_instance_transform(i, tree_transforms[i])
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = multi_mesh
    add_child(mmi)
```

### 8.3 NPC AI 更新频率控制

**问题**：多个村民同时运行 AI 状态机，每帧更新位置。

**方案**：
- 村民移动使用 `_physics_process`，但只在状态为 `MOVING_*` 时执行计算
- `WORKING` / `SLEEPING` / `IDLE` 状态时 `velocity = Vector3.ZERO`，无计算开销
- 日程更新只在每小时触发一次（`EventBus.time_changed`），而非每帧检查

```gdscript
func _physics_process(delta: float) -> void:
    # 只在需要移动时执行
    if current_state.begins_with("MOVING"):
        _move_toward_target(delta)
    elif current_state == "WANDERING":
        _wander(delta)
    else:
        # 静止状态，直接归零
        if velocity.length_squared() > 0.01:
            velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
            velocity.z = move_toward(velocity.z, 0.0, speed * 8.0 * delta)
            move_and_slide()
```

### 8.4 UI 刷新策略

**原则**：UI 只在数据变化时刷新，不每帧更新。

| UI 元素 | 刷新触发 | 频率 |
|---------|----------|------|
| 体力条 | `EventBus.stamina_changed` | 变化时 |
| 金币 | `EventBus.gold_changed` | 变化时 |
| 等级/经验 | `EventBus.level_changed` / `EventBus.exp_gained` | 变化时 |
| 季节/日期 | `EventBus.season_changed` / `EventBus.day_changed` | 每天/每季 |
| 时间 | `EventBus.time_changed` | 每分钟 |
| 快捷栏 | `EventBus.tool_changed` / `EventBus.item_added` | 变化时 |
| 背包网格 | 打开时 + `EventBus.item_added/removed` | 低频 |
| 小地图 | `_process` 中更新玩家标记 | 每帧（仅 2D Sprite 位置） |

### 8.5 作物生长更新

**问题**：可能有数百个种植网格，每天需要更新。

**方案**：
- 维护一个 `planted_cells: Array[GridCell]` 列表，只遍历已种植的网格
- 生长更新在 `day_changed` 事件中触发（每天一次），不在 `_process` 中
- 视觉更新只在阶段变化时替换纹理

```gdscript
func on_day_changed(_day: int) -> void:
    for cell in planted_cells:
        if cell.crop_instance and not cell.crop_instance.is_mature:
            var old_stage := cell.crop_instance.get_current_stage()
            cell.crop_instance.advance_growth()
            var new_stage := cell.crop_instance.get_current_stage()
            if new_stage != old_stage:
                _update_crop_visual(cell, new_stage)
            if cell.crop_instance.is_mature:
                EventBus.crop_matured.emit(cell, cell.crop_instance.crop_data)
```

### 8.6 迷雾更新

**方案**：
- 迷雾纹理 `256×256` 灰度图，约 64KB
- 只在玩家移动超过 0.5 单位时更新（避免每帧更新纹理）
- 使用 `ImageTexture.update()` 而非重新创建纹理

```gdscript
var _last_reveal_position := Vector2.ZERO

func _process(_delta: float) -> void:
    var player_pos := Vector2(Player.global_position.x, Player.global_position.z)
    if player_pos.distance_to(_last_reveal_position) > 0.5:
        _last_reveal_position = player_pos
        reveal_area(player_pos.x, player_pos.y, 3.0)
```

---

## 9. AI NPC Agent 系统

本章扩展 1.8 和 5.2 的确定性村民状态机。状态机继续负责移动、动画、碰撞、日程和离线回退；远程 Agent Service 只负责高层意图、对话、计划和候选动作。Godot 始终是金币、物品、任务、关系和世界位置的权威来源。

### 9.1 阶段目标

第一阶段中，每个 NPC 都是逻辑独立的 Agent，拥有独立的身份、性格、目标、记忆、关系、感知范围和工具权限。关键剧情使用结构化选项，日常交流允许玩家自由输入。服务不可用、超时或额度耗尽时，NPC 自动回退到本地日程和预置对话，不阻塞游戏。

第二阶段增加家庭、职业、组织和临时团队。Agent 只能读取自己有权限的共享知识频道，私人记忆不会自动向团队公开。Team Coordinator 可以拆解团队目标和分配任务，但不能绕过 Godot 的动作校验。

### 9.2 总体架构

```text
Godot 4.7
├── AgentGateway              HTTP、请求队列、超时和重试
├── AgentScheduler            NPC 优先级、调用频率和预算降级
├── WorldSnapshotBuilder      生成经过感知过滤的世界快照
├── NpcAgentController        管理单个 NPC 的 Agent 生命周期
├── AgentActionValidator      校验权限、参数和世界版本
├── AgentActionExecutor       转换为移动、说话、工作、交易等行为
├── DialogueController        结构化选项与自由输入
└── FallbackVillagerBrain     本地日程与预置对话
              │
              │ HTTPS + JSON；对话可选 SSE
              ▼
TypeScript Agent Service
├── Session / Decision / Dialogue / Outcome API
├── Agent Registry            以 save_id + npc_id 隔离 Agent
├── Loom Adapter              构造 Context 并运行 ReAct loop
├── Tool Registry             角色工具白名单
├── Memory Service            短期事件、长期摘要和关系
├── Knowledge Channel Service 第二阶段共享知识
├── Budget Scheduler          并发、Token、费用和优先级
├── LLM Provider              OpenAI-compatible Provider 抽象
└── Trace Store               感知、工具、决策和执行结果
```

服务代码位于 `services/agent-service/`。开发环境使用 `localhost`，正式环境部署为远程 HTTPS 服务。Godot 只依赖版本化 JSON 协议，不依赖 TypeScript 内部实现，也不保存 LLM API Key。

### 9.3 Agent Context

Agent 使用 `save_id + npc_id` 唯一标识，其 Loom Context 包含：

- `Identity`：角色、性格、价值观、能力和不可违反的限制。
- `Goal`：长期目标、当前目标、成功条件和优先级。
- `State`：近期 Observation、Decision、当前动作和未完成承诺。
- `Knowledge`：个人事实、启发式经验、短期记忆和长期摘要。
- `Affordances`：该角色获准使用的工具、资源和子循环。
- `Budget`：最大步骤、工具调用数、时限、Token 和费用。

角色定义使用版本化 JSON 数据，不把不可维护的完整角色文本写死在代码中。生产构建不得依赖 `~/workspace/loom` 绝对路径；Loom 必须作为锁定版本的 workspace、私有 npm 包或 git 依赖引入。

### 9.4 感知快照

Godot 只发送 NPC 合理可感知的信息：游戏时间、自身状态、附近玩家和 NPC 的可见行为、可见对象、可听事件、活跃任务以及近期相关事件。其他 NPC 的私人目标、背包和记忆默认不可见。自由输入和世界文本均标记为不可信外部数据，不能覆盖 Identity、约束或工具权限。

每个快照带单调递增的 `world_revision`。Agent 响应必须回显该版本；版本过期时 Godot 拒绝执行并根据最新快照重新决策。

### 9.5 决策循环

一次自主决策按以下顺序执行：

1. Godot 生成过滤后的世界快照。
2. Agent Service 加载 NPC 身份、目标、记忆和关系。
3. Loom Adapter 构建不可变 Context。
4. LLM 调用授权的只读工具补充上下文。
5. LLM 生成结构化候选动作。
6. 服务端验证 JSON Schema 并返回动作计划。
7. Godot 重新验证世界状态和动作权限。
8. Godot 执行动作并回传真实 Outcome。
9. Agent Service 将结果追加为 Observation，并更新记忆。

默认限制为最多 3 个 ReAct 轮次、6 次工具调用；自主决策超时 3 秒，对话超时 10 秒。每个 NPC 同时最多一个未完成决策。

### 9.6 工具与动作

只读工具包括 `inspect_visible_objects`、`inspect_local_inventory`、`inspect_relationship`、`recall_recent_events`、`recall_long_term_memory`、`inspect_schedule` 和 `inspect_active_quests`。

候选动作包括 `move_to`、`face_actor`、`speak`、`work`、`offer_trade`、`propose_quest`、`propose_gift` 和 `wait`。工具采用角色白名单；例如铁匠可以工作和提出矿料订单，但不能调用农夫的收获技能。

动作工具只生成候选命令。Godot 必须检查协议版本、幂等键、NPC 身份、世界版本、工具权限、目标可达性、资源、距离、时间、任务条件和文本长度。非法动作返回明确的 `rejected` Outcome，成为 Agent 下一次 Observation。

### 9.7 API 协议

```text
POST /v1/sessions/sync
POST /v1/npcs/{npc_id}/decide
POST /v1/npcs/{npc_id}/dialogue
POST /v1/decisions/{decision_id}/outcomes
POST /v1/sessions/{save_id}/checkpoint
GET  /v1/health
```

所有 `POST` 请求携带 `Authorization`、`Idempotency-Key` 和 `X-Protocol-Version: 1`。修改型请求必须幂等；重复请求返回原结果，不重复写入记忆、交易或任务。`GET /v1/health` 不要求鉴权和幂等键。

决策响应至少包含 `protocol_version`、`decision_id`、`world_revision`、`npc_id`、`trace_id`、`actions` 和 `next_think_after_ms`。每个动作具有唯一 `action_id`、受控的 `type` 和经过 Schema 校验的 `params`。

### 9.8 混合对话

关键剧情、交易、任务接受和重要承诺使用结构化选项。LLM 可以改变措辞和情绪，但不能改变选项的游戏语义。日常聊天允许自由输入；自由对话只能改变印象、近期记忆和未来意图。若产生任务或交易意图，服务返回结构化 `proposal`，Godot 展示确认按钮后才改变游戏状态。

对话可使用 SSE 流式显示文本，但必须以完整的结构化 JSON 事件结束。流式中断时丢弃未完成的 proposal，并显示本地回退文本。

### 9.9 调度和成本

| 优先级 | 场景 | 调度策略 |
|--------|------|----------|
| P0 | 正在对话或关键剧情 | 立即请求 |
| P1 | 玩家附近且可见 | 每 5–15 秒或事件触发 |
| P2 | 离屏但参与任务或团队 | 每游戏小时或重大事件 |
| P3 | 无关、休眠、睡觉 | 不调用 LLM |

相同事件在短时间内合并，同一 NPC 的请求串行执行。Agent Service 对每个存档实施全局并发、Token 和费用预算；达到预算后自动降级为本地模拟。

### 9.10 记忆与存档

短期窗口保存最近 24 条重要 Observation、12 轮对话、当前动作、活跃任务和未完成承诺。普通闲聊和重复观察通过 TTL 清理。

长期记忆保存玩家关系、重要承诺、共同事件、个人偏好、已知世界事实和职业经验。长期记忆是带来源、置信度和重要度的结构化摘要，不是完整聊天日志。

Godot 存档保存 Agent Profile 版本、长期摘要、关系、当前目标、未完成承诺和同步游标。服务端保存短期窗口、Trace、工具结果和可重建的长期索引。开发环境使用 SQLite，远程环境使用 PostgreSQL，两者实现相同 Repository 接口。

### 9.11 故障回退和安全

- 网络不可达、超时、429 或 5xx：回退到本地日程；5xx 最多退避重试一次。
- 非法 JSON 或未知动作：拒绝整份或对应动作并记录 Trace。
- 过期世界版本：不执行，使用新快照重新决策。
- NPC 卸载或删除：取消请求并忽略迟到响应。
- 存档冲突：以 Godot checkpoint 为权威创建新的服务端记忆版本。
- LLM API Key 只保存在 Agent Service；Godot 使用短期会话 Token。
- 工具必须通过 JSON Schema 和白名单，不允许任意代码、文件或网络调用。
- Trace 保存推理摘要、工具和结果，不依赖或记录模型隐藏思维链。

### 9.12 第二阶段团队协作

知识频道使用 `public:village`、`family:<id>`、`profession:<id>`、`organization:<id>` 和 `team:<id>` 命名，并带成员 ACL、允许发布的知识类型、来源、置信度和过期时间。Agent 只能通过实际对话、共同目击、授权发布工具或团队汇报传播信息。

Team Coordinator 负责拆解团队目标、选择具备角色能力的 NPC、发布子目标、收集进度和失败重分配。它不能读取成员私人记忆、替代成员 Agent 或绕过 Godot 校验。

### 9.13 测试与验收

TypeScript 测试覆盖 Context、Prompt、工具权限、Schema、记忆压缩、预算、超时、幂等、世界版本冲突和 Mock LLM ReAct loop。Godot 测试覆盖感知过滤、动作校验、迟到响应、回退状态机和 proposal 确认。双方共用协议 fixture，确保协议版本和动作类型一致。

集成测试使用 Mock Agent Service 完整跑通“感知 → 决策 → 校验 → 执行 → Outcome”。真实 Provider 仅用于人工验收，不作为 CI 依赖。压力测试覆盖 20、50 和 100 个逻辑 NPC 的分层调度。

### 9.14 实施顺序

1. **Phase A：协议与本地闭环**——共享 Schema、Mock Agent Service、Godot Gateway、感知、校验、执行与回退。
2. **Phase B：单 NPC Agent**——Loom Adapter、真实 Provider、短期记忆和混合对话。
3. **Phase C：全村独立 Agent**——Registry、分层调度、长期摘要、存档同步、预算和 Trace UI。
4. **Phase D：多 Agent Team**——权限知识频道、信息传播、Team Coordinator 和团队任务。

---

## 附录 A：文件变更清单

### 新增文件

```
scripts/
├── core/
│   ├── event_bus.gd
│   ├── game_data.gd
│   ├── game_state.gd
│   └── save_manager.gd
├── systems/
│   ├── grid_system.gd
│   ├── farming_system.gd
│   ├── building_system.gd
│   ├── economy_system.gd
│   ├── season_system.gd
│   ├── inventory_system.gd
│   ├── exploration_system.gd
│   ├── puzzle_system.gd
│   ├── story_system.gd
│   ├── tool_system.gd
│   ├── villager_system.gd
│   ├── collectible_system.gd
│   └── audio_manager.gd
├── actors/
│   ├── villager.gd
│   └── animal.gd
├── buildings/
│   └── building_instance.gd
├── collectibles/
│   └── collectible_pickup.gd
├── puzzles/
│   ├── puzzle.gd
│   ├── push_puzzle.gd
│   ├── path_puzzle.gd
│   ├── light_puzzle.gd
│   └── offering_puzzle.gd
└── ui/
    ├── inventory_ui.gd
    ├── build_ui.gd
    ├── map_ui.gd
    ├── dialogue_ui.gd
    └── shop_ui.gd
```

### 修改文件

```
scripts/main.gd              — 重写：连接新系统，移除战斗
scripts/actors/player.gd     — 扩展：体力、工具、交互
scripts/world/world.gd       — 扩展：添加 GridSystem/Buildings 子节点
scripts/world/vegetation_builder.gd  — 扩展：TreeInstance 升级
scripts/ui/hud.gd            — 重写：经营 HUD
scripts/camera/camera_rig.gd — 保留，可能添加自由模式
project.godot                — 添加 Autoload 注册、新 Input Map
```

### 删除文件（Phase 1 后）

```
scripts/combat/projectile.gd
scripts/shared/combat_math.gd
scenes/combat/projectile.tscn
```

### 保留不变

```
scripts/world/terrain_builder.gd
scripts/world/road_builder.gd
scripts/world/road_math.gd
scripts/world/tree_scatter.gd
scripts/camera/camera_math.gd
```

---

## 附录 B：Input Map 新增

```
project.godot 新增 input actions:

interact        — 鼠标右键 / E键
sprint          — Shift
inventory       — Tab / I
map             — M
tool_1 ~ tool_6 — 数字键 1-6
build_mode      — B
```

---

## 附录 C：物理层扩展

当前物理层：
| Layer | 用途 |
|-------|------|
| 1 | 地形 |
| 2 | 玩家 |
| 4 | NPC |
| 8 | 投射物 |
| 16 | 树干碰撞 |
| 32 | 镜头遮挡检测 |

新增物理层：
| Layer | 用途 |
|-------|------|
| 64 | 建筑碰撞 |
| 128 | 收集品触发 (Area3D) |
| 256 | 村民交互区域 |
| 512 | 谜题触发区域 |

玩家 collision_mask 更新为：`1 | 16 | 64`（地形 + 树干 + 建筑）

---

*文档版本：v1.0*
*创建日期：2026-07-21*
*基于：docs/game-design.md v1.0*
*项目路径：~/UnrealEngine/villa*
