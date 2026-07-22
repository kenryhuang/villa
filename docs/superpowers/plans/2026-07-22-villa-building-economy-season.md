# Villa Building, Economy, and Season Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build validated building placement, material/gold economy and orders, a seven-day seasonal clock, and environment/tree seasonal update hooks.

**Architecture:** Resources hold authored building/order/season data. BuildingSystem orchestrates injected Grid and Economy APIs without owning Grid behavior. SeasonSystem owns clock/calendar state, pushes its four literal configurations into injected visual nodes, and delegates tree RGB changes to existing vegetation/tree nodes.

**Tech Stack:** Godot 4.7, GDScript, Jolt Physics, the existing RefCounted headless test runner, WorldEnvironment, DirectionalLight3D, StandardMaterial3D.

## Global Constraints

- Keep Godot 4.7, GL Compatibility rendering, Jolt Physics, existing terrain/road geometry, authored tree scatter, and the no-plugin tests/run_tests.gd runner.
- A building footprint is Vector2i, rooted at its requested grid coordinate. Every covered cell must be FARMLAND or WASTELAND before placement; successful placement writes BUILDING, and removal restores the exact recorded prior state.
- Consume but do not implement GridSystem.get_cell(gx: int, gz: int) -> GridCell, GridSystem.set_cell_state(gx: int, gz: int, state: int) -> void, GridSystem.grid_to_world(gx: int, gz: int) -> Vector2, GridSystem.get_terrain_height_at_cell(gx: int, gz: int) -> float, and GridCell.State FARMLAND, WASTELAND, BUILDING.
- Initial gold is 100. spend_gold rejects zero, negative, and insufficient amounts. Resource costs are Dictionary[String, int]; gold uses the gold field, all other entries use InventorySystem.remove_item atomically.
- Daily order count is 2 or 3. Quantity is 1 through 5, days_remaining is 3, reward_exp is integer reward_gold / 2, and complete_order removes items before applying gold, experience, affinity, and order-completed state.
- Day begins at 06:00, one real second is one game minute, every season lasts 7 days, and season order is Spring, Summer, Autumn, Winter.
- Seasonal terrain tints are Spring Color(0.85, 1.0, 0.8), Summer Color(0.7, 0.9, 0.6), Autumn Color(1.0, 0.85, 0.55), Winter Color(0.9, 0.92, 0.95); terrain texture is res://assets/terrain/grass-seamless-blended.png.
- There are no authored seasonal tree textures. Preserve Sprite3D textures and add only an RGB tint hook; camera-occlusion alpha must remain untouched.
- Consume EventBus signals building_placed, building_removed, building_preview_moved, gold_changed, order_generated, order_completed, order_expired, season_changed, day_changed, and time_changed with the detailed-design signatures.
- Do not implement Grid generation/overlay, farming/crops, inventory stacking, player tools/UI, villager behavior, save serialization, or new art assets.

---

## File structure

| Path | Responsibility |
|---|---|
| scripts/data/building_data.gd | Authored building data |
| scripts/data/order.gd | Order state and predicates |
| scripts/data/season_config.gd | One season visual configuration |
| scripts/buildings/building_instance.gd | Runtime location and occupied-cell snapshot |
| scripts/systems/building_system.gd | Preview, validate, place, remove |
| scripts/systems/economy_system.gd | Gold, materials, orders |
| scripts/systems/season_system.gd | Clock, calendar, visuals |
| scripts/world/tree_instance.gd | Persistent RGB seasonal tint |
| scripts/world/vegetation_builder.gd | Delegate tint to runtime trees |
| scenes/main.tscn, scripts/main.gd | Services and visual injection |
| tests/test_building_system.gd, tests/test_economy_system.gd, tests/test_season_system.gd | Deterministic tests |

### Task 1: Building and order Resources plus atomic economy

**Files:**
- Create: scripts/data/building_data.gd
- Create: scripts/data/order.gd
- Create: scripts/systems/economy_system.gd
- Create: tests/test_economy_system.gd
- Modify: scripts/core/game_data.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Produces BuildingData exports: building_id, building_name, scene_path, footprint, cost, unlock_level, description, effect_type, effect_value.
- Produces Order.is_expired() -> bool and Order.can_complete(inventory: Node) -> bool.
- Extends GameData with `register_building(data: BuildingData)`, `get_building(id)`, `set_item_price(item_id, buy_price, sell_price)`, and `get_item_price(item_id) -> Dictionary`.
- Produces EconomySystem.configure(inventory_system: Node, game_state: Node, villager_system: Node) -> void, add_gold(amount: int) -> bool, spend_gold(amount: int) -> bool, has_resources(cost: Dictionary) -> bool, spend_resources(cost: Dictionary) -> bool, `buy_item(item_id: String, quantity: int) -> bool`, `sell_item(item_id: String, quantity: int) -> bool`, generate_daily_orders() -> Array[Order], complete_order(order: Order) -> bool, advance_orders_one_day() -> void, to_dict(), from_dict().

