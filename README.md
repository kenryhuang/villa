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
    buildings/                  原生 3D 建筑：Blender 谷仓、风车、食品工坊
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
    farm_minimap.gd             右下角北向小地图、人物位置与朝向、地形地标
    market_building.gd          可点击的原生 3D 市集、木结构店铺与交易柜台
    market_view.gd              原市场/交易面板的场景交互与窗口适配
    market_panel.gd             共用市场面板的 3D 背包图标适配
    market_site.gd              市集选址与占地，迁移时避开已有农田建筑
    farm_fishing.gd             3D 甩竿、概率咬钩、拉竿上鱼与背包结算
    fishing_location.gd         河湖岸边站位、水深、距离与抛线遮挡检测
    fishing_visual.gd           原生鱼竿／鱼线／浮漂／鱼模型及角色钓鱼骨骼动作
    farm_golf.gd                鼠标挥杆、站位、跟球、三洞流程与操作条
    golf_course_data.gd         湖西球场布局、果岭、沙坑与地表规则
    golf_course_visual.gd       原生球杆架、旗杆、洞杯、发球台和连接小路
    golf_visual.gd              三种球杆、角色挥杆骨骼动作、球与参考轨迹
    golf_ball.gd                球的飞行、反弹、坡面滚动、进洞与出界
    golf_swing.gd               鼠标后拉、前推速度和左右偏差计算
    golf_round.gd               三洞杆数、球位检查点与个人最佳存档
    farm_inventory_ui.gd        原背包的 3D 交互适配
    target_catalog.gd          将共用种子和建筑目录提供给目标菜单
    flat_grid.gd                扩展地形网格，保留原农庄坐标与存档
    terrain_profile.gd          平原、丘陵、山地、峡谷和河床的共享高度
    landscape.gd                地形分块、碰撞、河湖、木桥、橡树与预留钓位
    farm3d_farming_system.gd    原种植规则的 3D 视觉、水田灌溉适配
    farm_building_system.gd     原建造规则的角色距离、占地检查
    modeled_building.gd         谷仓模型、立体施工阶段、碰撞与放置预览
    modeled_windmill.gd         风车模型、生产叶片动画、院落交互范围
    modeled_food_workshop.gd    食品工坊模型、烹饪蒸汽、柜台交互范围
    windmill_view.gd            风车／食品工坊共用加工、队列、成品与维护面板
    windmill_panel_controller.gd 原生产面板的 3D 适配与实时行情估算
    windmill_yard.gd            3D 风车院落、施工阶段与输出位置
    windmill_outputs.gd         可点击的袋装／瓶装成品
    food_workshop_yard.gd       食品工坊石地院落、围栏与成品展台
    food_workshop_outputs.gd    可点击的食品、罐装成品与花束
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
  models/buildings/barn/       立体谷仓 GLB、木纹／石材／瓦片贴图
  models/buildings/windmill/   立体风车 GLB、木纹／石材／瓦片贴图
  models/buildings/food_workshop/ 食品工坊 GLB、木纹／石材／陶瓦贴图
  models/crops/               3D 作物：玫瑰五阶段，其余 13 种两阶段
  crops/、buildings/           原作物图片供旧游戏使用；建筑美术继续共用
  terrain/、ui/               共用地面贴图与 UI 主题、图标
art/blender/
  farm3d.blend                 可编辑的农庄源模型
  painted_oak.blend            可编辑的橡树源模型
  barn.blend                   可编辑的谷仓，按施工阶段分组
  windmill.blend               可编辑风车，施工分组与独立叶片轴
  food_workshop.blend          可编辑食品工坊，木屋、炉灶与厨房陈设
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
- 3D 存档写入项目目录 `data/farm_3d_save.json`；当前 v5 增加 NPC Agent 决策状态、真实农田任务与租用订单归属，兼容 v1/v2/v3/v4，保留市场行情、NPC 经济状态、市集位置和高尔夫成绩。找不到存档或存档损坏时直接按初始状态启动，下一次保存会写入新的格式化存档。每次启动后首次覆盖保存会留下同路径 `.bak`，本次运行后续自动保存不轮换该备份。
- `docs/superpowers/` 是历史设计记录，保留当时的文件名；当前目录以本页为准。

