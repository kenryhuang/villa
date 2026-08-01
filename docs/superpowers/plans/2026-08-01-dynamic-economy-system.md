# Dynamic Economy System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved player-and-NPC economy: finite market stock, daily supply-and-demand prices, building production, crafting, autonomous NPC trade, market UI, persistence, and deterministic balance verification.

**Architecture:** `GameState` remains the only player-wallet owner. New `MarketSystem`, `ProductionSystem`, and `NpcEconomySystem` own focused runtime state; one `DailySimulationSystem` executes irrigation, crop growth, production, NPC decisions, settlement, orders, and autosave in a fixed order. Every trade, production start, collection, and order delivery uses preflight-then-commit semantics.

**Tech Stack:** Godot 4.7, typed GDScript, existing hand-painted billboard/3D world, JSON saves, custom `SceneTree` tests.

---

## Scope and delivery order

Implement five testable phases:

1. Economy foundation: one wallet, catalog metadata, price math, finite stock, atomic trade.
2. Production: recipes, queues, passive outputs, irrigation, crop yields and regrowth.
3. World supply: finite gathering targets and material acquisition.
4. NPC market: important-NPC inventories, background demand, shortage-backed orders.
5. Delivery: economy hub, market chart/trade, orders/contracts, building panels, services, notifications, responsive visual verification, saves, waterwheel content, and a 28-day simulation.

Pause for review after Tasks 5, 9, 11, 17, and 20. Do not change building-construction timing or fixed-camera behavior.

## File map

**Create**

- `scripts/shared/market_math.gd` — pure pricing, smoothing, spread, slippage.
- `scripts/core/recipe_database.gd` — immutable recipe catalog.
- `scripts/data/producer_state.gd` — one building's serializable jobs/output.
- `scripts/data/npc_economy_state.gd` — one important NPC's wallet/inventory/plan.
- `scripts/world/resource_node.gd` — finite stone, clay, sand, and ore nodes.
- `scripts/systems/market_system.gd` — stock, quotes, ledger, history, settlement.
- `scripts/systems/production_system.gd` — queues, passive output, collection.
- `scripts/systems/npc_economy_system.gd` — NPC decisions/background demand.
- `scripts/systems/daily_simulation_system.gd` — authoritative day order.
- `scripts/systems/economy_notification_system.gd` — persisted notifications, unread state, and toast deduplication.
- `scripts/ui/economy_modal_coordinator.gd` — modal ownership and pause/resume semantics.
- `scripts/ui/market_panel.gd` — market categories, sorting, selection, and snapshots.
- `scripts/ui/market_price_chart.gd` — seven-day price graph and hover points.
- `scripts/ui/trade_panel.gd` — quantity, quotes, slippage, confirmation, and transaction feedback.
- `scripts/ui/order_panel.gd` — order filters, details, and delivery.
- `scripts/ui/contract_panel.gd` — contract signing, daily progress, and delivery.
- `scripts/ui/service_panel.gd` — blueprints, repairs, upgrades, and maintenance.
- `scripts/ui/building_economy_ui.gd` — routes building interaction to the correct panel.
- `scripts/ui/building_production_panel.gd` — recipes, queues, storage, and collection.
- `scripts/ui/building_status_panel.gd` — passive producer, irrigation, greenhouse, and barn status.
- `scripts/ui/world_range_overlay.gd` — waterwheel coverage visualization.
- `scripts/ui/economy_notification_ui.gd` — toast stack and notification center.
- `tests/run_economy_system_tests.gd` and focused `tests/test_economy_*.gd` files.

**Modify**

- `scripts/core/game_data.gd` — static market/content/NPC profile data only.
- `scripts/core/game_state.gd` — sole player wallet.
- `scripts/core/event_bus.gd` — market/production/order signals.
- `scripts/core/save_manager.gd` — versioned economy persistence.
- `scripts/data/crop_data.gd`, `crop_instance.gd` — yield/regrowth/tags.
- `scripts/buildings/building_instance.gd` — producer state persistence.
- `scripts/systems/economy_system.gd` — atomic trade and real orders.
- `scripts/systems/farming_system.gd`, `grid_system.gd` — ordered growth/harvest.
- `scripts/systems/tool_system.gd` — target-gated gathering.
- `scripts/actors/player_action_controller.gd` — axe/pickaxe routing.
- `scripts/main.gd` — construct/configure all systems.
- `scripts/ui/shop_ui.gd`, `scenes/ui/shop_ui.tscn` — compatible economy-hub shell and tabs.
- `scripts/ui/hud.gd`, `scenes/ui/hud.tscn` — market entry point.
- `scenes/ui/economy/*.tscn` — focused market, order, contract, service, building, and notification panels.

Whenever a task creates an economy test, register it in `tests/run_economy_system_tests.gd` in the same commit using this exact pattern, replacing the class/path with that task's test:

~~~gdscript
const MarketSystemTest = preload("res://tests/test_market_system.gd")
# inside _run(), before the final failure check
MarketSystemTest.new().run(assertions)
~~~

## Phase 1 — Economy foundation

### Task 1: Use one authoritative player wallet

**Files:**
- Create: `tests/run_economy_system_tests.gd`
- Create: `tests/test_economy_wallet.gd`
- Modify: `tests/test_phase1_systems.gd`
- Modify: `scripts/systems/economy_system.gd`
- Modify: `scripts/main.gd:135-151`

- [ ] **Step 1: Write the failing test**

~~~gdscript
class WalletDouble:
	extends Node
	var gold := 100
	func add_gold(amount: int) -> bool:
		if amount <= 0: return false
		gold += amount
		return true
	func spend_gold(amount: int) -> bool:
		if amount <= 0 or amount > gold: return false
		gold -= amount
		return true

func run(assertions: TestAssert) -> void:
	var inventory := InventorySystem.new()
	var wallet := WalletDouble.new()
	var economy := EconomySystem.new()
	assertions.truthy(economy.configure(inventory, wallet), "wallet injection succeeds")
	assertions.truthy(economy.spend_gold(30), "spending delegates")
	assertions.equal(wallet.gold, 70, "one wallet changes")
	assertions.truthy(economy.add_gold(10), "income delegates")
	assertions.equal(wallet.gold, 80, "same wallet changes")
	assertions.truthy(not economy.configure(inventory, null), "missing wallet rejected")
~~~

Create the runner using the existing `TestAssert` pattern and print `PASS: %d economy checks`.

- [ ] **Step 2: Run and verify failure**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
~~~

Expected: FAIL because `configure` does not accept a wallet.

- [ ] **Step 3: Implement the wallet boundary**

~~~gdscript
var _wallet_ref: Node
var _market_ref: Node

func configure(inventory: InventorySystem, wallet: Node, market: Node = null) -> bool:
	_inventory_ref = inventory
	_wallet_ref = wallet
	_market_ref = market
	return (
		_inventory_ref != null
		and _wallet_ref != null
		and _wallet_ref.has_method("add_gold")
		and _wallet_ref.has_method("spend_gold")
	)

func add_gold(amount: int) -> bool:
	return _wallet_ref != null and bool(_wallet_ref.add_gold(amount))

func spend_gold(amount: int) -> bool:
	return _wallet_ref != null and bool(_wallet_ref.spend_gold(amount))
~~~

Remove `EconomySystem.gold`. Inject `/root/GameState` from `main.gd` and update legacy tests to assert `wallet.gold`.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_tests.gd
git add scripts/systems/economy_system.gd scripts/main.gd tests/test_economy_wallet.gd tests/run_economy_system_tests.gd tests/test_phase1_systems.gd
git commit -m "refactor: use game state as economy wallet"
~~~

Expected: both runners PASS.

### Task 2: Add market metadata and the approved catalog

**Files:**
- Modify: `scripts/core/game_data.gd:35-96`
- Create: `tests/test_market_catalog.gd`
- Modify: `tests/run_economy_system_tests.gd`
- Modify: `tests/test_phase1_systems.gd`

- [ ] **Step 1: Test required data**