- [ ] **Step 1: Write failing tests**

Create tests/test_economy_system.gd and register it after PlayerLogicTest in tests/run_tests.gd:

~~~gdscript
extends RefCounted
const EconomyScript = preload("res://scripts/systems/economy_system.gd")
const OrderScript = preload("res://scripts/data/order.gd")

class InventoryDouble:
	var counts := {"wood": 4, "tomato": 3}
	func has_item(id: String, quantity: int) -> bool:
		return int(counts.get(id, 0)) >= quantity
	func remove_item(id: String, quantity: int) -> bool:
		if not has_item(id, quantity): return false
		counts[id] -= quantity
		return true
	func add_item(id: String, quantity: int) -> bool:
		counts[id] = int(counts.get(id, 0)) + quantity
		return true

class GameStateDouble:
	var gold := 100
	var player_state = null
	func add_gold(amount: int) -> bool:
		if amount <= 0: return false
		gold += amount; return true
	func spend_gold(amount: int) -> bool:
		if amount <= 0 or amount > gold: return false
		gold -= amount; return true
	func add_exp(_amount: int) -> bool: return false

func run(assertions) -> void:
	var inventory := InventoryDouble.new()
	var economy := EconomyScript.new()
	var state := GameStateDouble.new()
	economy.configure(inventory, state, null)
	assertions.truthy(economy.has_resources({"gold": 50, "wood": 4}), "combined cost is affordable")
	assertions.truthy(economy.spend_resources({"gold": 50, "wood": 4}), "combined spend succeeds")
	assertions.equal(state.gold, 50, "authoritative gold is debited")
	assertions.equal(inventory.counts.wood, 0, "materials are debited")
	assertions.equal(economy.spend_resources({"gold": 60, "tomato": 3}), false, "unaffordable cost rejects")
	assertions.equal(inventory.counts.tomato, 3, "rejection preserves materials")
	var order := OrderScript.new()
	order.item_id = "tomato"; order.quantity = 3
	order.reward_gold = 12; order.reward_exp = 6
	assertions.equal(economy.complete_order(order), true, "owned order completes")
	assertions.equal(state.gold, 62, "order credits authoritative gold")
	assertions.equal(order.is_active, false, "order becomes inactive")
~~~

- [ ] **Step 2: Run RED**

Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd

Expected: exit 1, preload error for the new Economy/Order files.

- [ ] **Step 3: Implement exact data and transaction behavior**

Create BuildingData extends Resource with defaults footprint = Vector2i(1, 1), cost = {}, unlock_level = 1, effect_value = 0, and empty-string defaults for every String export. Create Order extends Resource with order_id/item_id/villager_id empty, quantity 1, reward values 0, days_remaining 3, is_active true; expiry is days_remaining <= 0; completion requires active, unexpired, and inventory.has_item(item_id, quantity).

Create EconomySystem extends Node with injected inventory/game_state/villager collaborators and `active_orders`; it must not declare a gold field. `has_resources` rejects any quantity below 1 and reads `game_state.gold`. `spend_resources` calls `has_resources` first, then delegates gold to `game_state.spend_gold` and removes materials in sorted key order. `add_gold/spend_gold` delegate to GameState, which alone emits `gold_changed`. Register BuildingData and item buy/sell price dictionaries in GameData. `buy_item` calculates from GameData, verifies inventory capacity before spending, and rolls back gold if an unexpected add fails. `sell_item` verifies/removes items before delegating the reward to GameState.

generate_daily_orders returns [] when either candidate list is empty; otherwise uses randi_range(2, 3), ids day-%d-%d, candidate selection by randi_range, quantity randi_range(1, 5), reward_gold = max(1, GameData sell price times quantity), and reward_exp = reward_gold / 2. It appends active orders and emits order_generated. complete_order checks `Order.can_complete(inventory_system)`, removes items, delegates gold and XP to GameState, conditionally calls `villager_system.add_affinity(order.villager_id, 10)` as specified by detailed-design §1.6, deactivates the order, emits order_completed, and returns true. advance_orders_one_day decrements active orders; at zero it deactivates and emits order_expired. `to_dict/from_dict` round-trip active orders only; GameState owns gold and PlayerState.

