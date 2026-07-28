# BuildingSystem 完整实现与独立视觉验证设计

## 目标

完整实现 `docs/detailed-design.md` 1.4 BuildingSystem，并用独立 Godot 场景验证建造预览、占地验证、资源扣除、放置、拆除、碰撞、交互和镜头遮挡。

本阶段同时为现有九种建筑制作符合地图、树木和农作物的手绘半写实 2.5D 外观：

- 谷仓
- 温室
- 风车
- 鸡舍
- 蜂箱
- 水井
- 工作台
- 路灯
- 围栏

完成标准：

- 九种建筑都具有可加载的正式场景和独立外观。
- BuildingSystem 使用与 FarmingSystem、Player 相同的 GridSystem。
- 多格 footprint 的验证、放置和拆除保持原子性。
- 不合法位置和资源不足不会扣费或污染网格状态。
- 建筑能阻挡角色、接收交互射线，并在遮挡玩家时渐隐。
- 独立视觉验证场景能展示九种建筑并交互验证放置与拆除。
- 现有 GridSystem、FarmingSystem、玩家绑定和主场景运行不回归。

## 当前状态与迁移原则

当前 `scripts/systems/building_system.gd` 使用 GameData 字典和棕色 BoxMesh 占位，存在以下缺口：

- 没有 `BuildingData` 类型。
- 没有 `BuildingInstance` 类型。
- 没有九种建筑场景。
- `place_building()` 返回 `bool`，不返回实例。
- 拆除以数组下标定位，并统一恢复为 FARMLAND。
- 预览只显示一个 footprint 方盒，没有真实建筑外观或逐格标记。
- 主场景直接读取 BuildingSystem 私有字段。
- 没有建筑镜头遮挡、交互代理和独立验证。

迁移遵循：

- GameData 的九个建筑字典继续作为静态目录，避免破坏现有 BuildUI 和 Phase 1 数据测试。
- `BuildingData.from_dictionary()` 将可信 GameData 字典转换为类型化资源。
- BuildUI 继续传建筑 ID；BuildingSystem 在边界处解析为 BuildingData。
- 新的类型化核心接口作为唯一实现，旧 ID 入口只做兼容转发。
- 不保留棕色方盒作为正常视觉；资源失败时显示明确的手绘风格占位并输出警告。

## 数据模型

### BuildingData

文件：`scripts/data/building_data.gd`

`BuildingData extends Resource`，字段为：

```gdscript
@export var building_id := ""
@export var display_name := ""
@export var footprint := Vector2i.ONE
@export var cost: Dictionary = {}
@export_multiline var description := ""
@export var effect_type := ""
@export var effect_value := 0
@export_file("*.tscn") var scene_path := ""
@export var visual_width := 1.0
@export var visual_height := 1.0
```

接口：

```gdscript
static func from_dictionary(source: Dictionary) -> BuildingData
func is_valid() -> bool
```

字典字段映射：

- `id` → `building_id`
- `name` → `display_name`
- `footprint_x/footprint_z` → `footprint`
- `cost` → 深复制后的 `cost`
- `description` → `description`
- `effect` → `effect_type`
- `effect_value` → `effect_value`

场景路径和视觉尺寸由受信任的建筑视觉目录按 ID 补充，不接受 UI 提供任意资源路径或造价。

### BuildingInstance

文件：`scripts/buildings/building_instance.gd`

`BuildingInstance extends Node3D`，持有：

```gdscript
var building_data: BuildingData
var building_id := ""
var gx := 0
var gz := 0
var occupied_cells: Array[Dictionary] = []
```

每个 `occupied_cells` 元素包含：

```gdscript
{"gx": int, "gz": int, "previous_state": int}
```

接口：

```gdscript
func configure(data: BuildingData, origin_gx: int, origin_gz: int, cells: Array[Dictionary]) -> void
func get_interaction_area() -> Area3D
func set_camera_occluded(value: bool) -> void
func interact(player: Node) -> void
func to_dict() -> Dictionary
```

遮挡时前后视觉层平滑降到 30% 不透明度，无遮挡时恢复 100%。淡入淡出速度与树木一致。

## BuildingSystem

文件：`scripts/systems/building_system.gd`

### 场景结构

新增 `scenes/systems/building_system.tscn`：

```text
BuildingSystem (Node3D)
├── BuildingPreview (Node3D)
│   ├── VisualProxy (Node3D)
│   └── FootprintMarkers (Node3D)
└── BuildingInstances (Node3D)
```

主场景实例化该场景，不再直接 `BuildingSystem.new()`。如果主场景传入现有 `Buildings` 容器，系统使用该容器；否则使用场景内的 `BuildingInstances`。

### 核心接口

