# Villa Inventory, Tools, and Player Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the combat-player loop with a testable inventory, six-slot tool hotbar, stamina, direct interaction, and minimal inventory/HUD UI.

**Architecture:** Keep items and slots as small data objects; `Inventory` owns stacking and index mappings while the scene-node `InventorySystem` exposes that state to Player and UI. `ToolSystem` performs only tool dispatch against an already-resolved target, while `PlayerController` owns input/raycasts/movement and mutates the single injected `GameState.player_state` stamina authority. Grid and Farming remain external collaborators.

**Tech Stack:** Godot 4.7, GDScript, Jolt Physics, existing `tests/run_tests.gd` RefCounted runner, Godot Control scenes.

## Global Constraints

- Keep Godot at `4.7`, the GL Compatibility renderer, and Jolt Physics; add no test plugin or third-party dependency.
- Keep the authored world bounds (`Rect2(-17.2, -13.2, 34.4, 26.4)`), camera-relative `PlayerController.movement_from_input`, movement actions, jump, terrain layer `1`, player layer `2`, and tree-trunk layer `16` unchanged.
- Inventory capacity is exactly `20`; the hotbar contains exactly `6` reference mappings initialized to `[-1, -1, -1, -1, -1, -1]`; ordinary item stack limit defaults to `99`.
- Player stamina starts at and is capped at `100`; idle grounded recovery is `1.0` per second; sprint multiplier is `1.8`; sprint drain is `5.0` per second; direct tool ray range is `2.5` world units; nearby interaction range is `2.0`.
- Add and use only these input actions: `interact` (right mouse and `E`), `sprint` (`Shift`), `inventory` (`Tab` and `I`), and `tool_1` through `tool_6` (keys `1` through `6`). Preserve existing input actions.
- The plan consumes, without implementing, `GridSystem.get_cell_at_world(world_x: float, world_z: float) -> GridCell`, `GridCell.State.WASTELAND`, `GridCell.State.FARMLAND`, `GridCell.State.PLANTED`, and the Grid/Farming event contracts in `EventBus`.
- The plan consumes the complete `EventBus` declared by Plan 1 at `res://scripts/core/event_bus.gd`; it must not redeclare signals or create competing global state.
- A successful consumable use decrements exactly one unit and clears, rather than removes, an empty slot, preserving all hotbar indices. A failed add/remove/use/tool action leaves inventory and stamina unchanged.
- Do not implement seed planting, crop growth, grid generation, building placement, order/economy, villager AI, save/load, or seasonal logic in this plan.

---

## File structure

| Path | Responsibility |
|---|---|
| `scripts/data/item.gd` | `Item`, `SeedItem`, `CropItem`, `MaterialItem`, and `FoodItem` data/use rules. |
| `scripts/data/inventory_slot.gd` | One stable inventory slot with clear/empty semantics. |
| `scripts/systems/inventory.gd` | Pure slot collection, stack, removal, hotbar mapping, and item-use behavior. |
| `scripts/systems/inventory_system.gd` | Scene-node facade that owns one `Inventory`. |
| `scripts/systems/tool_system.gd` | `Tool` subclasses and validated target dispatch. |
| `scripts/actors/player.gd` | Stamina, sprint, hotbar selection, direct tool targeting, interaction, and retained movement. |
| `scripts/ui/hud.gd`, `scenes/ui/hud.tscn` | Stamina and six-slot HUD interface. |
| `scripts/ui/inventory_ui.gd`, `scenes/ui/inventory_ui.tscn` | Minimal show/refresh/close inventory interface. |
| `scenes/main.tscn`, `scripts/main.gd`, `project.godot` | Wire the scene services, UI, input map, and non-combat player configuration. |
| `tests/test_inventory.gd`, `tests/test_tool_system.gd`, `tests/test_player_logic.gd`, `tests/test_ui_contracts.gd`, `tests/smoke_test.gd`, `tests/run_tests.gd` | Deterministic coverage and runner registration. |

### Task 1: Stable item, slot, and inventory contracts

