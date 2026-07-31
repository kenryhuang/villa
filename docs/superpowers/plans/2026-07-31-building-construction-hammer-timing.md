# Building Construction Hammer and Timing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every existing building construction frame last 10 real-time seconds, preserve stage cross-fades and save progress, and show a swinging hammer above the building until construction completes.

**Architecture:** `BuildingInstance` remains the owner of per-building construction time, state, visuals, and serialization. Existing stage art and transition nodes remain unchanged; a billboarded SVG hammer is added under `VisualRoot`, while `construction_duration_for()` becomes footprint-independent and derives a 30-second total from the three existing stage transitions.

**Tech Stack:** Godot 4.7, typed GDScript, Sprite3D, SVG texture import, SceneTree test runners, existing visual verification scene.

---

## File Map

- Create `assets/buildings/construction/construction_hammer.svg`: transparent hand-painted-style hammer icon used by every unfinished building.
- Modify `scripts/buildings/building_instance.gd`: fixed ten-second stage thresholds, hammer node creation/configuration/animation/visibility, and compatible restore behavior.
- Modify `tests/test_building_construction_state.gd`: timing boundaries, large-delta behavior, cross-fade preservation, and hammer lifecycle tests.
- Modify `tests/test_building_art_assets.gd`: hammer asset existence/import contract.
- Modify `tests/test_building_save_integration.gd`: partial-stage elapsed-time restore and old short-duration migration coverage.
- Modify `tests/test_building_visual_scene.gd`: require a visible hammer on the staged construction demo.
- Modify `tests/visual/building_system_verification.gd`: include hammer visibility in the interactive visual contract.

### Task 1: Fixed Ten-Second Construction Frames

**Files:**
- Modify: `tests/test_building_construction_state.gd`
- Modify: `tests/test_building_save_integration.gd`
- Modify: `scripts/buildings/building_instance.gd:18-162`

- [ ] **Step 1: Write failing timing tests**

Replace the footprint-duration assertions at the start of `run()` with:

```gdscript
for footprint in [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 2)]:
	assertions.equal(
		BuildingInstance.construction_duration_for(footprint),
		30.0,
		"construction duration follows three ten-second frame transitions"
	)
```

After `instance.start_construction()`, change the barn duration expectation to `30.0`. Replace the first automatic advancement with exact boundary assertions:

```gdscript
var foundation_texture: Texture2D = instance.get_node("VisualRoot/ConstructionLayer").texture
instance.advance_construction(9.99)
assertions.equal(
	instance.construction_stage,
	BuildingInstance.ConstructionStage.FOUNDATION,
	"construction remains on foundation before ten seconds"
)
assertions.equal(stage_events.size(), 0, "no early stage signal")
instance.advance_construction(0.01)
assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.FRAME, "ten seconds advances to frame")
assertions.equal(stage_events, [BuildingInstance.ConstructionStage.FRAME], "frame transition emits once")
```

Replace the large-delta setup value `20.0` with `30.0`, keeping the expected ordered `FRAME`, `HALF_BUILT`, `COMPLETE` signal array.

In `tests/test_building_save_integration.gd`, replace the manual stage advance with:

```gdscript
placed.advance_construction(15.0)
assertions.equal(placed.construction_stage, BuildingInstance.ConstructionStage.FRAME, "save fixture reaches frame stage")
assertions.near(placed.construction_elapsed, 15.0, 0.001, "save fixture stores time inside frame stage")
```

After restore, replace the generic `0.1` advancement assertion with:

```gdscript
assertions.near(restored.construction_elapsed, 15.0, 0.001, "load restores partial frame elapsed time")
restored.advance_construction(4.99)
assertions.equal(restored.construction_stage, BuildingInstance.ConstructionStage.FRAME, "restored frame waits for remaining time")
restored.advance_construction(0.01)
assertions.equal(restored.construction_stage, BuildingInstance.ConstructionStage.HALF_BUILT, "restored frame advances at twenty seconds")
```

Before the legacy-record-without-fields case, add:

```gdscript
var short_duration_record: Dictionary = records[0].duplicate(true)
short_duration_record.construction_stage = BuildingInstance.ConstructionStage.HALF_BUILT
short_duration_record.construction_elapsed = 2.7
short_duration_record.construction_duration = 4.0
manager._apply_save_data({"grid": saved_grid, "buildings": [short_duration_record]})
restored = system.get_building_at(6, 6)
assertions.equal(restored.construction_stage, BuildingInstance.ConstructionStage.HALF_BUILT, "old save keeps authoritative stage")
assertions.near(restored.construction_elapsed, 20.0, 0.001, "old short duration aligns to new half-built threshold")
```

