# Player Side-Walk Cadence and Sharpness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore one-second normal side gait cycles and remove runtime edge softness through explicit non-mipmap filtering and alpha-border import processing.

**Architecture:** Extend the player visual contract with cycle-duration and sampling assertions before changing production values. Keep the nine-frame raster untouched; only update side timing, the configured sprite filter, and the side texture import option, then regenerate runtime captures and revalidate the existing animation suite.

**Tech Stack:** Godot 4.7 GDScript, `AnimatedSprite3D`, Godot texture import metadata, PNG atlases, custom `TestAssert`, deterministic display captures.

---

### Task 1: Add the Failing Cadence and Sampling Contract

**Files:**
- Modify: `tests/test_player_visual.gd`
- Test: `scripts/visual/player_visual.gd`
- Test: `assets/characters/player/player_farmer_side_walk.png.import`

- [x] **Step 1: Require the approved side timing**

Replace the shared-numeric-FPS assertions with:

```gdscript
assertions.near(PlayerVisualScript.SIDE_WALK_FPS, 9.0, 0.001, "nine side poses complete a one-second walk cycle")
assertions.near(PlayerVisualScript.SIDE_RUN_FPS, 13.5, 0.001, "nine side poses preserve the sprint cycle duration")
assertions.near(
	float(PlayerVisualScript.SIDE_WALK_FRAME_COUNT) / PlayerVisualScript.SIDE_WALK_FPS,
	float(PlayerVisualScript.WALK_FRAME_COUNT) / PlayerVisualScript.WALK_FPS,
	0.001,
	"side and non-side walking exchange supporting legs at the same cycle rate"
)
assertions.near(
	float(PlayerVisualScript.SIDE_WALK_FRAME_COUNT) / PlayerVisualScript.SIDE_RUN_FPS,
	float(PlayerVisualScript.WALK_FRAME_COUNT) / PlayerVisualScript.RUN_FPS,
	0.001,
	"side and non-side sprinting exchange supporting legs at the same cycle rate"
)
```

Inside the direction animation loop, expect `SIDE_WALK_FPS` for east/west and `WALK_FPS` for all other directions. Keep the runtime sprint `speed_scale = 1.5` assertion and update its message to nine poses at 13.5 FPS.

- [x] **Step 2: Require explicit runtime filtering**

After a valid `PlayerVisual.configure`, add:

```gdscript
assertions.equal(
	visual.texture_filter,
	BaseMaterial3D.TEXTURE_FILTER_LINEAR,
	"player art uses explicit linear filtering without mipmaps"
)
```

- [x] **Step 3: Require matching alpha-border import processing**

Inside `_assert_side_walk_art_contract`, read both import files and assert:

```gdscript
var side_import := FileAccess.get_file_as_string(SIDE_WALK_PATH + ".import")
var main_import := FileAccess.get_file_as_string(ATLAS_PATH + ".import")
assertions.truthy(
	"process/fix_alpha_border=true" in side_import,
	"side-walk import prepares transparent edge colors"
)
assertions.truthy(
	"process/fix_alpha_border=true" in main_import,
	"main player import prepares transparent edge colors"
)
```

- [x] **Step 4: Run the focused suite and verify RED**

```powershell
godot --headless --path . --log-file .godot\side-cadence-sharpness-red.log -s res://tests/run_tests.gd
```

Expected: FAIL on old 6/9 side timing, unequal 1.5-second side cycle, inherited texture filtering, and `fix_alpha_border=false`.

- [x] **Step 5: Commit the failing contract**

```powershell
git add -- tests/test_player_visual.gd
git commit -m "test: require matched side gait cadence"
```

### Task 2: Implement Cadence and Runtime Sharpness

**Files:**
- Modify: `scripts/visual/player_visual.gd`
- Modify: `assets/characters/player/player_farmer_side_walk.png.import`
- Test: `tests/test_player_visual.gd`

- [x] **Step 1: Restore one-second side gait timing**

Set:

```gdscript
const SIDE_WALK_FPS := 9.0
const SIDE_RUN_FPS := 13.5
```

Keep `SIDE_WALK_FRAME_COUNT := 9`, `WALK_FPS := 6.0`, and `RUN_FPS := 9.0` unchanged.

- [x] **Step 2: Select non-mipmap linear filtering explicitly**

In `PlayerVisual.configure`, set:

```gdscript
texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
```

Set it with the other configured rendering properties before making the sprite visible.

- [x] **Step 3: Prepare side-atlas transparent border colors**

In `assets/characters/player/player_farmer_side_walk.png.import`, change only:

```ini
process/fix_alpha_border=true
```

Keep lossless compression and mipmap generation disabled, then run:

```powershell
godot --headless --path . --log-file .godot\import-side-sharpness.log --import
```

- [x] **Step 4: Run the focused suite and verify GREEN**

```powershell
godot --headless --path . --log-file .godot\side-cadence-sharpness-green.log -s res://tests/run_tests.gd
```

Expected: all cadence, filter, import, scale, color, mirror, and gait checks pass.

- [x] **Step 5: Commit the implementation**

```powershell
git add -- scripts/visual/player_visual.gd assets/characters/player/player_farmer_side_walk.png.import
git commit -m "fix: match side gait cadence and filtering"
```

### Task 3: Update Captures and Final Evidence

**Files:**
- Modify: `tests/capture_player_side_walk.gd`
- Modify: `docs/validation/player-side-walk-9-frame-validation.md`
- Modify: `docs/superpowers/plans/2026-08-16-player-side-walk-cadence-sharpness.md`

- [x] **Step 1: Update runtime capture timing labels**

Change the runtime sheet labels from 6/9 FPS to 9/13.5 FPS and change the distinction failure text accordingly. Keep the live timer sampling and speed-scale checks.

- [x] **Step 2: Generate and inspect all five captures**

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility --log-file .godot\capture-side-cadence-sharpness.log -s res://tests/capture_player_side_walk.gd
```

Expected: five captures pass. Inspect the runtime sheet for faster leg exchange and inspect native-size painted edges for dark/soft transparent fringes.

- [x] **Step 3: Run focused and integration verification**

```powershell
godot --headless --path . --log-file .godot\side-cadence-focused-final.log -s res://tests/run_tests.gd
godot --headless --path . --log-file .godot\side-cadence-main-final.log -s res://tests/run_main_gameplay_integration_tests.gd
```

Expected: both runners print PASS.

- [x] **Step 4: Run wider regressions and whitespace checks**

```powershell
godot --headless --path . --log-file .godot\side-cadence-grid.log -s res://tests/run_grid_system_tests.gd
godot --headless --path . --log-file .godot\side-cadence-farming.log -s res://tests/run_farming_system_tests.gd
godot --headless --path . --log-file .godot\side-cadence-building.log -s res://tests/run_building_system_tests.gd
godot --headless --path . --log-file .godot\side-cadence-economy-ui.log -s res://tests/run_economy_ui_tests.gd
git diff --check
```

Expected: 106 grid, 578 farming, 3456 building, 129 economy UI, and no whitespace errors.

- [x] **Step 5: Document and commit final evidence**

Update the validation document with 9/13.5 FPS, equal cycle durations, explicit linear filtering, matching alpha-border imports, capture results, and test counts. Mark this plan complete and commit:

```powershell
git add -- tests/capture_player_side_walk.gd docs/validation/player-side-walk-9-frame-validation.md docs/superpowers/plans/2026-08-16-player-side-walk-cadence-sharpness.md
git commit -m "docs: validate side cadence and sharpness"
```

Preserve the current branch and worktree; do not merge, push, or remove them.
