# Main Game Farming and Building Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the verified grid, farming, and building systems into `main.tscn` so the player can select actions, farm, harvest, and build through one context-sensitive left-click controller.

**Architecture:** Add a `PlayerActionController` child to Player and inject the existing runtime systems from `main.gd`. The controller owns selection, raycasts, action priority, hover feedback, planting, harvesting, and building placement; `PlayerController` remains responsible for movement, while HUD emits slot-selection requests and displays the selected action.

**Tech Stack:** Godot 4.7.1, GDScript, Jolt Physics, existing RefCounted test harnesses, existing grid/farming/building scenes, existing painted grain and staged-construction assets.

## Global Constraints

- World interaction uses mouse left-click only.
- Quick slots 1–5 select hoe, watering can, axe, pickaxe, and fishing rod; slot 6 selects grain seed.
- `Q/E` remain camera rotation keys; `E` must not trigger world interaction.
- Farming/tool actions use the player's existing `2.5m` horizontal interaction range.
- Building preview and placement retain the existing unrestricted map range.
- Mature crop harvest takes priority over the selected tool or seed.
- Invalid actions consume no stamina, seed, crop output, or building material.
- Reuse the four scenes under `assets/crops/grain`; do not duplicate verifier logic or art.
- Reuse the current `BuildingSystem` and `BuildingInstance` construction stages and durations.
- Preserve existing terrain, road, vegetation, camera occlusion, NPC, and UI behavior.
- Use `/Applications/Godot.app/Contents/MacOS/Godot` for macOS verification.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/actors/player_action_controller.gd` | Selection state, action priority, raycasts, hover feedback, farm transactions, interaction dispatch, and build placement. |
| `scripts/actors/player.gd` | Movement, collision, stamina regeneration, and compatibility helpers only. |
| `scripts/systems/inventory_system.gd` | Capacity preflight used to keep harvesting atomic. |
| `scripts/core/save_manager.gd` | Finds the runtime inventory by group so main-scene inventory and quick mappings persist. |
| `scripts/systems/tool_system.gd` | Tool validation/execution followed by stamina deduction only on success. |
| `scripts/core/game_data.gd` | `grain_seed` and `grain` static item definitions. |
| `scripts/main.gd` | Runtime wiring, grain CropData registration, load/new-game ordering, starter resources, and UI/controller configuration. |
| `scenes/actors/player.tscn` | Authors `PlayerActionController` under Player. |
| `scripts/ui/hud.gd` | Emits quick-slot selection and renders labels, count, and selection highlight. |
| `scenes/ui/hud.tscn` | Makes all six slots mouse-clickable. |
| `tests/run_main_gameplay_integration_tests.gd` | Focused deterministic runner for this integration. |
| `tests/test_inventory_capacity.gd` | Inventory capacity and harvest-preflight contracts. |
| `tests/test_tool_action_transaction.gd` | Tool success/failure stamina contracts. |
| `tests/test_player_action_controller.gd` | Action priority, selection, planting, and harvesting contracts. |
| `tests/test_main_farming_building_integration.gd` | Real `main.tscn` dependency and gameplay-flow contract. |
| `tests/capture_main_gameplay_integration.gd` | Creates representative farm/build states in main and captures a visual acceptance image. |

---

### Task 1: Add grain catalog data and inventory capacity preflight

**Files:**
- Modify: `scripts/core/game_data.gd`
- Modify: `scripts/systems/inventory_system.gd`
- Create: `tests/test_inventory_capacity.gd`
- Create: `tests/run_main_gameplay_integration_tests.gd`

**Interfaces:**
- Consumes: `GameData.get_item(item_id: String) -> Dictionary`, `InventorySystem.slots`.
- Produces: `InventorySystem.can_add_item(item_id: String, quantity: int = 1) -> bool`, catalog entries `grain_seed` and `grain`.

- [ ] **Step 1: Write the failing inventory and catalog tests**

Create `tests/test_inventory_capacity.gd` with checks equivalent to:

```gdscript
extends RefCounted

