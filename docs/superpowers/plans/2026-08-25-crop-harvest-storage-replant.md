# Crop Harvest Storage and Replant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make mature crops discoverable and harvestable in P mode, publish exact success/capacity feedback to the right-side message stream, and preserve the existing atomic storage/replant lifecycle.

**Architecture:** `PlayerActionController` remains the command coordinator for the paired `FarmStorageSystem`/`FarmingSystem` transaction. A structured feedback signal is routed by `Main` to `HudMessageBus`, while `GridSystem` owns one reusable scene-authored `Label3D` for the ephemeral mature-crop hover hint. Farming lifecycle and save formats remain unchanged.

**Tech Stack:** Godot 4.4, GDScript, scene-authored `Label3D`, custom headless test runners.

---

## File map

- `scripts/actors/player_action_controller.gd`: format and emit committed harvest outcomes; pass mature hover text to the grid.
- `scripts/main.gd`: route controller feedback into the existing HUD message stream.
- `scripts/systems/grid_system.gd`: position and hide the cell-local hint with the highlight.
- `scenes/systems/grid_system.tscn`: define the styled reusable hint node.
- `tests/test_player_action_controller.gd`: harvest priority, exact feedback, capacity failure, and false-success prevention.
- `tests/test_main_item_container_wiring.gd`: right-side message routing.
- `tests/test_grid_system_complete.gd`: hint display, reuse, and hide behavior.
- `tests/test_crop_economy.gd`: every production crop yields a valid lifecycle-aware harvest preview.

### Task 1: Controller harvest feedback

**Files:**
- Modify: `tests/test_player_action_controller.gd`
- Modify: `scripts/actors/player_action_controller.gd`

- [ ] **Step 1: Write failing feedback assertions**

In `_test_selection_and_transactions()`, connect the new signal and assert exact results around the existing full-storage and successful-harvest actions:

```gdscript
var action_feedback: Array[Dictionary] = []
controller.action_feedback_requested.connect(
	func(text: String, severity: String, details: Dictionary) -> void:
		action_feedback.append({"text": text, "severity": severity, "details": details.duplicate(true)})
)

assertions.equal(action_feedback.size(), 1, "full storage emits one harvest feedback")
assertions.equal(action_feedback[-1].text, "仓库容量不足，还需 1 容量", "capacity feedback reports exact shortage")
assertions.equal(action_feedback[-1].severity, "warning", "capacity feedback is a warning")

assertions.equal(action_feedback.size(), 2, "successful harvest emits one additional feedback")
assertions.equal(action_feedback[-1].text, "收获谷物 ×1，已入仓", "success feedback uses localized committed quantity")
assertions.equal(action_feedback[-1].severity, "success", "committed harvest uses success severity")
```

In the existing injected transaction-failure test, record the same signal and assert one `error` record whose text does not contain `已入仓`.

- [ ] **Step 2: Verify the tests fail**

Run:

```powershell
godot --headless --path . --script res://tests/run_player_action_controller_tests.gd
```

Expected: FAIL because the feedback signal and formatter do not exist.

- [ ] **Step 3: Implement one structured feedback path**

Add:

```gdscript
signal action_feedback_requested(text: String, severity: String, details: Dictionary)

const HARVEST_FAILURE_LABELS := {
	"harvest_unavailable": "作物尚未成熟",
	"storage_capacity": "仓库容量不足",
	"transaction_failed": "收割失败，请重试",
}

func _fail_harvest(reason: String, items: Dictionary = {}, extra: Dictionary = {}) -> bool:
	var details := {"ok": false, "reason": reason, "items": items.duplicate(true)}
	details.merge(extra, true)
	_set_last_action_failure(details)
	var message := str(HARVEST_FAILURE_LABELS.get(reason, "收割失败，请重试"))
	if reason == "storage_capacity":
		message = "仓库容量不足，还需 %d 容量" % int(details.get("missing_capacity", 0))
	action_feedback_requested.emit(message, "warning" if reason == "storage_capacity" else "error", details)
	return false

func _harvest_success_text(items: Dictionary) -> String:
	var parts: Array[String] = []
	var item_ids: Array = items.keys()
	item_ids.sort()
	for item_id_value in item_ids:
		var item_id := str(item_id_value)
		var item_data: Variant = GameDataScript.get_item(item_id)
		var display_name := str(item_data.get("name", item_id)) if item_data is Dictionary else item_id
		parts.append("%s ×%d" % [display_name, int(items[item_id])])
	return "收获%s，已入仓" % "、".join(parts)
```

