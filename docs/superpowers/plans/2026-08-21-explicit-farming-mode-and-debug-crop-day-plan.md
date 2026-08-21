# Explicit Farming Mode and Debug Crop Day Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start gameplay in an explicit no-mode state, open the seed selector only after an explicit slot-6 command, and make debug N advance only crop growth.

**Architecture:** Add `ActionMode.NONE` as the controller's startup state and separate silent slot restoration from explicit slot activation. Make HUD palette visibility derive from the controller mode. Coordinate the debug crop-only step in `Main` without changing the authoritative calendar, daily economy cursors, or saves.

**Tech Stack:** Godot 4.7, GDScript, the repository's `TestAssert` SceneTree runners, Git.

---

## File Map

- Modify `scripts/actors/player_action_controller.gd`: startup mode, explicit/silent slot activation, seed selection side-effect removal.
- Modify `scripts/ui/hud.gd`: hide the action palette for `NONE` and reveal it for P/B.
- Modify `scripts/main.gd`: crop-only debug N coordinator.
- Modify `tests/test_player_action_controller.gd`: controller regression coverage.
- Modify `tests/test_hud_action_bar.gd`: initial palette and P-mode coverage.
- Modify `tests/test_season_system.gd`: formal versus suppressed day-event coverage.
- Modify `tests/test_main_item_container_wiring.gd`: real main-scene startup modal coverage.
- Create `tests/test_debug_crop_day.gd`: isolated Main coordinator coverage without the broken broad integration fixture.
- Create `tests/run_action_mode_debug_day_regression_tests.gd`: focused runner for this bug set.

> **Review correction:** Tasks 3–4 below record the initial implementation path. The final behavior supersedes their calendar-advance steps: `N` calls farming once at the current day and leaves `SeasonSystem` unchanged. This avoids desynchronizing the authoritative date from daily-simulation and market cursors.

### Task 1: Lock Down Controller Startup and Seed-Selector Semantics

**Files:**
- Create: `tests/run_action_mode_debug_day_regression_tests.gd`
- Modify: `tests/test_player_action_controller.gd`
- Modify: `scripts/actors/player_action_controller.gd`

- [ ] **Step 1: Create the focused regression runner**

```gdscript
extends SceneTree

const TestAssertScript = preload("res://tests/test_assert.gd")
const ControllerTest = preload("res://tests/test_player_action_controller.gd")
const HudTest = preload("res://tests/test_hud_action_bar.gd")
const SeasonTest = preload("res://tests/test_season_system.gd")
const MainWiringTest = preload("res://tests/test_main_item_container_wiring.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var assertions := TestAssertScript.new()
	ControllerTest.new().run(assertions, self)
	HudTest.new().run(assertions, self)
	SeasonTest.new().run(assertions)
	await MainWiringTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d action-mode/debug-day regression checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d action-mode/debug-day checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
```

- [ ] **Step 2: Add failing controller assertions**

Add assertions at the start of `_test_action_modes()`, using its `controller_script` argument, that instantiate a configured controller and record `seed_selection_requested` calls:

```gdscript
var startup_controller := controller_script.new()
var startup_inventory := InventoryDouble.new()
var startup_farming := FarmingDouble.new()
var startup_crop := CropData.new()
startup_crop.crop_id = "grain"
startup_crop.plant_item_id = "grain_seed"
startup_crop.growth_days = 3
startup_farming.crop_data = startup_crop
startup_controller.crop_data_override = startup_crop
tree.root.add_child(startup_controller)
startup_controller.configure(
	 null, GridDouble.new(), startup_farming, BuildingDouble.new(),
	 ToolDouble.new(), startup_inventory, null
)
var selector_requests: Array = []
startup_controller.seed_selection_requested.connect(func(cell): selector_requests.append(cell))
assertions.equal(startup_controller.get_action_mode(), PlayerActionController.ActionMode.NONE, "controller starts without an action mode")
assertions.equal(startup_controller.get_selected_slot(), -1, "controller starts without a selected slot")
assertions.truthy(startup_controller.set_selected_plant_item_id("grain_seed"), "startup seed can be restored")
assertions.equal(startup_controller.get_action_mode(), PlayerActionController.ActionMode.NONE, "restoring a seed does not enter farming mode")
assertions.equal(startup_controller.get_selected_slot(), -1, "restoring a seed does not select slot 6")
assertions.equal(selector_requests.size(), 0, "restoring a seed does not request the selector")
assertions.truthy(startup_controller.switch_mode(PlayerActionController.ActionMode.FARMING), "P semantics enter farming mode")
assertions.equal(selector_requests.size(), 0, "entering farming mode does not request the selector")
assertions.truthy(startup_controller.select_mode_slot(PlayerActionController.SEED_SLOT), "explicit slot 6 activates")
assertions.equal(selector_requests.size(), 1, "explicit slot 6 requests the selector exactly once")
startup_controller.free()
```