- [ ] **Step 4: Run GREEN**

~~~bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
~~~

Expected: both commands exit 0; rejected costs preserve every balance.

- [ ] **Step 5: Commit**

~~~bash
git add scripts/data/building_data.gd scripts/data/order.gd scripts/systems/economy_system.gd scripts/core/game_data.gd tests/test_economy_system.gd tests/run_tests.gd
git commit -m "feat: add building data and economy orders"
~~~

### Task 2: Footprint-safe building lifecycle

**Files:**
- Create: scripts/buildings/building_instance.gd
- Create: scripts/systems/building_system.gd
- Create: scenes/buildings/barn.tscn, greenhouse.tscn, windmill.tscn, chicken_coop.tscn, beehive.tscn, well.tscn, workbench.tscn, lamppost.tscn, fence.tscn
- Create: tests/test_building_system.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Consumes the Grid/Economy contracts in Global Constraints.
- Produces BuildingInstance.configure(data: BuildingData, gx: int, gz: int, cells: Array[Dictionary]) -> void, get_interaction_area() -> Area3D, and occupied_cells records containing gx, gz, previous_state.
- Produces BuildingSystem.configure(grid_system: Node, economy_system: Node, buildings_container: Node3D) -> void, enter_preview_mode(building_data: BuildingData) -> void, exit_preview_mode() -> void, update_preview(gx: int, gz: int) -> bool, can_place(building_data: BuildingData, gx: int, gz: int) -> bool, place_building(building_data: BuildingData, gx: int, gz: int) -> BuildingInstance, remove_building(instance: BuildingInstance) -> void, get_all_buildings() -> Array[BuildingInstance], get_buildings_of_type(type: String) -> Array[BuildingInstance].
- Produces nine loadable building scenes rooted at BuildingInstance, with static collision on layer 64 and interaction area on layer 256.

- [ ] **Step 1: Write failing Grid-boundary tests**

Create tests/test_building_system.gd and register it:

~~~gdscript
extends RefCounted
const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const BuildingSystemScript = preload("res://scripts/systems/building_system.gd")

class Cell:
	var state := 1
class GridDouble:
	const FARMLAND := 1
	const WASTELAND := 0
	const BUILDING := 4
	var cells := {}
	func get_cell(gx: int, gz: int): return cells.get(Vector2i(gx, gz))
	func set_cell_state(gx: int, gz: int, state: int) -> void: cells[Vector2i(gx, gz)].state = state
	func grid_to_world(gx: int, gz: int) -> Vector2: return Vector2(gx + .5, gz + .5)
	func get_terrain_height_at_cell(_gx: int, _gz: int) -> float: return 2.0
class EconomyDouble:
	func has_resources(_cost: Dictionary) -> bool: return true
	func spend_resources(_cost: Dictionary) -> bool: return true

func run(assertions) -> void:
	var grid := GridDouble.new()
	grid.cells[Vector2i(0, 0)] = Cell.new()
	grid.cells[Vector2i(1, 0)] = Cell.new()
	var system := BuildingSystemScript.new()
	var container := Node3D.new()
	system.configure(grid, EconomyDouble.new(), container)
	var data := BuildingDataScript.new()
	data.footprint = Vector2i(2, 1)
	assertions.truthy(system.can_place(data, 0, 0), "two free footprint cells pass")
	grid.cells[Vector2i(1, 0)].state = grid.BUILDING
	assertions.equal(system.can_place(data, 0, 0), false, "one occupied cell rejects all placement")
	container.free()
~~~

- [ ] **Step 2: Run RED**

Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd

Expected: exit 1 because BuildingSystem is absent.

- [ ] **Step 3: Implement preview/place/remove**

BuildingInstance extends Node3D, stores the data/coordinates/records passed to configure, and returns get_node_or_null("InteractionArea") as Area3D.

Create all nine scenes listed above with the common root script, one MeshInstance3D, `Collision` StaticBody3D on layer 64, and `InteractionArea` Area3D on layer 256; both bodies contain footprint-sized shapes. Extend the test to load every scene and assert those node paths and layers. Use simple BoxMesh/BoxShape placeholders sized from BuildingData; replacing them with final art is outside this plan.

BuildingSystem extends Node3D. It stores injected collaborators plus preview_data, preview_grid, preview_can_place, and a child Node3D named BuildingPreview. enter_preview_mode assigns data and shows it; exit_preview_mode clears/hides it; update_preview records coordinates, calls can_place, emits building_preview_moved, and returns the result.