After each required rollback in `_harvest()`, return `_fail_harvest(...)`. For capacity, pass `storage_capacity`, `storage_used`, and `missing_capacity` in `extra`. After both publications complete:

```gdscript
_last_action_failure_details.clear()
action_feedback_requested.emit(
	_harvest_success_text(items),
	"success",
	{"ok": true, "reason": "", "items": items.duplicate(true)},
)
return true
```

- [ ] **Step 4: Verify the controller suite passes**

Run the Step 2 command. Expected: `PASS: ... player action controller checks`.

- [ ] **Step 5: Commit**

```powershell
git add scripts/actors/player_action_controller.gd tests/test_player_action_controller.gd
git commit -m "feat: publish atomic harvest feedback"
```

### Task 2: Route feedback to the HUD message stream

**Files:**
- Modify: `tests/test_main_item_container_wiring.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Write the failing routing assertion**

```gdscript
main.action_controller.action_feedback_requested.emit(
	"收获胡萝卜 ×3，已入仓", "success", {"items": {"carrot": 3}}
)
var harvest_record: Dictionary = hud_message_bus.get_recent()[-1]
assertions.equal(str(harvest_record.source), "action", "harvest uses action message source")
assertions.equal(str(harvest_record.severity), "success", "harvest keeps success severity")
assertions.equal(str(harvest_record.text), "收获胡萝卜 ×3，已入仓", "harvest reaches the right message stream")
```

- [ ] **Step 2: Verify Main integration fails**

Run `godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd`.

Expected: FAIL because `Main` has not connected the signal.

- [ ] **Step 3: Connect and route the signal**

Add beside the existing `action_failure_hint` wiring:

```gdscript
if action_controller and action_controller.has_signal("action_feedback_requested"):
	var feedback_callback := Callable(self, "_on_action_feedback_requested")
	if not action_controller.action_feedback_requested.is_connected(feedback_callback):
		action_controller.action_feedback_requested.connect(feedback_callback)
```

Add beside `_on_action_failure_hint()`:

```gdscript
func _on_action_feedback_requested(text: String, severity: String, details: Dictionary) -> void:
	_publish_hud_message("action", severity, text, details)
```

- [ ] **Step 4: Verify Main integration passes**

Run the Step 2 command. Expected: `PASS: ... main gameplay integration checks`.

- [ ] **Step 5: Commit**

```powershell
git add scripts/main.gd tests/test_main_item_container_wiring.gd
git commit -m "feat: route harvest results to message stream"
```

### Task 3: Mature-crop hover hint

**Files:**
- Modify: `tests/test_grid_system_complete.gd`
- Modify: `tests/test_player_action_controller.gd`
- Modify: `scenes/systems/grid_system.tscn`
- Modify: `scripts/systems/grid_system.gd`
- Modify: `scripts/actors/player_action_controller.gd`

- [ ] **Step 1: Write failing grid and controller tests**

Add to the grid highlight contract:

```gdscript
var cell_hint := grid.get_node_or_null("GridCells/CellHint") as Label3D
assertions.truthy(cell_hint != null, "grid owns one reusable cell hint")
assertions.truthy(grid.highlight_cell(18, 14, Color.YELLOW, "点击收割"), "highlight accepts hint text")
assertions.truthy(cell_hint.visible, "non-empty hint becomes visible")
assertions.equal(cell_hint.text, "点击收割", "hint shows exact harvest action")
var hint_id := cell_hint.get_instance_id()
assertions.truthy(grid.highlight_cell(18, 14, Color.RED, "点击收割"), "same-cell hint updates")
assertions.equal(cell_hint.get_instance_id(), hint_id, "hint node is reused")
grid.clear_highlights()
assertions.truthy(not cell_hint.visible, "clearing hover hides hint")
```

Add controller helper assertions:

```gdscript
assertions.equal(controller.cell_hover_hint(mature), "点击收割", "mature crop exposes harvest hint")
assertions.equal(controller.cell_hover_hint(farmland), "", "ordinary farmland has no hint")
```

- [ ] **Step 2: Verify both suites fail**

Run:

```powershell
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_player_action_controller_tests.gd
```

Expected: FAIL for missing `CellHint`, fourth `highlight_cell` argument, and `cell_hover_hint()`.

- [ ] **Step 3: Add the reusable hint node and grid behavior**

Add under `GridCells` in `grid_system.tscn`:

```ini
[node name="CellHint" type="Label3D" parent="GridCells"]
visible = false
billboard = 1
fixed_size = true
no_depth_test = true
font_size = 28
outline_size = 8
modulate = Color(1, 0.95, 0.76, 1)
text = "点击收割"
```

Change the method signature exactly:

```gdscript
func highlight_cell(gx: int, gz: int, color: Color, hint_text: String = "") -> bool:
```

Insert this block after `highlight.visible = true` and before the method's existing `return true`:

```gdscript
var hint := get_node_or_null("GridCells/CellHint") as Label3D
if hint != null:
	var center_x := WORLD_ORIGIN_X + (float(gx) + 0.5) * CELL_SIZE
	var center_z := WORLD_ORIGIN_Z + (float(gz) + 0.5) * CELL_SIZE
	hint.position = Vector3(center_x, terrain.get_height_at(center_x, center_z) + 0.72, center_z)
	hint.text = hint_text
	hint.visible = not hint_text.is_empty()