func run(assertions: TestAssert) -> void:
	assertions.equal(GameData.get_item("grain_seed").category, "seed", "grain seed is registered")
	assertions.equal(GameData.get_item("grain").category, "crop", "grain harvest is registered")

	var inventory := InventorySystem.new()
	inventory.max_slots = 1
	assertions.truthy(inventory.can_add_item("grain_seed", 99), "empty slot accepts one full stack")
	assertions.truthy(not inventory.can_add_item("grain_seed", 100), "empty slot rejects more than one full stack")
	inventory.add_item("grain_seed", 98)
	assertions.truthy(inventory.can_add_item("grain_seed", 1), "partial stack accepts remaining item")
	assertions.truthy(not inventory.can_add_item("grain", 1), "full inventory rejects a different item")
	inventory.free()
```

Create `tests/run_main_gameplay_integration_tests.gd` as a `SceneTree` runner that instantiates `TestAssert`, runs `InventoryCapacityTest`, prints `PASS: N main gameplay integration checks` on success, prints every failure on error, and exits with `0` or `1`.

- [ ] **Step 2: Run the focused runner and verify it fails**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: non-zero exit because `grain_seed`, `grain`, and `can_add_item()` are absent.

- [ ] **Step 3: Add grain data and deterministic capacity calculation**

Add these item definitions to `GameData.ITEMS`:

```gdscript
"grain_seed": {
	"id": "grain_seed", "name": "谷物种子", "category": "seed",
	"sell_price": 0, "buy_price": 4, "max_stack": 99,
},
"grain": {
	"id": "grain", "name": "谷物", "category": "crop",
	"sell_price": 7, "buy_price": 0, "max_stack": 99,
},
```

Add this public preflight contract to `InventorySystem`:

```gdscript
func can_add_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false
	var item_data := GameData.get_item(item_id)
	var max_stack := int(item_data.get("max_stack", 99)) if item_data else 99
	var remaining := quantity
	for slot in slots:
		if slot.item_id == item_id:
			remaining -= maxi(0, max_stack - int(slot.quantity))
			if remaining <= 0:
				return true
	var free_slots := maxi(0, max_slots - slots.size())
	return remaining <= free_slots * max_stack
```

- [ ] **Step 4: Run the focused runner and verify it passes**

Run the command from Step 2.

Expected: exit `0` and a `PASS` line.

- [ ] **Step 5: Commit the catalog and inventory transaction**

```bash
git add scripts/core/game_data.gd scripts/systems/inventory_system.gd \
  tests/test_inventory_capacity.gd tests/run_main_gameplay_integration_tests.gd
git commit -m "feat: add grain inventory contracts"
```

---

### Task 2: Make tool stamina consumption transactional

**Files:**
- Modify: `scripts/systems/tool_system.gd`
- Create: `tests/test_tool_action_transaction.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

**Interfaces:**
- Consumes: `ToolSystem.use_tool_on(target: Variant) -> bool`, `GameState.player_state.stamina`.
- Produces: the guarantee that stamina decreases only after the selected tool action succeeds.

- [ ] **Step 1: Write failing stamina transaction tests**

Create a test double with `set_cell_state()` and `water_cell()` methods. In `tests/test_tool_action_transaction.gd`, set the autoload stamina to `100`, configure a `ToolSystem`, and assert:

```gdscript
var invalid := GridCell.new()
invalid.state = GridCell.State.FARMLAND
tool.switch_tool(ToolSystem.ToolType.HOE)
assertions.truthy(not tool.use_tool_on(invalid), "hoe rejects existing farmland")
assertions.equal(GameState.player_state.stamina, 100, "invalid hoe action consumes no stamina")

var valid := GridCell.new()
valid.state = GridCell.State.WASTELAND
assertions.truthy(tool.use_tool_on(valid), "hoe accepts wasteland")
assertions.equal(GameState.player_state.stamina, 95, "successful hoe action consumes stamina")
```

Register the test in the focused runner immediately after `InventoryCapacityTest`.

