# Building Output Pickup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the inert production-complete “收” glyph with hand-painted, per-item output piles around every producing building, and make each pile collect only its represented item into the player inventory.

**Architecture:** Keep `ProducerState.outputs` and `ProductionSystem.collect_outputs()` authoritative. Add an isolated `BuildingOutputPile` interaction node and a `BuildingOutputDisplay` projection component owned by `BuildingInstance`; `Main` routes pile requests to the production transaction, while `PlayerActionController` only owns raycast hover and distance feedback.

**Tech Stack:** Godot 4.7.1, typed GDScript, Sprite3D/AtlasTexture/Area3D, transparent SVG sprite atlases, project-local headless test runners, Git.

**Design reference:** `docs/superpowers/specs/2026-08-08-building-output-pickup-design.md`

---

## File map

- `scripts/buildings/building_output_pile.gd` — one item pile, atlas family mapping, density frame, hover tooltip, click request, and success/failure animation.
- `scripts/buildings/building_output_display.gd` — deterministic one-to-seven-pile projection and perimeter layout.
- `scripts/buildings/building_instance.gd` — owns the display, proxies collection requests, and removes the collect glyph state.
- `scripts/systems/production_system.gd` — synchronizes authoritative outputs into the display and retains only full/maintenance indicators.
- `scripts/main.gd` — routes pile requests through `collect_outputs()` and reports transaction failure.
- `scripts/actors/player_action_controller.gd` — generic pile hover tracking and explicit out-of-range feedback.
- `assets/items/output_piles/*.svg` — ten three-frame hand-painted-style pile atlases.
- `tests/test_building_output_pile.gd` — pile family, density, hover, collision, and interaction tests.
- `tests/test_building_output_display.gd` — projection, layout, lifecycle, and idempotence tests.
- Existing building, production, player-action, main-integration, and art tests — end-to-end coverage.

## Task 1: Add the isolated output-pile interaction node

**Files:**
- Create: `scripts/buildings/building_output_pile.gd`
- Create: `tests/test_building_output_pile.gd`
- Modify: `tests/run_building_system_tests.gd`

- [x] **Step 1: Write the failing component tests**

Create a test that exercises the complete public contract:

```gdscript
var pile := BuildingOutputPile.new()
tree.root.add_child(pile)
assertions.truthy(pile.configure("stone_brick", 1, 9), "known output configures")
assertions.equal(pile.item_id, "stone_brick", "pile exposes represented item")
assertions.equal(pile.density_frame(), 0, "one ninth uses sparse frame")
pile.update_quantity(4, 9)
assertions.equal(pile.density_frame(), 1, "four ninths uses medium frame")
pile.update_quantity(9, 9)
assertions.equal(pile.density_frame(), 2, "full storage uses dense frame")
pile.set_pointer_hovered(true)
assertions.equal(pile.tooltip_text(), "石砖 ×9", "hover tooltip has exact quantity")
assertions.equal(pile.collision_layer, 128, "pile uses existing interaction mask")
var requests: Array[String] = []
pile.collection_requested.connect(func(id: String) -> void: requests.append(id))
pile.interact(null)
assertions.equal(requests, ["stone_brick"], "click requests represented item")
pile.set_interaction_enabled(false)
pile.interact(null)
assertions.equal(requests.size(), 1, "disabled pile emits no request")
assertions.equal(BuildingOutputPile.visual_family("charcoal"), "ore", "charcoal maps explicitly")
assertions.equal(BuildingOutputPile.visual_family("unknown_item"), "crate", "unknown uses crate fallback")
pile.queue_free()
```

Register `BuildingOutputPileTest.new().run(assertions, self)` in `tests/run_building_system_tests.gd`.

- [x] **Step 2: Run the building suite and verify RED**

