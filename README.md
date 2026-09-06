# Villa · 3D 农庄

当前持续开发分支：`feature/3d-farm-preview`。使用同一个 Godot 项目，第三人称 3D 农庄是默认入口。

## 启动

- 在 Godot 中打开根目录 `project.godot`，按 **F5** 运行正式 3D 游戏。
- 命令行：`./tools/run_farm3d.ps1`，或 `godot_console.exe --path .`。
- 单独查看橡树：`./tools/preview_tree.ps1`；这是美术预览，不加载农庄玩法。
- 原游戏保留在 `scenes/main.tscn`，在编辑器打开该场景后按 **F6** 可单独运行。

## 目录分工

```text
project.godot                    项目配置，默认启动 scenes/farm3d/main.tscn
scenes/
  farm3d/
    main.tscn                    正式农庄场景：环境、角色、树木、相机
    inventory.tscn               3D 背包界面，继承原背包场景
    status_bar.tscn              从原 HUD 迁入的状态条组件
  preview/                      独立美术预览，目前仅橡树观察场景
  vegetation/                   可复用的橡树场景和配套碰撞
  buildings/                    共用的建筑场景
  ui/                           原游戏 UI；背包和消息面板继续共用
  main.tscn                     原游戏入口
scripts/
  farm3d/
    main.gd                     初始化农庄、跟随相机、自动保存、截图
    player.gd                   Farm3DPlayer：第三人称移动、跳跃、动画
    farm_session.gd             组装共用系统、目标操作、独立 3D 存档
    farm_interaction.gd         鼠标选格、点击操作、Esc 取消
    farm_hud.gd                 两级目标菜单、状态条、消息与背包入口
    farm_inventory_ui.gd        原背包的 3D 交互适配
    target_catalog.gd          将共用种子和建筑目录提供给目标菜单
    flat_grid.gd                原网格系统的平坦地图适配
    farm3d_farming_system.gd    原种植规则的 3D 视觉、水田灌溉适配
    farm_building_system.gd     原建造规则的角色距离、占地检查
    crop_visual_system.gd      按地块状态生成土块和作物视觉
    painted_meadow.gd          设置手绘草地材质
    farm_tool_visual.gd        保留的早期锄头动画，当前未挂接
  preview/                     仅独立美术预览脚本
  core/、data/                 共用状态、事件、数据与种子/建筑目录
  systems/                     共用种植、季节、库存、建筑、经济和生产规则
  ui/、actors/                 原 UI 与角色逻辑，部分由 3D 层复用
  tools/                       Blender 模型生成脚本
assets/
  models/farm3d/               角色、静态环境、田块、谷物 GLB
  models/vegetation/           手绘橡树 GLB 与贴图
  models/crops/               3D 作物：玫瑰五阶段，其余 13 种两阶段
  crops/、buildings/           原作物图片供旧游戏使用；建筑美术继续共用
  terrain/、ui/               共用地面贴图与 UI 主题、图标
art/blender/
  farm3d.blend                 可编辑的农庄源模型
  painted_oak.blend            可编辑的橡树源模型
  rose.blend                   可编辑的玫瑰五阶段源模型
  <crop_id>.blend             13 种作物各自包含播种／树苗与成熟模型
tools/                        游戏启动与独立美术预览命令
tests/                        3D 集成测试、共用系统测试、截图脚本
docs/validation/              操作说明、验证结果和截图
```

## 开发约定

- 正式 3D 场景和控制脚本放入 `scenes/farm3d/`、`scripts/farm3d/`。`preview` 仅用于模型观察等独立预览，不承载正式游戏入口。
- 种植、季节、背包、经济等共用规则继续维护在原系统目录；需要 3D 特有行为时，在 `farm3d` 中适配。
- 在 Blender 编辑 `art/blender/` 下的源文件，导出模型到 `assets/models/`。生成脚本已使用新路径；运行生成脚本会覆盖对应生成资产，具体见[模型说明](assets/models/farm3d/README.md)。
- 3D 存档继续使用 `user://farm_3d_save.json`，目录迁移不更改存档名称和格式。
- `docs/superpowers/` 是历史设计记录，保留当时的文件名；当前目录以本页为准。

## 操作与验证

完整操作和已迁入功能见 [3D 农庄集成说明](docs/validation/3d-farming-integration.md)。

```powershell
godot_console.exe --headless --editor --path . --quit
godot_console.exe --headless --path . --script tests/run_farm3d_scene_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_farm_interaction_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_target_system_tests.gd -- --farm-test
```

`--farm-test` 禁用玩家存档读写；截图也应带上该参数。