- [ ] **Step 2: Run the focused runner and verify the invalid action fails the stamina assertion**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: non-zero exit with `invalid hoe action consumes no stamina`.

- [ ] **Step 3: Reorder `use_tool_on()` to deduct only after success**

Keep the stamina precheck, execute the selected action into a boolean, and deduct after success:

```gdscript
var succeeded := false
match current_tool:
	ToolType.HOE:
		succeeded = _use_hoe(target)
	ToolType.WATERING_CAN:
		succeeded = _use_watering_can(target)
	ToolType.AXE:
		succeeded = _use_axe(target)
	ToolType.PICKAXE:
		succeeded = _use_pickaxe(target)
	ToolType.FISHING_ROD:
		succeeded = _use_fishing_rod(target)
if not succeeded:
	return false
game_state.player_state.stamina -= stamina_cost
if _event_bus:
	_event_bus.stamina_changed.emit(game_state.player_state.stamina)
return true
```

- [ ] **Step 4: Run the focused runner and farming/grid regression suites**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_grid_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_farming_system_tests.gd
```

Expected: all three commands exit `0`.

- [ ] **Step 5: Commit the transactional tool behavior**

```bash
git add scripts/systems/tool_system.gd tests/test_tool_action_transaction.gd \
  tests/run_main_gameplay_integration_tests.gd
git commit -m "fix: consume stamina after successful tool actions"
```

---

### Task 3: Implement the unified PlayerActionController

**Files:**
- Create: `scripts/actors/player_action_controller.gd`
- Modify: `scenes/actors/player.tscn`
- Modify: `scripts/actors/player.gd`
- Modify: `scripts/systems/farming_system.gd`
- Create: `tests/test_player_action_controller.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

**Interfaces:**
- Consumes: `GridSystem`, `FarmingSystem`, `BuildingSystem`, `ToolSystem`, `InventorySystem`, Player `interaction_range`, and camera projection APIs.
- Produces:
  - `configure(player, grid, farming, building, tools, inventory) -> void`
  - `select_slot(index: int) -> bool`
  - `get_selected_slot() -> int`
  - `perform_cell_action(cell: GridCell) -> bool`
  - `perform_build_action(gx: int, gz: int) -> BuildingInstance`
  - `selection_changed(index: int, label: String)` signal
  - `inventory_changed()` signal

- [ ] **Step 1: Write failing action priority and transaction tests**

In `tests/test_player_action_controller.gd`, test the pure resolver and direct cell actions:

```gdscript
assertions.equal(
	PlayerActionController.resolve_action(true, true, true, true, 5),
	PlayerActionController.Action.BUILD,
	"build mode has highest priority"
)
assertions.equal(
	PlayerActionController.resolve_action(false, true, true, true, 5),
	PlayerActionController.Action.INTERACT,
	"physical interaction precedes grid action"
)
assertions.equal(
	PlayerActionController.resolve_action(false, false, true, true, 0),
	PlayerActionController.Action.HARVEST,
	"mature crop precedes selected tool"
)
assertions.equal(
	PlayerActionController.resolve_action(false, false, true, false, 5),
	PlayerActionController.Action.PLANT,
	"seed slot plants on farmland"
)
```

Build a real `GridSystem` test cell through the existing grid test fixture or a small fake dependency, then assert:

- selecting slot 5 resolves to `grain_seed`;
- planting removes exactly one seed only on success;
- planting failure refunds the temporarily removed seed;
- harvesting refuses when `can_add_item("grain", 1)` is false;
- harvesting succeeds when capacity exists and adds exactly one `grain`.

Register this test after `ToolActionTransactionTest`.

- [ ] **Step 2: Run the focused runner and verify controller symbols are missing**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: non-zero exit because `PlayerActionController` does not exist.

- [ ] **Step 3: Implement controller selection and direct cell actions**

Create `PlayerActionController` with:

