# Production Yard Fence Art Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat SVG production-yard fences with three low, high-detail hand-painted PNG atlas families that match the existing buildings while preserving yard gameplay.

**Architecture:** Keep `BuildingProductionYard` as the single assembly and collision component. Replace its SVG texture contract with three `1024×2048` transparent PNG atlases using `512×512` frames, then add a small self-contained stage crossfade layer inside the component. Asset tests validate dimensions, alpha, frame occupancy, baseline stability, and the absence of runtime SVG references before lifecycle regression suites run.

**Tech Stack:** Godot 4.7, GDScript, PNG `Texture2D` atlases, Sprite3D atlas regions, Tween transitions, headless GDScript tests

---

### Task 1: Lock the raster art contract with failing tests

**Files:**
- Modify: `tests/test_building_production_yard.gd`
- Modify: `tests/run_building_system_tests.gd`

- [x] **Step 1: Add image-contract helpers and assertions**

Add constants for the three PNG paths and verify each image loads as `1024×2048`, has alpha, and contains opaque pixels inside every `512×512` frame:

```gdscript
const YARD_PNG_PATHS := {
	"timber": "res://assets/buildings/yards/timber_yard_fence.png",
	"masonry": "res://assets/buildings/yards/masonry_yard_fence.png",
	"industrial": "res://assets/buildings/yards/industrial_yard_fence.png",
}

func _frame_has_visible_pixels(image: Image, column: int, row: int) -> bool:
	for y in range(row * 512, (row + 1) * 512, 8):
		for x in range(column * 512, (column + 1) * 512, 8):
			if image.get_pixel(x, y).a > 0.05:
				return true
	return false
```

For every family, assert all eight frames are populated. Compute each frame's lowest visible sampled row and assert the baselines differ by no more than 20 pixels inside a family.

- [x] **Step 2: Assert runtime paths no longer use SVG**

Add component assertions:

```gdscript
for style in ["timber", "masonry", "industrial"]:
	assertions.truthy(
		str(BuildingProductionYardScript.TEXTURES[style]).ends_with(".png"),
		"%s yard uses raster painted art" % style
	)
assertions.equal(BuildingProductionYardScript.ATLAS_FRAME_SIZE, Vector2i(512, 512), "yard atlas uses high-detail frames")
```

- [x] **Step 3: Run the building suite and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: failures report missing PNG atlases and the old `256×192` frame contract.

- [x] **Step 4: Commit the failing tests**

```powershell
git add tests/test_building_production_yard.gd tests/run_building_system_tests.gd
git commit -m "test: define painted yard fence atlas contract"
```

### Task 2: Produce and import the three painted PNG atlases

**Files:**
- Create: `assets/buildings/yards/timber_yard_fence.png`
- Create: `assets/buildings/yards/masonry_yard_fence.png`
- Create: `assets/buildings/yards/industrial_yard_fence.png`
- Create through Godot import: matching `.png.import` files

- [x] **Step 1: Generate the timber atlas from building references**

Use the existing lumberyard, workbench, and chicken-coop front sprites as visual references. Generate a transparent `1024×2048` two-column/four-row sheet: straight-facing segment left, side-perspective segment right; foundation, posts, partial rails, completed low fence from top to bottom. Require amber heavy timber, stone feet, nails, rope, grass, irregular painterly edges, warm upper light, and cool occlusion.

- [x] **Step 2: Generate the masonry atlas from building references**

Use stone-kiln and quarry front sprites. Keep the exact same frame grid and baseline. Require irregular warm-gray stone piers, aged wood rails, brick chips, moss and soil contact, faceted hand-painted stone, and no flat vector outlines.

- [x] **Step 3: Generate the industrial atlas from building references**

Use mine and furnace front sprites. Keep the exact same frame grid and baseline. Require dark mine timber, rubble feet, rusted brackets and restrained rail details; explicitly exclude modern gray steel fencing and clean procedural geometry.

- [x] **Step 4: Inspect every atlas at original resolution**

Verify transparency, frame separation, consistent roots, no labels, no borders, no checkerboard baked into alpha, no cropped posts, and no duplicated full buildings in the output.

- [x] **Step 5: Import the PNGs in Godot**

Run:

```powershell
godot --headless --path . --import
```

Expected: three `.png.import` files are created and each resource loads as `Texture2D`.

- [x] **Step 6: Commit the raster assets**

```powershell
git add assets/buildings/yards/*.png assets/buildings/yards/*.png.import
git commit -m "art: add painted production yard fences"
```

### Task 3: Switch the runtime component to the raster atlases

**Files:**
- Modify: `scripts/buildings/building_production_yard.gd`
- Modify: `tests/test_building_production_yard.gd`

- [x] **Step 1: Add failing runtime frame assertions**

Configure every family at construction stages 0 through 3 and assert each segment's region is:

```gdscript
Rect2(
	float(orientation) * 512.0,
	float(stage) * 512.0,
	512.0,
	512.0
)
```

Also assert all completed fence segments remain low enough that their Sprite3D vertical size is below the existing building foundation visual envelope.

- [x] **Step 2: Run and verify RED**

Run the building suite and require failures against the old atlas dimensions and paths.

- [x] **Step 3: Update texture and frame constants**

Replace the component constants with:

```gdscript
const TEXTURES := {
	"timber": "res://assets/buildings/yards/timber_yard_fence.png",
	"masonry": "res://assets/buildings/yards/masonry_yard_fence.png",
	"industrial": "res://assets/buildings/yards/industrial_yard_fence.png",
}
const ATLAS_FRAME_SIZE := Vector2i(512, 512)
const SEGMENT_PIXEL_SIZE := 512.0
const SEGMENT_WORLD_SIZE := 1.04
```

Set each Sprite3D's `pixel_size` from `SEGMENT_WORLD_SIZE / SEGMENT_PIXEL_SIZE`, retain transparent rendering, and calibrate the vertical offset so every frame shares the same grid-edge root.

- [x] **Step 4: Warn once for missing or malformed atlases**

Validate texture presence and dimensions during `configure`. If invalid, leave perimeter collision and output slots intact, hide visual segments, and issue one warning per family. Do not fall back to the removed SVG art.

- [x] **Step 5: Run building tests and require GREEN**

Run the building suite. Expected: all atlas, family, segment-count, collision, preview, maintenance, and deactivation assertions pass.

- [x] **Step 6: Commit the runtime switch**

```powershell
git add scripts/buildings/building_production_yard.gd tests/test_building_production_yard.gd
git commit -m "feat: render painted production yard fences"
```

### Task 4: Add synchronized two-second fence-stage crossfades

**Files:**
- Modify: `scripts/buildings/building_production_yard.gd`
- Modify: `tests/test_building_production_yard.gd`

- [x] **Step 1: Write failing transition lifecycle tests**

After changing from stage 0 to stage 1, assert the component temporarily owns outgoing transition sprites, both frame sets use the correct atlas regions, and `advance_transition_for_test(2.0)` removes every outgoing sprite. Interrupt with stage 2 and assert only stage 2 remains after completion. Call `clear_immediately` mid-transition and assert no visual or tween child remains.

- [x] **Step 2: Run and verify RED**

Expected: failures report missing transition inspection and deterministic advancement methods.

- [x] **Step 3: Implement the transition layer**

Add:

```gdscript
const STAGE_CROSSFADE_SECONDS := 2.0
var _transition_sprites: Array[Sprite3D] = []
var _stage_tween: Tween
```

When stage changes, duplicate the current visual state into an outgoing layer, set the new regions on the primary segments, crossfade outgoing alpha from 1 to 0 and incoming alpha from 0 to 1 over two seconds, then free the outgoing layer. A new stage cancels and clears the old transition before starting the latest transition.

Expose deterministic test helpers:

```gdscript
func get_transition_sprite_count() -> int:
	return _transition_sprites.size()

func advance_transition_for_test(delta: float) -> void:
	_advance_transition(delta)
```

Use one internal elapsed-time path for both `_process` and tests so headless verification does not depend on wall-clock sleeps.

- [x] **Step 4: Preserve preview and maintenance tinting during transitions**

Apply the same preview/maintenance color transform to incoming and outgoing sprites, multiplying alpha rather than replacing texture color.

- [x] **Step 5: Run building tests and require GREEN**

Expected: stage transitions, interruption, preview, maintenance, and clear behavior all pass with no duplicate visual children.

- [x] **Step 6: Commit the transition**

```powershell
git add scripts/buildings/building_production_yard.gd tests/test_building_production_yard.gd
git commit -m "feat: crossfade yard fence construction"
```

### Task 5: Retire the rejected SVG art and verify the full feature

**Files:**
- Delete: `assets/buildings/yards/timber_yard_fence.svg`
- Delete: `assets/buildings/yards/timber_yard_fence.svg.import`
- Delete: `assets/buildings/yards/masonry_yard_fence.svg`
- Delete: `assets/buildings/yards/masonry_yard_fence.svg.import`
- Delete: `assets/buildings/yards/industrial_yard_fence.svg`
- Delete: `assets/buildings/yards/industrial_yard_fence.svg.import`
- Modify: `docs/superpowers/plans/2026-08-10-production-yard-fence-art-redesign.md`

- [x] **Step 1: Remove the obsolete SVG assets**

Delete only the six explicitly listed SVG source/import files after confirming runtime and tests reference PNG paths.

- [x] **Step 2: Run repository checks**

```powershell
rg -n "yard_fence\.svg" scripts tests project.godot
git diff --check
git status --short
```

Expected: no runtime/test SVG references and no whitespace errors.

- [x] **Step 3: Run all affected suites**

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_production_system_tests.gd
godot --headless --path . --script res://tests/run_economy_progression_tests.gd
godot --headless --path . --script res://tests/run_building_economy_ui_tests.gd
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
godot --headless --path . --script res://tests/run_production_chain_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: every runner exits `0` with a `PASS` summary and no hard failures.

- [x] **Step 4: Review visual acceptance criteria**

Inspect all three atlases and confirm low height, painterly edges, family-specific materials, consistent roots, transparent gaps, no modern geometric rail style, visible output zone, and construction continuity.

- [x] **Step 5: Commit the cleanup and completed plan**

```powershell
git add -A assets/buildings/yards docs/superpowers/plans/2026-08-10-production-yard-fence-art-redesign.md
git commit -m "chore: retire geometric yard fence art"
```