```powershell
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: parser/preload failure because `BuildingOutputPile` does not exist.

- [x] **Step 3: Implement the minimal pile node**

Create `class_name BuildingOutputPile extends Area3D` with `collection_requested(item_id)`, interaction layer 128, item/quantity state, and explicit current-output mapping:

```gdscript
const FAMILY_BY_ITEM := {
	"wood": "wood", "plank": "wood", "furniture": "crate", "wooden_crate": "crate",
	"stone": "stone", "stone_brick": "stone", "brick": "stone",
	"coal": "ore", "charcoal": "ore", "copper_ore": "ore", "iron_ore": "ore",
	"silver_ore": "ore", "gold_ore": "ore", "crystal": "ore",
	"copper_ingot": "metal", "iron_ingot": "metal", "steel": "metal",
	"machine_parts": "metal", "farm_tools": "metal", "lamp": "metal",
	"flour": "sack", "animal_feed": "sack",
	"glass": "bottle", "glass_jar": "bottle", "glass_bottle": "bottle",
	"sunflower_oil": "bottle", "fruit_jam": "bottle", "pickles": "bottle",
	"tomato_sauce": "bottle", "fruit_juice": "bottle", "perfume": "bottle",
	"cloth": "textile", "rope": "textile", "sachet": "textile",
	"bread": "food", "honey_cake": "food", "bouquet": "food",
	"honey": "small", "beeswax": "small", "egg": "small", "feather": "small",
	"candle": "small", "jewelry": "small",
}

const TINT_BY_ITEM := {
	"charcoal": Color("403832"),
	"stone_brick": Color("c7c1b3"),
	"brick": Color("b96346"),
}

func density_frame() -> int:
	if quantity_capacity > 0:
		var ratio := float(quantity) / float(quantity_capacity)
		return 0 if ratio <= 1.0 / 3.0 else (1 if ratio <= 2.0 / 3.0 else 2)
	return 0 if quantity <= 1 else (1 if quantity <= 3 else 2)

func interact(_player: Node) -> void:
	if _interaction_enabled and quantity > 0:
		collection_requested.emit(item_id)
```

`configure()` creates the main Sprite3D, enlarged tinted outline Sprite3D, Label3D, and CollisionShape3D. It loads the family atlas, crops the density frame with `AtlasTexture`, uses Billboard, applies `TINT_BY_ITEM` (default white), and resolves the localized item name from `GameData`. `play_failure()`, `show_interaction_rejected()`, and `play_collected()` change only local visuals.

- [x] **Step 4: Run the building suite and verify GREEN**

Expected: PASS with the new pile contract.

- [x] **Step 5: Commit**

```powershell
git add scripts/buildings/building_output_pile.gd tests/test_building_output_pile.gd tests/run_building_system_tests.gd
git commit -m "feat: add interactive building output pile"
```

## Task 2: Add deterministic output projection and perimeter layout

**Files:**
- Create: `scripts/buildings/building_output_display.gd`
- Create: `tests/test_building_output_display.gd`
- Modify: `tests/run_building_system_tests.gd`

- [x] **Step 1: Write failing display tests**

```gdscript
var display := BuildingOutputDisplay.new()
tree.root.add_child(display)
display.configure(Vector2i(3, 3))
display.sync_outputs({
	"wood": 1, "stone": 2, "coal": 3, "iron_ore": 4,
	"copper_ore": 5, "gold_ore": 6, "crystal": 7,
}, 9, true)
assertions.equal(display.get_pile_count(), 7, "all upgraded mine outputs remain clickable")
assertions.equal(display.get_item_ids(), [
	"coal", "copper_ore", "crystal", "gold_ore", "iron_ore", "stone", "wood",
], "pile assignment is stable by item id")
assertions.truthy(display.positions_are_unique(), "every pile owns a unique anchor")
display.sync_outputs({"stone": 2}, 9, true)
assertions.equal(display.get_item_ids(), ["stone"], "stale piles are removed")
display.sync_outputs({"stone": 2}, 9, true)
assertions.equal(display.get_pile_count(), 1, "repeat synchronization is idempotent")
display.sync_outputs({"stone": 2}, 9, false)
assertions.truthy(not display.has_enabled_collisions(), "inactive display disables interaction")
```

- [x] **Step 2: Run and verify RED**

Run the building suite. Expected: preload failure because `BuildingOutputDisplay` is absent.

- [x] **Step 3: Implement the display**

Create `class_name BuildingOutputDisplay extends Node3D`. Sort positive-count item IDs, reconcile a dictionary of pile nodes, and assign the seven spec anchors:

```gdscript
func sync_outputs(outputs: Dictionary, quantity_capacity: int, enabled: bool) -> void:
	var ids: Array[String] = []
	for value in outputs.keys():
		if int(outputs[value]) > 0:
			ids.append(str(value))
	ids.sort()
	for existing_id in _piles.keys():
		if str(existing_id) not in ids:
			_remove_pile(str(existing_id))
	var positions := layout_positions(ids.size(), _footprint)
	for index in ids.size():
		var id := ids[index]
		var pile := _pile_for(id)
		pile.update_quantity(int(outputs[id]), quantity_capacity)
		pile.position = positions[index]
		pile.scale = Vector3.ONE * (0.75 if ids.size() > 4 and index >= 4 else 1.0)
		pile.set_interaction_enabled(enabled)
	visible = enabled and not ids.is_empty()
