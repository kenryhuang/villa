# Player Side-Walk Scale and Color Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize every side-walk pose to the established 151-pixel player height and transfer the original side-view dark-denim palette without changing gait anatomy or runtime behavior.

**Architecture:** Extend the existing player visual contract with reference-based height and denim measurements, then make the deterministic side-walk assembler normalize every source independently to the same height and apply bounded per-frame denim channel gains derived from the original east-facing atlas. Continue deriving west by exact mirroring and validate the result with a new direction-comparison capture.

**Tech Stack:** Godot 4.7 GDScript `Image` APIs, PNG sprite atlases, the existing custom `TestAssert` runner, deterministic viewport captures.

---

### Task 1: Add the Failing Scale and Denim Contract

**Files:**
- Modify: `tests/test_player_visual.gd:5-260`
- Test: `assets/characters/player/player_farmer_atlas.png`
- Test: `assets/characters/player/player_farmer_side_walk.png`

- [x] **Step 1: Add shared visual reference constants**

Add these constants beside `SIDE_WALK_FRAME_COUNT`:

```gdscript
const FRAME_SIZE := Vector2i(192, 192)
const TARGET_CHARACTER_HEIGHT := 151
const REFERENCE_EAST_ROW := 2
const REFERENCE_WALK_START_COLUMN := 2
const REFERENCE_WALK_FRAME_COUNT := 6
const DENIM_LUMINANCE_TOLERANCE := 4.0 / 255.0
const DENIM_CHANNEL_TOLERANCE := 10.0 / 255.0
```

- [x] **Step 2: Add denim measurement helpers**

Add deterministic helpers after `_frame_used_rect`:

```gdscript
func _is_denim_pixel(color: Color) -> bool:
	return (
		color.a > 0.10
		and color.b > 45.0 / 255.0
		and color.b - color.r > 15.0 / 255.0
		and color.g - color.r > 5.0 / 255.0
	)


func _denim_mean(image: Image, regions: Array[Rect2i]) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for region in regions:
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var color := image.get_pixel(x, y)
				if not _is_denim_pixel(color):
					continue
				total += Vector3(color.r, color.g, color.b)
				count += 1
	return total / float(maxi(1, count))


func _luminance(color: Vector3) -> float:
	return color.x * 0.2126 + color.y * 0.7152 + color.z * 0.0722
```

- [x] **Step 3: Assert exact height and reference denim alignment**

Inside `_assert_side_walk_art_contract`, load the original atlas image before iterating side frames. Build six original east reference regions and twelve side regions:

```gdscript
var reference_texture := load(ATLAS_PATH) as Texture2D
var reference_image := reference_texture.get_image()
var reference_regions: Array[Rect2i] = []
for column in REFERENCE_WALK_FRAME_COUNT:
	reference_regions.append(Rect2i(
		Vector2i(
			(REFERENCE_WALK_START_COLUMN + column) * FRAME_SIZE.x,
			REFERENCE_EAST_ROW * FRAME_SIZE.y
		),
		FRAME_SIZE
	))
var side_regions: Array[Rect2i] = []
for column in SIDE_WALK_FRAME_COUNT:
	side_regions.append(Rect2i(Vector2i(column * FRAME_SIZE.x, 0), FRAME_SIZE))
```

Replace the loose baseline-only size check with:

```gdscript
assertions.equal(
	bounds.size.y,
	TARGET_CHARACTER_HEIGHT,
	"side pose %d/%d matches the established player height" % [row, column]
)
assertions.equal(
	bounds.end.y,
	184,
	"side pose %d/%d keeps the planted baseline" % [row, column]
)
```

After exact mirror assertions, compare aggregate colors:

```gdscript
var reference_denim := _denim_mean(reference_image, reference_regions)
var side_denim := _denim_mean(image, side_regions)
assertions.near(
	_luminance(side_denim),
	_luminance(reference_denim),
	DENIM_LUMINANCE_TOLERANCE,
	"side-walk denim matches original east luminance"
)
for channel in 3:
	assertions.near(
		side_denim[channel],
		reference_denim[channel],
		DENIM_CHANNEL_TOLERANCE,
		"side-walk denim channel %d matches original east" % channel
	)
```

- [x] **Step 4: Run the focused suite and verify RED**

Run:

```powershell
godot --headless --path . --log-file .godot\side-scale-color-red.log -s res://tests/run_tests.gd
```

Expected: FAIL because current side frames are 177-182 pixels tall instead of 151, and their denim luminance is about 103.3 instead of 63.2.

- [x] **Step 5: Commit the failing contract**

```powershell
git add tests/test_player_visual.gd
git commit -m "test: require aligned side-walk scale and denim"
```

### Task 2: Normalize Scale and Transfer Denim in the Assembler

**Files:**
- Modify: `scripts/tools/assemble_player_side_walk.gd:1-140`
- Modify: `assets/characters/player/player_farmer_side_walk.png`
- Test: `tests/test_player_visual.gd`

- [x] **Step 1: Replace common maximum scaling with the fixed target contract**

Replace `MAX_CHARACTER_SIZE`, `ANCHOR_FRAMES`, and `FRAME_SCALE_ADJUSTMENTS` with:

```gdscript
const TARGET_CHARACTER_HEIGHT := 151
const REFERENCE_ATLAS_PATH := "res://assets/characters/player/player_farmer_atlas.png"
const REFERENCE_EAST_ROW := 2
const REFERENCE_WALK_START_COLUMN := 2
const REFERENCE_WALK_FRAME_COUNT := 6
const MIN_DENIM_GAIN := 0.45
const MAX_DENIM_GAIN := 1.20
const FRAME_X_OFFSETS := [0, -6, 0, 0, 0, -3, 0, 0, 0, 2, 0, 0]
```

Load the original atlas before processing side frames and fail if it is missing:

```gdscript
var reference_atlas := Image.load_from_file(ProjectSettings.globalize_path(REFERENCE_ATLAS_PATH))
if reference_atlas == null or reference_atlas.is_empty():
	_fail("Missing player reference atlas '%s'." % REFERENCE_ATLAS_PATH)
	return
var reference_denim := _reference_denim_mean(reference_atlas)
```

Remove `maximum_bounds` and the special anchor-size branch. Every source must only be nonempty and have transparent corners.

- [x] **Step 2: Add deterministic denim selection and measurement**

Add:

```gdscript
func _is_denim_pixel(color: Color) -> bool:
	return (
		color.a > 0.10
		and color.b > 45.0 / 255.0
		and color.b - color.r > 15.0 / 255.0
		and color.g - color.r > 5.0 / 255.0
	)


func _denim_mean(image: Image, region: Rect2i) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var color := image.get_pixel(x, y)
			if _is_denim_pixel(color):
				total += Vector3(color.r, color.g, color.b)
				count += 1
	return total / float(maxi(1, count))


func _reference_denim_mean(atlas: Image) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for column in REFERENCE_WALK_FRAME_COUNT:
		var region := Rect2i(
			Vector2i(
				(REFERENCE_WALK_START_COLUMN + column) * FRAME_SIZE.x,
				REFERENCE_EAST_ROW * FRAME_SIZE.y
			),
			FRAME_SIZE
		)
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var color := atlas.get_pixel(x, y)
				if _is_denim_pixel(color):
					total += Vector3(color.r, color.g, color.b)
					count += 1
	return total / float(maxi(1, count))
```

- [x] **Step 3: Add bounded per-frame color transfer**

Add:

```gdscript
func _match_denim(source: Image, target: Vector3) -> void:
	var source_mean := _denim_mean(source, Rect2i(Vector2i.ZERO, source.get_size()))
	var gains := Vector3(
		clampf(target.x / maxf(source_mean.x, 0.001), MIN_DENIM_GAIN, MAX_DENIM_GAIN),
		clampf(target.y / maxf(source_mean.y, 0.001), MIN_DENIM_GAIN, MAX_DENIM_GAIN),
		clampf(target.z / maxf(source_mean.z, 0.001), MIN_DENIM_GAIN, MAX_DENIM_GAIN)
	)
	for y in source.get_height():
		for x in source.get_width():
			var color := source.get_pixel(x, y)
			if not _is_denim_pixel(color):
				continue
			color.r = clampf(color.r * gains.x, 0.0, 1.0)
			color.g = clampf(color.g * gains.y, 0.0, 1.0)
			color.b = clampf(color.b * gains.z, 0.0, 1.0)
			source.set_pixel(x, y, color)
```

Call `_match_denim(source, reference_denim)` on a duplicate of each loaded source before resizing.

- [x] **Step 4: Normalize every pose independently to 151 pixels**

Replace `_fit_into_cell(source, common_scale)` with:

```gdscript
func _fit_into_cell(source: Image) -> Image:
	var used := source.get_used_rect()
	var crop := source.get_region(used)
	var scale := float(TARGET_CHARACTER_HEIGHT) / float(crop.get_height())
	crop.resize(
		maxi(1, roundi(crop.get_width() * scale)),
		TARGET_CHARACTER_HEIGHT,
		Image.INTERPOLATE_LANCZOS
	)
	var cell := Image.create_empty(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	cell.fill(Color.TRANSPARENT)
	var origin := Vector2i(
		(FRAME_SIZE.x - crop.get_width()) / 2,
		BASELINE_Y - TARGET_CHARACTER_HEIGHT
	)
	cell.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), origin)
	return cell
```

Build every frame with `_fit_into_cell(sources[index])`, then apply the recalibrated horizontal offset and mirror it.

- [x] **Step 5: Assemble, import, and run the focused suite**

Run:

```powershell
godot --headless --path . --log-file .godot\assemble-side-scale-color.log -s res://scripts/tools/assemble_player_side_walk.gd
godot --headless --path . --log-file .godot\import-side-scale-color.log --import
godot --headless --path . --log-file .godot\side-scale-color-green.log -s res://tests/run_tests.gd
```

Expected: assembly PASS, imported atlas remains 2304 by 384, and the focused suite passes all scale, color, mirror, baseline, gait, and runtime assertions.

- [x] **Step 6: Commit the deterministic correction**