~~~gdscript
for item_id in ["wood","clay","sand","coal","copper_ore","iron_ore",
	"iron_ingot","glass","honey","egg","flour","fruit_jam"]:
	var item := GameData.get_item(item_id)
	assertions.truthy(not item.is_empty(), item_id + " registered")
	assertions.truthy(item.get("base_price", 0) > 0, item_id + " priced")
	assertions.truthy(item.get("target_stock", 0) > 0, item_id + " stock target")
	assertions.truthy(item.get("daily_liquidity", 0) > 0, item_id + " liquidity")
assertions.equal(GameData.get_item("iron").get("migrate_to"), "iron_ingot", "legacy iron migrates")
~~~

- [ ] **Step 2: Run; expect missing fields/items**

Run the economy runner. Expected: FAIL.

- [ ] **Step 3: Add exact metadata contract**

~~~gdscript
{
	"id":"wood", "name":"木材", "category":"material",
	"sell_price":1, "buy_price":2, "base_price":3,
	"target_stock":80, "initial_stock":60, "daily_liquidity":30,
	"volatility":"essential", "max_stack":99,
}
~~~

Apply these fields to every tradable item. Add raw materials `clay`, `sand`, `coal`, `copper_ore`, `iron_ore`, `silver_ore`, `gold_ore`, `crystal`; processed materials `plank`, `charcoal`, `stone_brick`, `brick`, `rope`, `cloth`, `copper_ingot`, `iron_ingot`, `steel`; outputs `honey`, `beeswax`, `egg`, `feather`; containers `glass_jar`, `glass_bottle`, `salt`; products `flour`, `animal_feed`, `sunflower_oil`, `fruit_jam`, `pickles`, `tomato_sauce`, `fruit_juice`, `bread`, `honey_cake`.

Keep legacy `iron` non-tradable with `"migrate_to":"iron_ingot"`. Add:

~~~gdscript
static func get_market_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in ITEMS.values():
		if item.get("base_price", 0) > 0 and item.get("category", "") != "legacy":
			result.append(item)
	return result
~~~

Replace the old exact 27-item assertion with required-ID assertions.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_tests.gd
git add scripts/core/game_data.gd tests/test_market_catalog.gd tests/test_phase1_systems.gd tests/run_economy_system_tests.gd
git commit -m "feat: add dynamic economy catalog"
~~~

### Task 3: Implement deterministic price math

**Files:**
- Create: `scripts/shared/market_math.gd`
- Create: `tests/test_market_math.gd`
- Modify: `tests/run_economy_system_tests.gd`

- [ ] **Step 1: Test caps and slippage**

~~~gdscript
assertions.equal(MarketMath.target_price(100,0,100,100,0,100,1.0,1.0), 250, "global ceiling")
assertions.equal(MarketMath.target_price(100,400,100,0,100,100,1.0,1.0), 50, "global floor")
assertions.equal(MarketMath.smooth_price(100,250,100), 115, "daily rise cap")
assertions.equal(MarketMath.smooth_price(100,50,100), 85, "daily fall cap")
assertions.equal(MarketMath.quote_total(100,1,20,true), 110, "buy spread")
assertions.equal(MarketMath.quote_total(100,1,20,false), 90, "sell spread")
assertions.truthy(MarketMath.quote_total(100,20,20,true) > 2200, "buy slippage")
assertions.truthy(MarketMath.quote_total(100,20,20,false) < 1800, "sell slippage")
~~~

- [ ] **Step 2: Run; expect missing script**

- [ ] **Step 3: Implement formulas**

~~~gdscript
class_name MarketMath
extends RefCounted

static func target_price(base:int, stock:int, target_stock:int, demand:int,
		supply:int, liquidity:int, season:float, event:float) -> int:
	var safe_stock := maxi(target_stock, 1)
	var safe_flow := maxi(liquidity, 1)
	var sf := clampf(1.0 + float(safe_stock-stock)/safe_stock*0.6, 0.70, 1.60)
	var df := clampf(1.0 + float(demand-supply)/safe_flow*0.35, 0.70, 1.60)
	var raw := base * sf * df * clampf(season,0.85,1.25) * clampf(event,0.80,1.50)
	return clampi(roundi(raw), ceili(base*0.50), floori(base*2.50))

static func smooth_price(current:int, target:int, base:int) -> int:
	return clampi(target, maxi(ceili(base*0.5),ceili(current*0.85)),
		mini(floori(base*2.5),floori(current*1.15)))

static func quote_total(mid:int, quantity:int, liquidity:int, is_buy:bool) -> int:
	if mid <= 0 or quantity <= 0: return 0
	var total := 0
	for i in range(quantity):
		var pressure := float(i) / maxi(liquidity,1)
		var spread := 1.10 if is_buy else 0.90
		var slip := 1.0+pressure*0.20 if is_buy else maxf(0.50,1.0-pressure*0.20)
		total += maxi(1, roundi(mid*spread*slip))
	return total
~~~

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
git add scripts/shared/market_math.gd tests/test_market_math.gd tests/run_economy_system_tests.gd
git commit -m "feat: add deterministic market math"
~~~

### Task 4: Add finite market state and atomic player trade

**Files:**
- Create: `scripts/systems/market_system.gd`
- Create: `tests/test_market_system.gd`
- Create: `tests/test_economy_transactions.gd`
- Modify: `scripts/systems/economy_system.gd`
- Modify: `scripts/core/event_bus.gd`
- Modify: `tests/run_economy_system_tests.gd`

- [ ] **Step 1: Test stock, ledger, settlement, history, and rollback**

~~~gdscript
market.configure([{"id":"wood","base_price":100,"initial_stock":10,
	"target_stock":10,"daily_liquidity":10}])
assertions.equal(market.get_stock("wood"), 10, "finite stock")
assertions.truthy(market.commit_buy("wood",3), "market sale")
assertions.equal(market.get_stock("wood"), 7, "stock decreases")
assertions.truthy(market.commit_sell("wood",5), "market purchase")
assertions.equal(market.get_stock("wood"), 12, "stock increases")
assertions.truthy(market.settle_day(2), "day settles")
assertions.truthy(not market.settle_day(2), "day is idempotent")
for day in range(3,12): market.settle_day(day)
assertions.equal(market.get_history("wood").size(), 7, "seven-day history")
~~~

For `EconomySystem` assert successful buy/sell, insufficient gold, insufficient market stock, missing inventory, zero quantity, and full inventory. Every failed case must preserve wallet, inventory, and market stock.

- [ ] **Step 2: Run; expect missing market methods**

- [ ] **Step 3: Implement market contract**

`MarketSystem` exposes `configure`, `get_item_state`, `get_stock`, `get_mid_price`, `get_history`, `quote_buy`, `quote_sell`, `can_buy`, `commit_buy`, `commit_sell`, `add_external_demand`, `add_external_supply`, `settle_day`, `to_dict`, and `from_dict`. `settle_day` accepts per-item season/event factor dictionaries. Runtime entries contain:

~~~gdscript
{"item_id":item_id, "base_price":base, "mid_price":base,
 "stock":initial, "target_stock":target, "daily_liquidity":liquidity,
 "demand":0, "supply":0, "history":[base]}
~~~

`commit_buy` reduces stock/increases demand; `commit_sell` increases stock/supply. Settlement rejects old/same days, calls `MarketMath`, resets ledger, and trims history.

Add signals `market_stock_changed`, `market_price_changed`, `market_settled`.

Implement `EconomySystem.buy_item(item_id, quantity)` and `sell_item` using this order: validate references/quantity → validate stock/capacity/ownership → calculate total → validate wallet → remove source asset → commit market side → add destination asset. Roll back every prior mutation if a later operation fails.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --editor --quit
git add scripts/systems/market_system.gd scripts/systems/economy_system.gd scripts/core/event_bus.gd tests/test_market_system.gd tests/test_economy_transactions.gd tests/run_economy_system_tests.gd
git commit -m "feat: add finite atomic market trading"
~~~

### Task 5: Establish deterministic day order and market persistence