**Files:**
- Create: `scripts/data/item.gd`
- Create: `scripts/data/inventory_slot.gd`
- Create: `scripts/systems/inventory.gd`
- Create: `scripts/systems/inventory_system.gd`
- Create: `tests/test_inventory.gd`
- Modify: `scripts/core/game_data.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `Item.can_stack_with(other: Item) -> bool`, `Item.on_use(stamina: int, max_stamina: int) -> Dictionary`, and exported `item_id`, `item_name`, `item_type`, `icon_path`, `description`, `max_stack`, `consumable`, `sell_price`.
- Produces: `FoodItem.stamina_restore: int = 30`; `FoodItem.on_use` returns `{ "used": true, "stamina": min(stamina + stamina_restore, max_stamina) }`.
- Produces: `InventorySlot.is_empty() -> bool` and `InventorySlot.clear() -> void`.
- Produces: `Inventory.add_item(item: Item, quantity: int = 1) -> bool`, `remove_item(item_id: String, quantity: int = 1) -> bool`, `has_item(item_id: String, quantity: int = 1) -> bool`, `get_item_count(item_id: String) -> int`, `swap_slots(from_index: int, to_index: int) -> void`, `set_quick_slot(slot_index: int, quick_index: int) -> bool`, `get_quick_item(index: int) -> Item`, and `use_item(slot_index: int, stamina: int, max_stamina: int) -> Dictionary`.
- Produces: `InventorySystem.initialize() -> void` and forwarding methods with the same signatures as `Inventory` plus `inventory: Inventory`.
- Extends GameData with `register_item(item: Item) -> bool` and `get_item(item_id: String) -> Item`; duplicate/empty IDs fail without replacement.
- Consumes existing EventBus signals: `item_added(item: Item)`, `item_removed(item: Item, quantity: int)`, `item_used(item: Item)`, `stamina_changed(value: int)`, `inventory_opened()`, `inventory_closed()`, and `tool_changed(tool: Tool)`.

- [ ] **Step 1: Write the failing inventory tests and register them**

Create `tests/test_inventory.gd` and add its preload/invocation to `tests/run_tests.gd` immediately after `PlayerLogicTest`:

```gdscript
extends RefCounted

const ItemScript = preload("res://scripts/data/item.gd")
const InventoryScript = preload("res://scripts/systems/inventory.gd")

func _item(id: String, stack: int = 99) -> Item:
	var item := ItemScript.new()
	item.item_id = id
	item.max_stack = stack
	return item

func run(assertions) -> void:
	var inventory := InventoryScript.new()
	var wood := _item("wood", 3)
	assertions.truthy(inventory.add_item(wood, 5), "inventory accepts two stacks")
	assertions.equal(inventory.slots.size(), 2, "five wood uses two slots at stack three")
	assertions.equal(inventory.slots[0].quantity, 3, "first stack fills")
	assertions.equal(inventory.slots[1].quantity, 2, "second stack contains remainder")
	assertions.truthy(inventory.set_quick_slot(1, 0), "valid hotbar mapping is accepted")
	assertions.equal(inventory.get_quick_item(0).item_id, "wood", "hotbar references inventory slot")
	assertions.truthy(inventory.remove_item("wood", 5), "remove spanning stacks succeeds")
	assertions.truthy(inventory.slots[0].is_empty(), "first removed stack is cleared")
	assertions.equal(inventory.quick_slot_mappings[0], 1, "mapping index remains stable after clear")
	assertions.equal(inventory.get_quick_item(0), null, "mapped empty slot has no quick item")
	assertions.equal(inventory.remove_item("wood", 1), false, "insufficient removal does not mutate")
```

- [ ] **Step 2: Run the runner and verify RED**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`

Expected: exit `1` with a preload error for `scripts/data/item.gd`.

- [ ] **Step 3: Implement the exact data and container behavior**

Create `item.gd` with `class_name Item extends Resource`, `enum ItemType { TOOL, SEED, CROP, MATERIAL, COLLECTIBLE, FOOD, FISH }`, the exported fields in this task’s interface, `can_stack_with` comparing only nonempty equal `item_id`s, and base `on_use` returning `{ "used": false, "stamina": stamina }`. Define the four documented subclasses in the same file; `FoodItem.on_use` must be:

```gdscript
func on_use(stamina: int, max_stamina: int) -> Dictionary:
	return {"used": true, "stamina": mini(stamina + stamina_restore, max_stamina)}
```

