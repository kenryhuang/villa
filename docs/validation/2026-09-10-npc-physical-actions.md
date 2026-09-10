# NPC 到场操作（2026-09-10）

原先阿禾、老李、学者林的通用命令没有独立 `move`；项目步骤有移动能力，农作、调查、配送已有实际行程，但直接市场交易、准备物资和租用加工可以远程完成。因此选择这些操作时人物没有走动。

## 实现

- 通用命令加入 `move`，参数为世界坐标 `{x, z}`，东为 +x、南为 +z。Godot 与服务端均校验有限数值及地图边界；实际可达性由游戏寻路判断。建筑内部目标自动选择可达交互位置。
- `buy`、`sell`、`prepare_supplies` 自动前往真实市集柜台；`rent_production` 自动前往指定建筑的交互位置。无需先调用 `move`。到达后检查当时的价格、库存、余额、材料、租费与队列，再复用原经济和加工逻辑。
- 项目中的 `buy`、`sell`、`rent` 也包含实际行走；仍支持原有显式 `move` 步骤。项目预算与材料继续在接受计划时托管，到场执行交易时才消耗相应托管资产。
- 行走使用原 NPC 寻路和行走动画，修正途经路径节点误判到达的问题，并保留精确终点，避免只走到格子中心后卡住。
- 单次决策内连续动作按顺序执行：行走中的操作保持 `in_progress`，抵达后完成；租用加工会进一步等到成品交付，再继续下一步。无需模型为每段路额外发起工具调用。
- 活动与剩余动作进入原存档；加载替换执行器后重新绑定移动回调。重复结果不重复扣款。不可达或连续 30 游戏分钟无行走进展会失败，直接行程有 720 游戏分钟期限。
- 调试状态显示实际行程，如“前往市场采购”“前往加工建筑”。农作、实地调查、配送继续使用原有到场执行系统。

自主决策仍由 Agent 选择；工具可用不代表每次思考都会选择移动。对话、查询和报价等操作不强制移动，租用成品仍按原设计自动交付背包。

## 验证

独立测试均使用 `--farm-test`，移动测试写入 `tmp/npc-movement-save.json`，不读写玩家主存档，也不调用在线模型。

本次结果：移动 40、3D Agent 58、Agent 核心 1713、P3 32、P6 63、P8 77、P9 51、P12 51 项检查通过；服务端 87 项测试通过。

| 测试 | 验证内容 |
| --- | --- |
| `tests/run_3d_npc_movement_tests.gd` | 40 项：三名角色工具权限、真实中途位置、到达判定、连续购物、途中完整存读档、幂等、不可达、堵塞、物资采购、到场收费加工及完成后出售 |
| `tests/run_3d_agent_tests.gd` | 3D 集成、农作、实际到达后租用、经济存档与对话 |
| `tests/run_agent_system_tests.gd` | 原 Agent 验证、执行、事件和记忆回归 |
| `tests/run_living_world_p3_tests.gd` | 项目实际到场买卖加工、容量限制与恢复 |
| `tests/run_living_world_p6_tests.gd` | 任务插队、实际取送货与原项目恢复 |
| `tests/run_living_world_p8_tests.gd` | 雇佣、学习和设备合资项目到场执行 |
| `tests/run_living_world_p9_tests.gd` | 实地调查与情报存档 |
| `tests/run_living_world_p12_tests.gd` | 36 人社会与调度回归，另加 `--living-world-scenario=P12` |
| `services/agent-service` 的 `npm test` | 工具白名单、坐标约束、组合动作说明及服务端回归 |

示例：

```powershell
godot_console.exe --headless --path . --script tests/run_3d_npc_movement_tests.gd -- --farm-test
```