```

`layout_positions()` derives offsets from footprint half-extents; `_pile_for()` creates once and proxies `collection_requested`; `_remove_pile()` plays the 0.2-second fade before freeing.

- [x] **Step 4: Run and verify GREEN**

Expected: PASS with one-to-seven layout, stable order, removal, and idempotence.

- [x] **Step 5: Commit**

```powershell
git add scripts/buildings/building_output_display.gd tests/test_building_output_display.gd tests/run_building_system_tests.gd
git commit -m "feat: project building outputs around footprints"
```

## Task 3: Integrate the display into BuildingInstance and remove “收”

**Files:**
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `tests/test_building_instance.gd`
- Modify: `tests/test_building_construction_state.gd`

- [x] **Step 1: Replace collect-glyph tests with output-display tests**

```gdscript
assertions.truthy(instance.has_node("BuildingOutputDisplay"), "building owns output display")
instance.call("set_economy_indicator", "collect")
assertions.equal(instance.call("get_economy_indicator"), "", "collect glyph state is rejected")
assertions.truthy(not instance.get_node("EconomyIndicator").visible, "collect glyph never renders")
instance.producer_state.outputs = {"plank": 2}
instance.call("sync_output_display", instance.producer_state.outputs, 9)
assertions.equal(instance.call("get_output_pile_count"), 1, "stored output creates one pile")
```

Add preview, construction, visibility, and `deactivate()` assertions that disable display collisions without changing `producer_state.outputs`.

- [x] **Step 2: Run and verify RED**

Run the building suite. Expected: FAIL because the display bridge is absent and collect is still accepted.

- [x] **Step 3: Integrate the component**

Preload/create `BuildingOutputDisplay` in `_ensure_nodes()` and add:

```gdscript
signal output_collection_requested(building: BuildingInstance, item_id: String)

func sync_output_display(outputs: Dictionary, quantity_capacity: int) -> void:
	var display := get_node_or_null("BuildingOutputDisplay") as BuildingOutputDisplay
	if display != null:
		display.sync_outputs(outputs, quantity_capacity, _output_display_enabled())

func _output_display_enabled() -> bool:
	return not _preview_mode and is_construction_complete() and visible and is_in_group("building_instance")

func _on_output_collection_requested(item_id: String) -> void:
	output_collection_requested.emit(self, item_id)

func request_output_collection(item_id: String) -> void:
	_on_output_collection_requested(item_id)

func get_output_pile_count() -> int:
	return (get_node("BuildingOutputDisplay") as BuildingOutputDisplay).get_pile_count()

func get_output_pile_item_ids() -> Array[String]:
	return (get_node("BuildingOutputDisplay") as BuildingOutputDisplay).get_item_ids()