- [ ] **Step 2: Run the building suite and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: FAIL because `construction_duration_for()` still returns 3, 4, or 5 seconds and the instance reaches `COMPLETE` before the 9.99-second boundary assertion.

- [ ] **Step 3: Implement fixed stage thresholds**

Add beside the existing fade constants:

```gdscript
const CONSTRUCTION_SECONDS_PER_STAGE := 10.0
const CONSTRUCTION_TRANSITION_COUNT := int(ConstructionStage.COMPLETE) - int(ConstructionStage.FOUNDATION)
```

Replace `construction_duration_for()` with:

```gdscript
static func construction_duration_for(_footprint: Vector2i) -> float:
	return CONSTRUCTION_SECONDS_PER_STAGE * float(CONSTRUCTION_TRANSITION_COUNT)
```

Replace the threshold calculations in `advance_construction()` with:

```gdscript
var first_threshold := CONSTRUCTION_SECONDS_PER_STAGE
var second_threshold := CONSTRUCTION_SECONDS_PER_STAGE * 2.0
```

Replace the elapsed alignment in `advance_construction_stage()` with:

```gdscript
match construction_stage:
	ConstructionStage.FOUNDATION:
		construction_elapsed = maxf(construction_elapsed, CONSTRUCTION_SECONDS_PER_STAGE)
		_transition_construction_stage(ConstructionStage.FRAME)
	ConstructionStage.FRAME:
		construction_elapsed = maxf(construction_elapsed, CONSTRUCTION_SECONDS_PER_STAGE * 2.0)
		_transition_construction_stage(ConstructionStage.HALF_BUILT)
	ConstructionStage.HALF_BUILT:
		complete_construction()
```

Replace the stage minimums in `restore_construction()` with:

```gdscript
if construction_stage == ConstructionStage.FRAME:
	construction_elapsed = maxf(construction_elapsed, CONSTRUCTION_SECONDS_PER_STAGE)
elif construction_stage == ConstructionStage.HALF_BUILT:
	construction_elapsed = maxf(construction_elapsed, CONSTRUCTION_SECONDS_PER_STAGE * 2.0)
```

- [ ] **Step 4: Run the building suite and verify GREEN**

Run the same building suite. Expected: PASS, including exact 9.99/10-second boundaries and the three-stage large-delta transition.

- [ ] **Step 5: Commit the timing change**

```powershell
git add scripts/buildings/building_instance.gd tests/test_building_construction_state.gd tests/test_building_save_integration.gd
git commit -m "feat: advance building construction every ten seconds"
```

### Task 2: Swinging Construction Hammer

**Files:**
- Create: `assets/buildings/construction/construction_hammer.svg`
- Modify: `tests/test_building_art_assets.gd`
- Modify: `tests/test_building_construction_state.gd`
- Modify: `scripts/buildings/building_instance.gd:18-41,273-360,496-544`

- [ ] **Step 1: Write failing hammer asset and lifecycle tests**

Add to `tests/test_building_art_assets.gd`:

```gdscript
const HAMMER_ICON_PATH := "res://assets/buildings/construction/construction_hammer.svg"
```

At the end of `run()` add:

```gdscript
assertions.truthy(ResourceLoader.exists(HAMMER_ICON_PATH), "construction hammer icon exists")
if ResourceLoader.exists(HAMMER_ICON_PATH):
	var hammer_texture := load(HAMMER_ICON_PATH) as Texture2D
	assertions.truthy(hammer_texture != null, "construction hammer imports as Texture2D")
```

After `instance.start_construction()` in `tests/test_building_construction_state.gd`, add:

```gdscript
var hammer := instance.get_node_or_null("VisualRoot/ConstructionHammer") as Node3D
var hammer_sprite := instance.get_node_or_null("VisualRoot/ConstructionHammer/HammerSprite") as Sprite3D
assertions.truthy(hammer != null, "construction creates hammer pivot")
assertions.truthy(hammer_sprite != null, "construction creates hammer sprite")
if hammer != null and hammer_sprite != null:
	assertions.truthy(hammer.visible, "unfinished construction shows hammer")
	assertions.truthy(hammer_sprite.texture != null, "hammer uses imported icon")
	var starting_rotation := hammer.rotation.z
	instance._animate_construction_hammer(0.2)
	assertions.truthy(not is_equal_approx(hammer.rotation.z, starting_rotation), "hammer swings while construction runs")
	instance.set_preview_mode(true)
	assertions.truthy(not hammer.visible, "building preview hides construction hammer")
	instance.set_preview_mode(false)
	assertions.truthy(hammer.visible, "leaving preview restores unfinished hammer")
```

