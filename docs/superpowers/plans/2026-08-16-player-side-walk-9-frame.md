# Player Side-Walk 9-Frame Reduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce east/west walking to the approved nine poses and run it at the same 6 FPS base cadence as all other directions.

**Architecture:** Make the player visual test contract describe the nine-frame raster and timing first, then make the deterministic assembler select the approved non-contiguous source indices and update `PlayerVisual` to consume the smaller atlas. Replace twelve-frame-only half-cycle checks and captures with explicit phase pairs that work for the approved odd-length sequence.

**Tech Stack:** Godot 4.7 GDScript, `Image`/`AtlasTexture`/`SpriteFrames`, PNG sprite atlas, custom `TestAssert`, deterministic viewport captures.

---

### Task 1: Add the Failing Nine-Frame Runtime and Raster Contract

**Files:**
- Modify: `tests/test_player_visual.gd`
- Test: `scripts/visual/player_visual.gd`
- Test: `assets/characters/player/player_farmer_side_walk.png`

- [ ] **Step 1: Change the expected side frame count and timing**

Set the side contract to nine frames and require side timing to match the shared walk/run constants:

```gdscript
const SIDE_WALK_FRAME_COUNT := 9
const SIDE_PHASE_PAIRS := [[0, 4], [1, 5], [2, 7], [3, 8]]
```

Replace the old 12 FPS assertion with:

```gdscript
assertions.near(
	PlayerVisualScript.SIDE_WALK_FPS,
	PlayerVisualScript.WALK_FPS,
	0.001,
	"side walk uses the same base fps as every direction"
)
assertions.near(
	PlayerVisualScript.SIDE_RUN_FPS,
	PlayerVisualScript.RUN_FPS,
	0.001,
	"side sprint uses the same fps as every direction"
)
```

Inside the direction loop, expect `6.0` for every walk animation. Update the sprint assertion message to describe nine poses at 9 FPS.

- [ ] **Step 2: Change the expected raster size**

Inside `_assert_side_walk_art_contract`, retain all height, baseline, denim, component, gutter, and mirror checks but change the import and size expectations to:

```gdscript
assertions.truthy(texture != null, "nine-frame side-walk atlas imports")
assertions.equal(image.get_size(), Vector2i(1728, 384), "side walk is a 9x2 atlas")
```

- [ ] **Step 3: Replace twelve-frame temporal assumptions**

In `_assert_side_walk_temporal_continuity`, keep adjacent lower-body and boot differences over the full loop, use broad reviewed upper bounds of 160 lower-body pixels and 120 boot pixels, and replace `frame + 6` with:

```gdscript
for pair in SIDE_PHASE_PAIRS:
	var first_frame := int(pair[0])
	var second_frame := int(pair[1])
	assertions.truthy(
		_lower_body_silhouette_difference(
			silhouettes[first_frame], silhouettes[second_frame]
		) >= 20,
		"%s poses %d/%d preserve opposite-leg phases"
		% [direction, first_frame, second_frame]
	)
```

Use these retained named transitions:

```gdscript
[
	{"from": 0, "to": 1, "name": "left boot leaves the opening stride"},
	{"from": 1, "to": 2, "name": "left boot crosses the right support leg"},
	{"from": 3, "to": 4, "name": "left boot extends after crossing"},
	{"from": 4, "to": 5, "name": "left boot loads after contact"},
	{"from": 5, "to": 6, "name": "right boot leaves the ground"},
	{"from": 6, "to": 7, "name": "right boot crosses the left support leg"},
	{"from": 7, "to": 8, "name": "right boot extends after crossing"},
]
```

- [ ] **Step 4: Run the focused suite and verify RED**

Run:

```powershell
godot --headless --path . --log-file .godot\side-nine-red.log -s res://tests/run_tests.gd
```

Expected: FAIL because `PlayerVisual` still exposes twelve side frames at 12/18 FPS and the current atlas remains `2304x384`.

- [ ] **Step 5: Commit the failing contract**

```powershell
git add -- tests/test_player_visual.gd
git commit -m "test: require nine-frame side walk"
```

### Task 2: Assemble and Play the Approved Nine Frames

**Files:**
- Modify: `scripts/tools/assemble_player_side_walk.gd`
- Modify: `scripts/visual/player_visual.gd`
- Modify: `assets/characters/player/player_farmer_side_walk.png`
- Test: `tests/test_player_visual.gd`

- [ ] **Step 1: Make the assembler select approved source indices**

Replace the fixed twelve-frame loop and offsets with:

```gdscript
const SOURCE_FRAME_INDICES := [0, 2, 4, 5, 6, 8, 9, 10, 11]
const FRAME_COUNT := 9
const FRAME_X_OFFSETS := [0, 0, 0, -3, 0, 0, 2, 0, 0]
```

Load sources by output index and source index:

```gdscript
for output_index in FRAME_COUNT:
	var source_index: int = SOURCE_FRAME_INDICES[output_index]
	var source_path := INPUT_DIR.path_join("east-%02d.png" % source_index)
	var source := Image.load_from_file(ProjectSettings.globalize_path(source_path))
	if source == null or source.is_empty() or not _has_transparent_corners(source):
		_fail("Missing or invalid east source frame %02d." % source_index)
		return
	var used := source.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		_fail("East source frame %02d is empty." % source_index)
		return
	source = source.duplicate()
	_match_denim(source, reference_denim)
	sources.append(source)
```

Keep the existing independent 151-pixel fit, y=184 baseline, denim transfer, offset, and exact mirror code.

- [ ] **Step 2: Make `PlayerVisual` consume nine frames at shared FPS**

