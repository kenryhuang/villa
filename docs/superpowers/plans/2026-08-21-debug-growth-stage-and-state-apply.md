# Debug Growth Stage and State Apply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make debug N visibly advance every growing crop by one stage and make debug-panel Apply return without synchronous event-driven UI rebuilds.

**Architecture:** Add a stage-oriented debug API to `FarmingSystem` and keep `Main` as the keyboard/feedback coordinator. Treat debug state application as direct authority synchronization that publishes only real field changes, then defer and coalesce expensive UI observers while preserving synchronous refresh for direct UI commands.

**Tech Stack:** Godot 4.7, GDScript, repository `TestAssert` SceneTree runners, Git.

---

## File Map

- Modify `scripts/systems/farming_system.gd`: dedicated next-visible-stage debug mutation and result counts.
- Modify `scripts/main.gd`: route N to the new API, display feedback, and explicitly refresh HUD after debug apply.
- Modify `scripts/debug/debug_state_editor.gd`: emit only changed state events and suppress formal day events.
- Modify `scripts/ui/service_panel.gd`: defer/coalesce event-driven refreshes and skip hidden rendering.
- Modify `scripts/ui/building_production_panel.gd`: defer/coalesce event-driven refreshes and skip hidden rendering.
- Modify `scripts/ui/building_status_panel.gd`: defer/coalesce event-driven refreshes and skip hidden rendering.
- Modify `tests/test_debug_crop_day.gd`: real crop stage, visual, date, and Main feedback regressions.
- Modify `tests/test_debug_state_editor.gd`: exact changed-event and no-day-event contracts.
- Modify `tests/test_service_panel.gd`: event refresh scheduling and hidden-panel regressions.
- Modify `tests/test_building_economy_ui.gd`: hidden building-panel event refresh regression.

### Task 1: Advance the Next Visible Crop Stage

**Files:**
- Modify: `tests/test_debug_crop_day.gd`
- Modify: `scripts/systems/farming_system.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Write failing real-farming assertions**

Create a four-stage, six-day crop in `test_debug_crop_day.gd`, plant it in a real grid/farming fixture, and assert:

```gdscript
var first := farming.debug_advance_growth_stage()
assertions.near(instance.growth_progress, 2.0, 0.001, "first N reaches stage-one threshold")
assertions.equal(instance.get_current_stage(), 1, "first N changes the visible stage")
assertions.equal(first, {"advanced": 1, "matured": 0}, "stage step reports one crop")
assertions.equal(int(farming.get_crop_visual(cell).get_meta("crop_stage", -1)), 1, "stage step refreshes the real visual")
```

Continue twice and assert progress `4.0`, then `6.0`, lifecycle `MATURE`, and final result `{"advanced": 1, "matured": 1}`. Water before one call and assert the water flags are unchanged.

- [ ] **Step 2: Run the focused runner and verify RED**

Run:

```powershell
godot_console.exe --headless --path . --script res://tests/run_debug_crop_day_tests.gd
```

Expected: FAIL because `debug_advance_growth_stage` does not exist.

- [ ] **Step 3: Implement the minimal farming API**

Add to `farming_system.gd`:

```gdscript
func debug_advance_growth_stage() -> Dictionary:
	var result := {"advanced": 0, "matured": 0}
	for cell in get_all_planted_cells():
		if is_paused_greenhouse_cell(cell):
			continue
		var instance: CropInstance = cell.crop_instance
		var stage_count := instance.get_stage_count()
		if instance.lifecycle_state != CropInstance.LifecycleState.GROWING or stage_count < 2:
			continue
		var old_stage := instance.get_current_stage()
		var next_stage := mini(old_stage + 1, stage_count - 1)
		var target := float(instance.crop_data.growth_days) * float(next_stage) / float(stage_count - 1)
		var next_state := CropInstance.LifecycleState.MATURE if next_stage == stage_count - 1 else CropInstance.LifecycleState.GROWING
		if not instance.set_growth_state(target, next_state):
			continue
		_update_visual(cell, instance)
		result.advanced += 1
		_queue_farming_event_batch([{"signal": &"crop_grew", "args": [cell.gx, cell.gz, next_stage]}])
		if next_state == CropInstance.LifecycleState.MATURE:
			result.matured += 1
			_queue_farming_event_batch([{"signal": &"crop_matured", "args": [cell.gx, cell.gz]}])
	return result
