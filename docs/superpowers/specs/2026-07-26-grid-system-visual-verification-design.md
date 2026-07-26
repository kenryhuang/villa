# GridSystem 完整实现与独立视觉验收设计

## 目标

补齐 `docs/detailed-design.md` 1.2 中 GridSystem 的数据、规则、视觉和持久化闭环，并提供一个不依赖完整游戏主场景的独立 Godot 验收场景。验证器必须使用正式 GridSystem 和正式 TerrainBuilder，不能复制或伪造生产逻辑。

## 范围

本次包含：

- 36×28、共 1008 格的网格数据和坐标转换。
- 地形高度、坡度、道路及外部阻塞区域分类。
- 合法状态迁移、耕作限制、种植、浇水和收获数据。
- 单网格网格线、选中格高亮和状态调试覆盖层。
- GridSystem 序列化/恢复，以及 SaveManager 的运行时节点定位。
- 独立视觉验收场景、独立自动化测试入口和实际图形运行验证。

本次不包含：

- 完整作物美术和生长动画。
- 建筑模型、NPC、经济、背包和 AI Agent。
- 新水体美术。正式游戏没有水体定义时，不凭高度图猜测水域；接口接受显式阻塞区域，视觉验证器会提供测试水域。
- 对现有完整测试套件中无关的 Player、GameData 和 Inventory 接口错误做顺带修复。

## 方案选择

采用“正式系统可视化 + 独立验证器”的方案。

未采用以下方案：

- 只在测试场景画网格：实现快，但正式游戏仍然不可见，会产生假通过。
- 为每个格子创建 MeshInstance3D：结构直观，但 1008 个节点会造成不必要的场景树和渲染开销。

正式 GridSystem 使用一个 `ArrayMesh` 绘制全部网格线，使用一个动态高亮网格显示当前格子；验证器额外使用一个调试覆盖网格按状态着色。这样正式场景和验证场景共享同一份数据与规则，同时保持低节点数。

## 正式 GridSystem 架构

新增可复用场景：

```text
GridSystem (Node3D)
├── GridOverlay (MeshInstance3D)
├── GridCells (Node3D)
│   └── CellHighlight (MeshInstance3D)
└── GridData (Node)
```

场景文件为 `scenes/systems/grid_system.tscn`，脚本仍为 `scripts/systems/grid_system.gd`。

`Main` 从该场景实例化 GridSystem，再把真实 `TerrainBuilder` 和 `RoadBuilder.MAIN_ROUTE` 传给 `configure()`。GridSystem 加入 `grid_system` group，其他系统通过注入引用访问；SaveManager 通过 group 查找，避免依赖 `/root/GridSystem` 这类错误绝对路径。

## 初始化与数据模型

`configure()` 完成以下动作：

1. 保存 TerrainBuilder 引用。
2. 创建全部 1008 个轻量 `GridCell`。1008 个 RefCounted 数据对象成本可控，完整初始化可消除存档、调试和遍历时的“未访问格子不存在”歧义。
3. 为每个格子采样中心高度与坡度。
4. 根据道路折线和道路宽度，把相交格标记为 `ROAD`。
5. 根据调用方传入的显式阻塞区域标记 `WATER` 或 `DECORATION`。
6. 构建 GridOverlay。

仍保留按坐标查询接口，但 `_cells.size()` 在配置后必须恒为 1008。

道路判定采用“格子中心到道路折线段的最短距离 ≤ 该段插值半宽 + 半格对角线”。这样道路边缘不会留下可错误开垦的半格。

显式阻塞区域使用：

```gdscript
func configure(
    terrain_node: TerrainBuilder,
    road_route: Array[Dictionary] = [],
    blocked_regions: Array[Dictionary] = []
) -> void
```

每个阻塞区域为：

```gdscript
{
    "state": GridCell.State.WATER,
    "rect": Rect2(world_x, world_z, width, depth),
}
```

## 规则与状态迁移

公开状态变更继续通过 `set_cell_state()`，并强制执行：

- 越界失败。
- `WASTELAND → FARMLAND` 必须通过 `can_farm_at()`。
- 坡度大于 0.35、ROAD、WATER、BUILDING、DECORATION 均不可开垦。
- `FARMLAND → PLANTED` 只能由 `plant_crop()` 完成。
- `PLANTED → FARMLAND` 只能在成功收获后完成。
- 初始化道路和阻塞区使用私有初始化方法，不绕开运行期规则暴露给普通调用方。

锄头仍调用 `set_cell_state()`；坡度和占用限制由 GridSystem 自身保证，避免每个调用方重复实现。

收获只检查成熟状态，不在收获动作中推进生长。作物推进仍由 FarmingSystem 的日期更新负责。

每次成功修改继续发出当前 EventBus 信号：

```gdscript
cell_state_changed(gx, gz, new_state)
cell_watered(gx, gz)
crop_planted(gx, gz, crop_id)
crop_harvested(gx, gz, crop_id)
```

## 正式视觉实现

### GridOverlay