In `scripts/visual/player_visual.gd`, set:

```gdscript
const SIDE_WALK_FRAME_COUNT := 9
const SIDE_WALK_FPS := WALK_FPS
const SIDE_RUN_FPS := RUN_FPS
```

Change the invalid-raster error to `PlayerVisual requires valid nine-frame side walk` and leave the existing side direction registration and `speed_scale` calculation intact.

- [ ] **Step 3: Assemble and import the smaller atlas**

Run:

```powershell
godot --headless --path . --log-file .godot\assemble-side-nine.log -s res://scripts/tools/assemble_player_side_walk.gd
godot --headless --path . --log-file .godot\import-side-nine.log --import
```

Expected: assembler reports nine east and nine mirrored west frames; import completes with a `1728x384` atlas.

- [ ] **Step 4: Run the focused suite and verify GREEN**

Run:

```powershell
godot --headless --path . --log-file .godot\side-nine-green.log -s res://tests/run_tests.gd
```

Expected: all nine-frame count, timing, raster, color, scale, mirror, gait, and runtime assertions pass.

- [ ] **Step 5: Commit the implementation**

```powershell
git add -- scripts/tools/assemble_player_side_walk.gd scripts/visual/player_visual.gd assets/characters/player/player_farmer_side_walk.png
git commit -m "fix: reduce side walk to nine frames"
```

### Task 3: Update Deterministic Visual Captures

**Files:**
- Modify: `tests/capture_player_side_walk.gd`
- Generated: `.godot/player-side-walk-validation/east-strip.png`
- Generated: `.godot/player-side-walk-validation/west-strip.png`
- Generated: `.godot/player-side-walk-validation/half-cycle-pairs.png`
- Generated: `.godot/player-side-walk-validation/runtime-walk-sprint.png`
- Generated: `.godot/player-side-walk-validation/direction-scale-color.png`

- [ ] **Step 1: Resize and relabel the strips**

Set `FRAME_COUNT := 9` and label the east strip `EAST - 9 sequential walk frames`. The strip output becomes `1728x240` for both directions.

- [ ] **Step 2: Capture explicit odd-cycle phase pairs**

Add `const SIDE_PHASE_PAIRS := [[0, 4], [1, 5], [2, 7], [3, 8]]`. Render four columns and two rows in `_capture_half_cycle_pairs`, with each column taking its two frame indices from the corresponding pair. The output becomes `768x438`.

- [ ] **Step 3: Update runtime and direction samples**

Change runtime labels to 6 FPS walk and 9 FPS sprint, and change the failure text to `6 FPS walk from 9 FPS sprint`. Keep live 1/6-second sampling and speed-scale checks.

For the six-column direction comparison, sample revised frames:

```gdscript
var revised_indices := [0, 2, 3, 4, 6, 8]
```

- [ ] **Step 4: Generate and inspect all five captures**

Run:

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility --log-file .godot\capture-side-nine.log -s res://tests/capture_player_side_walk.gd
```

Expected: five captures pass. Inspect the east strip, half-cycle pairs, runtime sheet, and direction comparison. Confirm the sequence has no repeated contact pose and still alternates supporting legs.

- [ ] **Step 5: Commit capture coverage**

```powershell
git add -- tests/capture_player_side_walk.gd
git commit -m "test: capture nine-frame side walk"
```

### Task 4: Revalidate and Document the Nine-Frame Atlas

**Files:**
- Delete: `docs/validation/player-side-walk-12-frame-validation.md`
- Create: `docs/validation/player-side-walk-9-frame-validation.md`
- Modify: `docs/superpowers/plans/2026-08-16-player-side-walk-9-frame.md`

- [ ] **Step 1: Run focused and integration verification**

```powershell
godot --headless --path . --log-file .godot\side-nine-focused-final.log -s res://tests/run_tests.gd
godot --headless --path . --log-file .godot\side-nine-main-final.log -s res://tests/run_main_gameplay_integration_tests.gd
```

Expected: both runners print PASS with no assertion failure.

- [ ] **Step 2: Run wider regressions**

```powershell
godot --headless --path . --log-file .godot\side-nine-grid.log -s res://tests/run_grid_system_tests.gd
godot --headless --path . --log-file .godot\side-nine-farming.log -s res://tests/run_farming_system_tests.gd
godot --headless --path . --log-file .godot\side-nine-building.log -s res://tests/run_building_system_tests.gd
godot --headless --path . --log-file .godot\side-nine-economy-ui.log -s res://tests/run_economy_ui_tests.gd
git diff --check
```

Expected: 106 grid, 578 farming, 3456 building, 129 economy UI, and no whitespace errors.

- [ ] **Step 3: Record final evidence**

Create `docs/validation/player-side-walk-9-frame-validation.md` with the retained source mapping, `1728x384` raster, 151-pixel height, y=184 baseline, denim measurements, 6/9 FPS timing, five capture dimensions, focused/main/wider test counts, and visual inspection outcome. Remove the superseded twelve-frame validation file.

- [ ] **Step 4: Commit validation evidence**

```powershell
git add -- docs/validation/player-side-walk-12-frame-validation.md docs/validation/player-side-walk-9-frame-validation.md docs/superpowers/plans/2026-08-16-player-side-walk-9-frame.md
git commit -m "docs: validate nine-frame side walk"
```

- [ ] **Step 5: Preserve the current development workspace**

Confirm `git status --short` contains only intentional untracked `tmp/` material. Keep `feature/painted-production-buildings` and its current worktree in place; do not merge, push, or remove it.