- [ ] **Step 3: Run the focused controller runner and verify RED**

Run:

```powershell
godot_console.exe --headless --path . --script res://tests/run_player_action_controller_tests.gd
```

Expected: FAIL because `ActionMode.NONE` is absent and seed restoration currently selects slot 6.

- [ ] **Step 4: Implement the minimal controller behavior**

Change the enum and initial state:

```gdscript
enum ActionMode {
	NONE,
	FARMING,
	BUILDING,
}

var _action_mode := ActionMode.NONE
```

Make `slot_from_key()` return `-1` in `NONE`. Change `_activate_current_slot` to accept a selector flag:

```gdscript
func _activate_current_slot(request_seed_selector: bool = true) -> bool:
	# existing activation logic remains
	if _selected_slot == SEED_SLOT and request_seed_selector:
		seed_selection_requested.emit(null)
	return true
```

Call `_activate_current_slot(false)` from `switch_mode()` and retain the default call from `select_mode_slot()`. Return `true` for every valid P/B mode switch even when its remembered slot is `-1`. Remove the `select_slot(SEED_SLOT)` block from `set_selected_plant_item_id()`.

- [ ] **Step 5: Run the controller runner and verify GREEN**

Run the command from Step 2.

Expected: PASS with zero parser errors and zero controller assertion failures.

- [ ] **Step 6: Commit the controller slice**

```powershell
git add scripts/actors/player_action_controller.gd tests/test_player_action_controller.gd tests/run_action_mode_debug_day_regression_tests.gd
git commit -m "fix: require explicit farming slot activation"
```

### Task 2: Gate the HUD Palette Behind P/B

**Files:**
- Modify: `tests/test_hud_action_bar.gd`
- Modify: `scripts/ui/hud.gd`

- [ ] **Step 1: Add failing HUD assertions**

Immediately after configuring the HUD/controller fixture, assert the startup and P states:

```gdscript
hud.configure_action_bar(controller, inventory, EconomyDouble.new())
assertions.equal(hud.get_palette_button_count(), 0, "startup HUD hides action shortcuts before P or B")
assertions.truthy(controller.switch_mode(PlayerActionController.ActionMode.FARMING), "HUD fixture enters farming mode")
assertions.equal(hud.get_palette_button_count(), 6, "P reveals six farming shortcuts")
```

Update later fixture sections that intentionally inspect farming buttons to call `switch_mode(FARMING)` first.

- [ ] **Step 2: Run the focused regression runner and verify RED**

Run the focused runner created in Task 1:

```powershell
godot_console.exe --headless --path . --script res://tests/run_action_mode_debug_day_regression_tests.gd
```

Expected: the named startup-palette assertion fails because `rebuild_action_palette()` currently treats every non-building state as farming.

- [ ] **Step 3: Implement mode-derived palette visibility**

Add a helper:

```gdscript
func _has_active_action_mode() -> bool:
	return (
		action_controller != null
		and action_controller.get_action_mode() in [
			PlayerActionController.ActionMode.FARMING,
			PlayerActionController.ActionMode.BUILDING,
		]
	)
```