**Files:**
- Create: `scripts/systems/daily_simulation_system.gd`
- Create: `tests/test_daily_simulation_system.gd`
- Create: `tests/test_economy_save_integration.gd`
- Modify: `scripts/systems/farming_system.gd`
- Modify: `scripts/systems/economy_system.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Test exact order**

Use call-recording doubles and assert:

~~~gdscript
["production.apply:2","farming.grow:2","production.finish:2",
 "npc.simulate:2","economy.expire:2","market.settle:2",
 "economy.orders:2","save:0"]
~~~

A second `run_day(2)` returns false and adds no calls. Save/restore changed stock, price history, and `last_settled_day`.

- [ ] **Step 2: Run; expect missing coordinator**

- [ ] **Step 3: Implement one day listener**

~~~gdscript
func run_day(day:int) -> bool:
	if day <= last_simulated_day: return false
	if production_system: production_system.apply_daily_effects(day)
	if farming_system: farming_system.on_day_changed(day)
	if production_system: production_system.finish_daily_outputs(day)
	if npc_economy_system: npc_economy_system.simulate_day(day)
	if economy_system: economy_system.advance_order_deadlines(day)
	if market_system: market_system.settle_day(day)
	if economy_system: economy_system.generate_demand_orders(day)
	last_simulated_day = day
	if save_manager: save_manager.save_game(save_manager.current_slot)
	return true
~~~

Only `DailySimulationSystem` listens for authoritative gameplay day changes. Remove day subscriptions from Farming/Economy/SaveManager. Save `economy_version:1`, market state, and `last_simulated_day`. Old saves initialize a market at the loaded day without replay.

Split the current economy day handler into `advance_order_deadlines(day)`, which performs the existing expiry loop, and `generate_demand_orders(day)`, which temporarily calls the existing generator. Task 11 replaces only the generator body with shortage-backed behavior, so the coordinator compiles and runs at every intermediate commit.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_farming_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_building_system_tests.gd
git add scripts/systems/daily_simulation_system.gd scripts/systems/farming_system.gd scripts/systems/economy_system.gd scripts/core/save_manager.gd scripts/main.gd tests/test_daily_simulation_system.gd tests/test_economy_save_integration.gd
git commit -m "feat: orchestrate deterministic economy days"
~~~

## Phase 2 — Production and farming output

### Task 6: Add recipe data and atomic production queues

**Files:**
- Create: `scripts/core/recipe_database.gd`
- Create: `scripts/data/producer_state.gd`
- Create: `scripts/systems/production_system.gd`
- Create: `tests/test_recipe_database.gd`
- Create: `tests/test_production_system.gd`
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `scripts/core/event_bus.gd`

- [ ] **Step 1: Test recipes and queue lifecycle**

~~~gdscript
assertions.equal(RecipeDatabase.get_recipe("plank").inputs, {"wood":2}, "plank inputs")
assertions.equal(RecipeDatabase.get_recipe("iron_ingot").inputs,
	{"iron_ore":2,"coal":1}, "smelting inputs")
assertions.equal(RecipeDatabase.get_recipe("fruit_jam").station,
	"food_workshop", "jam station")
assertions.truthy(production.start_recipe(workbench,"plank",1,inventory), "queue starts")
production.advance_minutes(120)
assertions.equal(workbench.producer_state.get_output_count("plank"),1,"output stored")
assertions.truthy(production.collect_all(workbench,inventory),"collection succeeds")
~~~

Also test missing inputs, station mismatch, two-slot limit, full output pause, full player inventory, and `ProducerState` round-trip.

- [ ] **Step 2: Run; expect missing recipe/production scripts**

- [ ] **Step 3: Implement exact data contracts**

Each recipe contains `id`, `display_name`, `station`, `inputs`, `outputs`, `duration_minutes`, `unlock_tier`. Register all section 7.2 recipes from the design, using 120–360 minutes for materials, 360–720 for food, and 1080–2160 for durable/luxury goods.

`ProducerState` owns `station_id`, `max_queue_slots=2`, `output_capacity=3`, `jobs`, `outputs` and `to_dict/from_dict`. `ProductionSystem` exposes:

~~~gdscript
func get_building_snapshot(building: BuildingInstance) -> Dictionary
func preflight_recipe(building: BuildingInstance, recipe_id: String,
		batches: int, inventory: InventorySystem) -> Dictionary
func start_recipe(building: BuildingInstance, recipe_id: String,
		batches: int, inventory: InventorySystem) -> bool
func add_input(building: BuildingInstance, item_id: String,
		quantity: int, inventory: InventorySystem) -> bool
func advance_minutes(minutes: int) -> void
func collect_all(building: BuildingInstance, inventory: InventorySystem) -> bool
func collect_item(building: BuildingInstance, item_id: String,
		inventory: InventorySystem) -> bool
func apply_daily_effects(total_day: int) -> void
func finish_daily_outputs(total_day: int) -> void
~~~

Preflight all multiplied inputs and queue capacity before removing materials. Completed jobs wait if output is full. Collection preflights every output quantity before moving anything. Attach and serialize `producer_state` through `BuildingInstance.to_dict()`.

Connect `EventBus.time_changed` to a production clock that converts `(hour, minute)` into elapsed game minutes and calls `advance_minutes(delta)`. Add `sync_clock(hour, minute)` for new game/load so restoring at midday cannot advance a queue twice; the remaining job minutes remain authoritative in the save.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_building_system_tests.gd
git add scripts/core/recipe_database.gd scripts/data/producer_state.gd scripts/systems/production_system.gd scripts/buildings/building_instance.gd scripts/core/event_bus.gd tests/test_recipe_database.gd tests/test_production_system.gd
git commit -m "feat: add building production queues"
~~~

### Task 7: Implement hive, coop, waterwheel, greenhouse, and barn effects

**Files:**
- Create: `tests/test_building_economy_effects.gd`
- Create: `scenes/buildings/stone_kiln.tscn`
- Create: `scenes/buildings/furnace.tscn`
- Create: `scenes/buildings/food_workshop.tscn`
- Create: `scenes/buildings/textile_machine.tscn`
- Create: `scenes/buildings/lumberyard.tscn`
- Create: `scenes/buildings/quarry.tscn`
- Create: `scenes/buildings/mine.tscn`
- Modify: `scripts/systems/production_system.gd`
- Modify: `scripts/systems/farming_system.gd`
- Modify: `scripts/core/game_data.gd`
- Modify: `scripts/data/building_data.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Test approved effects**

Assert honey every two days; four nearby mature flowers yield two honey plus one beeswax; fed coop yields two eggs daily; no feed yields nothing; full storage pauses; waterwheel waters valid cells within radius four before growth; distant cells remain dry; greenhouse cells ignore seasons; barn collects nearby output after its capacity preflight. Assert lumberyard yields wood, quarry yields stone with occasional coal, and mine yields depth-tier ore according to its configured table.

- [ ] **Step 2: Run; expect effect failures**

- [ ] **Step 3: Implement effects**

~~~gdscript
func passive_output_for(id:String, day:int, flowers:int) -> Dictionary:
	match id:
		"beehive":
			if day % 2 != 0: return {}
			return {"honey":2,"beeswax":1} if flowers >= 4 else {"honey":1}
		"chicken_coop":
			return {"egg":2}
	return {}
~~~

Remove one `animal_feed` before coop output. Count mature flower-tagged crops within four cells, capped at four. A waterwheel must border a water cell and waters a four-cell Euclidean radius during `apply_daily_effects`. Keep well manual. Greenhouse exposes 8–12 mapped cells and waterwheel connection. Barn central collection is atomic.

Add `waterwheel` with `2×2` footprint and `irrigation` effect. Add processor/automation definitions for stone kiln, furnace, food workshop, textile machine, lumberyard, quarry, and mine. Each new scene uses `BuildingInstance` with `authored_building_id`, so its procedural fallback is functional before dedicated art exists. Expose advanced buildings through the scrollable `BuildUI`; keep the nine-slot action palette unchanged until a separate palette-pagination design is approved. Task 13 replaces only the explicitly requested waterwheel fallback with painted art.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_farming_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_building_system_tests.gd
git add scripts/systems/production_system.gd scripts/systems/farming_system.gd scripts/core/game_data.gd scripts/data/building_data.gd scripts/main.gd scenes/buildings/stone_kiln.tscn scenes/buildings/furnace.tscn scenes/buildings/food_workshop.tscn scenes/buildings/textile_machine.tscn scenes/buildings/lumberyard.tscn scenes/buildings/quarry.tscn scenes/buildings/mine.tscn tests/test_building_economy_effects.gd
git commit -m "feat: add building economy effects"
~~~