func show_output_collection_failure(item_id: String, reason: String) -> void:
	(get_node("BuildingOutputDisplay") as BuildingOutputDisplay).show_collection_failure(item_id, reason)
```

Change `set_economy_indicator()` to accept only `full` and `maintenance`; remove collect text/color entries. Resynchronize after configure, preview changes, construction transitions, restore, and visibility changes; clear interactions in `deactivate()`.

- [x] **Step 4: Run and verify GREEN**

Expected: PASS and no test expects a “收” glyph.

- [x] **Step 5: Commit**

```powershell
git add scripts/buildings/building_instance.gd tests/test_building_instance.gd tests/test_building_construction_state.gd
git commit -m "feat: attach output piles to completed buildings"
```

## Task 4: Synchronize authoritative production outputs

**Files:**
- Modify: `scripts/systems/production_system.gd`
- Modify: `tests/test_production_system.gd`

- [x] **Step 1: Write failing synchronization tests**

Replace the existing collect-indicator assertion after workbench completion:

```gdscript
assertions.equal(workbench.get_economy_indicator(), "", "stored output uses no collect glyph")
assertions.equal(workbench.get_output_pile_count(), 1, "stored output projects one pile")
assertions.equal(workbench.get_output_pile_item_ids(), ["plank"], "pile represents output")
```

Also assert that `full` and `maintenance` remain, a requested-item collection removes only that pile, a failed capacity preflight leaves every pile unchanged, and `register_building()` reconstructs piles from restored output.

- [x] **Step 2: Run production tests and verify RED**

```powershell
godot_console --headless --path . --script res://tests/run_economy_system_tests.gd
```

Expected: FAIL because `refresh_indicator()` still emits collect and does not synchronize piles.

- [x] **Step 3: Synchronize state inside refresh_indicator()**

```gdscript
func refresh_indicator(building: BuildingInstance) -> String:
	if building == null or not is_instance_valid(building):
		return ""
	var kind := ""
	var state := _get_state(building)
	if _building_is_active(building):
		if is_maintenance_overdue(building):
			kind = "maintenance"
		elif state != null and _is_output_full(building, state):
			kind = "full"
	if building.has_method("sync_output_display"):
		building.call(
			"sync_output_display",
			state.outputs if state != null else {},
			_storage_quantity_capacity(building)
		)
	if building.has_method("set_economy_indicator"):
		building.call("set_economy_indicator", kind)
	return kind
```

Keep completion, passive daily output, collection, registration, restore, upgrade, and unregistration routed through `refresh_indicator()`. Do not make the visual component subscribe directly to EventBus.

- [x] **Step 4: Run production and building suites and verify GREEN**

```powershell
godot_console --headless --path . --script res://tests/run_economy_system_tests.gd
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: both PASS; existing atomic transaction behavior remains green.

- [x] **Step 5: Commit**

```powershell
git add scripts/systems/production_system.gd tests/test_production_system.gd
git commit -m "feat: synchronize production outputs into world piles"
```

## Task 5: Route pile clicks through Main into the existing transaction

**Files:**
- Modify: `scripts/main.gd`
- Modify: `tests/test_main_farming_building_integration.gd`

- [x] **Step 1: Write the failing real-game collection test**

In the instantiated-main integration, place/complete a stone kiln and seed two outputs:

```gdscript
kiln.producer_state.outputs = {"charcoal": 2, "stone_brick": 3}
main.production_system.refresh_indicator(kiln)
var charcoal_before := main.inventory_system.get_item_count("charcoal")
kiln.request_output_collection("charcoal")
assertions.equal(main.inventory_system.get_item_count("charcoal"), charcoal_before + 2, "pile request reaches player assets")
assertions.equal(kiln.producer_state.outputs, {"stone_brick": 3}, "request removes only represented item")
assertions.equal(kiln.get_output_pile_item_ids(), ["stone_brick"], "other pile remains")
```