## 操作与验证

完整操作和已迁入功能见 [3D 农庄集成说明](docs/validation/3d-farming-integration.md)。

**NPC Agents**：复用原 `scripts/ai_agent/`、NPC 场景、农田执行器、对话和调试界面。阿禾、老李、学者林出现在农庄，小地图蓝点标记位置；走近点击可对话与回应交易／合作。阿禾使用独立的真实农田。Agent 可查询地图、市场行情、角色、玩家建筑、队列和租费，提交自备原料的租用加工订单。风车每批 4 金币，食品工坊每批 6 金币；其他配方站按基础费加加工时间计算。租金进入玩家账户，NPC 与玩家共用队列，租客成品完成后自动进入自己的背包，维护会暂停订单，有租用订单的建筑不能拆除。

开发构建底部 **调试** → **NPC Agents / 决策间隔 / 环境与租费**，可查看状态、手动触发决策、调整间隔、打开原有 Input/Reasoning/Output 请求追踪；不暂停游戏时间。原服务仍负责远程模型与独立角色记忆，未配置服务时角色和调试界面可用，自动决策关闭。

**只启动服务、手工运行游戏**：运行 `./tools/run_farm3d.ps1 -ServiceOnly`，服务在后台持续运行，不启动 Godot；随后自行从编辑器运行正式 3D 场景即可。运行 `./tools/run_farm3d.ps1 -StopAgents` 停止本机 Agent 服务；已停止时会直接提示。游戏优先读取当前目录的客户端配置，缺失时自动读取 `.worktrees` 内已有的配置文件，无需复制。`-Agents` 仍用于同时启动服务和游戏，`-CheckAgents` 用于短暂检查服务后退出。

**NPC 对话输入**：打开对话框时暂停游戏时间与角色运动，保留文字编辑、发送和关闭操作，Agent 网络通信继续运行。输入 I/G/WASD 等字符不会触发背包、小地图或移动；Enter 发送，Shift+Enter 换行，Esc 或关闭按钮退出。关闭后恢复原来的暂停状态，清除残留移动输入，需要重新按下移动键才会行走。

用 `./tools/run_farm3d.ps1 -Agents` 同时启动当前分支的服务和 3D 游戏。脚本优先使用当前项目配置，再查找 Git worktree 中已有的本地配置，直接读取原文件；也可传 `-AgentClientConfig <路径> -AgentServiceConfig <路径>`。本机旧服务经健康响应和进程启动参数确认后会自动替换，其他程序占用端口时保留该进程并报错。脚本在退出或启动失败时关闭自己启动的服务。`-CheckAgents` 仅验证服务启动和能力，不启动游戏，检查完成后清理本次启动的服务。单独启动 Godot 可传 `-- --agent-client-config=<现有客户端配置路径>`。远程记忆沿用原服务的 SQLite 数据库，以存档中的独立 session ID 隔离。保存后异步导出记忆检查点，并在农场存档旁写入 `.agent-memory.json` 清单；读档时验证世界文件 SHA-256，缺失、不匹配或服务不可用时提示并从农场当前状态继续。

**风车**：从“建筑”菜单放置，完工后走到南面院门前点击建筑。选择面粉、动物饲料或葵花油，设置批量并投入背包原料。关闭面板后加工，完成后点击院落成品或在面板收进背包。面板支持两格队列、实时行情参考与原系统维护；打开时暂停游戏时间，Esc 关闭恢复。模型与验证见[3D 风车说明](docs/validation/windmill-3d.md)。