- 使用一个 `ArrayMesh`，primitive 为 `LINES`。
- 绘制 37 条纵向边界和 29 条横向边界。
- 每一世界单位采样一次地形高度，线顶点高度为地形高度加 `0.035`，避免 z-fighting。
- 使用半透明、无光照材质。
- 默认隐藏；建造模式、耕作工具或调试场景可以调用 `set_grid_visible(true)`。

### CellHighlight

- 使用一个四边形 `ArrayMesh`，四角分别采样地形高度。
- `highlight_cell(gx, gz, color)` 更新唯一高亮网格的位置、顶点和颜色。
- 越界调用会清除高亮并返回 `false`。
- `clear_highlights()` 隐藏高亮。

正式 GridSystem 不为每个格子创建视觉节点。

## 序列化

GridSystem 提供：

```gdscript
func to_dict() -> Dictionary
func from_dict(data: Dictionary) -> bool
```

只保存偏离初始化状态的数据：

- state
- watered
- crop_id
- growth_progress
- is_watered_today

加载时先重新执行地形、道路和阻塞区初始化，再应用存档差异。非法坐标、未知状态和未知作物记录被跳过并产生警告，不让整个存档加载失败。

SaveManager 使用：

```gdscript
get_tree().get_first_node_in_group("grid_system")
```

不再访问 GridSystem 私有 `_cells`。

## 独立视觉验收场景

新增：

```text
tests/visual/grid_system_verification.tscn
tests/visual/grid_system_verification.gd
```

节点结构：

```text
GridSystemVerification (Node3D)
├── World
├── GridSystem
├── VerificationStateOverlay
├── Camera3D
├── DirectionalLight3D
└── UI (CanvasLayer)
    ├── StatusPanel
    ├── CellInspector
    └── Instructions
```

启动时：

1. 构建正式地形和道路。
2. 配置正式 GridSystem。
3. 注入一个测试 WATER 区域和一个测试 DECORATION 区域。
4. 显示正式 GridOverlay。
5. 执行自动验收并在 StatusPanel 显示结果。

交互：

- 鼠标移动：射线命中地形并高亮当前格。
- 左键：选择格子。
- `H`：对选中格执行锄头状态变更。
- `P`：使用内置测试 CropData 种植。
- `W`：浇水。
- `G`：显示/隐藏正式网格线。
- `S`：显示/隐藏坡度及状态覆盖层。
- `R`：重建验证场景状态。
- `Esc`：退出。

CellInspector 实时显示：

```text
Grid: (gx, gz)
World: (x, y, z)
State: WASTELAND
Height: 0.123
Slope: 0.042
Farmable: true
```

状态覆盖颜色：

- WASTELAND：透明灰
- FARMLAND：棕色
- PLANTED：绿色
- BUILDING：橙色
- ROAD：土黄色
- WATER：蓝色
- DECORATION：紫色
- 坡度超限且仍为 WASTELAND：红色

## 自动验收

新增独立入口 `tests/run_grid_system_tests.gd`，只加载网格相关测试，避免被当前全量测试入口的无关编译错误阻塞。

必须覆盖：

- 配置后存在 1008 格。
- 四角坐标和世界坐标转换。
- 每格有地形高度与坡度。
- 道路格被分类为 ROAD。
- 显式水域和装饰区域分类正确。
- 陡坡、道路、水域、建筑、装饰不可开垦。
- 合法状态迁移、种植、浇水、成熟收获。
- 收获不会推进作物生长。
- EventBus 信号参数。
- GridOverlay 为单个 MeshInstance3D，且具有非空 ArrayMesh。
- 高亮成功、越界清除、清除接口。
- `to_dict()` / `from_dict()` 往返保持状态。
- 主场景向 Player、FarmingSystem、BuildingSystem、ToolSystem 注入同一个 GridSystem。
- SaveManager 能通过 group 找到运行中的 GridSystem。

自动测试通过后，使用 Godot 图形模式单独启动视觉场景。验收窗口必须能看到地形、完整网格线、状态覆盖层和 CellInspector，控制台不得出现 GDScript 错误。

## 错误处理

- TerrainBuilder 缺失或未构建：`configure()` 返回 `false`，GridOverlay 保持隐藏，并输出明确错误。
- 道路或阻塞区域数据格式错误：跳过该条并输出警告。
- 视觉网格构建失败：数据网格仍可用，自动验收报告视觉项失败。
- 重复 `configure()`：清空旧数据和旧 mesh 后安全重建，不重复连接 EventBus。
- 存档中存在非法格子：跳过非法记录，不覆盖合法基础分类。

## 完成标准

只有同时满足以下条件才算 1.2 完成：

1. 独立网格测试入口全部通过。
2. 主场景 GridSystem 接线测试通过。
3. 独立视觉场景可启动并正确显示。
4. 图形运行无 GDScript 错误和资源加载错误。
5. 网格状态能够保存并恢复。
6. 正式 GridSystem 节点数不会随 1008 格线性增长。