Fill the inventory and assert a rejected request leaves source and destination unchanged and displays “资产库空间不足” through the HUD feedback label.

- [x] **Step 2: Run main integration and verify RED**

```powershell
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: FAIL because the output request signal is not connected to Main.

- [x] **Step 3: Add lifecycle-safe request routing**

Connect/disconnect `output_collection_requested` beside the existing `interacted` signal in `_on_building_instance_placed()` and `_on_economy_building_removed()`. Add:

```gdscript
func _on_building_output_collection_requested(building: BuildingInstance, item_id: String) -> void:
	if building == null or not is_instance_valid(building) or production_system == null:
		return
	var result := production_system.collect_outputs(building, inventory_system, item_id)
	if bool(result.get("ok", false)):
		return
	building.show_output_collection_failure(item_id, str(result.get("reason", "transaction_failed")))
	if hud != null and hud.has_method("show_build_feedback"):
		var message := "资产库空间不足" if str(result.get("reason", "")) == "inventory_capacity" else "无法收取制品"
		hud.call("show_build_feedback", message, result)
```

Connect all restored/existing buildings during initial setup, not only future placements.

- [x] **Step 4: Run main and production suites and verify GREEN**

Expected: both PASS; a pile click collects exactly one item kind and rejected transactions preserve it.

- [x] **Step 5: Commit**

```powershell
git add scripts/main.gd tests/test_main_farming_building_integration.gd
git commit -m "feat: collect building output piles into inventory"
```

## Task 6: Add hover and explicit distance feedback without breaking tools

**Files:**
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `tests/test_player_action_controller.gd`

- [x] **Step 1: Write failing input-priority tests**

Add a pile double with `interact()`, `set_pointer_hovered()`, and `show_interaction_rejected()`, then assert:

```gdscript
controller.switch_mode(PlayerActionController.ActionMode.FARMING)
controller.call("_update_output_hover", pile)
assertions.truthy(pile.hovered, "normal pointer hover highlights output pile")
controller.call("_update_output_hover", null)
assertions.truthy(not pile.hovered, "moving away clears pile hover")
controller.player_ref.global_position = Vector3.ZERO
assertions.truthy(not controller.call("_try_interaction_hit", pile, Vector3(20, 0, 0)), "distant pile does not collect")
assertions.equal(pile.rejected_reason, "too_far", "distant pile reports explicit rejection")
controller.switch_mode(PlayerActionController.ActionMode.BUILDING)
assertions.truthy(not controller.perform_target_interaction(pile), "build placement retains click priority")
```

Retain the existing axe/pickaxe hover assertions to prove output hover does not create cell shadows or alter gathering eligibility circles.

- [x] **Step 2: Run player-action tests and verify RED**

```powershell
godot_console --headless --path . --script res://tests/run_player_action_controller_tests.gd
```

Expected: FAIL because output hover and explicit range rejection do not exist.

- [x] **Step 3: Add narrowly scoped pile hover routing**

Track `_hovered_output_pile`. During normal `_process()`, reuse the existing interaction raycast:

```gdscript
func _update_output_hover(target: Node) -> void:
	var next := target if target != null and target.is_in_group("building_output_pile") else null
	if next == _hovered_output_pile:
		return
	if _hovered_output_pile != null and is_instance_valid(_hovered_output_pile):
		_hovered_output_pile.call("set_pointer_hovered", false)
	_hovered_output_pile = next
	if _hovered_output_pile != null:
		_hovered_output_pile.call("set_pointer_hovered", true)
