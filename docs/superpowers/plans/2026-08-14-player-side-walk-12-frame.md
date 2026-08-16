# Player Side Walk 12-Frame Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the discontinuous seven-pose lateral walk with a biomechanically coherent, hand-painted 12-frame east/west loop whose limb identities remain stable.

**Architecture:** Build one authored east-facing 12-frame row, assemble and validate it through a reproducible Godot image tool, then derive the west row by exact horizontal mirroring. `PlayerVisual` owns only playback and atlas slicing; biomechanical, transparency, mirroring, baseline, and temporal-continuity contracts stay in `test_player_visual.gd`.

**Tech Stack:** Godot 4.7 GDScript, `Image`/`AtlasTexture`/`SpriteFrames`, built-in image generation for painted raster poses, PNG alpha assets, existing custom test runners.

---

### Task 1: Lock the 12-frame asset and playback contracts

**Files:**
- Modify: `tests/test_player_visual.gd:5-365`
- Modify: `scripts/visual/player_visual.gd:1-115`

- [x] **Step 1: Replace seven-pose assertions with failing 12-frame assertions**

Change the side-walk contract to require 12 columns, 2 rows, exact mirroring, stable baseline, and 12 frames in both side animations:

```gdscript
const SIDE_WALK_FRAME_COUNT := 12

func _assert_side_walk_art_contract(assertions: TestAssert) -> void:
	var texture := load(SIDE_WALK_PATH) as Texture2D
	assertions.truthy(texture != null, "twelve-frame side-walk atlas imports")
	if texture == null:
		return
	var image := texture.get_image()
	assertions.equal(image.get_size(), Vector2i(2304, 384), "side walk is a 12x2 atlas")
	var cell_size := Vector2i(192, 192)
	for row in 2:
		for column in SIDE_WALK_FRAME_COUNT:
			var bounds := _frame_used_rect(image, cell_size, row, column)
			assertions.truthy(bounds.size.x > 0 and bounds.size.y > 0, "side pose %d/%d is painted" % [row, column])
			assertions.truthy(bounds.end.y in range(182, 187), "side pose %d/%d keeps the planted baseline" % [row, column])
	for column in SIDE_WALK_FRAME_COUNT:
		var east := image.get_region(Rect2i(Vector2i(column * 192, 0), cell_size))
		var west := image.get_region(Rect2i(Vector2i(column * 192, 192), cell_size))
		east.flip_x()
		assertions.truthy(_images_equal(east, west), "west pose %d exactly mirrors east" % column)
```

Update animation checks:

```gdscript
for direction in ["e", "w"]:
	var animation_name := PlayerVisual.walk_animation_name(direction)
	assertions.equal(visual.sprite_frames.get_frame_count(animation_name), 12, "%s uses twelve poses" % direction)
	assertions.near(visual.sprite_frames.get_animation_speed(animation_name), 12.0, 0.001, "%s walks at 12 FPS" % direction)
```

- [x] **Step 2: Add half-cycle and loop-boundary continuity assertions**

Replace the old seven-frame alternation assumptions with symmetric pairs and include frame 11→0:

```gdscript
func _assert_twelve_frame_side_gait(frames: SpriteFrames, animation_name: String, assertions: TestAssert) -> void:
	var poses: Array[Image] = []
	for frame_index in 12:
		var pose := _frame_image(frames.get_frame_texture(animation_name, frame_index))
		pose.resize(48, 48, Image.INTERPOLATE_LANCZOS)
		poses.append(pose)
	var adjacent_differences: Array[int] = []
	for frame_index in 12:
		adjacent_differences.append(_lower_body_silhouette_difference(poses[frame_index], poses[(frame_index + 1) % 12]))
	assertions.truthy(adjacent_differences.min() >= 12, "side gait has no duplicated adjacent pose: %s" % adjacent_differences)
	assertions.truthy(adjacent_differences.max() <= 105, "side gait has no single-frame leg jump: %s" % adjacent_differences)
	for frame_index in 6:
		assertions.truthy(
			_lower_body_silhouette_difference(poses[frame_index], poses[frame_index + 6]) >= 20,
			"pose %d has a distinct opposite-leg half-cycle partner" % frame_index
		)
```

- [x] **Step 3: Run the player visual suite and verify RED**

Run:

```powershell
godot --path . --headless -s res://tests/run_tests.gd
```

Expected: FAIL because the current image is `1344×384`, the side animations contain 7 frames, and the atlas does not satisfy the 12-frame contract.

- [x] **Step 4: Change only the playback constants needed for the new contract**