At the start of `rebuild_action_palette()`, free old buttons, set `quick_bar.visible` from this helper, hide the building category bar for `NONE`, configure the mode button as `"选择模式"`, and return before creating buttons. For P/B, set `quick_bar.visible = true` and use the existing six farming or building entries.

- [ ] **Step 4: Run the focused runner and verify GREEN**

Run the command from Step 2.

Expected: startup palette assertion and six-button P assertion pass.

- [ ] **Step 5: Commit the HUD slice**

```powershell
git add scripts/ui/hud.gd tests/test_hud_action_bar.gd
git commit -m "fix: hide action palette until mode selection"
```

### Task 3: Add a Crop-Only Calendar Advance

**Files:**
- Modify: `tests/test_season_system.gd`
- Modify: `scripts/systems/season_system.gd`
- Modify: `scripts/ui/hud.gd`

- [ ] **Step 1: Add failing season event assertions**

Add a tree-backed clock test with the real EventBus autoload:

```gdscript
var event_bus := Engine.get_main_loop().root.get_node_or_null("EventBus")
var formal_days: Array[int] = []
var callback := func(day: int): formal_days.append(day)
event_bus.day_changed.connect(callback)
var debug_clock := SeasonSystemScript.new()
Engine.get_main_loop().root.add_child(debug_clock)
debug_clock.hour = 14
debug_clock.minute = 35
debug_clock.advance_to_next_day(false)
assertions.equal(debug_clock.current_day, 2, "debug next day advances the calendar")
assertions.equal(formal_days.size(), 0, "debug next day suppresses formal day_changed")
debug_clock.advance_to_next_day()
assertions.equal(formal_days.size(), 1, "normal next day still emits formal day_changed")
event_bus.day_changed.disconnect(callback)
debug_clock.free()
```

- [ ] **Step 2: Run the core runner and verify RED**

```powershell
godot_console.exe --headless --path . --script res://tests/run_tests.gd
```

Expected: FAIL because `advance_to_next_day(false)` is not accepted and formal day emission cannot be suppressed.

- [ ] **Step 3: Implement optional formal-day emission**

Use defaulted parameters to preserve normal callers:

```gdscript
func advance_game_minutes(minutes_to_add: int, emit_day_changed: bool = true) -> void:
	# existing loop
	if _event_bus and emit_day_changed:
		_event_bus.day_changed.emit(total_days)

func advance_to_next_day(emit_day_changed: bool = true) -> void:
	var minutes_until_next_day := (24 - hour) * 60 - minute
	advance_game_minutes(maxi(1, minutes_until_next_day), emit_day_changed)
```

Keep `season_changed` and `time_changed` emissions enabled. In `Hud._on_time_changed`, refresh both time and season/day text so the debug path updates the visible date without a formal day event.

- [ ] **Step 4: Run the core runner and verify GREEN for season checks**

Run the command from Step 2.

Expected: new season assertions pass. Record any pre-existing unrelated failures separately.

- [ ] **Step 5: Commit the calendar slice**

```powershell
git add scripts/systems/season_system.gd scripts/ui/hud.gd tests/test_season_system.gd
git commit -m "feat: support crop-only debug calendar advance"
```

### Task 4: Route N Around Formal Daily Simulation

**Files:**
- Create: `tests/test_debug_crop_day.gd`
- Modify: `tests/run_action_mode_debug_day_regression_tests.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Add a failing isolated N coordinator test**

Create `tests/test_debug_crop_day.gd` with a farming double and the real season clock:

```gdscript
extends RefCounted

const MainScript = preload("res://scripts/main.gd")
const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")

class FarmingDouble:
	extends Node
	var days: Array[int] = []
	func on_day_changed(day: int) -> void:
		days.append(day)