```

If `_perform_pointer_action()` hits a pile outside `interaction_range`, call `show_interaction_rejected("too_far")`, emit `build_feedback_requested` with message “距离太远”, and consume the click. Preserve active build placement precedence and existing gathering target logic.

- [x] **Step 4: Run player-action and gathering suites and verify GREEN**

```powershell
godot_console --headless --path . --script res://tests/run_player_action_controller_tests.gd
godot_console --headless --path . --script res://tests/run_resource_gathering_tests.gd
```

Expected: both PASS, including unchanged axe/pickaxe targeting behavior.

- [x] **Step 5: Commit**

```powershell
git add scripts/actors/player_action_controller.gd tests/test_player_action_controller.gd
git commit -m "feat: add output pile hover and range feedback"
```

## Task 7: Author the hand-painted atlases and verify the complete feature

**Files:**
- Create: `assets/items/output_piles/{wood,stone,ore,metal,sack,bottle,textile,food,crate,small}.svg`
- Modify: `tests/test_building_art_assets.gd`
- Modify: `tests/test_main_farming_building_integration.gd`
- Modify: `docs/superpowers/plans/2026-08-08-building-output-pickup.md`

- [x] **Step 1: Add the failing asset contract**

```gdscript
const OUTPUT_PILE_FAMILIES := [
	"wood", "stone", "ore", "metal", "sack",
	"bottle", "textile", "food", "crate", "small",
]
for family in OUTPUT_PILE_FAMILIES:
	var path := "res://assets/items/output_piles/%s.svg" % family
	assertions.truthy(ResourceLoader.exists(path), "%s pile atlas exists" % family)
	var texture := load(path) as Texture2D
	assertions.equal(texture.get_size(), Vector2(576, 192), "%s atlas has three frames" % family)
```

Add a catalog test that collects recipe outputs plus passive/resource effect outputs and verifies every current output item has an explicit family mapping rather than relying on the future-item crate fallback.

- [x] **Step 2: Run the building suite and verify RED**

Expected: FAIL listing the ten missing atlases.

- [x] **Step 3: Create the ten atlases**

Create transparent 576×192 SVG atlases with three equal 192×192 panels. Every panel shares one ground baseline and progresses from sparse to medium to full. Use irregular shapes, warm painted highlights, dark brown contour strokes, and restrained ground shadows matching the painted buildings. Do not add text, numbers, background rectangles, or UI borders.

Keep stone-kiln products distinct through item tint: black-brown charcoal, pale gray stone bricks, and red-brown fired bricks. The atlas supplies silhouette/texture; `BuildingOutputPile` supplies item tint.

- [x] **Step 4: Import and run focused verification**

```powershell
godot_console --headless --editor --path . --quit-after 2
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
godot_console --headless --path . --script res://tests/run_economy_system_tests.gd
godot_console --headless --path . --script res://tests/run_player_action_controller_tests.gd
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot_console --headless --path . --script res://tests/run_production_chain_tests.gd
```

Expected: all five suites PASS without parser errors, missing resources, or output-pickup failures.

- [x] **Step 5: Verify save/load reconstruction and hygiene**

Extend the integration test to save a kiln with two outputs, reload, and assert exactly two reconstructed piles with no pile nodes in serialized building data. Then run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors and only intentional source, test, SVG, `.import`, and plan files. Do not add generated `.uid` files that were not already tracked.

- [x] **Step 6: Mark the plan complete and commit**

Change all plan checkboxes to `[x]`, then commit:

```powershell
git add assets/items/output_piles scripts tests docs/superpowers/plans/2026-08-08-building-output-pickup.md
git commit -m "feat: finish hand-painted building output pickups"
```

## Final verification

- [x] Run `git status --short` and confirm only the final planned commit remains.
- [x] Record exact PASS counts for building, economy, player-action, main-gameplay, and production-chain runners.
- [x] Render a completed stone kiln and verify it shows no “收”, renders distinct exterior product piles, while integration tests verify clicking one pile collects only that item.

Verification evidence (2026-08-08):

- `1895` building system checks passed.
- `64618` economy checks passed.
- `124` player action controller checks passed.
- `1166` main gameplay integration checks passed.
- `89` production chain integration checks passed.
- The focused stone-kiln render showed distinct charcoal and stone-brick piles outside the footprint with no “收” glyph.