In `player_visual.gd` use:

```gdscript
const SIDE_WALK_FRAME_COUNT := 12
const SIDE_WALK_FPS := 12.0
```

Validate the raster with `Vector2(SIDE_WALK_FRAME_COUNT * cell_size.x, 2 * cell_size.y)`. Leave sprint scaling unchanged in this task so Task 4 can introduce it test-first.

```gdscript
if side_walk == null or side_walk.get_size() != Vector2(
	SIDE_WALK_FRAME_COUNT * cell_size.x,
	2 * cell_size.y
):
	push_error("PlayerVisual requires valid twelve-frame side walk '%s'." % SIDE_WALK_PATH)
	return false
```

Expected: tests still fail only on the old raster dimensions/art contract.

- [x] **Step 5: Commit the executable contract**

```powershell
git add scripts/visual/player_visual.gd tests/test_player_visual.gd
git commit -m "test: require twelve-frame lateral gait"
```

---

### Task 2: Produce the twelve east-facing painted poses

**Files:**
- Reference: `assets/characters/player/player_farmer_side_walk.png`
- Reference: `assets/characters/player/player_farmer_atlas.png`
- Temporary: `tmp/player-side-walk/east-contact-sheet.png`
- Temporary: `tmp/player-side-walk/east-00.png` through `east-11.png`

- [x] **Step 1: Generate a single coherent 4×3 east-facing contact sheet**

Use the built-in image generation edit flow with the current side-walk PNG as the edit/style target. The prompt must preserve identity while requesting the exact gait:

```text
Use case: precise-object-edit
Asset type: hand-painted 2D game-character animation contact sheet
Primary request: rebuild the farmer's side-view walk as exactly 12 sequential east-facing poses arranged left-to-right, top-to-bottom in a clean 4x3 grid.
Input image: edit target and strict identity/style reference.
Pose sequence: 0 right heel contact; 1 right loading; 2 right support with left foot lifting; 3 left leg passing; 4 left knee high; 5 left foot extending; 6 left heel contact; 7 left loading; 8 left support with right foot lifting; 9 right leg passing; 10 right knee high; 11 right foot extending back into frame 0.
Constraints: right and left leg identities never swap; arms counter-swing; same straw hat, face, hair, white shirt, blue overalls, brown boots, proportions, camera, lighting, and hand-painted style in every panel; character faces right in every panel; one complete character centered in every equal cell; stable foot baseline and scale.
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background, identical in every cell, no shadows or gradients.
Avoid: standing pose, duplicated pose, extra limbs, ghost limbs, cropped hat or boots, panel dividers touching the character, labels, text, watermark.
```

- [x] **Step 2: Inspect the generated sheet before extracting frames**

Use `view_image` at original detail. Reject and regenerate if any of these are visible:

- p0→p1→p2 changes the forward leg from right to left;
- p2→p5 fails to keep the right leg as the support leg;
- p6 is not the opposite-leg equivalent of p0;
- arms swing with the same-side leg;
- face, hat, torso width, boot design, scale, or baseline changes;
- any cell contains multiple characters, fragments, text, or a nonuniform background.

- [x] **Step 3: Remove the chroma key and split the approved 4×3 source**

Copy the approved output to `tmp/player-side-walk/east-contact-sheet.png`, run the installed chroma removal helper, then split its 4×3 cells into `east-00.png`…`east-11.png`. Each extracted frame must retain alpha and contain exactly one character. Inspect all twelve extracted images at original detail. Do not commit `tmp/` inputs.

---

### Task 3: Add a reproducible atlas assembler and create the final PNG

**Files:**
- Create: `scripts/tools/assemble_player_side_walk.gd`
- Create: `scripts/tools/assemble_player_side_walk.gd.uid`
- Modify: `assets/characters/player/player_farmer_side_walk.png`
- Test: `tests/test_player_visual.gd`

- [x] **Step 1: Add the deterministic assembly tool**

Create a `SceneTree` script that reads exactly twelve transparent east frames, normalizes each into a `192×192` cell without stretching, writes row 0, horizontally flips each cell into row 1, and saves the `2304×384` atlas:

```gdscript
extends SceneTree

const FRAME_SIZE := Vector2i(192, 192)
const FRAME_COUNT := 12
const INPUT_DIR := "res://tmp/player-side-walk/frames"
const OUTPUT_PATH := "res://assets/characters/player/player_farmer_side_walk.png"

func _init() -> void:
	var sources: Array[Image] = []
	var maximum_bounds := Vector2i.ZERO
	for index in FRAME_COUNT:
		var source := Image.load_from_file(ProjectSettings.globalize_path(
			INPUT_DIR.path_join("east-%02d.png" % index)
		))
		if source == null or source.is_empty() or not _has_transparent_corners(source):
			push_error("Missing east frame %02d" % index)
			quit(1)
			return
		var used := source.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			push_error("Empty east frame %02d" % index)
			quit(1)
			return
		maximum_bounds = maximum_bounds.max(used.size)
		sources.append(source)
	var common_scale := minf(178.0 / maximum_bounds.x, 178.0 / maximum_bounds.y)
	var output := Image.create_empty(FRAME_SIZE.x * FRAME_COUNT, FRAME_SIZE.y * 2, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for index in FRAME_COUNT:
		var frame := _fit_into_cell(sources[index], common_scale)
		output.blit_rect(frame, Rect2i(Vector2i.ZERO, FRAME_SIZE), Vector2i(index * FRAME_SIZE.x, 0))
		var west := frame.duplicate()
		west.flip_x()
		output.blit_rect(west, Rect2i(Vector2i.ZERO, FRAME_SIZE), Vector2i(index * FRAME_SIZE.x, FRAME_SIZE.y))
	var error := output.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	quit(0 if error == OK else 1)

func _fit_into_cell(source: Image, common_scale: float) -> Image:
	var used := source.get_used_rect()
	var crop := source.get_region(used)
	crop.resize(maxi(1, roundi(crop.get_width() * common_scale)), maxi(1, roundi(crop.get_height() * common_scale)), Image.INTERPOLATE_LANCZOS)
	var cell := Image.create_empty(192, 192, false, Image.FORMAT_RGBA8)
	cell.fill(Color.TRANSPARENT)
	var origin := Vector2i((192 - crop.get_width()) / 2, 184 - crop.get_height())
	cell.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), origin)
	return cell

func _has_transparent_corners(source: Image) -> bool:
	for point in [Vector2i.ZERO, Vector2i(source.get_width() - 1, 0), Vector2i(0, source.get_height() - 1), source.get_size() - Vector2i.ONE]:
		if source.get_pixelv(point).a > 0.05:
			return false
	return true
```

The implementation must reject an empty/opaque-corner frame and must not overwrite the output unless all 12 inputs validate.

- [x] **Step 2: Assemble the final atlas**

Run:

```powershell
godot --path . --headless -s res://scripts/tools/assemble_player_side_walk.gd
```

Expected: exit 0 and `player_farmer_side_walk.png` becomes exactly `2304×384` with 12 east frames and 12 deterministic west mirrors.

- [x] **Step 3: Run the player visual tests and iterate on art, not thresholds**

Run:

```powershell
godot --path . --headless -s res://tests/run_tests.gd
```

Expected: the 12-frame dimensions, mirror, connected-component, alpha, baseline, half-cycle, and adjacency checks pass. If continuity fails, correct the offending painted pose; do not weaken the agreed thresholds merely to accept a jump.

- [x] **Step 4: Commit the assembled art and reproducible tool**

```powershell
git add assets/characters/player/player_farmer_side_walk.png assets/characters/player/player_farmer_side_walk.png.import scripts/tools/assemble_player_side_walk.gd scripts/tools/assemble_player_side_walk.gd.uid tests/test_player_visual.gd
git commit -m "feat: rebuild lateral walk as twelve poses"
```

---

### Task 4: Verify runtime walk/run timing and regressions

**Files:**
- Modify: `tests/test_player_visual.gd`
- Modify: `scripts/visual/player_visual.gd`

- [x] **Step 1: Add a failing runtime sprint-speed test**

```gdscript
visual.sync_motion(Vector2.RIGHT * 3.0, false, true)
assertions.equal(visual.animation, &"walk_e", "east movement selects lateral walk")
assertions.near(visual.speed_scale, 1.0, 0.001, "east walk plays twelve frames at 12 FPS")
visual.sync_motion(Vector2.RIGHT * 5.0, true, true)
assertions.near(visual.speed_scale, 1.5, 0.001, "east sprint plays twelve frames at 18 FPS")
visual.sync_motion(Vector2.ZERO, false, true)
assertions.truthy(str(visual.animation).begins_with("idle_"), "stopping returns to separate idle art")
```

- [x] **Step 2: Run the test and verify RED if side sprint still uses generic `RUN_FPS`**

Run:

```powershell
godot --path . --headless -s res://tests/run_tests.gd
```

Expected before final playback implementation: FAIL with side sprint speed `0.75` or another non-`1.5` value.