### Task 8: Add crop yields, regrowth, flowers, and seasonal content

**Files:**
- Create: `tests/test_crop_economy.gd`
- Modify: `scripts/data/crop_data.gd`
- Modify: `scripts/data/crop_instance.gd`
- Modify: `scripts/systems/grid_system.gd:233-247`
- Modify: `scripts/actors/player_action_controller.gd:572-590`
- Modify: `scripts/main.gd:237-289`
- Modify: `tests/run_farming_system_tests.gd`

- [ ] **Step 1: Test deterministic harvest shape**

~~~gdscript
{"items":{"tomato":3},"exp":5,"regrowing":true}
~~~

Test carrot yield 2–3 and removal, tomato yield 2–3 with two-day regrowth, rose `flower` tag, repeatability with seed 42, and atomic multi-quantity capacity failure. Test apple, peach, grape, and lemon as persistent fruit crops; lemon rejects outdoor planting outside its configured climate but succeeds in a greenhouse.

- [ ] **Step 2: Run; expect current single-item harvest to fail**

- [ ] **Step 3: Implement fields and roster**

Add `yield_min`, `yield_max`, `regrow_days`, `tags:Array[String]`, `harvest_count`, and `growth_form` (`annual`, `bush`, `tree`, `vine`). Seed yield RNG from coordinates, crop ID, and harvest count. Preserve regrowing crops and perennial fruit; remove non-regrowing annual crops. Update controller to preflight/add every quantity.

Register grain 3 days; carrot 3; potato 4; tomato 4/regrow 2; strawberry 4/regrow 2; blueberry 5/regrow 2; watermelon 5; sunflower 4; lavender 4; pumpkin 5; rose 4. Tag sunflower/lavender/rose as flowers and use the seasons/yields approved in section 5.1. Register persistent apple (autumn), peach (summer), grape (summer/autumn vine), and lemon (greenhouse-focused) definitions plus their sapling/seed items. Fruit art may use the existing crop fallback until a dedicated fruit-visual design is approved; gameplay, inventory, production, market, and save behavior must be complete here.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_farming_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_main_gameplay_integration_tests.gd
git add scripts/data/crop_data.gd scripts/data/crop_instance.gd scripts/systems/grid_system.gd scripts/actors/player_action_controller.gd scripts/main.gd tests/test_crop_economy.gd tests/run_farming_system_tests.gd
git commit -m "feat: add crop yields and regrowth"
~~~

## Phase 3 — World material supply

### Task 9: Replace free rewards with finite gatherable targets

**Files:**
- Create: `scripts/world/resource_node.gd`
- Create: `tests/test_resource_gathering.gd`
- Modify: `scripts/world/tree_instance.gd`
- Modify: `scripts/systems/tool_system.gd`
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/world/world.gd`
- Modify: `scenes/world/world.tscn`

- [ ] **Step 1: Test target validity and depletion**

Assert axe-null fails; axe-tree grants two wood; axe-rock fails; pickaxe-rock grants two stone; three hits deplete; respawn waits exact days; full inventory prevents both reward and damage; state round-trips.

- [ ] **Step 2: Run; expect target-free tool behavior to fail**

- [ ] **Step 3: Implement common gatherable API**

`ResourceNode` exports `resource_id`, `required_tool`, `hits_remaining`, `yield_per_hit`, `bonus_table`, `respawn_days` and implements `can_gather`, `preview_reward`, `commit_gather`, `advance_day`, `to_dict/from_dict`. Extend `TreeInstance` with the same interface using axe/wood/three-day respawn.

Configure rock bonuses for coal/copper/iron; riverbank nodes produce clay/sand. `ToolSystem` preflights all rewards before commit. Route axe/pickaxe slots via `perform_target_interaction`. Persist stable resource ID, position, hits, and respawn day.

Add a `ResourceNodes` container to `world.tscn`. `world.gd` uses a fixed world-generation seed to create stable stone/ore nodes on wasteland and clay/sand nodes beside water, with simple shaded mesh fallbacks and interaction collision. Loading restores saved nodes by stable ID instead of spawning duplicates.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_tests.gd
git add scripts/world/resource_node.gd scripts/world/tree_instance.gd scripts/systems/tool_system.gd scripts/actors/player_action_controller.gd scripts/core/save_manager.gd tests/test_resource_gathering.gd
git commit -m "feat: add finite material gathering"
~~~

## Phase 4 — NPC market and orders

### Task 10: Simulate important NPCs and background demand

**Files:**
- Create: `scripts/data/npc_economy_state.gd`
- Create: `scripts/systems/npc_economy_system.gd`
- Create: `tests/test_npc_economy_system.gd`
- Modify: `scripts/core/game_data.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Test real inventory and group demand**

A woodworker with two wood and reserve five buys three, produces only after inputs exist, retains reserves, and sells excess planks. Residents add food demand, builders add plank/brick demand, artisans add ingot demand, tourists add luxury demand. State round-trips wallet, inventory, plan, and simulated day.

- [ ] **Step 2: Run; expect missing NPC economy scripts**

- [ ] **Step 3: Implement mixed simulation**

`NpcEconomyState` owns `npc_id`, `gold`, `inventory`, `reserve_targets`, `production_recipes`, `sale_targets`, `last_simulated_day`. Daily priority is: essentials → production inputs → production → reserves → excess sale → investment flag. NPC trades use the same finite stock and quotes as players.

Profiles: Lao Li general merchant/import buffer; Xiao Hua flowers/honey/luxuries; Tiejiang Zhang ore/ingot/tools; A Shui food supply; Xuezhe Lin luxury/research demand. Aggregate residents/builders/artisans/tourists write daily demand with season/event multipliers and human-readable demand tags. Track consecutive zero-stock days for essential goods; on day three Lao Li imports a capped quantity at elevated cost, resets the streak, and never imports rare goods.

- [ ] **Step 4: Run twice and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
git add scripts/data/npc_economy_state.gd scripts/systems/npc_economy_system.gd scripts/core/game_data.gd scripts/main.gd tests/test_npc_economy_system.gd
git commit -m "feat: simulate npc market behavior"
~~~

Expected: identical PASS results.

### Task 11: Generate real shortage orders and contracts

**Files:**
- Create: `tests/test_economy_orders.gd`
- Modify: `scripts/systems/economy_system.gd`
- Modify: `scripts/systems/npc_economy_system.gd`
- Modify: `scripts/core/event_bus.gd`

- [ ] **Step 1: Test shortage, premium, transfer, expiry, contract breach**

A ten-iron shortage creates at most ten units for that NPC. Daily premium is 15–30%; urgent is 40–60%. Completion transfers player items to NPC inventory and pays once. Expired orders move nothing. A three-day, five-grain/day contract tracks delivered days and one breach per missed day.

- [ ] **Step 2: Run; expect random-order implementation to fail**

- [ ] **Step 3: Implement stable records**

~~~gdscript
{"order_id":"tiejiang_zhang:iron_ore:12","npc_id":"tiejiang_zhang",
 "item_id":"iron_ore","quantity":5,"unit_price":22,"reward_gold":110,
 "expires_day":14,"kind":"daily","completed":false}
~~~

`generate_demand_orders` reads actual NPC shortages and deduplicates NPC/item. `complete_order` atomically transfers to NPC inventory then pays. Contracts add `quantity_per_day`, `start_day`, `end_day`, `delivered_days`, `breaches`. Persist IDs/completion; add `order_updated` and `contract_updated` signals.

Replace index-based order access with stable IDs and expose:

~~~gdscript
func get_orders() -> Array[Dictionary]
func get_contracts() -> Array[Dictionary]
func complete_order(order_id: String) -> bool
func sign_contract(contract_id: String) -> bool
func deliver_contract(contract_id: String, quantity: int) -> bool
~~~

