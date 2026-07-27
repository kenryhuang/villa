# FarmingSystem 完整实现与独立视觉验收设计

## 目标

逐条验证并补齐 `docs/detailed-design.md` 1.3 的种植生命周期，建立不依赖完整游戏 UI 的独立视觉验收场景。验证器必须使用正式 TerrainBuilder、GridSystem、SeasonSystem 和 FarmingSystem。

## 正式系统

- 新增 `scenes/systems/farming_system.tscn`，节点为 `FarmingSystem/CropVisuals`，根节点加入 `farming_system` group。
- `configure(grid, season, game_state)` 可重复调用，不重复连接 `EventBus.day_changed`。
- `plant()` 只接受 FARMLAND 格，创建 CropInstance 和正式作物视觉。
- `water()` 设置格子和作物当日浇水状态。
- `on_day_changed()` 只推进未成熟作物；浇水增加 1.5 天，未浇水增加 1 天，每日结束清除水状态。
- 错误季节不推进作物，但仍清除当日浇水。
- `set_greenhouse_cells()` 标记忽略季节的格子，为 1.4 建筑系统提供接线接口。
- `harvest()` 只收获成熟作物，奖励经验并移除视觉。
- `rebuild_visuals()` 根据 GridSystem 当前作物数据重建视觉，用于读档恢复。

## 作物视觉

当前没有作物阶段图片，因此按设计允许的 Phase 1 占位方案使用 `MeshInstance3D`：

- 种子：低矮棕色方块。
- 幼苗：小型绿色方块。
- 生长期：较高黄绿色方块。
- 成熟：最高金黄色方块。

每个作物只创建一个 MeshInstance3D，阶段变化时更新尺寸和材质。视觉位置取 GridCell 的地形高度。

## 生命周期修正

- CropInstance 增加 `is_mature()`。
- `advance_growth()` 对进度做成熟值截断。
- 已成熟作物再次推进返回 false，不重复触发 `crop_matured`。
- `crop_grew` 只在阶段变化时触发。
- `crop_matured` 只在首次到达成熟时触发。

## 独立自动测试

新增 `tests/run_farming_system_tests.gd`，只加载种植、CropInstance 和作物视觉测试，避免无关旧测试阻塞。覆盖：

- 种植、浇水、1.5倍生长、每日清水。
- 未浇水生长。
- 季节阻塞及正确季节恢复。
- 温室格忽略季节。
- 成熟截断且只成熟一次。
- 未成熟拒绝收获、成熟收获和经验奖励。
- 视觉创建、阶段尺寸/颜色变化、收获移除。
- 重复 configure 不重复连接。
- rebuild_visuals 恢复读档视觉。
- Main 使用可复用 FarmingSystem 场景并共享同一 GridSystem。

## 独立视觉验收

新增：

```text
tests/visual/farming_system_verification.tscn
tests/visual/farming_system_verification.gd
tests/test_farming_visual_scene.gd
tests/capture_farming_visual.gd
```

场景显示四个相邻农田，分别处于种子、幼苗、生长期和成熟阶段。界面显示总作物数、视觉数、当前季节、选中格状态、浇水状态、生长进度和阶段。

控制：

- `1`–`4` 选择作物。
- `W` 浇水。
- `N` 推进一天。
- `S` 切换季节。
- `H` 切换选中格温室状态。
- `X` 收获。
- `R` 重置。
- `Esc` 退出。

## 完成标准

- 独立种植测试全部通过。
- Main 接线测试通过。
- 独立视觉场景严格解析并运行无错误。
- 图形截图能同时看到四个阶段、农田网格和诊断面板。
- 主场景图形模式正常启动。