```gdscript
class_name PlayerActionController
extends Node

signal selection_changed(index: int, label: String)
signal inventory_changed

enum Action { NONE, BUILD, INTERACT, HARVEST, PLANT, TOOL }

const SEED_SLOT := 5
const SEED_ITEM_ID := "grain_seed"
const CROP_ID := "grain"
const SLOT_LABELS := ["锄头", "浇水壶", "斧头", "镐", "鱼竿", "谷物种子"]
const TOOL_BY_SLOT := [
	ToolSystem.ToolType.HOE,
	ToolSystem.ToolType.WATERING_CAN,
	ToolSystem.ToolType.AXE,
	ToolSystem.ToolType.PICKAXE,
	ToolSystem.ToolType.FISHING_ROD,
]
```

`select_slot()` accepts indices `0–5`; slots `0–4` call `tool_system.switch_tool()`, slot `5` selects seed mode, and every success emits `selection_changed`.

`perform_cell_action()` applies this order:

```gdscript
if _is_mature(cell):
	return _harvest(cell)
if _selected_slot == SEED_SLOT:
	return _plant(cell)
if _selected_slot in [0, 1]:
	return tool_system.use_tool_on(cell)
return false
```

`_plant()` verifies farmland, season, seed quantity, and crop data; removes one seed, calls `farming_system.plant()`, and refunds the seed when planting returns `null`.

`_harvest()` verifies maturity and `inventory_system.can_add_item(CROP_ID, 1)` before calling `farming_system.harvest()`, then adds every returned item and emits `inventory_changed`.

Add `FarmingSystem.can_plant(cell: GridCell, crop_data: CropData) -> bool` and use it from `_plant()`. It returns true only for empty farmland in the correct season or a greenhouse cell. Slots 3–5 do not act on bare grid cells; their future tree, rock, and fishing targets remain outside this integration.

- [ ] **Step 4: Add mouse raycasts, hover, build placement, and physical interaction**

Implement `_process()` and `_unhandled_input()`:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := _slot_from_key(event.keycode)
		if slot >= 0 and select_slot(slot):
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and building_system.is_in_build_mode():
			building_system.exit_preview_mode()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		if _perform_pointer_action():
			get_viewport().set_input_as_handled()
```

`_perform_pointer_action()` must:

1. place the selected building when build mode is active;
2. otherwise raycast collision masks `4 | 64 | 128`, resolve the parent interaction target, enforce horizontal range, and call `start_dialogue`, `interact`, or `collect`;
3. otherwise resolve a grid cell within `interaction_range` and call `perform_cell_action()`.

The build path calls the public `perform_build_action(gx, gz)`, which delegates to `building_system.place_selected_building(gx, gz)`. This public method is the deterministic integration-test seam.

`_process()` must update building preview without range restriction, or highlight the hovered cell with gold/blue/green/red based on current state. It clears the single-cell highlight while build mode is active or while the pointer is over a consuming UI control.

- [ ] **Step 5: Author the controller node and remove duplicate player input**

Add the controller script resource and node to `scenes/actors/player.tscn`:

```gdscript
[node name="ActionController" type="Node" parent="."]
script = ExtResource("player_action_controller")
```

Remove `_unhandled_input()`, `_use_current_tool()`, `_interact()`, `_raycast_to_grid_cell()`, and `_switch_tool()` from `player.gd`. Retain the static movement and interaction-target helpers if existing regression tests still call them.

- [ ] **Step 6: Run focused controller tests**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: exit `0` and all action-priority/transaction checks pass.

- [ ] **Step 7: Commit the controller**

```bash
git add scripts/actors/player_action_controller.gd scripts/actors/player.gd \
  scripts/systems/farming_system.gd scenes/actors/player.tscn \
  tests/test_player_action_controller.gd \
  tests/run_main_gameplay_integration_tests.gd
git commit -m "feat: add unified player action controller"
```

---

### Task 4: Make the HUD quick bar clickable and stateful

**Files:**
- Modify: `scripts/ui/hud.gd`
- Modify: `scenes/ui/hud.tscn`
- Create: `tests/test_hud_action_bar.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