Create `InventorySlot` as `RefCounted` with nullable `item`, `quantity = 0`, `is_empty` (`item == null or quantity <= 0`), and `clear` setting both fields to empty values. Create `Inventory` as `RefCounted` with `max_slots = 20`, an empty `Array[InventorySlot]`, and exactly six `-1` quick mappings. It must first fill compatible nonfull slots, then append or reuse the first empty slot, and must reject an add whose complete quantity will not fit; calculate capacity before mutation. `remove_item` must first call `has_item`, then drain slots in index order and call `clear` at zero. Validate all indices before swapping/mapping and return `false` for invalid mapping indices. `use_item` must reject invalid/empty slots, call `item.on_use`, decrement only when `used` and `consumable` are both true, clear at zero, and return that dictionary.

Create `InventorySystem extends Node` containing `var inventory := Inventory.new()` and forwarding each method. `initialize` resets `inventory = Inventory.new()`. Extend GameData with a private item dictionary plus the two published item methods, and register authored item Resources during setup. Emit the existing item signals only after the corresponding successful facade operation; do not modify EventBus declarations.

- [ ] **Step 4: Run the focused and complete tests and verify GREEN**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
```

Expected: exit `0`; the inventory test’s ten checks pass and editor import reports no class-name or parse error.

- [ ] **Step 5: Commit the isolated inventory foundation**

```bash
git add scripts/data/item.gd scripts/data/inventory_slot.gd scripts/systems/inventory.gd scripts/systems/inventory_system.gd scripts/core/game_data.gd tests/test_inventory.gd tests/run_tests.gd
git commit -m "feat: add stable inventory and item contracts"
```

### Task 2: Tool dispatch against published Grid and tree interfaces

**Files:**
- Create: `scripts/systems/tool_system.gd`
- Create: `tests/test_tool_system.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `GridCell.state`, `GridCell.watered`, `GridCell.State.WASTELAND`, `GridCell.State.FARMLAND`, `GridCell.State.PLANTED`, and `TreeInstance.take_damage(level: int) -> void`.
- Produces: `Tool extends Item`, `HoeTool`, `WateringCanTool`, `AxeTool`, and `ToolSystem.try_use(tool: Tool, target: Variant, stamina: int) -> Dictionary`.
- Produces: each result dictionary as `{ "used": bool, "stamina": int }`; a successful action returns `stamina - tool.stamina_cost`, all failures return the input stamina.

- [ ] **Step 1: Write the failing tool behavior tests**

Create `tests/test_tool_system.gd`, register it in `run_tests.gd`, and use small duck-typed test targets:

```gdscript
extends RefCounted

const ToolSystemScript = preload("res://scripts/systems/tool_system.gd")

class TestCell:
	var state := 0
	var watered := false

class TestTree:
	var damage := 0
	func take_damage(level: int) -> void:
		damage += level

func run(assertions) -> void:
	var tools := ToolSystemScript.new()
	var hoe := ToolSystemScript.HoeTool.new()
	hoe.stamina_cost = 5
	var cell := TestCell.new()
	cell.state = tools.WASTELAND_STATE
	var cultivated := tools.try_use(hoe, cell, 10)
	assertions.truthy(cultivated.used, "hoe accepts wasteland")
	assertions.equal(cultivated.stamina, 5, "hoe spends configured stamina")
	assertions.equal(cell.state, tools.FARMLAND_STATE, "hoe changes only published cell state")
	var axe := ToolSystemScript.AxeTool.new()
	axe.level = 2
	var tree := TestTree.new()
	assertions.equal(tools.try_use(axe, tree, 3).used, false, "insufficient stamina rejects tool")
	assertions.equal(tree.damage, 0, "rejected tool has no target effect")
```

