# CLAUDE.md

## Agent 读取工具设计红线（务必遵守）

LLM/agent NPC 通过读取工具（`discover_tools`、`query_world`、`inspect_self_resources` 等）
探索调查时，凡是涉及**世界事实**——市场库存与价格、现有建筑状态、农田、天气、任务、
角色关系等——必须返回游戏运行时的**实时数据**，不允许用静态表、catalog 常量或
JSON 里的固定数值冒充实时状态。

- 静态内容仅限：目录元数据（物品 id/name/category）、领域/工具说明、规则文本。
  即便如此，列表行也应尽量附带实时字段。市场三层分工（商行经济，见
  `docs/design/2026-09-14-seed-market-minimal-loop-design.md`）：
  - `items` 行携带 `mid_price`/`stock`/`incoming`（商行柜台现货与在途到货，
    来源 `MarketSystem.get_mid_price/get_stock` + `merchant_system.incoming`）。
    注意 `_query` 先构建全部行再分页切片，列表行只允许 O(1)/有界开销的调用。
  - `detail`（`get_agent_item_view`）提供滑点报价、`max_sell_quantity`
    （二分搜索，较重）、商行规则与 `procurement` 深度。
  - `supply`（`merchant_system.supply_view`）提供采购/运输/外部供应商状态。
- 商行模型下 `MarketSystem.items.stock` 即商行柜台可售现货（出口发车时已转入
  在途 shipments，无额外承诺扣减），`can_buy` 直接以 stock 判定。
- 实时链路：Godot 侧入口 `scripts/ai_agent/agent_world_query_router.gd`
  （`query_world`/`inspect_self_resources`），经 SSE 由 `services/agent-service` 的
  `world_read_broker.ts` 桥接到 LLM loop（`agent_loop.ts` 的 `services.read`）。
- `agent_action_executor_router.gd` 里的 `CROP_BY_SEED`/`SURVEY_RESULTS` 等固定表
  只是 headless 回退（`farm3d_session` 无效时）；真实 3D 模式下动作走
  `visible_npc_farm_system.queue_batch`、`_knowledge.begin_fieldwork` 等实际系统。
  新增执行路径时不得让真实模式落入固定表。
- 守护测试：`tests/run_agent_loop_tests.gd` 断言市场列表行等于 `MarketSystem`
  实时值且不等于 catalog 常量，并向 `merchant.shipments` 注入在途单验证
  `incoming` 随商行状态变化；扩展读取工具时补充同类活性断言。

## 经济数值约定

- 种子价 ≈ 成品单价的 50%；树苗/种苗（多次采收）≈ 成品单价的 2 倍溢价。
- 每块农田单次收获 3–5 个（平均 4，一个种子对应约 4 个单位成品）。
- 价格数据源：`scripts/core/game_data.gd`（ITEMS 表）；产量数据源：
  `scripts/core/crop_catalog.gd`。改数值需同步 `tests/test_crop_economy.gd`
  的设计表和 `tests/test_market_catalog.gd` 的精确断言（如 wood）。

## 常用命令

- 启动 agent service（后台，含健康检查）：`tools\run_farm3d.ps1 -ServiceOnly`
- 停止：`tools\run_farm3d.ps1 -StopAgents`
- Godot 测试：`godot --headless --path . --script tests/run_<suite>.gd`
- 服务测试：`services/agent-service` 下 `npm test`
- 已知基线失败（与常规改动无关）：`run_economy_system_tests.gd` 12 个
  （production/UI/maintenance），`run_agent_loop_tests.gd` 的 "Isolated 3D fixture"。