```

- [ ] **Step 4: Route Main and add feedback assertions**

Change `_advance_debug_crop_day()` to call the new API without touching `SeasonSystem`:

```gdscript
func _advance_debug_crop_day() -> bool:
	if farming_system == null:
		return false
	var result: Dictionary = farming_system.debug_advance_growth_stage()
	var advanced := int(result.get("advanced", 0))
	var matured := int(result.get("matured", 0))
	var message := (
		"推进了 %d 株作物，其中 %d 株成熟" % [advanced, matured]
		if advanced > 0
		else "没有可推进的作物"
	)
	if hud != null:
		hud.show_action_hint(message)
	return true
```

- [ ] **Step 5: Run the focused runner and verify GREEN**

Run the Step 2 command. Expected: PASS with real visual and date assertions.

- [ ] **Step 6: Commit the crop slice**

```powershell
git add scripts/systems/farming_system.gd scripts/main.gd tests/test_debug_crop_day.gd
git commit -m "fix: advance debug crops by visible stage"
```

### Task 2: Publish Only Real Debug State Changes

**Files:**
- Modify: `tests/test_debug_state_editor.gd`
- Modify: `scripts/debug/debug_state_editor.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Write failing event-contract assertions**

Record all state signals, apply an unchanged snapshot, and assert every event list remains empty. In the direct elapsed-day cases, replace the old day assertion with:

```gdscript
assertions.equal(day_events, [], "direct date edit never emits formal day_changed")
assertions.equal(fixture.daily.run_day_calls, 0, "direct date edit never runs daily simulation")
```

Add a changed-field case proving level/experience, gold, stamina, item and season signals each occur exactly when their authoritative value changes.

- [ ] **Step 2: Run the debug-panel runner and verify RED**

Run:

```powershell
godot_console.exe --headless --path . --script res://tests/run_debug_panel_tests.gd
```

Expected: FAIL because unchanged applies emit four state events and every date apply emits `day_changed`.

- [ ] **Step 3: Implement changed-only event publication**

Change the scalar portion of `_emit_success_events()` to:

```gdscript
if int(draft.level) != int(before.level):
	_emit_signal_if_available("level_changed", [int(draft.level)])
	_emit_signal_if_available("exp_gained", [0])
if int(draft.gold) != int(before.gold):
	_emit_signal_if_available("gold_changed", [int(draft.gold)])
if int(draft.stamina) != int(before.stamina):
	_emit_signal_if_available("stamina_changed", [int(draft.stamina)])
```

Keep the existing sorted exact item-delta loop and changed-only `season_changed` block. Delete the final `_emit_signal_if_available("day_changed", ...)` call.

- [ ] **Step 4: Explicitly refresh the HUD after success**

In `Main._on_debug_panel_apply_requested()`, call:

```gdscript
hud.configure_season_system(season_system)
hud.refresh_action_bar()
```

before showing the success result. This updates date/time without publishing a formal gameplay event.

- [ ] **Step 5: Run the debug-panel runner and verify GREEN**

Run the Step 2 command. Expected: PASS with no formal day events.

- [ ] **Step 6: Commit the state-event slice**

```powershell
git add scripts/debug/debug_state_editor.gd scripts/main.gd tests/test_debug_state_editor.gd
git commit -m "fix: publish precise debug state events"
```

### Task 3: Coalesce Expensive Observer Refreshes

**Files:**
- Modify: `tests/test_service_panel.gd`
- Modify: `tests/test_building_economy_ui.gd`
- Modify: `scripts/ui/service_panel.gd`
- Modify: `scripts/ui/building_production_panel.gd`
- Modify: `scripts/ui/building_status_panel.gd`