```powershell
git add scripts/tools/assemble_player_side_walk.gd assets/characters/player/player_farmer_side_walk.png
git commit -m "fix: align side-walk scale and denim"
```

### Task 3: Add a Direction-Comparison Capture

**Files:**
- Modify: `tests/capture_player_side_walk.gd:1-220`
- Generated: `.godot/player-side-walk-validation/direction-scale-color.png`

- [x] **Step 1: Add the fifth capture to `_capture_all`**

After the existing runtime capture, add:

```gdscript
if await _capture_direction_comparison(visual):
	captures += 1
```

Change the expected capture count from four to five.

- [x] **Step 2: Render south, original east, and revised east at identical cell scale**

Add `_capture_direction_comparison`. Use six columns and three labeled rows. Row one uses `walk_s` frames 0-5, row two reads original east cells from the main atlas at row 2 and columns 2-7, and row three uses revised `walk_e` frames `[0, 2, 4, 6, 8, 10]`. Save the result as `direction-scale-color.png` at 1152 by 690:

```gdscript
func _capture_direction_comparison(visual: PlayerVisual) -> bool:
	const SAMPLE_COUNT := 6
	const ROW_HEIGHT := 230
	var size := Vector2i(FRAME_SIZE.x * SAMPLE_COUNT, ROW_HEIGHT * 3)
	var canvas := _new_canvas(size)
	var atlas := load(ATLAS_PATH) as Texture2D
	var labels := ["SOUTH WALK", "ORIGINAL EAST REFERENCE", "REVISED EAST WALK"]
	var revised_indices := [0, 2, 4, 6, 8, 10]
	for row in 3:
		_add_label(canvas, labels[row], Rect2(10, row * ROW_HEIGHT + 4, size.x - 20, 30), 20, HORIZONTAL_ALIGNMENT_CENTER)
		for column in SAMPLE_COUNT:
			var texture: Texture2D
			if row == 0:
				texture = visual.sprite_frames.get_frame_texture(&"walk_s", column)
			elif row == 1:
				texture = _atlas_frame(atlas, Vector2i(192, 192), 2, 2 + column)
			else:
				texture = visual.sprite_frames.get_frame_texture(&"walk_e", revised_indices[column])
			_add_frame(canvas, texture, Vector2(column * FRAME_SIZE.x, row * ROW_HEIGHT + 38), FRAME_SIZE)
	return await _save_canvas(canvas, size, "direction-scale-color.png")
```

Add a local `_atlas_frame` helper matching `PlayerVisual._atlas_frame`, setting `filter_clip = true`.

- [x] **Step 3: Generate and inspect all captures**

Run:

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility --log-file .godot\capture-side-scale-color.log -s res://tests/capture_player_side_walk.gd
```

Expected: five captures pass. Inspect `direction-scale-color.png` and `east-strip.png`. Revised east frames must match south/original-east height and dark-denim character while retaining the approved gait.

- [x] **Step 4: Commit capture coverage**

```powershell
git add tests/capture_player_side_walk.gd
git commit -m "test: capture side-walk visual alignment"
```

### Task 4: Revalidate and Document the Aligned Atlas

**Files:**
- Modify: `docs/validation/player-side-walk-12-frame-validation.md`
- Modify: `docs/superpowers/plans/2026-08-16-player-side-walk-scale-color-alignment.md`

- [x] **Step 1: Run focused and integration verification**

Run:

```powershell
godot --headless --path . --log-file .godot\side-scale-color-focused-final.log -s res://tests/run_tests.gd
godot --headless --path . --log-file .godot\side-scale-color-main-final.log -s res://tests/run_main_gameplay_integration_tests.gd
```

Expected: both runners print PASS with no assertion failures.

- [x] **Step 2: Run wider regressions**

Run:

```powershell
godot --headless --path . --log-file .godot\side-scale-color-grid.log -s res://tests/run_grid_system_tests.gd
godot --headless --path . --log-file .godot\side-scale-color-farming.log -s res://tests/run_farming_system_tests.gd
godot --headless --path . --log-file .godot\side-scale-color-building.log -s res://tests/run_building_system_tests.gd
godot --headless --path . --log-file .godot\side-scale-color-economy-ui.log -s res://tests/run_economy_ui_tests.gd
git diff --check
```

Expected: 106 grid, 578 farming, 3456 building, 129 economy UI, and no whitespace errors.

- [x] **Step 3: Record final measurements and evidence**

Update the validation document with:

- exact 151-pixel side-walk height and y=184 baseline;
- original east and revised east denim channel means and luminance;
- confirmation that p0 is semantically unchanged but resampled;
- five capture names and dimensions;
- focused, integration, and wider test counts.

- [x] **Step 4: Commit validation evidence**

```powershell
git add docs/validation/player-side-walk-12-frame-validation.md docs/superpowers/plans/2026-08-16-player-side-walk-scale-color-alignment.md
git commit -m "docs: validate side-walk visual alignment"
```

- [x] **Step 5: Preserve the worktree for continued development**

Confirm `git status --short` contains only intentional untracked `tmp/` material, leave the branch and worktree in place, and do not push or merge.