**Interfaces:**
- Consumes: `PlayerActionController.select_slot(index: int)`, `InventorySystem.get_item_count(item_id: String)`.
- Produces:
  - `VillaHud.quick_slot_selected(index: int)` signal
  - `configure_action_bar(action_controller, inventory) -> void`
  - `refresh_action_bar() -> void`

- [ ] **Step 1: Write the failing HUD contract test**

Instantiate `hud.tscn`, configure it with a controller and inventory, and assert:

- `BottomBar/QuickBar` has six `Button` children;
- buttons display `1 锄头` through `6 谷物种子 xN`;
- pressing slot 6 emits index `5`;
- calling `select_slot(5)` changes the HUD selection style and `ToolLabel` to `谷物种子`;
- removing one seed refreshes the sixth button count.

Register the test after `PlayerActionControllerTest`.

- [ ] **Step 2: Run the focused runner and verify the HUD contract fails**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: non-zero exit because the six authored slots are not clickable Buttons and the action-bar API is absent.

- [ ] **Step 3: Convert slots to Buttons and bind all selection paths**

Change `Slot1` through `Slot6` in `hud.tscn` to `Button` nodes with `mouse_default_cursor_shape = 2`.

In `hud.gd`:

```gdscript
signal quick_slot_selected(index: int)

const ACTION_NAMES := ["锄头", "浇水壶", "斧头", "镐", "鱼竿", "谷物种子"]

func configure_action_bar(controller: PlayerActionController, inventory: InventorySystem) -> void:
	action_controller = controller
	inventory_ref = inventory
	for index in range(quick_bar.get_child_count()):
		var button := quick_bar.get_child(index) as Button
		button.pressed.connect(_on_quick_slot_pressed.bind(index))
	action_controller.selection_changed.connect(_on_action_selection_changed)
	action_controller.inventory_changed.connect(refresh_action_bar)
	refresh_action_bar()
	_on_action_selection_changed(action_controller.get_selected_slot(), ACTION_NAMES[action_controller.get_selected_slot()])
```

`_on_quick_slot_pressed()` emits `quick_slot_selected(index)` and calls `action_controller.select_slot(index)`. `refresh_action_bar()` renders every label and applies a selected `StyleBoxFlat` to the active slot.

- [ ] **Step 4: Run focused and UI scene tests**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/test_runtime_ui_scenes.gd
```

Expected: both commands exit `0`.

- [ ] **Step 5: Commit the action bar**

```bash
git add scripts/ui/hud.gd scenes/ui/hud.tscn tests/test_hud_action_bar.gd \
  tests/run_main_gameplay_integration_tests.gd
