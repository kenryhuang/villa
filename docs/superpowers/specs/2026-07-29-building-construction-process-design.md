# BuildingSystem 短时施工过程设计

## 目标

当前 `BuildingSystem.place_building()` 在资源与网格校验后直接显示成品。新增一个短时、可观察、可存档的施工过程，使主游戏和独立视觉验收都能看到：

```text
地基 → 骨架 → 半成品 → 成品
```

本阶段采用用户选择的“每栋建筑专用阶段贴图”方案。九种建筑各自拥有地基、骨架和半成品三张施工图，成品继续使用现有前后分层贴图。

完成标准：

- `P / Enter` 放置后先出现施工地基，不再立即显示成品。
- 1×1、2×2、3×3 建筑分别用 3、4、5 秒完成。
- 多个建筑可同时独立施工。
- 施工从地基阶段开始占格、扣除资源并阻挡玩家。
- 施工期间关闭建筑功能交互，完成后自动启用。
- 骨架阶段开始参与镜头遮挡。
- 独立视觉验收支持 `N` 单步推进施工阶段。
- `X` 可取消施工且恢复原网格，不退还资源。
- 施工阶段和时间进度可存档；旧存档中的建筑按已完成处理。
- Building、Farming、Grid、Player 和主场景验证不回归。

## 范围

包含：

- `BuildingInstance` 施工状态机。
- `BuildingSystem` 施工信号和放置集成。
- 九类建筑共 27 张专用施工 PNG。
- 程序化尘土、木屑和阶段切换反馈。
- 主场景自动实时推进。
- 独立视觉验收的开始、单步推进、取消和状态显示。
- 存档与读档兼容。

不包含：

- 按游戏日推进。
- NPC 搬运、施工任务或工人寻路。
- 分批支付材料、退款或取消确认框。
- 建筑升级、维修和移动。
- 施工声音。

## 施工状态模型

### BuildingInstance

`scripts/buildings/building_instance.gd` 增加：

```gdscript
enum ConstructionStage {
    FOUNDATION,
    FRAME,
    HALF_BUILT,
    COMPLETE,
}

signal construction_stage_changed(
    building: BuildingInstance,
    stage: ConstructionStage
)
signal construction_completed(building: BuildingInstance)

var construction_stage := ConstructionStage.COMPLETE
var construction_elapsed := 0.0
var construction_duration := 0.0
```

正式放置的新建筑调用：

```gdscript
func start_construction() -> void
```

读档或自动化测试使用：

```gdscript
func restore_construction(stage: int, elapsed: float) -> void
func advance_construction(delta: float) -> void
func advance_construction_stage() -> void
func complete_construction() -> void
func is_construction_complete() -> bool
func get_construction_progress() -> float
```

`advance_construction(delta)` 是唯一的时间推进逻辑。`_process(delta)` 只在未完成时调用它，因此测试无需等待真实时间。

### 时长规则

根据 footprint 最大边计算总时长：

```gdscript
max(footprint.x, footprint.y) == 1 → 3.0 秒
max(footprint.x, footprint.y) == 2 → 4.0 秒
max(footprint.x, footprint.y) >= 3 → 5.0 秒
```

前三个施工阶段各占总时长的三分之一：

```text
0%–33%   FOUNDATION
33%–66%  FRAME
66%–100% HALF_BUILT
100%     COMPLETE
```

一次大 `delta` 可以跨越多个阶段，但每个实际跨越的阶段只发出一次阶段信号。完成信号只发出一次。

## 放置与拆除数据流

### 放置

现有原子放置顺序保持不变：

1. 校验 BuildingData、场景、GridSystem、EconomySystem、资源和 footprint。
2. 实例化 BuildingInstance。
3. 保存每个格子的原状态。
4. 将 footprint 全部改为 `BUILDING`。
5. 扣除资源；失败时完整回滚网格。
6. 配置并加入建筑容器。
7. 调用 `start_construction()`。
8. 发出既有放置信号及新增施工开始信号。

从第 7 步开始，实例已是正式跟踪建筑。查询、拆除和存档都不需要处理临时节点替换。

### 取消或拆除

施工中和完成后的建筑走同一个 `remove_building()`：

- 立即关闭碰撞、交互、遮挡和处理。
- 仅恢复仍处于 `BUILDING` 的 footprint 格子。
- 从系统跟踪数组移除。
- 不退还资源。
- 发出既有拆除信号。

## 专用施工视觉

### 素材目录

每栋建筑新增：

```text
assets/buildings/construction/<building_id>/<building_id>_foundation.png
assets/buildings/construction/<building_id>/<building_id>_frame.png
assets/buildings/construction/<building_id>/<building_id>_half_built.png
```

九种建筑共 27 张 1024×1024 透明 PNG：

- barn
- greenhouse
- windmill
- chicken_coop
- beehive
- well
- workbench
- lamp
- fence

### 美术约束

- 与现有树木、作物和成品建筑相同的手绘半写实风格。
- 固定等距三分之四视角，左上方暖光。
- 与对应成品保持一致的 footprint、轮廓方向、材质和色调。
- 地基图显示针对该建筑的石基、木桩或基座。
- 骨架图显示该建筑真实可辨认的梁柱、支架或主体结构。
- 半成品图显示大部分主体，但缺少屋顶、门窗、叶片或前景附件。
- 透明背景，无文字、水印、环境地块和其他建筑碎片。
- 图片根部与成品使用同一锚点，阶段切换不跳位。

素材生成使用现有成品前后层作为风格和轮廓参考。每种建筑先生成包含三阶段的统一构图，再分离为三张透明图，确保阶段连续。