- [ ] **Step 2: Run the runner and verify RED**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`

Expected: exit `1` because `tool_system.gd` is absent.

- [ ] **Step 3: Implement tool data and a single dispatch point**

Create `ToolSystem extends Node`. Define `Tool extends Item` with `enum ToolType { HOE, WATERING_CAN, AXE, PICKAXE, LANTERN, GLIDER, ROPE, COMPASS, DIVING_MASK, FISHING_ROD }`, exported `tool_type`, `stamina_cost = 5`, `range = 2.0`, and `level = 1`. Put `HoeTool`, `WateringCanTool`, and `AxeTool` inside this script as named subclasses. Expose integer constants `WASTELAND_STATE`, `FARMLAND_STATE`, and `PLANTED_STATE` initialized from `GridCell.State` so tests and production use the same published state values.

Implement `try_use` exactly in this order: reject null tools or `stamina < tool.stamina_cost`; ask the concrete tool to apply its effect; return unchanged stamina when application returns false; return reduced stamina only after a true application. Hoe accepts a target with `state == WASTELAND_STATE` and sets it to `FARMLAND_STATE`; watering accepts `state == PLANTED_STATE` and sets `watered = true`; axe accepts a target with `take_damage` and calls `take_damage(tool.level)`. Each tool must reject all other targets. Do not add seed, crop, or grid logic.

- [ ] **Step 4: Run the tests and verify GREEN**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`

Expected: exit `0`, and invalid target/insufficient-stamina cases leave target and stamina unchanged.

- [ ] **Step 5: Commit the tool boundary**

```bash
git add scripts/systems/tool_system.gd tests/test_tool_system.gd tests/run_tests.gd
git commit -m "feat: add stamina-aware tool dispatch"
```

### Task 3: Convert PlayerController from firing to stamina, hotbar, and interaction

**Files:**
- Modify: `scripts/actors/player.gd`
- Modify: `tests/test_player_logic.gd`
- Modify: `project.godot`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `InventorySystem.get_quick_item(index: int) -> Item`, `ToolSystem.try_use(tool: Tool, target: Variant, stamina: int) -> Dictionary`, `GridSystem.get_cell_at_world(world_x: float, world_z: float) -> GridCell`, injected `PlayerState`, and target `interact(player: PlayerController) -> void`.
- Produces: `PlayerController.configure(new_camera_rig: Node, new_world: Node, new_inventory_system: InventorySystem, new_tool_system: ToolSystem, new_grid_system: Node, new_player_state: PlayerState) -> void`.
- Produces: `PlayerController.select_tool(index: int) -> void`, `apply_stamina_step(delta: float, sprinting: bool, grounded: bool) -> int`, `use_current_tool() -> void`, and `interact_nearest() -> void`.

- [ ] **Step 1: Replace combat assertions with failing player-loop assertions**

Replace `tests/test_player_logic.gd` with the retained movement checks plus:

```gdscript
var player = PlayerScript.new()
player.player_state = PlayerStateScript.new()
player.player_state.stamina = 10
assertions.equal(player.apply_stamina_step(1.0, true, true), 5, "sprint drains five stamina per second")
assertions.equal(player.apply_stamina_step(2.0, false, true), 7, "grounded idle recovers one stamina per second")
player.player_state.stamina = 1
assertions.equal(player.apply_stamina_step(1.0, true, true), 0, "sprint clamps stamina at zero")
assertions.equal(player.is_sprinting, false, "depletion cancels sprint")
player.free()
```

Remove the old `take_damage` expectation and remove `ProjectileLogicTest` from the runner only after its test file is deleted by the separate combat-removal work; leave its current runner registration unchanged in this task.

- [ ] **Step 2: Run the focused suite and verify RED**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`

Expected: exit `1` because `apply_stamina_step` does not exist.

- [ ] **Step 3: Implement the non-combat player contract and input map**

Remove `fire_requested`, `health_changed`, `CombatMathScript`, health/cooldown fields, `take_damage`, and `_request_fire` from `player.gd`. Keep gravity, jump, movement, facing interpolation, `move_and_slide`, and `_clamp_to_world`. Add `player_state: PlayerState`, `is_sprinting`, `current_tool`, `tool_index`, the constants from Global Constraints, and nullable references set by `configure(camera_rig, world, inventory_system, tool_system, grid_system, player_state)`.

`apply_stamina_step` calculates the next value from `player_state.stamina`, calls `player_state.set_stamina(next)`, sets `is_sprinting = false` and emits `stamina_depleted` at zero, and returns the authoritative value. PlayerController must not declare duplicate stamina/max_stamina fields. `_unhandled_input` must call `Input.is_action_pressed("sprint")`, `Input.is_action_just_pressed("interact")`, `Input.is_action_just_pressed("inventory")`, `Input.is_action_just_pressed("tool_1")` through `tool_6`, and left mouse tool use. `select_tool` must set `tool_index`, cast the mapped item to `Tool`, and emit `tool_changed`.

Raycast from the active camera through the mouse to `INTERACT_RANGE`, exclude `get_rid()`, and request mask `1 | 16 | 64`; if the collider exposes `get_grid_cell`, use that result, otherwise resolve a hit position through the injected GridSystem. `interact_nearest` must scan group `interactable`, select the closest member no farther than `2.0`, and call its `interact(self)` only when that method exists. Add the four named input actions to `project.godot` using the key/mouse bindings in Global Constraints.

- [ ] **Step 4: Run unit and import checks and verify GREEN**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
```

