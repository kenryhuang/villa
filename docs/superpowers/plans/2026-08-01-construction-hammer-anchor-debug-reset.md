# Construction Hammer Anchor and Debug Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the construction hammer on the building's screen-right foundation at a 0.6-second cadence and add a Debug-only HUD button that clears slot 0 and reloads a new game.

**Architecture:** `ConstructionFeedback` will keep its world origin at the building base and pass a camera-plane offset into the hammer billboard shader, making placement independent of camera yaw. `VillaHud` owns only the Debug button and signal; `Main` owns reset orchestration, while `SaveManager` provides reliable idempotent slot clearing.

**Tech Stack:** Godot 4.7, GDScript, spatial shaders, scene-based UI, headless contract tests, rendered acceptance captures.

---

## File Map

- Modify `scripts/buildings/construction_feedback.gd`: 0.6-second cadence and camera-plane anchor parameters.
- Modify `assets/buildings/construction/construction_hammer.gdshader`: apply the screen-space foundation offset.
- Modify `tests/test_construction_feedback.gd`: component timing, fixed origin, and shader-offset contracts.
- Modify `tests/capture_building_visual.gd`: capture default and rotated-camera construction closeups.
- Modify `scenes/ui/hud.tscn`: add the top-right Debug reset button.
- Modify `scripts/ui/hud.gd`: Debug visibility configuration and reset signal.
- Modify `tests/test_hud_action_bar.gd`: HUD visibility and signal contracts.
- Modify `scripts/core/save_manager.gd`: idempotently clear a selected slot and surface filesystem failure.
- Modify `scripts/main.gd`: current-slot setting, Debug reset state preparation, and reload handler.
- Modify `tests/test_main_farming_building_integration.gd`: slot clearing, resources, buildings, and HUD wiring.

### Task 1: Camera-relative hammer anchor and faster strike

**Files:**
- Modify: `tests/test_construction_feedback.gd`
- Modify: `scripts/buildings/construction_feedback.gd`
- Modify: `assets/buildings/construction/construction_hammer.gdshader`

- [ ] **Step 1: Write failing component contracts**

Add assertions that `STRIKE_PERIOD` is `0.6`, the pivot has no world-space X/Z offset, and the hammer material exposes a positive `screen_offset.x`:

```gdscript
assertions.near(FeedbackScript.STRIKE_PERIOD, 0.6, 0.001, "construction strike repeats every 0.6 seconds")
assertions.near(pivot.position.x, 0.0, 0.001, "hammer anchor starts from building base center")
assertions.near(pivot.position.z, 0.0, 0.001, "hammer anchor does not drift with camera yaw")
var screen_offset: Vector2 = hammer_material.get_shader_parameter("screen_offset")
assertions.truthy(screen_offset.x > 0.0, "hammer moves toward screen-right foundation")
```

Advance by `0.15` seconds and assert the phase reaches the end of the raised hold at the new 0.6-second cadence.

- [ ] **Step 2: Verify the new contracts fail**

Run:

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: failures report the old `0.9` period, non-zero pivot X/Z, and missing `screen_offset`.

- [ ] **Step 3: Implement camera-plane anchoring**

In `construction_feedback.gd`, set:

```gdscript
const STRIKE_PERIOD := 0.6
pivot.position = Vector3(0.0, hammer_height * 0.22, 0.0)
hammer_material.set_shader_parameter(
	"screen_offset",
	Vector2(visual_size.x * 0.30, 0.0)
)
```

In `construction_hammer.gdshader`, add and apply the offset after rotating around `pivot_uv`:

```glsl
uniform vec2 screen_offset = vec2(0.0);
// ... rotate anchored into VERTEX.xy ...
VERTEX.xy += screen_offset;
```

This offset is evaluated in the billboard plane, so screen-right stays screen-right as the camera orbits.

- [ ] **Step 4: Verify the building suite passes**

Run the building runner again. Expected: all building checks pass, including the new timing and anchor contracts.

- [ ] **Step 5: Commit the hammer behavior**

```powershell
git add tests/test_construction_feedback.gd scripts/buildings/construction_feedback.gd assets/buildings/construction/construction_hammer.gdshader
git commit -m "fix: anchor construction hammer to foundation"
```

### Task 2: Debug-only HUD reset control

**Files:**
- Modify: `tests/test_hud_action_bar.gd`
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/hud.gd`

- [ ] **Step 1: Write failing HUD tests**

Require `DebugResetButton`, call `configure_debug_reset(false)` and `configure_debug_reset(true)`, and assert visibility follows the argument. Connect `debug_reset_requested`, emit a button press, and assert it fires exactly once when enabled.

```gdscript
var reset_button := hud.get_node("DebugResetButton") as Button
hud.configure_debug_reset(false)
assertions.falsy(reset_button.visible, "debug reset is hidden when unavailable")
hud.configure_debug_reset(true)
assertions.truthy(reset_button.visible, "debug reset appears in debug mode")
```

- [ ] **Step 2: Verify the HUD test fails**

Run:

```powershell
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: missing `DebugResetButton`, signal, and configuration method.

- [ ] **Step 3: Add the HUD button and signal**

Add a top-right anchored `Button` named `DebugResetButton`, text `重置存档`, initially hidden. In `hud.gd` add:

```gdscript
signal debug_reset_requested
@onready var debug_reset_button: Button = $DebugResetButton

func configure_debug_reset(available: bool) -> void:
	debug_reset_button.visible = available

func _on_debug_reset_pressed() -> void:
	if debug_reset_button.visible:
		debug_reset_requested.emit()
```

Connect `pressed` once in `_ready()`.

- [ ] **Step 4: Verify the main gameplay runner passes**

Run the main gameplay runner. Expected: all checks pass and the new signal fires once.

- [ ] **Step 5: Commit the HUD control**

```powershell
git add tests/test_hud_action_bar.gd scenes/ui/hud.tscn scripts/ui/hud.gd
git commit -m "feat: add debug reset control to HUD"
```

### Task 3: Reset the current save and runtime state

**Files:**
- Modify: `tests/test_main_farming_building_integration.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Write failing reset integration tests**

Instantiate `Main` with `load_save_on_start = false` and a safe `save_slot = 4`. Spend starter resources, place a building, save slot 4, call `reset_debug_state()`, then assert:

```gdscript
assertions.truthy(reset_result, "debug reset prepares a clean new game")
assertions.equal(main.building_system.get_building_count(), 0, "debug reset clears buildings")
assertions.equal(main.inventory_system.get_item_count("wood"), 250, "debug reset restores starter wood")
assertions.falsy(main.save_manager.has_save(4), "debug reset deletes the current save slot")
```

Also assert the HUD signal is connected to Main and `save_slot` defaults to `0`.

- [ ] **Step 2: Verify reset tests fail**

Run the main gameplay runner. Expected: missing `save_slot`, `has_save`, and `reset_debug_state` contracts.

- [ ] **Step 3: Implement reliable slot clearing**

In `save_manager.gd` add:

```gdscript
func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_save_path(slot))

func clear_save(slot: int) -> bool:
	var path := _save_path(slot)
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(path) == OK

func _save_path(slot: int) -> String:
	return SAVE_DIR + SAVE_PREFIX + str(slot) + SAVE_EXT
```

Route existing save/load/delete path creation through `_save_path`. Preserve `delete_save` semantics explicitly:

```gdscript
func delete_save(slot: int) -> bool:
	if not has_save(slot):
		return false
	return clear_save(slot)
```

- [ ] **Step 4: Implement Main reset orchestration**

Add `@export var save_slot := 0`, use it in startup loading, and configure/connect the HUD with `OS.is_debug_build()`. Add:

```gdscript
func reset_debug_state() -> bool:
	if not OS.is_debug_build():
		return false
	if building_system.is_in_build_mode():
		building_system.exit_preview_mode()
	building_system.clear_buildings(true)
	_grant_new_game_items()
	if hud:
		hud.refresh_action_bar()
	return save_manager.clear_save(save_slot)

func _on_debug_reset_requested() -> void:
	if not reset_debug_state():
		push_error("Unable to clear the current debug save.")
		return
	var reload_error := get_tree().reload_current_scene()
	if reload_error != OK:
		push_error("Unable to reload the current scene: %s" % error_string(reload_error))
```

- [ ] **Step 5: Verify reset integration passes and slot 4 is removed**

Run the main gameplay runner and confirm `user://villa_saves/save_4.json` does not remain after the test.

- [ ] **Step 6: Commit reset orchestration**

```powershell
git add tests/test_main_farming_building_integration.gd scripts/core/save_manager.gd scripts/main.gd
git commit -m "feat: reset current game from debug HUD"
```

### Task 4: Visual acceptance and regression

**Files:**
- Modify: `tests/capture_building_visual.gd`
- Modify: `tests/test_building_visual_scene.gd`

- [ ] **Step 1: Strengthen the visual contract**

Replace the old loose world-position threshold with checks that the pivot X/Z are zero and the hammer shader has a positive camera-plane X offset. Keep the progress indicator contracts unchanged.

- [ ] **Step 2: Add a rotated-camera capture**

After the default closeup, orbit the capture camera 90 degrees around the same focus and save `res://.godot/villa-building-construction-rotated-closeup.png`. Keep the feedback at impact phase `0.48` in both images.

- [ ] **Step 3: Run and inspect visual acceptance**

Run:

```powershell
godot --path . --audio-driver Dummy --script res://tests/capture_building_visual.gd
```

Inspect both closeups. Expected: hammer head overlaps the screen-right foundation edge in both camera orientations; progress remains upper-right and unobscured.

- [ ] **Step 4: Run full regression**

Run editor import/parse plus:

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path . --script res://tests/test_player_grid_binding.gd
godot --headless --path . --script res://tests/test_building_visual_scene.gd
```

Expected: every runner exits `0`; `git diff --check` is clean.

- [ ] **Step 5: Commit visual verification**

```powershell
git add tests/capture_building_visual.gd tests/test_building_visual_scene.gd
git commit -m "test: verify foundation hammer across camera angles"
```

### Task 5: Review and integrate

- [ ] **Step 1: Request code review of the exact feature range**

Review from `5ce605e` through feature `HEAD`, focusing on destructive reset safety, Debug gating, camera-relative placement, and test isolation.

- [ ] **Step 2: Apply accepted review findings with TDD**

For each accepted behavior defect, add a failing regression check, apply the minimal fix, and rerun the affected suite.

- [ ] **Step 3: Verify the final branch and merge locally**

Rerun the complete Task 4 regression, fast-forward `main`, rerun focused building and main gameplay suites on merged `main`, then remove the owned worktree and merged feature branch. Do not push unless explicitly requested.