```gdscript
func configure(grid_system: GridSystem, economy_system: Node, buildings_container: Node3D = null) -> bool
func enter_preview_mode(building: Variant) -> bool
func exit_preview_mode() -> void
func is_in_build_mode() -> bool
func get_preview_data() -> BuildingData
func update_preview(gx: int, gz: int) -> bool
func update_preview_position(world_x: float, world_z: float) -> bool
func can_place(data: BuildingData, gx: int, gz: int) -> bool
func can_place_building(building_id: String, gx: int, gz: int) -> bool
func place_building(data: BuildingData, gx: int, gz: int) -> BuildingInstance
func place_selected_building(gx: int, gz: int) -> BuildingInstance
func place_building_by_id(building_id: String, gx: int, gz: int) -> BuildingInstance
func remove_building(instance: BuildingInstance) -> bool
func get_all_buildings() -> Array[BuildingInstance]
func get_buildings_of_type(effect_type: String) -> Array[BuildingInstance]
func get_building_count() -> int
func clear_buildings(restore_grid := true) -> void
```

BuildUI 继续调用 `enter_preview_mode(building_id)`；主场景点击时调用 `place_selected_building()`，不再读取 `_current_building_id`。

### 信号

保留兼容信号：

```gdscript
signal build_mode_entered
signal build_mode_exited
signal building_placed(building_id: String, gx: int, gz: int)
signal building_removed(building_id: String)
```

增加：

```gdscript
signal building_preview_moved(gx: int, gz: int, can_place: bool)
signal building_instance_placed(instance: BuildingInstance)
signal building_instance_removed(instance: BuildingInstance)
```

## 预览

进入预览模式后，BuildingSystem 实例化目标建筑场景的视觉副本：

- 仅保留 `VisualRoot`。
- 禁用碰撞、交互和遮挡区域。
- 整体半透明。
- 可放置时使用柔和绿色调。
- 不可放置时使用柔和红色调。

`FootprintMarkers` 为 footprint 中每个格子建立薄的半透明 BoxMesh 标记：

- 可放置：绿色。
- 不可放置：红色。
- 标记贴合各自格子的缓存地形高度。
- 每次更新复用现有标记；只有 footprint 尺寸改变时重建。

预览根节点位于 footprint 的几何中心，建筑视觉根部与实际放置位置一致。

## 放置验证

`can_place()` 必须同时满足：

1. BuildingData 有效。
2. GridSystem 和 EconomySystem 已配置。
3. footprint 的宽高均大于零。
4. footprint 中每个 cell 都存在。
5. 每个 cell 状态为 `WASTELAND` 或 `FARMLAND`。
6. 每个 cell 的缓存地形高度是有限数值。
7. EconomySystem `has_resources(cost)` 返回 true。
8. 建筑场景路径存在且能加载为 PackedScene。

任何条件不满足都返回 false，不修改资源、不修改网格、不创建跟踪记录。

## 原子放置

`place_building()` 按以下顺序执行：

1. 调用 `can_place()`。
2. 加载并实例化 BuildingInstance。
3. 收集 footprint 中所有 cell 和原状态。
4. 将全部 cell 改为 BUILDING。
5. 如果任一状态修改失败，恢复已经修改的 cell 并释放实例。
6. 调用 `spend_resources(cost)`。
7. 如果扣除失败，恢复全部 cell 并释放实例。
8. 配置 BuildingInstance。
9. 计算 footprint 的世界中心和平均地形高度。
10. 加入建筑容器和跟踪数组。
11. 触发放置信号并退出预览。

资源只在所有网格状态成功改变后扣除；扣除失败时网格完整回滚。

## 拆除

`remove_building(instance)`：

1. 验证实例属于当前系统。
2. 逐格读取 `occupied_cells`。
3. 只有当前仍为 BUILDING 的格子才恢复为记录的原状态。
4. 从跟踪数组移除实例。
5. 触发拆除信号。
6. `queue_free()`。

拆除不退款。外部系统在建筑放置后修改过的非 BUILDING 格子不会被拆除流程覆盖。

## 建筑场景与碰撞

路径：

```text
scenes/buildings/barn.tscn
scenes/buildings/greenhouse.tscn
scenes/buildings/windmill.tscn
scenes/buildings/chicken_coop.tscn
scenes/buildings/beehive.tscn
scenes/buildings/well.tscn
scenes/buildings/workbench.tscn
scenes/buildings/lamp.tscn
scenes/buildings/fence.tscn
```

统一节点结构：

```text
BuildingInstance
├── VisualRoot
│   ├── BackLayer
│   └── FrontLayer
├── Collision
│   └── CollisionShape3D
├── InteractionArea
│   └── CollisionShape3D
└── CameraOccluder
    └── CollisionShape3D
```

层设置：

- `Collision`：layer `16 | 64`，mask `0`。layer 16 阻挡当前玩家和 NPC，layer 64 支持建筑射线识别。
- `InteractionArea`：layer `64 | 256`，mask `0`。
- `CameraOccluder`：layer `32`，mask `0`，只用于相机遮挡射线。

Player 的交互射线允许 Area3D，并在命中建筑子节点时向上查找 BuildingInstance 的 `interact()`。

CameraRig 同时处理 `tree_instance` 和 `building_instance` 组中实现了 `set_camera_occluded()` 的节点。

## 手绘分层建筑视觉

素材路径：

