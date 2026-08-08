# Restored Building Output Pickup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make output piles on save-restored buildings reliably collect into inventory, then show a clear world-space inventory feedback animation before disappearing.

**Architecture:** Keep `ProductionSystem.collect_outputs()` as the only authoritative inventory transaction. `Main` will reconcile signal bindings after every committed load, while `BuildingOutputPile` will own only the post-success visual animation triggered when output synchronization removes a collected pile.

**Tech Stack:** Godot 4.7, GDScript, existing custom headless test runners.

---

### Task 1: Rebind restored building output signals

**Files:**
- Modify: `tests/test_main_farming_building_integration.gd`
- Modify: `scripts/main.gd:325-337`

- [ ] **Step 1: Write the failing restored-building pickup test**

Add a completed kiln to the authoritative building registry without calling `_on_building_instance_placed()`, give it charcoal output, invoke `_on_save_load_completed()`, then click the pile:

```gdscript
var restored_kiln := (load(kiln_data.scene_path) as PackedScene).instantiate() as BuildingInstance
main.buildings_container.add_child(restored_kiln)
restored_kiln.configure(kiln_data, 4, 4, [])
restored_kiln.complete_construction()
main.building_system._buildings.append(restored_kiln)
main.production_system.register_building(restored_kiln)
restored_kiln.producer_state.outputs = {"charcoal": 2}
main.production_system.refresh_indicator(restored_kiln)
main.call("_on_save_load_completed", main.save_slot)
var restored_pile = restored_kiln.get_node("BuildingOutputDisplay").get_pile("charcoal")
var click := InputEventMouseButton.new()
click.button_index = MOUSE_BUTTON_LEFT
click.pressed = true
restored_pile.handle_direct_pointer_event(click, true, false)
assertions.equal(
	main.inventory_system.get_item_count("charcoal"),
	charcoal_before + 2,
	"load completion reconnects restored output pickup to inventory"
)
```

Clean the fixture by unregistering the kiln, removing it from `_buildings`, and freeing it.

- [ ] **Step 2: Run the main integration suite and verify RED**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: FAIL at `load completion reconnects restored output pickup to inventory`; inventory count is unchanged because the restored kiln has no `output_collection_requested` connection to `Main`.

- [ ] **Step 3: Implement idempotent post-load binding reconciliation**

Add this focused helper to `scripts/main.gd`:

```gdscript
func _rebind_restored_buildings() -> void:
	if building_system == null:
		return
	for building in building_system.get_all_buildings():
		_on_building_instance_placed(building)
```

Call `_rebind_restored_buildings()` at the start of `_on_save_load_completed()` after null guards and before production cursor synchronization. Reuse `_on_building_instance_placed()` because its signal connection checks are already idempotent.

- [ ] **Step 4: Run the main integration suite and verify GREEN**

Run the command from Step 2.

Expected: PASS, including the restored kiln inventory assertion.

- [ ] **Step 5: Commit the signal repair**

```powershell
git add scripts/main.gd tests/test_main_farming_building_integration.gd
git commit -m "fix: reconnect restored building output pickup"
```

### Task 2: Animate successful collection into inventory

**Files:**
- Modify: `tests/test_building_output_pile.gd`
- Modify: `tests/run_building_system_tests.gd`
- Modify: `scripts/buildings/building_output_pile.gd`

- [ ] **Step 1: Write the failing success-animation test**

Make `test_building_output_pile.gd::run()` asynchronous. Configure a charcoal pile with quantity 2, call `play_collected()`, and assert the immediate and completed states:

```gdscript
var collected_pile := BuildingOutputPileScript.new()
tree.root.add_child(collected_pile)
collected_pile.configure("charcoal", 2, 9)
collected_pile.play_collected()
var feedback := collected_pile.get_node("PickupFeedback") as Label3D
assertions.equal(feedback.text, "木炭 +2", "collection feedback shows deposited quantity")
assertions.truthy(feedback.visible, "collection feedback appears immediately")
assertions.equal(collected_pile.collision_layer, 0, "collection animation disables repeat pickup")
await tree.create_timer(0.5).timeout
assertions.truthy(
	not is_instance_valid(collected_pile),
	"collected pile disappears after the inventory animation"
)
```

Update `tests/run_building_system_tests.gd` to call:

```gdscript
await BuildingOutputPileTest.new().run(assertions, self)
```

- [ ] **Step 2: Run the building suite and verify RED**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: FAIL because `PickupFeedback` does not exist and the old animation completes in 0.2 seconds without quantity feedback.

- [ ] **Step 3: Implement the 0.45-second success animation**

In `building_output_pile.gd`, add:

```gdscript
const COLLECTION_ANIMATION_DURATION := 0.45
```

Create a hidden `PickupFeedback` `Label3D` in `_ensure_nodes()` with fixed size, compact font, green text, outline, billboard mode, no depth test, and a position just above `Tooltip`.

In `play_collected()`:

1. Capture the localized item name and current quantity before disabling interaction.
2. Set feedback text to `"%s +%d"`, show it, and hide hover UI.
3. Animate the pile sprite upward by `0.24`, scale it to `0.55`, and fade it out over `0.45` seconds.
4. Animate `PickupFeedback` upward by `0.22` and fade it out over the same duration.
5. Queue-free the pile only after all parallel tracks finish.

- [ ] **Step 4: Run the building suite and verify GREEN**

Run the command from Step 2.

Expected: PASS with the feedback text, disabled interaction, and delayed disappearance assertions.

- [ ] **Step 5: Run cross-system regression suites**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_player_action_controller_tests.gd
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot_console --headless --path . --script res://tests/run_production_chain_tests.gd
git diff --check
```

Expected: every command exits `0`; no new failures or diff formatting errors.

- [ ] **Step 6: Commit animation and tests**

```powershell
git add scripts/buildings/building_output_pile.gd tests/test_building_output_pile.gd tests/run_building_system_tests.gd
git commit -m "feat: animate building output collection"
```

### Task 3: Final review

**Files:**
- Review: all files changed by Tasks 1-2

- [ ] **Step 1: Request code review**

Review the committed range from the plan commit through Task 2, focusing on load ordering, duplicate signal connections, inventory transaction boundaries, repeat-click prevention, tween lifecycle, and test cleanup.

- [ ] **Step 2: Address every Critical or Important finding**

Apply focused fixes with a failing test first, rerun the affected suite, and commit each correction.

- [ ] **Step 3: Run final verification**

Rerun the four suites and `git diff --check`, then confirm `git status --short` is empty.