func run(assertions: TestAssert, tree: SceneTree) -> void:
	var event_bus := tree.root.get_node_or_null("EventBus")
	var formal_days: Array[int] = []
	var callback := func(day: int): formal_days.append(day)
	event_bus.day_changed.connect(callback)
	var clock := SeasonSystemScript.new()
	var farming := FarmingDouble.new()
	tree.root.add_child(clock)
	tree.root.add_child(farming)
	clock.hour = 14
	clock.minute = 35
	var main := MainScript.new()
	main.season_system = clock
	main.farming_system = farming
	assertions.truthy(main._advance_debug_crop_day(), "debug crop day succeeds with required systems")
	assertions.equal(clock.current_day, 2, "debug crop day advances the calendar once")
	assertions.equal(farming.days, [2], "debug crop day advances farming once")
	assertions.equal(formal_days.size(), 0, "debug crop day does not emit formal day_changed")
	event_bus.day_changed.disconnect(callback)
	main.free()
	clock.free()
	farming.free()
```

The fixture deliberately does not provide daily simulation, market, or save-manager references; a passing call proves the coordinator depends only on calendar and farming.

- [ ] **Step 2: Register the debug test in the focused runner**

Add:

```gdscript
const DebugCropDayTest = preload("res://tests/test_debug_crop_day.gd")
```

and invoke it after `SeasonTest`:

```gdscript
DebugCropDayTest.new().run(assertions, self)
```

- [ ] **Step 3: Run the focused regression runner and verify RED**

```powershell
godot_console.exe --headless --path . --script res://tests/run_action_mode_debug_day_regression_tests.gd
```

Expected: FAIL because N currently advances the formal daily and market cursors.

- [ ] **Step 4: Implement the Main coordinator**

Add:

```gdscript
func _advance_debug_crop_day() -> bool:
	if season_system == null or farming_system == null:
		return false
	season_system.advance_to_next_day(false)
	farming_system.on_day_changed(season_system.total_days)
	return true
```

Change the N handler to call `_advance_debug_crop_day()` and mark input handled only on success. Do not call `DailySimulationSystem.catch_up_farming_to_day()`, `run_day()`, or `SaveManager.save_game()`.

- [ ] **Step 5: Run the focused runner and verify GREEN**

Run the command from Step 2.

Expected: crop growth/date checks pass while daily and market cursors remain unchanged.

- [ ] **Step 6: Commit the N slice**

```powershell
git add scripts/main.gd tests/test_debug_crop_day.gd tests/run_action_mode_debug_day_regression_tests.gd
git commit -m "fix: make debug N advance crops only"
```

### Task 5: Protect Real Main Startup and Consolidate Verification

**Files:**
- Modify: `tests/test_main_item_container_wiring.gd`

- [ ] **Step 1: Add the failing real-scene startup assertion**

After the main scene has processed four frames, add:

```gdscript
assertions.equal(
	main.action_controller.get_action_mode(),
	PlayerActionController.ActionMode.NONE,
	"real Main starts without an action mode"
)
assertions.truthy(not main.seed_selector_panel.visible, "real Main does not open the seed selector at startup")
assertions.equal(main.hud.get_palette_button_count(), 0, "real Main hides shortcuts until P or B")
```

- [ ] **Step 2: Run the focused runner**

```powershell
godot_console.exe --headless --path . --script res://tests/run_action_mode_debug_day_regression_tests.gd
```

Expected: PASS with zero failures.

- [ ] **Step 3: Run adjacent suites**

```powershell
godot_console.exe --headless --path . --script res://tests/run_seed_selector_panel_tests.gd
godot_console.exe --headless --path . --script res://tests/run_player_action_controller_tests.gd
godot_console.exe --headless --path . --script res://tests/run_tests.gd
```

Expected: the seed selector and player controller suites pass. Compare `run_tests.gd` failures, if any, against the recorded baseline rather than hiding unrelated failures.

- [ ] **Step 4: Verify repository state and commit the regression harness**

```powershell
git diff --check
git status --short
git add tests/test_main_item_container_wiring.gd tests/run_action_mode_debug_day_regression_tests.gd
git commit -m "test: cover explicit mode and debug crop day regressions"
```

- [ ] **Step 5: Review final history and diff**

```powershell
git log -6 --oneline --decorate
git diff 7400247..HEAD --stat
git status --short --branch
```

Expected: only the approved controller, HUD, calendar, Main, and regression-test files changed; worktree is clean.