```

Append to `clear_highlights()`:

```gdscript
var hint := get_node_or_null("GridCells/CellHint") as Label3D
if hint:
	hint.visible = false
```

- [ ] **Step 4: Supply hint text only for mature P-mode targets**

```gdscript
func cell_hover_hint(cell: GridCell) -> String:
	return "点击收割" if _is_mature(cell) else ""
```

Replace the existing controller highlight call with:

```gdscript
grid_system.highlight_cell(
	cell.gx, cell.gz, _highlight_color(cell, ground_point), cell_hover_hint(cell)
)
```

- [ ] **Step 5: Verify hover behavior**

Run:

```powershell
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_player_action_controller_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: all three commands exit 0 with PASS summaries.

- [ ] **Step 6: Commit**

```powershell
git add scenes/systems/grid_system.tscn scripts/systems/grid_system.gd scripts/actors/player_action_controller.gd tests/test_grid_system_complete.gd tests/test_player_action_controller.gd
git commit -m "feat: show mature crop harvest hint"
```

### Task 4: All-crop lifecycle regression and final verification

**Files:**
- Modify: `tests/test_crop_economy.gd`

- [ ] **Step 1: Add a harvest preview contract for every default crop**

Inside the existing default-roster loop, after registering each crop:

```gdscript
var grid := GridSystemScript.new()
var farming := FarmingSystemScript.new()
farming.configure(grid, null, null)
grid.set_cell_state(0, 0, GridCell.State.FARMLAND)
var planted := grid.plant_crop(0, 0, crop)
assertions.truthy(planted != null, "%s plants for harvest contract" % crop_id)
if planted != null:
	planted.set_growth_state(float(crop.growth_days), CropInstance.LifecycleState.MATURE)
	var preview: Dictionary = farming.preview_harvest(grid.get_cell(0, 0))
	assertions.truthy(not preview.is_empty(), "%s produces a mature harvest preview" % crop_id)
	assertions.truthy(int(preview.get("items", {}).get(crop_id, 0)) > 0, "%s routes its crop product" % crop_id)
	assertions.equal(
		int(preview.get("post_cell_state", -1)),
		GridCell.State.FARMLAND if crop.lifecycle_type == "annual" else GridCell.State.PLANTED,
		"%s has the designed post-harvest state" % crop_id,
	)
farming.free()
grid.free()
```

- [ ] **Step 2: Run the farming suite**

Run `godot --headless --path . --script res://tests/run_farming_system_tests.gd`.

Expected: PASS. A production definition that contradicts the approved lifecycle table must be corrected rather than weakening the assertion.

- [ ] **Step 3: Commit**

```powershell
git add tests/test_crop_economy.gd
git commit -m "test: cover harvest lifecycle for every crop"
```

- [ ] **Step 4: Run final verification**

```powershell
godot --headless --path . --script res://tests/run_player_action_controller_tests.gd
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_inventory_storage_ui_tests.gd
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path . --script res://tests/run_tests.gd
git diff --check
git status --short
```

Expected: focused suites PASS; the full runner introduces no failure beyond its recorded baseline; `git diff --check` is empty; the implementation worktree has no uncommitted changes.