git commit -m "feat: add clickable farming action bar"
```

---

### Task 5: Wire the verified systems into the real main scene

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/systems/inventory_system.gd`
- Modify: `tests/test_player_grid_binding.gd`
- Create: `tests/test_main_farming_building_integration.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

**Interfaces:**
- Consumes: all interfaces from Tasks 1–4 and the existing system `configure()` methods.
- Produces: `main.action_controller`, registered grain CropData, correct new/load initialization, persisted runtime inventory discovery, and one shared runtime instance of each 1.1–1.4 system.

- [ ] **Step 1: Write the failing real-main integration test**

Instantiate `main.tscn`, wait three frames, then assert:

```gdscript
assertions.truthy(main.action_controller != null, "main exposes player action controller")
assertions.equal(main.action_controller.grid_system, main.grid_system, "controller shares main grid")
assertions.equal(main.action_controller.farming_system, main.farming_system, "controller shares farming system")
assertions.equal(main.action_controller.building_system, main.building_system, "controller shares building system")
assertions.equal(main.action_controller.inventory_system, main.inventory_system, "controller shares inventory")
assertions.truthy(GameData.get_crop("grain") != null, "main registers grain crop")
assertions.equal(GameData.get_crop("grain").stage_scenes.size(), 4, "grain uses four verified stage scenes")
```

For deterministic cell operations, pick a flat `WASTELAND` cell near the player, move the player above it, then execute:

1. select hoe and call `perform_cell_action(cell)`;
2. select grain seed and plant;
3. select watering can and water;
4. call `farming_system.on_day_changed()` until mature;
5. click through `perform_cell_action(cell)` and verify `grain` count increases.

Enter `fence` preview mode on a valid cell, call controller build placement, and assert a `BuildingInstance` starts at `FOUNDATION`.

Register the test last in the focused runner and pass the runner's `SceneTree` to it.

Set `main.load_save_on_start = false` before adding the instantiated scene to the test tree so the contract never reads, deletes, or overwrites the user's real slot-0 save.

- [ ] **Step 2: Run the focused runner and verify main wiring fails**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: non-zero exit because `main.action_controller` is not configured and grain is not registered.

- [ ] **Step 3: Register the verified grain crop before load**

Replace the default placeholder crop registration with an idempotent grain registration:

```gdscript
func _register_grain_crop() -> void:
	if GameData.get_crop("grain") != null:
		return
	var grain := CropData.new()
	grain.crop_id = "grain"
	grain.name = "谷物"
	grain.growth_days = 3
	grain.seasons.assign([0, 1, 2])
	grain.exp_reward = 5
	grain.stage_scenes.assign([
		"res://assets/crops/grain/grain_stage_0_seed.tscn",
		"res://assets/crops/grain/grain_stage_1_sprout.tscn",
		"res://assets/crops/grain/grain_stage_2_growing.tscn",
		"res://assets/crops/grain/grain_stage_3_mature.tscn",
	])
	GameData.register_crop(grain)
```

- [ ] **Step 4: Correct new-game/load ordering and starter resources**

Make `_initial_game_state()`:

```gdscript
func _initial_game_state() -> void:
	_register_grain_crop()
	var loaded := load_save_on_start and save_manager.load_game(0)
	if not loaded:
		_grant_new_game_items()
	else:
		_backfill_legacy_grain_slot()
	farming_system.rebuild_visuals()
	economy_system.generate_daily_orders()
	hud.refresh_action_bar()
```

`_grant_new_game_items()` clears the runtime inventory, adds `grain_seed: 20`, `wood: 250`, `stone: 150`, `iron: 50`, and `glass: 50`, then maps the seed inventory slot to quick mapping index `5`. `_backfill_legacy_grain_slot()` maps an existing grain seed to slot 6 without duplicating items; if an old save has no grain seed, the slot stays empty.

Declare `@export var load_save_on_start := true` on Main. Test and capture scripts set it to `false` before the scene enters the tree; production keeps the default.

- [ ] **Step 5: Make SaveManager discover Main's runtime inventory**

Add `inventory_system` to a group in `InventorySystem._ready()`:

```gdscript
add_to_group("inventory_system")
```

Replace direct `/root/InventorySystem` lookups in SaveManager gather/apply paths with:

```gdscript
func _get_inventory_system() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("inventory_system")
```

Extend the main integration test to call `_gather_save_data()` and assert the saved inventory contains the runtime slots and `quick_mappings[5]`.

- [ ] **Step 6: Inject the controller and remove Main's duplicate build input**

Add:

```gdscript
@onready var action_controller: PlayerActionController = $Actors/Player/ActionController
```

After system configuration:

```gdscript
player.configure(camera_rig, world, tool_system, grid_system)
action_controller.configure(
	player,
	grid_system,
	farming_system,
	building_system,
	tool_system,
	inventory_system
)
hud.configure_action_bar(action_controller, inventory_system)
```

Delete `main.gd`'s `_process()`, `_raycast_to_ground()`, and `_unhandled_input()` build handling so only `PlayerActionController` consumes world clicks.

- [ ] **Step 7: Update the player-grid binding contract**

Change `tests/test_player_grid_binding.gd` to assert the `ActionController` exists and owns Main's grid/farming/building references. Remove calls to the deleted private player raycast/tool methods.

- [ ] **Step 8: Run focused and subsystem suites**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_grid_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_farming_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_building_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/test_player_grid_binding.gd
```

Expected: all five commands exit `0`.