Update legacy callers/tests in the same task; no UI may mutate an order dictionary directly.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
git add scripts/systems/economy_system.gd scripts/systems/npc_economy_system.gd scripts/core/event_bus.gd tests/test_economy_orders.gd
git commit -m "feat: generate orders from npc shortages"
~~~

## Phase 5 — UI, saves, presentation, and balance

Implement design section 15 exactly. Do not add a real-time order book, tomorrow-price prediction, draggable/cancellable production queues, simultaneous economy windows, gamepad-only layout, mobile layout, or technical stock charts in this phase.

UI design coverage:

| Design sections | Implementation tasks |
|---|---|
| 15.1–15.5 goals, hierarchy, HUD, hub, market | Task 12 |
| 15.6–15.7 orders and contracts | Task 15 |
| 15.8 services | Task 14 |
| 15.9–15.11 production, passive buildings, interaction | Task 16 |
| 15.12 notifications | Task 17 |
| 15.13 empty/error/disabled states | Tasks 12, 15, 16, 19 |
| 15.14–15.15 visual language, input, adaptation | Task 18 |
| 15.16–15.18 boundaries, data flow, acceptance | Task 19 |
| 15.19 automated and visual verification | Tasks 18–19 |
| 15.20 first-release exclusions | Phase 5 scope guard above |

### Task 12: Build the economy hub shell, modal behavior, and market UI

**Files:**
- Create: `tests/test_market_ui.gd`
- Create: `tests/test_market_price_chart.gd`
- Create: `scripts/ui/economy_modal_coordinator.gd`
- Create: `scripts/ui/market_panel.gd`
- Create: `scripts/ui/market_price_chart.gd`
- Create: `scripts/ui/trade_panel.gd`
- Create: `scenes/ui/economy/market_panel.tscn`
- Create: `scenes/ui/economy/trade_panel.tscn`
- Modify: `scripts/ui/shop_ui.gd`
- Modify: `scenes/ui/shop_ui.tscn`
- Modify: `scripts/ui/hud.gd`
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/main.gd`
- Modify: `tests/test_runtime_ui_scenes.gd`

- [ ] **Step 1: Write failing shell, pause, chart, and trade tests**

Require `Header`, four economy tabs, modal layer, category list, item list, price chart, stock/trend labels, quantity spin, buy/sell buttons, gold, and close button. Assert opening pauses the tree, closing restores the prior pause state, Escape closes only the top panel, and HUD emits one market request.

Test chart normalization directly:

~~~gdscript
assertions.equal(
	MarketPriceChart.normalized_points([10]),
	PackedVector2Array([Vector2(0.5, 0.5)]),
	"one price renders at chart center"
)
var flat := MarketPriceChart.normalized_points([10, 10, 10])
assertions.near(flat[0].y, 0.5, 0.001, "flat history uses centered y")
var trend := MarketPriceChart.normalized_points([10, 15, 20])
assertions.equal(trend[0], Vector2(0.0, 1.0), "lowest first price maps bottom-left")
assertions.equal(trend[2], Vector2(1.0, 0.0), "highest latest price maps top-right")
~~~

Test the large-trade threshold:

~~~gdscript
assertions.truthy(TradePanel.needs_confirmation(20, 20, 100, 1000, 10, 9), "daily liquidity triggers confirmation")
assertions.truthy(TradePanel.needs_confirmation(1, 20, 600, 1000, 10, 10), "half-wallet spend triggers confirmation")
assertions.truthy(TradePanel.needs_confirmation(10, 100, 100, 1000, 10, 8), "ten-percent tail drop triggers confirmation")
assertions.truthy(not TradePanel.needs_confirmation(1, 20, 10, 1000, 10, 10), "ordinary trade stays immediate")
~~~

Selecting wood must display finite stock, three prices, supply, demand, liquidity, 1–7 history points, tags, player quantity, and slippage-adjusted totals. A successful trade refreshes gold/inventory/stock in one frame; every failed trade preserves all three.

- [ ] **Step 2: Run UI tests and verify the old scene fails**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/test_runtime_ui_scenes.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
~~~

Expected: FAIL on missing tabs, chart, modal coordinator, or trade helpers.

- [ ] **Step 3: Implement the shell and focused panel APIs**

~~~gdscript
# shop_ui.gd: compatible root and tab router
func configure(inventory: InventorySystem, economy: EconomySystem,
		market: MarketSystem) -> bool
func open(tab_id: String = "market") -> void
func select_tab(tab_id: String) -> bool
func close() -> void

# market_panel.gd
func configure(inventory: InventorySystem, economy: EconomySystem,
		market: MarketSystem) -> bool
func select_category(category: String) -> void
func set_sort_mode(mode: String) -> void
func select_item(item_id: String) -> void
func refresh_snapshot() -> void

# trade_panel.gd
static func needs_confirmation(quantity: int, liquidity: int, total: int,
		gold: int, first_unit: int, last_unit: int) -> bool
func set_item(item_id: String) -> void
func refresh_quote() -> void
func request_buy() -> void
func request_sell() -> void
~~~

`EconomyModalCoordinator.acquire(owner)` stores the prior tree pause state, sets `get_tree().paused = true`, and makes the owner process while paused. `release(owner)` restores the prior state only when the owner owns the modal. ShopUI uses it for open/close and preserves the selected tab/category/item.

Create the exact shell hierarchy from design section 15.4. Market categories are raw materials, crops, processed materials, food/handicrafts, and rare goods. Sorting supports recommended, rise, fall, shortage, owned quantity, and name.

`MarketPriceChart.normalized_points()` maps 1–7 integer prices into normalized coordinates; `_draw()` converts them into the control rectangle with 10% vertical padding, thickens the final segment, and registers hover points without predicting future values.

Declare `class_name MarketPriceChart`, `class_name TradePanel`, `class_name MarketPanel`, and `class_name EconomyModalCoordinator` so tests and sibling panels use the same typed names shown in this plan.

Trade controls show reference unit price, actual total, stock/capacity limits, and `none/light/clear/severe` impact. Disabled buttons show the exact reason. Ordinary actions call only `EconomySystem.buy_item`/`sell_item`; the modal confirmation shows first unit, last unit, total, and next-day pressure.

Add HUD `market_requested`, top-right `市场`, and notification-count buttons without overlapping `DebugResetButton`. Main configures ShopUI and connects the market request. Add the warm paper/card colors from design section 15.14 using scene-local `StyleBoxFlat` resources; Task 18 centralizes them into a shared theme.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/test_runtime_ui_scenes.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_main_gameplay_integration_tests.gd
git add scripts/ui/economy_modal_coordinator.gd scripts/ui/market_panel.gd scripts/ui/market_price_chart.gd scripts/ui/trade_panel.gd scripts/ui/shop_ui.gd scenes/ui/shop_ui.tscn scenes/ui/economy/market_panel.tscn scenes/ui/economy/trade_panel.tscn scripts/ui/hud.gd scenes/ui/hud.tscn scripts/main.gd tests/test_market_ui.gd tests/test_market_price_chart.gd tests/test_runtime_ui_scenes.gd
git commit -m "feat: add economy hub and market ui"
~~~

### Task 13: Finalize versioned saves, new-game economy, and waterwheel art

**Files:**
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/main.gd:223-309`
- Modify: `scripts/data/building_data.gd`
- Create: `scenes/buildings/waterwheel.tscn`
- Create: `assets/buildings/painted/waterwheel/waterwheel_back.png`
- Create: `assets/buildings/painted/waterwheel/waterwheel_front.png`
- Modify: `tests/test_economy_save_integration.gd`
- Modify: `tests/test_building_art_assets.gd`
- Modify: `tests/test_building_visual_scene.gd`

- [ ] **Step 1: Test full round-trip and migration**

Round-trip market history, NPC state, queued job, output, contract, depleted resource, and last simulated day. Old `iron:5` becomes `iron_ingot:5`. Missing economy fields initialize once. Same-day load cannot settle again. Assert new game contains 12 grain seeds, 30 wood, 20 stone, 10 fiber, 150 gold, and no debug iron/glass. Assert waterwheel scene/layers load with nonzero alpha.