### 节点与切换

`BuildingInstance/VisualRoot` 增加：

```text
ConstructionLayer (Sprite3D)
ConstructionEffects (Node3D)
```

施工中：

- 隐藏 `BackLayer`、`FrontLayer` 和成品 fallback。
- `ConstructionLayer` 显示当前阶段专用图。
- 切换阶段时旧图在约 0.12 秒内淡出，新图在约 0.18 秒内淡入。
- 地基阶段播放轻微落下与尘土扩散。
- 骨架阶段播放短促木屑。
- 半成品阶段播放更轻的木屑和尘雾。
- 完成时施工层淡出，成品前后层淡入，并播放柔和尘雾。

特效统一使用低粒子数 `CPUParticles3D`，粒子 Mesh 和材质在运行时创建，不增加额外贴图依赖。

如果某张施工图缺失，显示与 footprint 匹配的程序化木架 fallback 并输出警告，不允许出现完全不可见但仍有碰撞的施工现场。自动测试仍要求正式九类素材全部存在。

## 碰撞、交互与遮挡

施工全过程：

- `Collision` 使用正式 footprint 碰撞，layer 保持 `16 | 64`，mask 为 `0`。
- 玩家和 NPC 从地基阶段开始不能穿过。
- 实例保留 `building_instance` 组，以便查询、拆除和存档。

按阶段：

| 阶段 | Collision | InteractionArea | CameraOccluder |
|---|---:|---:|---:|
| FOUNDATION | 开 | 关 | 关 |
| FRAME | 开 | 关 | 开 |
| HALF_BUILT | 开 | 关 | 开 |
| COMPLETE | 开 | 开 | 开 |

`interact()` 在未完成时直接返回，不发出 `interacted` 信号。完成后恢复当前交互行为。

## 信号

`BuildingSystem` 增加：

```gdscript
signal building_construction_started(instance: BuildingInstance)
signal building_construction_stage_changed(instance: BuildingInstance, stage: int)
signal building_construction_completed(instance: BuildingInstance)
```

系统在放置后连接实例的阶段与完成信号，并转发给外部消费者。拆除时节点释放会自动断开连接。

`EventBus` 增加同语义的类型化施工信号，便于 HUD、音效和后续 NPC 系统消费。

既有兼容信号的参数不变。

## 存档

`BuildingInstance.to_dict()` 增加：

```json
{
  "construction_stage": 1,
  "construction_elapsed": 1.42,
  "construction_duration": 4.0
}
```

读档流程：

1. 重建建筑实例和 footprint 快照。
2. 如果记录包含施工字段，调用 `restore_construction()`。
3. 如果旧记录没有施工字段，按 `COMPLETE` 恢复，保持旧存档兼容。
4. `elapsed` 限制在 `0..duration`；无效阶段按 `COMPLETE` 处理。

恢复施工不再次扣除资源，也不重复发出施工开始信号。读档后未完成实例继续从保存进度自动推进。

## 独立视觉验收

`tests/visual/building_system_verification.tscn` 的九建筑画廊继续显示完成态，用于比较成品模型；交互区专门展示施工。

控制：

- `1–9`：选择建筑。
- 方向键：移动预览。
- `P / Enter`：开始施工。
- `N`：将最近一次施工建筑推进到下一阶段。
- `X`：取消预览格或最近施工建筑。
- `B`：切换目标格阻塞。
- `M`：切换材料充足状态。
- `R`：重置。
- `Esc`：退出。

状态面板增加：

- 当前施工建筑。
- `FOUNDATION / FRAME / HALF_BUILT / COMPLETE`。
- 施工百分比和总时长。
- 施工碰撞是否启用。
- 功能交互是否按阶段关闭或开启。
- `N` 单步推进结果。
- 取消施工后的网格恢复检查。

自动截图默认在交互区放置一栋处于 `FRAME` 阶段的谷仓，确保截图本身能证明施工过程存在。

## 自动化验证

Building 定向套件增加：

- footprint 到 3/4/5 秒时长映射。
- 新放置建筑从 `FOUNDATION` 开始。
- 时间推进产生正确阶段。
- 大 delta 跨阶段时不重复完成。
- `N` 每次恰好推进一个阶段。
- 施工中碰撞开启、交互关闭。
- 骨架阶段开启遮挡。
- 完成阶段启用交互和成品双层视觉。
- 施工中拆除恢复混合原网格状态且不退款。
- 27 张施工图存在、为 1024×1024 RGBA 且透明。
- 存档保存阶段和 elapsed。
- 读档恢复施工状态并继续推进。
- 无施工字段的旧存档恢复为完成态。
- 施工信号和兼容信号参数稳定。

最终回归：

- Godot 编辑器完整解析。
- BuildingSystem 定向套件。
- FarmingSystem 定向套件。
- GridSystem 定向套件。
- Player/Grid 绑定。
- Building、Farming、Grid 三个视觉场景契约。
- Building 独立视觉场景运行与 1600×1000 截图。
- 主场景运行。
- `git diff --check`。

## 错误处理与边界

- 资源或网格原子放置失败时不创建施工实例。
- 施工贴图失败不影响占地和状态推进，但必须显示 fallback。
- 被拆除或失效实例不再处理时间。
- `N` 在没有施工建筑时只更新提示，不报错。
- 已完成建筑收到 `advance_construction_stage()` 不产生任何变化或重复信号。
- 预览实例不进入施工状态、不占格、不启用碰撞。
- 画廊通过显式 `complete_construction()` 进入完成态，不绕开正常放置、资源和网格契约。