Expected: exit `0`; player logic no longer references a combat class or a projectile scene.

- [ ] **Step 5: Commit the player-loop conversion**

```bash
git add scripts/actors/player.gd tests/test_player_logic.gd project.godot
git commit -m "feat: add player stamina and tool interaction"
```

### Task 4: Provide minimal HUD and inventory UI interfaces

**Files:**
- Modify: `scripts/ui/hud.gd`
- Modify: `scenes/ui/hud.tscn`
- Create: `scripts/ui/inventory_ui.gd`
- Create: `scenes/ui/inventory_ui.tscn`
- Create: `tests/test_ui_contracts.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `EventBus.stamina_changed`, `EventBus.tool_changed`, `EventBus.inventory_opened`, `EventBus.inventory_closed`, and `InventorySystem.get_quick_item(index: int) -> Item`.
- Produces: `VillaHud.set_stamina(value: int, max_value: int) -> void`, `VillaHud.set_quick_slot(index: int, item: Item, selected: bool) -> void`, `InventoryUI.bind(inventory_system: InventorySystem) -> void`, `InventoryUI.open() -> void`, `InventoryUI.close() -> void`, and `InventoryUI.refresh() -> void`.

- [ ] **Step 1: Write failing scene contract tests**

Create `tests/test_ui_contracts.gd`, register it in the runner, and assert the minimum public scene shape:

```gdscript
extends RefCounted

const HudScene = preload("res://scenes/ui/hud.tscn")
const InventoryScene = preload("res://scenes/ui/inventory_ui.tscn")

func run(assertions) -> void:
	var hud = HudScene.instantiate()
	assertions.truthy(hud.has_node("TopBar/StaminaBar"), "HUD exposes stamina bar")
	assertions.equal(hud.get_node("BottomBar/QuickBar").get_child_count(), 6, "HUD exposes six quick slots")
	var inventory_ui = InventoryScene.instantiate()
	assertions.equal(inventory_ui.visible, false, "inventory starts hidden")
	assertions.truthy(inventory_ui.has_node("Panel/Grid"), "inventory exposes item grid")
	hud.free()
	inventory_ui.free()
```

- [ ] **Step 2: Run the runner and verify RED**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`

Expected: exit `1` because the new nodes and inventory scene do not exist.

- [ ] **Step 3: Build the two minimal UI contracts**

Replace the combat labels in `hud.tscn` with a `TopBar/StaminaBar` `TextureProgressBar` (`min_value = 0`, `max_value = 100`, `value = 100`) and `BottomBar/QuickBar` `HBoxContainer` containing exactly six `TextureRect` children named `QuickSlot_0` through `QuickSlot_5`, each with a child `Label` showing `1` through `6`. Make `VillaHud._ready` subscribe to stamina and tool events. `set_stamina` sets both maximum and current value; it uses red `Color(1.0, 0.2, 0.2, 1.0)` below `30`, otherwise green `Color(0.2, 0.8, 0.2, 1.0)`. `set_quick_slot` loads `item.icon_path` only when nonempty, clears the texture for null, and colors the selected slot white and the rest `Color(1, 1, 1, 0.65)`.