- [ ] **Step 9: Commit main integration**

```bash
git add scripts/main.gd scripts/core/save_manager.gd scripts/systems/inventory_system.gd \
  tests/test_player_grid_binding.gd \
  tests/test_main_farming_building_integration.gd \
  tests/run_main_gameplay_integration_tests.gd
git commit -m "feat: integrate farming and building into main game"
```

---

### Task 6: Real runtime and visual acceptance

**Files:**
- Create: `tests/capture_main_gameplay_integration.gd`
- Modify only when a failing contract identifies a defect: files already listed in Tasks 1–5

**Interfaces:**
- Consumes: real `main.tscn`, controller direct-action API, crop stage scenes, and staged building scenes.
- Produces: `/private/tmp/villa-main-gameplay-integration.png` and a clean runtime verification log.

- [ ] **Step 1: Write the capture script with explicit acceptance contracts**

The capture script must:

1. instantiate `main.tscn` and await rendering/physics initialization;
2. prepare four nearby farm cells showing seed, sprout, growing, and mature grain using the real `FarmingSystem`;
3. place one building at `FOUNDATION` and one at `COMPLETE` using the real `BuildingSystem`;
4. assert all six visuals exist in the real main tree;
5. aim the existing camera so the player, crops, and both buildings are visible;
6. save `/private/tmp/villa-main-gameplay-integration.png`;
7. exit non-zero on any missing visual or runtime error.

Set `load_save_on_start = false` before adding Main to the tree so the capture is deterministic and leaves the user's save untouched.

- [ ] **Step 2: Run parsing and real-scene smoke checks**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --editor --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --quit-after 5 res://scenes/main.tscn
```

Expected: both commands exit `0` with no `SCRIPT ERROR`, parser error, or invalid property access.

- [ ] **Step 3: Run the complete targeted verification matrix**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_grid_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_farming_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_building_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/test_player_grid_binding.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/test_runtime_ui_scenes.gd
```

Expected: every command exits `0`.

- [ ] **Step 4: Capture and inspect the integrated main-game image**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . \
  --script res://tests/capture_main_gameplay_integration.gd
```

Expected: exit `0`, `CAPTURED: /private/tmp/villa-main-gameplay-integration.png`, and a non-empty PNG. Inspect it for terrain contact, crop-stage readability, construction visibility, scale consistency, and camera occlusion.

- [ ] **Step 5: Record the broad-suite baseline without hiding known failures**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/run_tests.gd
```

Expected: record the actual result. Any existing baseline failures unrelated to this integration are reported separately; no new parser or integration failures are acceptable.

- [ ] **Step 6: Commit the visual verifier and any evidence-driven fixes**

```bash
git add tests/capture_main_gameplay_integration.gd \
  scripts/actors/player_action_controller.gd scripts/actors/player.gd \
  scripts/systems/inventory_system.gd scripts/systems/tool_system.gd \
  scripts/core/game_data.gd scripts/main.gd scripts/ui/hud.gd \
  scenes/actors/player.tscn scenes/ui/hud.tscn \
  tests/test_inventory_capacity.gd tests/test_tool_action_transaction.gd \
  tests/test_player_action_controller.gd tests/test_hud_action_bar.gd \
  tests/test_main_farming_building_integration.gd \
  tests/run_main_gameplay_integration_tests.gd tests/test_player_grid_binding.gd
git commit -m "test: verify main farming and building gameplay"
```

---

## Final Acceptance

- [ ] Left-click is consumed by exactly one world-action controller.
- [ ] Slots 1–6 are selectable by mouse and keyboard and visibly reflect selection.
- [ ] Hoe, seed, water, day growth, mature click, harvest output, and experience form one working loop.
- [ ] Building selection, preview, material spend, footprint occupation, and staged construction form one working loop.
- [ ] Invalid actions consume nothing.
- [ ] Existing grid, farming, building, player binding, UI, editor parsing, and main-scene smoke checks pass.
- [ ] The integrated screenshot shows the verified crop and building visuals inside the original main world.