- [ ] **Step 2: Run; expect migration/new-game/asset failures**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_building_system_tests.gd
~~~

Expected: FAIL on missing migration fields, formal starter values, or waterwheel assets.

- [ ] **Step 3: Implement version 1 save and art**

Save all section 11 state under `economy_version:1`. Migrate legacy stacks without losing quantities. Configure the stated new-game inventory/gold.

During execution load the `imagegen` skill and create two warm hand-painted transparent layers matching current buildings. Back: timber wheel, stone/wood support, channel. Front: paddles, low stones, grass accents. No text, border, character, ground-plane shadow, or photorealism. Build scene with `BuildingInstance` conventions from `well.tscn`; keep wheel static in this milestone.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_building_system_tests.gd
godot --headless --path D:\UnityProject\villa --editor --quit
git add scripts/core/save_manager.gd scripts/main.gd scripts/data/building_data.gd scenes/buildings/waterwheel.tscn assets/buildings/painted/waterwheel tests/test_economy_save_integration.gd tests/test_building_art_assets.gd tests/test_building_visual_scene.gd
git commit -m "feat: finalize economy saves and waterwheel"
~~~

### Task 14: Add progression unlocks, upgrades, repair, and maintenance sinks

**Files:**
- Create: `scripts/systems/economy_progression_system.gd`
- Create: `scripts/ui/service_panel.gd`
- Create: `scenes/ui/economy/service_panel.tscn`
- Create: `tests/test_economy_progression.gd`
- Create: `tests/test_service_panel.gd`
- Modify: `scripts/systems/tool_system.gd`
- Modify: `scripts/systems/production_system.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/ui/shop_ui.gd`
- Modify: `scenes/ui/shop_ui.tscn`

- [ ] **Step 1: Test unlock and sink rules**

Assert a new game exposes workbench, stone kiln, and beehive recipes; windmill/coop/waterwheel/furnace require tier-one blueprints; greenhouse/mine/textile machine require tier two. Purchasing a blueprint deducts once and persists. Tool use reduces durability only after a successful action; repair deducts the quoted cost and restores durability atomically. A producer with overdue weekly maintenance pauses without consuming inputs and resumes after the exact material/coin payment. Building upgrades increase queue slots, speed, or storage but never mutate market price.

Instantiate `service_panel.tscn` and assert category filters for blueprints, recipes, repairs, upgrades, maintenance, transport/storage, and land expansion. A service card must expose gate, current level/owned state, exact gold/material cost, effect, action button, and disabled-reason label. Purchasing an owned blueprint or activating a disabled service must not deduct gold.

- [ ] **Step 2: Run; expect missing progression contracts**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
~~~

Expected: FAIL on missing progression/service APIs or scene nodes.

- [ ] **Step 3: Implement progression state**

`EconomyProgressionSystem` owns `unlocked_blueprints`, `unlocked_recipes`, and per-building `upgrade_levels`. Tier zero is granted on new game; tier-one/tier-two blueprints are purchased from market service entries after day/level gates. `ToolSystem` stores current/max durability per tool and exposes `get_repair_quote`/`repair_tool`. `ProductionSystem` stores `maintenance_due_day` and pauses before starting or advancing work when overdue. Save every progression, durability, upgrade, and maintenance field under economy version 1.

Expose the service transaction boundary:

~~~gdscript
func get_available_services() -> Array[Dictionary]
func purchase(service_id: String) -> bool
func repair(tool_id: String) -> bool
func upgrade(building: BuildingInstance, upgrade_id: String) -> bool
func maintain(building: BuildingInstance) -> bool
~~~

Implement:

~~~gdscript
func configure(progression: EconomyProgressionSystem,
		tool_system: ToolSystem, production: ProductionSystem) -> bool
func select_category(category_id: String) -> void
func refresh_services() -> void
func request_service(service_id: String) -> void
~~~

Add a `服务` tab to ShopUI. Each service card calls only the progression/tool/production transaction API. Purchased blueprints show `已拥有`; repair shows current/max durability and restored value; upgrade shows queue/speed/capacity deltas and never implies price gain.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_main_gameplay_integration_tests.gd
git add scripts/systems/economy_progression_system.gd scripts/systems/tool_system.gd scripts/systems/production_system.gd scripts/core/save_manager.gd scripts/main.gd scripts/ui/service_panel.gd scenes/ui/economy/service_panel.tscn scripts/ui/shop_ui.gd scenes/ui/shop_ui.tscn tests/test_economy_progression.gd tests/test_service_panel.gd
git commit -m "feat: add economy progression and upkeep"
~~~

### Task 15: Add order and contract UI

**Files:**
- Create: `scripts/ui/order_panel.gd`
- Create: `scripts/ui/contract_panel.gd`
- Create: `scenes/ui/economy/order_panel.tscn`
- Create: `scenes/ui/economy/contract_panel.tscn`
- Create: `tests/test_order_contract_ui.gd`
- Modify: `scripts/ui/shop_ui.gd`
- Modify: `scenes/ui/shop_ui.tscn`
- Modify: `scripts/main.gd`
- Modify: `tests/run_economy_system_tests.gd`

- [ ] **Step 1: Write failing status, filter, delivery, and signing tests**

Test the exact order status mapping:

~~~gdscript
assertions.equal(OrderPanel.status_for({"completed":true}, 0, 2), "completed", "completed wins")
assertions.equal(OrderPanel.status_for({"expires_day":1}, 5, 2), "expired", "past deadline expires")
assertions.equal(OrderPanel.status_for({"quantity":5,"expires_day":3}, 5, 2), "deliverable", "owned quantity enables delivery")
assertions.equal(OrderPanel.status_for({"quantity":5,"expires_day":3}, 2, 2), "accepted", "short inventory remains accepted")
~~~

Instantiate both scenes and require order filters `all/daily/urgent/event/construction/completed`, NPC/title/item/owned/deadline/premium/detail/deliver nodes, and contract active/available lists with daily progress, next deadline, breaches, total income, sign, and deliver controls.

Deliver an order and assert player inventory, NPC inventory, player gold, row status, and HUD unread count update once. Sign a contract and assert one confirmation; daily delivery has no confirmation. Loading the same day cannot add another breach or payment.

- [ ] **Step 2: Run and verify the panels are missing**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
~~~

Expected: FAIL on missing scripts/scenes.

- [ ] **Step 3: Implement focused panel APIs**

~~~gdscript
# order_panel.gd
static func status_for(order: Dictionary, owned: int, total_day: int) -> String
func configure(economy: EconomySystem, npc_economy: NpcEconomySystem,
		inventory: InventorySystem) -> bool
func set_filter(filter_id: String) -> void
func select_order(order_id: String) -> void
func request_delivery(order_id: String) -> void
func refresh_orders() -> void

# contract_panel.gd
func configure(economy: EconomySystem, inventory: InventorySystem) -> bool
func select_contract(contract_id: String) -> void
func request_sign(contract_id: String) -> void
func request_delivery(contract_id: String, quantity: int) -> void
func refresh_contracts() -> void
~~~

Use the layouts in design sections 15.6–15.7. Order cards show NPC/role, item, requested/owned, days, kind, premium, and state. Details show the real NPC shortage reason. Delivery calls only `EconomySystem.complete_order`.

Contract signing uses `ShopUI/ModalLayer` confirmation because it creates a cross-day obligation. Contract delivery calls only `EconomySystem.deliver_contract`, displays daily/total progress, and never pays twice. Both panels preserve filter/selection across tab changes and use explicit empty states.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/test_runtime_ui_scenes.gd
git add scripts/ui/order_panel.gd scripts/ui/contract_panel.gd scenes/ui/economy/order_panel.tscn scenes/ui/economy/contract_panel.tscn scripts/ui/shop_ui.gd scenes/ui/shop_ui.tscn scripts/main.gd tests/test_order_contract_ui.gd tests/run_economy_system_tests.gd
git commit -m "feat: add order and contract ui"
~~~