Create `InventoryUI extends Control`, default hidden, with `Panel/Grid` as a five-column `GridContainer` containing exactly twenty `TextureRect` children with `ItemIcon` and `QuantityLabel` descendants. `bind` stores its inventory facade. `open` sets `visible = true`, calls `refresh`, and selects visible mouse mode. `close` hides it and emits `inventory_closed`; `refresh` clears all twenty cells, then fills each nonempty indexed slot’s icon and quantity. In `_ready`, subscribe `inventory_opened` to `open` and `inventory_closed` to a private hide-only handler so `close` cannot recursively emit its own signal. Escape calls `close`.

- [ ] **Step 4: Run UI, runner, and import checks and verify GREEN**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
```

Expected: exit `0`; both scenes instantiate headlessly and expose exactly the tested node paths.

- [ ] **Step 5: Commit the UI boundary**

```bash
git add scripts/ui/hud.gd scenes/ui/hud.tscn scripts/ui/inventory_ui.gd scenes/ui/inventory_ui.tscn tests/test_ui_contracts.gd tests/run_tests.gd
git commit -m "feat: add inventory and hotbar UI"
```

### Task 5: Wire scene services and perform acceptance verification

**Files:**
- Modify: `scenes/main.tscn`
- Modify: `scripts/main.gd`
- Modify: `tests/smoke_test.gd`

**Interfaces:**
- Consumes: `PlayerController.configure(camera_rig, world, inventory_system, tool_system, grid_system, player_state)`, `GameState.player_state`, `InventorySystem.initialize()`, `InventoryUI.bind(inventory_system)`, and `VillaHud.set_stamina(value, max_value)`.
- Produces: `Main/Systems/InventorySystem`, `Main/Systems/ToolSystem`, `Main/UI/InventoryUI`, and HUD initialization with player stamina.

- [ ] **Step 1: Add failing scene-wiring assertions**

Extend `tests/smoke_test.gd` after the existing HUD assertion:

```gdscript
assertions.truthy(main.has_node("Systems/InventorySystem"), "main contains inventory system")
assertions.truthy(main.has_node("Systems/ToolSystem"), "main contains tool system")
assertions.truthy(main.has_node("UI/InventoryUI"), "main contains inventory UI")
```

- [ ] **Step 2: Run the runner and verify RED**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`

Expected: exit `1` because the Systems and UI nodes are missing.

- [ ] **Step 3: Add exact main-scene dependencies and inject the Plan 2 GridSystem**

In `scenes/main.tscn`, reuse the `Systems` parent and `Systems/GridSystem` created by Plan 2, add `InventorySystem` and `ToolSystem` script nodes, and add a `UI` CanvasLayer with the existing HUD and `InventoryUI` instances beneath it. Preserve World, Actors, CameraRig, and current NPC nodes. In `main.gd`, remove player fire/health signal connections and per-frame projectile HUD update; retain terrain placement and camera target setup. Add onready references for GridSystem, the two new systems, and inventory UI; call `inventory_system.initialize()`, bind the UI, call `player.configure(camera_rig, world, inventory_system, tool_system, grid_system, GameState.player_state)`, and call `hud.set_stamina(GameState.player_state.stamina, GameState.player_state.max_stamina)`. Do not recreate or reinitialize GridSystem here.

- [ ] **Step 4: Verify the complete slice**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 10
```

Expected: all tests/imports exit `0`; the main scene starts without projectile firing, missing-node, or missing-resource errors. In the desktop editor, verify Shift drains/restores stamina, keys 1–6 update the selected hotbar frame, Tab/I opens the inventory and Escape closes it, and left-click only invokes an equipped tool’s direct target flow.

- [ ] **Step 5: Commit the vertical slice**

```bash
git add scenes/main.tscn scripts/main.gd tests/smoke_test.gd
git commit -m "feat: wire inventory tools into player scene"
```

### Task 6: Final verification

**Files:**
- Verify only; no source changes.

**Interfaces:**
- Consumes the completed inventory, tool, player, and UI contracts.
- Produces a verified implementation branch.

- [ ] **Step 1: Re-run automated verification**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
```

Expected: both commands exit `0` with no assertion, parse, or import failure.

- [ ] **Step 2: Confirm commits and working tree**

Run: `git status --short && git log -6 --oneline`

Expected: only intentional implementation commits appear; no generated `.godot` or imported artifact is staged.