```text
assets/buildings/painted/<building_id>/<building_id>_back.png
assets/buildings/painted/<building_id>/<building_id>_front.png
```

共十八张 1024×1024 透明 PNG。每座建筑固定一个朝向。

视觉规则：

- 与现有树木和农作物相同的手绘半写实笔触。
- 等距三分之四俯视角。
- 左上方暖光。
- 自然、偏低饱和度的木、石、瓦、玻璃和金属颜色。
- 后层包含主体和地面接触阴影。
- 前层包含门廊、工具、花草、围栏或其他前景细节。
- 不包含文字、水印、方形地块或环境背景。
- 温室使用不透明的青绿色手绘玻璃高光，不要求真实折射或半透明玻璃。

视觉尺寸：

| 建筑 | footprint | 宽 | 高 |
|---|---:|---:|---:|
| 谷仓 | 2×2 | 2.3 | 2.2 |
| 温室 | 3×3 | 3.2 | 2.2 |
| 风车 | 2×2 | 2.2 | 3.4 |
| 鸡舍 | 2×2 | 2.1 | 1.8 |
| 蜂箱 | 1×1 | 0.9 | 1.15 |
| 水井 | 1×1 | 1.15 | 1.35 |
| 工作台 | 1×1 | 1.1 | 0.9 |
| 路灯 | 1×1 | 0.65 | 1.8 |
| 围栏 | 1×1 | 1.05 | 0.85 |

运行时设置：

- Billboard enabled。
- Opaque prepass alpha cut。
- 不投射实时阴影。
- 图片根部锚定 footprint 中心。
- 后层略暗并排在后方。
- 前层轻微向镜头方向偏移。

## 建筑功能边界

本阶段记录并公开 `effect_type/effect_value`，但不在 BuildingSystem 内实现后续系统行为：

- 谷仓背包扩容由 1.5 InventorySystem 消费。
- 温室季节忽略由 FarmingSystem 集成层消费。
- 风车、工作台加工由制作系统消费。
- 鸡舍、蜂箱生产由动物和生产系统消费。
- 水井灌溉由后续灌溉系统消费。
- 路灯照明由时间与照明系统消费。

BuildingSystem 只负责可靠地产生和移除 BuildingInstance，并发布信号。

## 独立视觉验证

新增：

```text
tests/visual/building_system_verification.tscn
tests/visual/building_system_verification.gd
tests/test_building_visual_scene.gd
tests/capture_building_visual.gd
```

验证场景使用真实 World、GridSystem 和 BuildingSystem。九种建筑通过 BuildingSystem 放置在模型画廊区，旁边保留交互建造区。

操作：

- `1–9` 选择建筑。
- 方向键移动预览。
- `P` 或 Enter 放置。
- `X` 拆除最近放置建筑。
- `B` 切换预览目标格的阻塞状态。
- `M` 切换材料充足状态。
- `R` 重置。
- `Esc` 退出。

状态面板显示：

- BuildingSystem 绑定 GridSystem。
- 九个建筑数据和场景全部有效。
- 九个手绘模型、碰撞、交互、遮挡区域完整。
- footprint 占用数与预期一致。
- 绿色／红色预览状态。
- 资源扣除和失败不扣除。
- 放置和拆除数量。
- 原状态恢复检查。

视觉验收截图检查：

- 九种建筑在当前地图上风格协调。
- 大小与 footprint 相符。
- 根部贴地。
- 前后层无透明排序闪烁。
- 没有色键边缘、方形背景或裁切碎片。
- 建筑之间能够快速辨认。
- 状态面板和建筑画廊在 1600×1000 中完整可见。

## 自动化验证

新增 BuildingSystem 定向测试入口，覆盖：

- BuildingData 字典转换和有效性。
- 九个场景路径、节点结构、碰撞层和纹理契约。
- 多格 footprint 验证。
- 越界、占用、无效高度、资源不足和无效场景拒绝。
- 成功放置只扣除一次资源。
- 失败放置不扣资源且不修改网格。
- 实例位置位于 footprint 中心。
- occupied_cells 保存每格原状态。
- 拆除恢复混合的 WASTELAND 和 FARMLAND。
- 查询全部建筑和按 effect_type 查询。
- 预览逐格标记和绿／红状态。
- 重建或读取保存数据所需字段。
- 建筑碰撞、交互与遮挡接口。

最终回归：

- Godot 编辑器完整解析。
- BuildingSystem 定向套件。
- FarmingSystem 定向套件。
- GridSystem 定向套件。
- Player/Grid 绑定。
- Building、Farming、Grid 三个视觉场景契约。
- Building 视觉场景运行。
- 主场景运行。
- `git diff --check`。

## 不在本阶段范围

- 建筑旋转。
- 建筑内部场景和菜单。
- 建筑升级、维修、移动和退款。
- 建造过程动画、工人施工和粒子效果。
- 风车叶片动画、动态温室玻璃和昼夜灯光。
- 谷仓、温室、生产建筑的实际玩法效果。
- 修改地图、树木或作物视觉素材。