- [x] **Step 3: Complete side-specific runtime speed selection**

Use `SIDE_RUN_FPS / SIDE_WALK_FPS` only for east/west and preserve `RUN_FPS / WALK_FPS` for the other six directions. Do not change `PlayerController.speed`, sprint speed, collision, or movement math.

```gdscript
const SIDE_RUN_FPS := 18.0

func sync_motion(planar_velocity: Vector2, sprinting: bool, on_floor: bool) -> void:
	# Existing direction and airborne handling remains unchanged.
	if moving:
		var movement_animation := StringName(walk_animation_name(_last_direction))
		var is_side_direction := _last_direction in ["e", "w"]
		var base_fps := SIDE_WALK_FPS if is_side_direction else WALK_FPS
		var run_fps := SIDE_RUN_FPS if is_side_direction else RUN_FPS
		var movement_speed := run_fps / base_fps if sprinting else 1.0
		_play_if_needed(movement_animation, movement_speed)
		return
```

- [x] **Step 4: Run focused and integration suites**

Run:

```powershell
godot --path . --headless -s res://tests/run_tests.gd
godot --path . --headless -s res://tests/run_main_gameplay_integration_tests.gd
```

Expected: both exit 0 with no new script errors or player-scene regressions.

- [x] **Step 5: Commit runtime playback**

```powershell
git add scripts/visual/player_visual.gd tests/test_player_visual.gd
git commit -m "feat: play twelve-frame side gait"
```

---

### Task 5: Capture and review the final gait

**Files:**
- Create: `tests/capture_player_side_walk.gd`
- Create: `tests/capture_player_side_walk.gd.uid`
- Create: `docs/validation/player-side-walk-12-frame-validation.md`
- Modify: `docs/superpowers/plans/2026-08-14-player-side-walk-12-frame.md`

- [x] **Step 1: Create a deterministic capture runner**

The runner must render:

1. a numbered 12-frame east strip;
2. a numbered 12-frame west strip;
3. six half-cycle comparison pairs (`0/6` through `5/11`);
4. in-game east walk at 12 FPS;
5. in-game east sprint at 18 FPS;
6. in-game west walk and sprint.

Write PNG outputs under `res://.godot/player-side-walk-validation/`; do not commit generated captures.

- [x] **Step 2: Run deterministic captures**

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility -s res://tests/capture_player_side_walk.gd
```

Expected: exit 0 and all required images are present at their declared dimensions.

- [x] **Step 3: Review every transition at original resolution**

Inspect the strip and gameplay images with `view_image`. Explicitly verify `0→1→2`, `2→3→4→5`, `5→6→7`, `8→9→10→11`, and `11→0`. Reject any leg identity swap, foot sliding, baseline jump, duplicate pose, scale change, ghost limb, or broken mirror.

- [x] **Step 4: Run the full project regression suite**

```powershell
godot --path . --headless -s res://tests/run_tests.gd
godot --path . --headless -s res://tests/run_grid_system_tests.gd
godot --path . --headless -s res://tests/run_farming_system_tests.gd
godot --path . --headless -s res://tests/run_building_system_tests.gd
godot --path . --headless -s res://tests/run_economy_system_tests.gd
godot --path . --headless -s res://tests/run_economy_ui_tests.gd
godot --path . --headless -s res://tests/run_main_gameplay_integration_tests.gd
git diff --check
```

Expected: every runner exits 0; only documented pre-existing warning fixtures remain; `git diff --check` has no output.

- [ ] **Step 5: Record validation and commit**

Record exact PASS counts, output paths, reviewed transitions, 12/18 FPS results, and any known non-blocking warnings in `docs/validation/player-side-walk-12-frame-validation.md`. Mark all plan checkboxes complete, then commit:

```powershell
git add tests/capture_player_side_walk.gd tests/capture_player_side_walk.gd.uid docs/validation/player-side-walk-12-frame-validation.md docs/superpowers/plans/2026-08-14-player-side-walk-12-frame.md
git commit -m "docs: validate twelve-frame side walk"
```

---

## Completion checklist

- [x] The side walk atlas is `2304×384` and contains no idle pose.
- [x] East has 12 distinct, sequential gait poses; west is its exact mirror.
- [x] Limb identities remain stable through all adjacent frames and the loop boundary.
- [x] Walk plays at 12 FPS and side sprint at 18 FPS without changing movement physics.
- [x] Character identity, baseline, scale, transparency, and hand-painted style remain stable.
- [x] Focused, integration, full regression, and visual-capture checks all pass.