### Task 16: Add production-building and passive-building UI

**Files:**
- Create: `scripts/ui/building_economy_ui.gd`
- Create: `scripts/ui/building_production_panel.gd`
- Create: `scripts/ui/building_status_panel.gd`
- Create: `scripts/ui/world_range_overlay.gd`
- Create: `scenes/ui/economy/building_economy_ui.tscn`
- Create: `scenes/ui/economy/building_production_panel.tscn`
- Create: `scenes/ui/economy/building_status_panel.tscn`
- Create: `tests/test_building_economy_ui.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `scripts/core/event_bus.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

- [ ] **Step 1: Write failing routing, preflight, collection, and range tests**

~~~gdscript
assertions.equal(BuildingEconomyUI.panel_kind_for("windmill", "crafting"), "production", "windmill uses production panel")
assertions.equal(BuildingEconomyUI.panel_kind_for("beehive", "honey"), "status", "hive uses status panel")
assertions.equal(BuildingEconomyUI.panel_kind_for("waterwheel", "irrigation"), "status", "waterwheel uses status panel")
assertions.equal(BuildingEconomyUI.panel_kind_for("unknown", ""), "", "unknown effect opens nothing")
~~~

Instantiate a completed windmill and require recipe list, input/output values, batch controls, two queue slots, state labels, storage list, collect-all, and per-item collect. Assert missing inputs show exact quantity; starting once deducts once; closing and reopening preserves the job; output-full and maintenance-paused states match `ProductionSystem`.

Instantiate hive, coop, waterwheel, greenhouse, barn, lumberyard, quarry, and mine fixtures. Require their section-15.10 fields. Assert `WorldRangeOverlay` receives the same `Vector2i` cells as `ProductionSystem.get_irrigated_cells`; close/build-mode removes every overlay cell.

- [ ] **Step 2: Run and verify building UI is missing**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_main_gameplay_integration_tests.gd
~~~

Expected: FAIL on missing building economy UI.

- [ ] **Step 3: Implement the routing and panel contracts**

~~~gdscript
# building_economy_ui.gd
static func panel_kind_for(building_id: String, effect_type: String) -> String
func configure(production: ProductionSystem, inventory: InventorySystem,
		progression: EconomyProgressionSystem,
		modal: EconomyModalCoordinator) -> bool
func open_for(building: BuildingInstance) -> bool
func close() -> void

# building_production_panel.gd
func show_building(building: BuildingInstance) -> void
func select_recipe(recipe_id: String) -> void
func set_batches(batches: int) -> void
func request_start() -> void
func request_collect_all() -> void
func request_collect_item(item_id: String) -> void
func refresh_snapshot() -> void

# building_status_panel.gd
func show_building(building: BuildingInstance) -> void
func request_add_input(item_id: String, quantity: int) -> void
func request_collect_all() -> void
func set_range_preview(enabled: bool) -> void
func refresh_snapshot() -> void
~~~

Build the three-column production layout from section 15.9. Recipe entries show lock/material/time/margin states. Batch maximum is constrained by inventory, input capacity, and queue slots. Queue states are waiting, running, completed-awaiting-storage, output-full, maintenance-paused. First release exposes no cancel/refund action.

`BuildingStatusPanel` switches typed ViewData for hive, coop, waterwheel, greenhouse, barn, and resource producers. Feed/input transfers and all collection calls are atomic. Waterwheel preview uses semi-transparent blue-green grid geometry, has no collision, and clears on close/build-mode.

Connect `BuildingInstance.interacted` through Main. Construction-state buildings keep their construction UI and cannot open economy panels. Full-screen building panels acquire the modal coordinator and pause time; the range overlay alone does not.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_building_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_main_gameplay_integration_tests.gd
git add scripts/ui/building_economy_ui.gd scripts/ui/building_production_panel.gd scripts/ui/building_status_panel.gd scripts/ui/world_range_overlay.gd scenes/ui/economy/building_economy_ui.tscn scenes/ui/economy/building_production_panel.tscn scenes/ui/economy/building_status_panel.tscn scripts/main.gd scripts/buildings/building_instance.gd scripts/core/event_bus.gd tests/test_building_economy_ui.gd tests/run_main_gameplay_integration_tests.gd
git commit -m "feat: add building economy ui"
~~~

### Task 17: Add persisted economy notifications and HUD toasts

**Files:**
- Create: `scripts/systems/economy_notification_system.gd`
- Create: `scripts/ui/economy_notification_ui.gd`
- Create: `scenes/ui/economy/economy_notification_ui.tscn`
- Create: `tests/test_economy_notifications.gd`
- Modify: `scripts/core/event_bus.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/ui/hud.gd`
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/main.gd`
- Modify: `tests/run_economy_system_tests.gd`

- [ ] **Step 1: Write failing deduplication, unread, persistence, and navigation tests**

Use this record shape:

~~~gdscript
{"notification_id":"production:12:windmill@4,5","kind":"completed",
 "title":"生产完成","body":"风车完成了面粉 ×3","total_day":12,
 "target_type":"building","target_id":"windmill@4,5","unread":true}
~~~

Assert same-kind/same-target messages within three real seconds merge and increment `count`; unrelated messages remain separate; only the newest 20 persist; unread count caps visually at `9+`; reading changes only unread state; save/load preserves records without replay; click routes market item, building, order, or contract.

Require a maximum of three visible toast cards. Ordinary timeout is three seconds, urgent timeout six seconds, hover pauses timeout, and toast cards use `MOUSE_FILTER_PASS` so world input is not blocked outside the card.

- [ ] **Step 2: Run and verify notification components are missing**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/test_runtime_ui_scenes.gd
~~~

Expected: FAIL on missing notification scripts/scenes.

- [ ] **Step 3: Implement system-owned notification state**

~~~gdscript
func push(kind: String, title: String, body: String, total_day: int,
		target_type: String = "", target_id: String = "") -> String
func mark_read(notification_id: String) -> bool
func mark_all_read() -> void
func get_recent(limit: int = 20) -> Array[Dictionary]
func get_unread_count() -> int
func to_dict() -> Dictionary
func from_dict(data: Dictionary) -> bool
~~~

Subscribe the system to ≥10% price movement, shortage/recovery, caravan, production completed/full, feed/maintenance, order/contract, and unlock signals. Generate each event once using stable IDs. `EconomyNotificationUI` owns `ToastStack` and `NotificationCenter`; it merges presentation only after the system has merged state.

HUD shows `[市场] [通知 N]`, at most two urgent summaries, and an overflow summary. Target clicks call Main routing methods that open the correct economy tab/item, select the building, or select the order/contract.

- [ ] **Step 4: Verify and commit checkpoint**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/test_runtime_ui_scenes.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_main_gameplay_integration_tests.gd
git add scripts/systems/economy_notification_system.gd scripts/ui/economy_notification_ui.gd scenes/ui/economy/economy_notification_ui.tscn scripts/core/event_bus.gd scripts/core/save_manager.gd scripts/ui/hud.gd scenes/ui/hud.tscn scripts/main.gd tests/test_economy_notifications.gd tests/run_economy_system_tests.gd
git commit -m "feat: add economy notifications"
~~~

### Task 18: Apply the shared economy theme and responsive/accessibility rules

**Files:**
- Create: `assets/ui/economy/economy_theme.tres`
- Create: `scripts/ui/economy_layout.gd`
- Create: `tests/test_economy_ui_responsive.gd`
- Modify: `scenes/ui/shop_ui.tscn`
- Modify: `scenes/ui/economy/market_panel.tscn`
- Modify: `scenes/ui/economy/trade_panel.tscn`
- Modify: `scenes/ui/economy/order_panel.tscn`
- Modify: `scenes/ui/economy/contract_panel.tscn`
- Modify: `scenes/ui/economy/service_panel.tscn`
- Modify: `scenes/ui/economy/building_economy_ui.tscn`
- Modify: `scenes/ui/economy/building_production_panel.tscn`
- Modify: `scenes/ui/economy/building_status_panel.tscn`
- Modify: `scenes/ui/economy/economy_notification_ui.tscn`

- [ ] **Step 1: Write failing layout, focus, scale, and contrast tests**

~~~gdscript
assertions.equal(EconomyLayout.mode_for_size(Vector2(3000,2000)), "three_column", "target viewport uses columns")
assertions.equal(EconomyLayout.mode_for_size(Vector2(1920,1080)), "three_column", "desktop uses columns")
assertions.equal(EconomyLayout.mode_for_size(Vector2(1280,720)), "drawer", "minimum viewport uses drawer")
assertions.equal(EconomyLayout.clamp_scale(0.5), 0.8, "scale has lower bound")
assertions.equal(EconomyLayout.clamp_scale(2.0), 1.4, "scale has upper bound")
~~~

Instantiate every panel at 3000×2000, 1920×1080, and 1280×720. Assert controls remain within viewport, visible text has positive size, trade total/disabled reason stay visible, modal layers consume clicks, toast background does not, and focus traversal reaches every interactive control. Calculate WCAG relative contrast for primary text/background and require ≥4.5.

- [ ] **Step 2: Run and verify style/layout tests fail**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/test_runtime_ui_scenes.gd
~~~

Expected: FAIL on missing theme/layout helpers or responsive assertions.

- [ ] **Step 3: Implement shared tokens and responsive layout**

`EconomyLayout.mode_for_size()` returns drawer below 1500 logical pixels; `clamp_scale()` permits only 0.8–1.4. In drawer mode, selecting an item opens details over the list while preserving trade total and disabled reason.

Create theme colors exactly from design section 15.14: panel `#F1E5C8`, card `#FFF7E6`, primary text `#513B2F`, secondary `#7B6758`, positive `#5F8755`, warning `#C58B35`, error `#B65C4B`, selection `#7E9D70`, modal `#211A16A6`. Use 18 minimum body, 20 button, and 28–36 title sizes, 8–12 corner radii, visible keyboard focus borders, text tooltips for icon buttons, and arrow/text alongside colors.