After completion add:

```gdscript
if hammer != null:
	assertions.truthy(not hammer.visible, "completed construction hides hammer")
```

- [ ] **Step 2: Run the building suite and verify RED**

Run the building suite. Expected: FAIL for the missing SVG resource and missing `VisualRoot/ConstructionHammer` nodes.

- [ ] **Step 3: Add the shared transparent SVG asset**

Create `assets/buildings/construction/construction_hammer.svg` with:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="wood" x1="0" x2="1">
      <stop offset="0" stop-color="#6b3519"/>
      <stop offset="0.45" stop-color="#d58a3f"/>
      <stop offset="1" stop-color="#713819"/>
    </linearGradient>
    <linearGradient id="iron" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#eef1ed"/>
      <stop offset="0.45" stop-color="#aeb6b2"/>
      <stop offset="1" stop-color="#555e5e"/>
    </linearGradient>
  </defs>
  <path d="M58 42 L72 42 L78 116 Q77 123 69 124 L62 124 Q55 122 56 115 Z" fill="url(#wood)" stroke="#4b2a18" stroke-width="4" stroke-linejoin="round"/>
  <path d="M18 24 Q18 15 28 13 L94 13 Q103 14 104 23 L103 38 Q101 45 93 45 L28 45 Q18 43 18 35 Z" fill="url(#iron)" stroke="#3f4849" stroke-width="5"/>
  <path d="M101 20 L118 26 L118 35 L102 40 Z" fill="#697273" stroke="#3f4849" stroke-width="4" stroke-linejoin="round"/>
  <path d="M27 19 L68 19" fill="none" stroke="#ffffff" stroke-opacity="0.65" stroke-width="4" stroke-linecap="round"/>
  <path d="M62 51 L69 51 L73 105" fill="none" stroke="#f0b46c" stroke-opacity="0.55" stroke-width="4" stroke-linecap="round"/>
</svg>
```

- [ ] **Step 4: Implement hammer nodes, sizing, animation, and visibility**

Add constants and phase state:

```gdscript
const CONSTRUCTION_HAMMER_PATH := "res://assets/buildings/construction/construction_hammer.svg"
const HAMMER_SWING_PERIOD := 0.8
const HAMMER_SWING_MIN := deg_to_rad(-25.0)
const HAMMER_SWING_MAX := deg_to_rad(22.0)

var _hammer_phase := 0.0
```

In `_ensure_nodes()` create the pivot and sprite before physics nodes:

```gdscript
if visual_root.get_node_or_null("ConstructionHammer") == null:
	var hammer := Node3D.new()
	hammer.name = "ConstructionHammer"
	visual_root.add_child(hammer)
	var hammer_sprite := Sprite3D.new()
	hammer_sprite.name = "HammerSprite"
	hammer.add_child(hammer_sprite)
```

At the end of `_configure_visuals()` call `_configure_construction_hammer()`. Add:

```gdscript
func _configure_construction_hammer() -> void:
	var hammer := get_node("VisualRoot/ConstructionHammer") as Node3D
	var sprite := hammer.get_node("HammerSprite") as Sprite3D
	var texture := _load_texture(CONSTRUCTION_HAMMER_PATH)
	sprite.texture = texture
	if texture == null:
		hammer.visible = false
		push_warning("Missing construction hammer art '%s'." % CONSTRUCTION_HAMMER_PATH)
		return
	var desired_height := clampf(minf(data.visual_size.x, data.visual_size.y) * 0.24, 0.28, 0.5)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.pixel_size = desired_height / float(texture.get_height())
	sprite.position.y = desired_height * 0.42
	sprite.sorting_offset = 0.35
	hammer.position = Vector3(data.visual_size.x * 0.38, data.visual_size.y * 0.88, 0.08)
	_update_construction_hammer_visibility()


func _update_construction_hammer_visibility() -> void:
	var hammer := get_node_or_null("VisualRoot/ConstructionHammer") as Node3D
	if hammer == null:
		return
	var sprite := hammer.get_node_or_null("HammerSprite") as Sprite3D
	hammer.visible = (
		not _preview_mode
		and not is_construction_complete()
		and sprite != null
		and sprite.texture != null
	)