- [ ] **Step 1: Write failing deferred-refresh assertions**

For a visible service panel, emit `gold_changed`, `item_added`, and `item_removed` in one frame. Assert `_refresh_queued` becomes true without immediately replacing the first card; after `await tree.process_frame`, assert it becomes false and the card is replaced once. Hide the panel, emit again, and assert no refresh is queued.

For building UI, open then close a building, emit an inventory event, and assert both child panels leave `_snapshot_refresh_queued` false while hidden.

- [ ] **Step 2: Run UI runners and verify RED**

Run:

```powershell
godot_console.exe --headless --path . --script res://tests/run_economy_system_tests.gd
godot_console.exe --headless --path . --script res://tests/run_building_economy_ui_tests.gd
```

Expected: FAIL because event handlers currently rebuild synchronously and expose no queued state.

- [ ] **Step 3: Implement service refresh scheduling**

Add this scheduling state and helpers to `service_panel.gd`, then route both event callbacks to `_queue_event_refresh()`:

```gdscript
var _refresh_queued := false

func _queue_event_refresh() -> void:
	if not is_visible_in_tree() or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_flush_event_refresh")

func _flush_event_refresh() -> void:
	_refresh_queued = false
	if is_visible_in_tree():
		refresh_services()

func _on_gold_changed(_gold: int) -> void:
	_queue_event_refresh()

func _on_service_state_changed(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	_queue_event_refresh()
```

- [ ] **Step 4: Implement building refresh scheduling**

Add the following state and helpers to both building panel scripts:

```gdscript
var _snapshot_refresh_queued := false

func _queue_snapshot_refresh() -> void:
	if not is_visible_in_tree() or _snapshot_refresh_queued:
		return
	_snapshot_refresh_queued = true
	call_deferred("_flush_snapshot_refresh")

func _flush_snapshot_refresh() -> void:
	_snapshot_refresh_queued = false
	if is_visible_in_tree():
		refresh_snapshot()
```

In each `_on_economy_state_changed()`, retain the existing building filters and replace its final `refresh_snapshot()` with `_queue_snapshot_refresh()`. Direct command paths continue calling `refresh_snapshot()` synchronously.

- [ ] **Step 5: Run UI runners and verify GREEN**

Run both Step 2 commands. Expected: PASS with one deferred visible refresh and no hidden refresh.

- [ ] **Step 6: Commit the observer slice**

```powershell
git add scripts/ui/service_panel.gd scripts/ui/building_production_panel.gd scripts/ui/building_status_panel.gd tests/test_service_panel.gd tests/test_building_economy_ui.gd
git commit -m "perf: coalesce economy panel event refreshes"
```

### Task 4: Regression Verification

**Files:**
- Verify only; no planned production edits.

- [ ] **Step 1: Run focused regressions**

```powershell
godot_console.exe --headless --path . --script res://tests/run_debug_crop_day_tests.gd
godot_console.exe --headless --path . --script res://tests/run_debug_panel_tests.gd
godot_console.exe --headless --path . --script res://tests/run_farming_system_tests.gd
godot_console.exe --headless --path . --script res://tests/run_economy_system_tests.gd
godot_console.exe --headless --path . --script res://tests/run_building_economy_ui_tests.gd
```

Expected: all focused runners PASS.

- [ ] **Step 2: Run broad gameplay regressions**

```powershell
godot_console.exe --headless --path . --script res://tests/run_action_mode_debug_day_regression_tests.gd
godot_console.exe --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot_console.exe --headless --path . --script res://tests/run_tests.gd
```

Expected: no new failures. Compare any known broad-suite economy/save failures with the branch baseline instead of attributing them to this change.

- [ ] **Step 3: Inspect the final diff and status**

```powershell
git diff HEAD~3 --check
git status --short
```

Expected: no whitespace errors and no unintended files.