Wire Esc, Tab/Shift+Tab, arrow navigation, Enter activation, numeric keyboard entry, and mouse-wheel quantity changes. Preserve selected tab/category/item/scroll during resize.

- [ ] **Step 4: Verify and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/test_runtime_ui_scenes.gd
godot --headless --path D:\UnityProject\villa --editor --quit
git add assets/ui/economy/economy_theme.tres scripts/ui/economy_layout.gd scenes/ui/shop_ui.tscn scenes/ui/economy tests/test_economy_ui_responsive.gd
git commit -m "feat: add responsive economy ui theme"
~~~

### Task 19: Verify complete economy UI flows and visual presentation

**Files:**
- Create: `tests/test_economy_ui_integration.gd`
- Create: `tests/capture_economy_ui.gd`
- Create: `tests/run_economy_ui_tests.gd`
- Modify: `tests/test_runtime_ui_scenes.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

- [ ] **Step 1: Write end-to-end UI scenarios**

The dedicated runner must execute these scenarios:

1. HUD → market → select wood → adjust quantity → immediate sale.
2. Shortage item → large sale → confirmation with first/last/total/pressure.
3. Order delivery → NPC inventory/player wallet/row/notification update.
4. Contract sign → daily delivery → reload → no duplicate payment/breach.
5. Windmill interaction → start flour → finish → collect.
6. Chicken coop with no feed → add feed → next-day eggs → collect.
7. Waterwheel panel → range preview → close → overlay clears.
8. Service blueprint → owned state → repeat click does not charge.
9. Three merged production notifications → target navigation.
10. Open/close every modal → original pause state restored.

Assert exact state invariants after every scenario, not just visible labels.

- [ ] **Step 2: Run and verify integration failures before final wiring**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_ui_tests.gd
~~~

Expected: FAIL until every cross-panel route and refresh signal is wired.

- [ ] **Step 3: Complete routing without cross-panel state access**

Main owns navigation methods:

~~~gdscript
func open_economy_tab(tab_id: String, target_id: String = "") -> void
func open_building_economy(building: BuildingInstance) -> void
func close_economy_modal() -> void
func navigate_economy_target(target_type: String, target_id: String) -> bool
~~~

Panels query systems or read immutable ViewData; they do not inspect sibling nodes. Route EventBus changes to local refresh methods. A full market refresh updates rows in place and preserves scroll/selection. A failed command always reloads the system snapshot before displaying its reason.

- [ ] **Step 4: Capture all required visual states**

`capture_economy_ui.gd` saves deterministic PNGs under `res://.godot/economy-ui-verification/` for:

- market normal;
- shortage plus large confirmation;
- running producer;
- full/maintenance-paused producer;
- orders/contracts;
- waterwheel overlay;
- three merged toasts;
- empty/error state;

at 3000×2000, 1920×1080, and 1280×720. Inspect captures for truncation, overlap, unreadable chart, offscreen detail, focus/disabled ambiguity, and click-through.

- [ ] **Step 5: Run UI matrix and commit**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_ui_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/test_runtime_ui_scenes.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/capture_economy_ui.gd
git add scripts/main.gd tests/test_economy_ui_integration.gd tests/capture_economy_ui.gd tests/run_economy_ui_tests.gd tests/test_runtime_ui_scenes.gd tests/run_main_gameplay_integration_tests.gd
git commit -m "test: verify complete economy ui flows"
~~~

### Task 20: Verify and tune a deterministic 28-day economy

**Files:**
- Create: `tests/test_economy_simulation.gd`
- Modify: `tests/run_economy_system_tests.gd`
- Modify: `scripts/core/game_data.gd`
- Modify: `scripts/core/recipe_database.gd`
- Modify: `docs/superpowers/specs/2026-08-01-dynamic-economy-system-design.md` only when simulation replaces a provisional number

- [ ] **Step 1: Write fixed-seed acceptance simulation**

With seed `20260801`, simulate no player plus raw gathering, crop, food-processing, and mining/manufacturing strategies. Assert: no negative values; prices stay 50–250%; daily movement ≤15%; essential shortage ≤3 days; dumping depresses then recovers; no instant recipe arbitrage; route income spread ≤20%; repeated run matches. Print exact item/day/route on failure.

- [ ] **Step 2: Run and record actual failing metrics**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
~~~

Structural assertions must pass; record every balance failure before changing data.

- [ ] **Step 3: Tune data, not invariants**

Adjust base price, starting/target stock, liquidity, recipe ratios/time, group demand, NPC reserves, and premiums. Do not weaken global bounds, ±15%, three-day recovery, atomicity, or determinism. Preserve target net income: early 40–80, mid 150–300, late 500–1000.

- [ ] **Step 4: Run the complete fresh matrix**

~~~powershell
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_grid_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_farming_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_building_system_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path D:\UnityProject\villa --script res://tests/test_runtime_ui_scenes.gd
godot --headless --path D:\UnityProject\villa --script res://tests/run_economy_ui_tests.gd
godot --headless --path D:\UnityProject\villa --editor --quit
godot --headless --path D:\UnityProject\villa --quit-after 5
~~~

Expected: every command exits 0 with no parse, resource, runtime, or assertion failures.

- [ ] **Step 5: Check every approved section**

Verify manual/automated/market material paths; crop and building outputs; finite player/NPC market; real NPC state; shortage orders; non-guaranteed processing profit; complete persistence; economy-hub pause semantics; market stock/quotes/chart/slippage; order/contract delivery; production/passive-building panels; services; notification deduplication/navigation; 3000×2000, 1920×1080, and 1280×720 layouts; and unchanged construction/camera/farming regressions.

- [ ] **Step 6: Commit verified balance**

~~~powershell
git add scripts/core/game_data.gd scripts/core/recipe_database.gd tests/test_economy_simulation.gd tests/run_economy_system_tests.gd docs/superpowers/specs/2026-08-01-dynamic-economy-system-design.md
git commit -m "test: verify twenty-eight day economy balance"
~~~

## Checkpoints

After Tasks 5, 9, 11, 17, and 20, report exact commands/results, commits, save migrations, visual-capture paths, and any numeric deviation from the approved design. Do not advance past a failing checkpoint.