**食品工坊**：从“建筑”菜单放置 4×4 工坊，完工后走到南面操作台前点击建筑。原有十种配方全部复用，包括风车面粉制作面包／蜂蜜蛋糕、普通鱼制作烤鱼／腌鱼，以及果酱、腌菜等加工。选择配方和批量后投入背包原料，Esc 关闭继续生产；点击成品或在面板收进背包，再到市集出售。配方列表可滚动，窄屏使用页签。模型、完整配方与验证见[3D 食品工坊说明](docs/validation/food-workshop-3d.md)。

农庄西南侧新增实体市集（默认西 12 / 南 12 米，小地图标注“市集”）。走到南面的柜台前，**左键点击建筑**即可买卖；**Esc** 关闭。作物、鱼获和材料沿用原市场目录、批量报价、有限库存、NPC 供需和每日价格结算。说明与实景见[3D 市场移植](docs/validation/market-3d.md)。

地图已扩展至 **256 × 224 米**，中央为原农庄平原，西侧为丘陵及新增湖西球场，北侧为山地，东侧河流穿过峡谷。南面从草地逐渐过渡到沙地，南湖有三处保留岸边钓位，河流和湖泊的其他合适岸边也能钓鱼。按 **Tab** 查看全景，按 **R** 返回农庄。原地形布局见[扩展地图说明](docs/validation/landscape-3d.md)，新增球场见下文。

**高尔夫（C：鼠标挥杆）**：从市集旁“湖西高尔夫”路牌沿小路到球杆架（西 124 / 南 62 米），点击或按 **E** 免费开始。走到球旁按 **E** 站位，角色右手主握杆、向左挥击。**A/D** 瞄准，**Q/E** 调整站距，**W/S 或滚轮** 上下调整触球点；球下部配合大力度可以挑高，中心轻击可以推球。**按住左键向后拉鼠标，再向前推过击球点**；后拉幅度与前推速度影响力度，横向偏移影响出球方向。**右键拖动** 可在准备、挥杆和跟球时转动镜头。**1/2/3** 选择开球杆、挖起杆、推杆，**− / =** 调整本次游戏的挥杆灵敏度。球停后走过去继续，进洞后前往下一发球台按 E。**球场内按 R 重开本轮**，人物和球回到第 1 洞，本轮清零、个人最佳保留。三洞计分并保存个人最佳，Esc 退出站位／跟球。实景与验证见[高尔夫说明](docs/validation/golf-3d.md)。

右下角小地图默认显示，按 **G** 关闭／打开，固定上北、下南、左西、右东；浅色箭头显示人物位置和朝向，标出农庄、山地、丘陵、河流、木桥、沙地及南湖。底部显示所在区域与相对原农庄中心（世界原点）的东西／南北距离（米），旋转相机不会改变地图方向。

按住 **Shift** 奔跑，移动速度为普通行走的 **2.5 倍**（当前行走 4.2 米/秒、奔跑 10.5 米/秒），松开即恢复行走；奔跑时步行动画同步加快。

**钓鱼**：走到平缓干燥的河岸或湖岸，工具栏的“鱼竿”亮起后选择。按 **E／左键** 甩竿，等待浮漂下沉和“咬钩”提示，再按 **E／左键** 拉竿；上鱼动画结束后渔获自动入包，按 **I** 查看。每竿有概率咬钩，空竿或错过后可重试；**Esc** 收竿离开。详见[3D 钓鱼说明与实景](docs/validation/fishing-3d.md)。

```powershell
godot_console.exe --headless --editor --path . --quit
godot_console.exe --headless --path . --script tests/run_farm3d_scene_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_farm_interaction_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_target_system_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_landscape_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_minimap_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_south_lake_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_fishing_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_market_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_windmill_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_food_workshop_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_agent_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_save_protection_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_golf_tests.gd -- --farm-test
godot_console.exe --headless --path . --script tests/run_3d_golf_terrain_tests.gd -- --farm-test
```

`--farm-test` 禁用玩家存档读写；截图也应带上该参数。