can_place loops dx in range(data.footprint.x) and dz in range(data.footprint.y), rejects null or states not FARMLAND/WASTELAND, then calls economy.has_resources(data.cost). place_building returns null unless can_place and spend_resources succeed. On success it records every cell’s old state, writes BUILDING to all cells, instantiates data.scene_path as PackedScene or creates BuildingInstance.new when scene_path is empty, configures it, positions it at grid_to_world origin plus get_terrain_height_at_cell, adds it to the supplied container/tracked list, emits building_placed, and returns it. remove_building restores every recorded state, removes tracking, emits building_removed, and queue_free. get_buildings_of_type compares building_data.effect_type.

- [ ] **Step 4: Run GREEN**

Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd

Expected: exit 0; null, occupied, and out-of-bounds cells never spend or mutate.

- [ ] **Step 5: Commit**

~~~bash
git add scripts/buildings/building_instance.gd scripts/systems/building_system.gd scenes/buildings tests/test_building_system.gd tests/run_tests.gd
git commit -m "feat: add validated building placement"
~~~

### Task 3: Deterministic calendar and exact visual configs

**Files:**
- Create: scripts/data/season_config.gd
- Modify: scripts/systems/season_system.gd
- Modify: tests/test_season_system.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Produces SeasonConfig fields season, season_name, terrain_tint, ambient_color, ambient_energy, sun_color, sun_energy, sky_color, allowed_crops, special_event.
- Extends the existing SeasonSystem while preserving `advance_game_minutes(minutes: int) -> void`, Season { SPRING, SUMMER, AUTUMN, WINTER }, DAYS_PER_SEASON = 7, and MINUTES_PER_REAL_SECOND = 1.0; produces `advance_day()`, `configure_visuals(world_environment, sun, terrain_material, vegetation)`, and `apply_season_visuals(season)`.

- [ ] **Step 1: Write failing rollover tests**

Create tests/test_season_system.gd and register it:

~~~gdscript
extends RefCounted
const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")
func run(assertions) -> void:
	var season := SeasonSystemScript.new()
	season.hour = 23; season.minute = 59
	season.advance_game_minutes(1)
	assertions.equal(season.hour, 6, "midnight returns clock to six")
	assertions.equal(season.current_day, 2, "midnight advances local day")
	season.current_day = 7
	season.current_season = season.Season.WINTER
	season.advance_day()
	assertions.equal(season.current_day, 1, "season day wraps after seven")
	assertions.equal(season.current_season, season.Season.SPRING, "winter wraps to spring")
	assertions.equal(season.total_days, 3, "day rollover increments total days")
~~~

- [ ] **Step 2: Run RED**

Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd

Expected: exit 1 because SeasonConfig and visual configuration methods are missing from the existing minimum SeasonSystem.

- [ ] **Step 3: Implement clock and seasonal configuration**

SeasonConfig extends Resource with the fields/defaults above. Preserve the minimum clock from Plan 1: Spring/day 1/total day 1/06:00, fractional `_process` accumulation, and `advance_game_minutes`. Extract its existing midnight body into `advance_day()` without changing signal order; `advance_game_minutes` calls it at 24:00.

Define four literal configs using all detailed-design ambient/sun/sky/energy values, Chinese names 春 夏 秋 冬, the shared terrain path, and the tints in Global Constraints. configure_visuals stores all four collaborators. apply_season_visuals returns when a collaborator is null; otherwise it loads the terrain path, sets terrain material albedo texture/color, environment ambient color/energy/background color, sun color/energy, then calls vegetation.update_tree_season(season, config.terrain_tint).

- [ ] **Step 4: Run GREEN**

~~~bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
~~~

Expected: both exit 0; Spring follows Winter and no state skips 06:00.

- [ ] **Step 5: Commit**

~~~bash
git add scripts/data/season_config.gd scripts/systems/season_system.gd tests/test_season_system.gd tests/run_tests.gd
git commit -m "feat: add seasonal clock and visuals"
~~~

### Task 4: Preserve tree textures while adding seasonal RGB hooks

**Files:**
- Modify: scripts/world/tree_instance.gd
- Modify: scripts/world/vegetation_builder.gd
- Modify: tests/test_tree_instance.gd
- Modify: tests/test_vegetation_builder.gd

**Interfaces:**
- Produces TreeInstance.set_season_tint(tint: Color) -> void.
- Produces VegetationBuilder.update_tree_season(season: int, tint: Color) -> void.

- [ ] **Step 1: Write failing tint tests**

Append to the existing configured tree assertions:

~~~gdscript
tree.set_season_tint(Color(1.0, 0.85, 0.55, 1.0))
assertions.equal(tree.sprite.modulate.r, 1.0, "season tint sets red")
assertions.equal(tree.sprite.modulate.g, 0.85, "season tint sets green")
assertions.equal(tree.sprite.modulate.b, 0.55, "season tint sets blue")
~~~

In test_vegetation_builder.gd, after making a configured runtime tree, put it under a VegetationBuilder and assert:

~~~gdscript
vegetation.update_tree_season(2, Color(1.0, 0.85, 0.55, 1.0))
assertions.equal(tree.sprite.modulate.g, 0.85, "vegetation delegates autumn tint")
~~~

- [ ] **Step 2: Run RED**

Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd

Expected: exit 1, missing seasonal methods.

- [ ] **Step 3: Implement alpha-safe tint delegation**

Add season_tint = Color.WHITE to TreeInstance. set_season_tint stores tint and, when sprite exists, replaces only sprite.modulate.r/g/b while leaving sprite.modulate.a unchanged. Add VegetationBuilder.update_tree_season that loops children and calls set_season_tint only where has_method succeeds. Do not edit TEXTURES, Sprite3D textures, placement, scale, collision layers, or opacity_step.

- [ ] **Step 4: Run GREEN**

~~~bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
~~~

Expected: exit 0; tree collision/camera tests remain green and tint changes no alpha.

- [ ] **Step 5: Commit**

~~~bash
git add scripts/world/tree_instance.gd scripts/world/vegetation_builder.gd tests/test_tree_instance.gd tests/test_vegetation_builder.gd
git commit -m "feat: add seasonal tree tint hooks"
~~~

### Task 5: Wire published services into the world

**Files:**
- Modify: scenes/main.tscn
- Modify: scripts/main.gd
- Modify: tests/smoke_test.gd

**Interfaces:**
- Consumes world.terrain, world.vegetation, Main/Environment.environment, Main/Sun, BuildingSystem.configure, EconomySystem.configure, SeasonSystem.configure_visuals, SeasonSystem.apply_season_visuals.
- Produces World/Buildings, Systems/BuildingSystem, Systems/EconomySystem, Systems/SeasonSystem, and initial Spring application.

- [ ] **Step 1: Write failing scene assertions**

Add to tests/smoke_test.gd:

~~~gdscript
assertions.truthy(main.has_node("World/Buildings"), "world has building container")
assertions.truthy(main.has_node("Systems/BuildingSystem"), "main has building system")
assertions.truthy(main.has_node("Systems/EconomySystem"), "main has economy system")
assertions.truthy(main.has_node("Systems/SeasonSystem"), "main has season system")
~~~

- [ ] **Step 2: Run RED**

Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd

Expected: exit 1, missing container/system nodes.

- [ ] **Step 3: Perform exact injection**

Add Node3D World/Buildings. Add BuildingSystem and EconomySystem under the existing Systems parent; reuse `Systems/SeasonSystem` from Plan 2 rather than adding a second. In main.gd obtain `Systems/GridSystem`, `Systems/InventorySystem`, the `GameState` Autoload, world terrain, vegetation, World/Buildings, Environment, Sun, and TerrainMesh.material_override as StandardMaterial3D. Configure Economy with InventorySystem and GameState; leave VillagerSystem null until Plan 5 adds it. Configure BuildingSystem with the existing GridSystem, Economy, and Buildings. Configure the existing SeasonSystem visuals, connect EventBus.day_changed to economy.advance_orders_one_day, call apply_season_visuals(current_season), and enable its processing. Do not create a second GridSystem/SeasonSystem or reimplement Grid/Farming behavior.

- [ ] **Step 4: Verify GREEN and visual acceptance**

~~~bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 10
~~~

Expected: exit 0, 28 runtime trees, Spring visual values, and no missing Grid or duplicate Systems error. In the editor, advance all seasons and verify terrain/environment/sun/tree RGB changes while camera fade still changes only alpha; verify invalid building placement does not mutate a Grid cell.

- [ ] **Step 5: Commit**

~~~bash
git add scenes/main.tscn scripts/main.gd tests/smoke_test.gd
git commit -m "feat: wire building economy and seasons"
~~~

### Task 6: Final verification

**Files:**
- Verify only; no source changes.

**Interfaces:**
- Consumes the complete building/economy/season contracts.
- Produces a verified implementation branch.

- [ ] **Step 1: Re-run complete verification**

~~~bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 10
~~~

Expected: all commands exit 0 with no failed assertion, parse/import error, missing resource, or runtime error.

- [ ] **Step 2: Confirm source-control scope**

Run: git status --short && git log -6 --oneline

Expected: only the planned implementation commits are present; no generated import output is staged.