func _animate_construction_hammer(delta: float) -> void:
	var hammer := get_node_or_null("VisualRoot/ConstructionHammer") as Node3D
	if hammer == null or not hammer.visible or delta <= 0.0:
		return
	_hammer_phase = fmod(_hammer_phase + delta / HAMMER_SWING_PERIOD, 1.0)
	var weight := (sin(_hammer_phase * TAU) + 1.0) * 0.5
	hammer.rotation.z = lerpf(HAMMER_SWING_MIN, HAMMER_SWING_MAX, weight)
```

Call `_update_construction_hammer_visibility()` from `set_preview_mode()` and `_apply_construction_stage()`. In `deactivate()`, explicitly set the hammer pivot's `visible` property to `false` before disabling processing. Call `_animate_construction_hammer(delta)` in `_process(delta)` after construction advancement and before the preview early return.

- [ ] **Step 5: Import assets and verify GREEN**

Run:

```powershell
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: the SVG imports as `Texture2D`; timing, hammer animation, completion visibility, and existing transition checks all pass.

- [ ] **Step 6: Commit the hammer change**

```powershell
git add assets/buildings/construction/construction_hammer.svg scripts/buildings/building_instance.gd tests/test_building_art_assets.gd tests/test_building_construction_state.gd
git commit -m "feat: show swinging hammer during construction"
```

### Task 3: Visual Contract

**Files:**
- Modify: `tests/test_building_visual_scene.gd`
- Modify: `tests/visual/building_system_verification.gd:392-411`

- [ ] **Step 1: Extend the visual scene test and verify RED**

Add `"VisualRoot/ConstructionHammer"` to `required_path` in `tests/test_building_visual_scene.gd`. In the `FRAME` branch add:

```gdscript
var hammer := building.get_node("VisualRoot/ConstructionHammer") as Node3D
if not hammer.visible:
	push_error("frame construction demo must show swinging hammer")
	instance.free()
	quit(1)
	return
hammer.visible = false
if bool(instance.call("_construction_contract_passes")):
	push_error("building visual contract must reject a hidden construction hammer")
	instance.free()
	quit(1)
	return
hammer.visible = true
```

Run:

```powershell
godot --headless --path . --script res://tests/test_building_visual_scene.gd
```

Expected: FAIL with `building visual contract must reject a hidden construction hammer` because `_construction_contract_passes()` does not yet include the hammer requirement.

- [ ] **Step 2: Add hammer visibility to the interactive verifier contract**

In `_construction_contract_passes()` add:

```gdscript
var hammer := _active_construction.get_node("VisualRoot/ConstructionHammer") as Node3D
```

Change the completion return to:

```gdscript
return interaction.collision_layer == (64 | 256) and not construction_layer.visible and not hammer.visible
```

Add `and hammer.visible` to the unfinished return expression immediately after `construction_layer.visible`.

- [ ] **Step 3: Run building and visual tests**

Run:

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/test_building_visual_scene.gd
```

Expected: timing and save-migration coverage remain green, and the visual construction demo exposes a visible hammer that is required by its contract.

- [ ] **Step 4: Commit visual coverage**

```powershell
git add tests/test_building_visual_scene.gd tests/visual/building_system_verification.gd
git commit -m "test: verify timed construction feedback"
```

### Task 4: Full Regression and Visual Acceptance

**Files:**
- Modify only if a verified regression requires a scoped correction.

- [ ] **Step 1: Parse the complete project**

```powershell
godot --headless --editor --path . --quit
```

Expected: exit code 0 with no parse or resource import errors.

- [ ] **Step 2: Run subsystem and main integration suites**

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path . --script res://tests/test_player_grid_binding.gd
```

Expected: every command exits 0 and reports PASS.

- [ ] **Step 3: Run visual contracts and capture a fresh image**

```powershell
godot --headless --path . --script res://tests/test_building_visual_scene.gd
godot --path . --script res://tests/capture_building_visual.gd
```

Expected: the visual contract passes and `/tmp/villa-building-system-verification.png` is regenerated at 1600×1000.

- [ ] **Step 4: Inspect the screenshot and repository state**

Open `/tmp/villa-building-system-verification.png` at original resolution. Confirm the active construction uses the frame-stage art, the hammer is above its upper-right edge without covering the building, and the completed gallery has no hammers.

Run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors and no uncommitted implementation files.

- [ ] **Step 5: Commit only a verified final correction**

If Step 1–4 required a scoped correction, stage only the corrected files, inspect them with `git diff --cached --name-only`, and commit:

```powershell
git commit -m "fix: finalize construction timing feedback"
```

If no correction was required, do not create an empty commit.
