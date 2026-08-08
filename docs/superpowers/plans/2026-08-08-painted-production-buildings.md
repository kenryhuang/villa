# Painted Production Buildings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the seven production-chain geometry placeholders with anchored hand-painted building art, three painted construction stages, and state-driven local work animations.

**Architecture:** Keep `BuildingInstance` responsible for composing building layers and deriving activity from existing authoritative construction, producer, preview, and economy-indicator state. Add a focused `BuildingActivityVisual` that only validates and animates a four-frame transparent overlay, and add explicit art-profile metadata for anchors and frame rates. Preserve the existing fallback path for unrelated future buildings while making missing art for the seven shipped production buildings a test failure.

**Tech Stack:** Godot 4.7.1, typed GDScript, Sprite3D/AtlasTexture, PNG RGBA assets, OpenAI image generation, project-local headless tests, Git.

**Design reference:** `docs/superpowers/specs/2026-08-08-painted-production-buildings-design.md`

---

## File map

- `scripts/data/building_data.gd` — explicit ground anchor and per-building activity FPS metadata.
- `scripts/buildings/building_activity_visual.gd` — isolated activity-atlas validation, frame stepping, fade, reset, and visibility.
- `scripts/buildings/building_instance.gd` — creates the activity layer, applies explicit anchors, and derives `active` from existing building state.
- `assets/buildings/painted/<id>/` — completed back/front layers and four-frame activity atlas for seven buildings.
- `assets/buildings/construction/<id>/` — foundation, frame, and half-built art for seven buildings.
- `tests/test_building_activity_visual.gd` — focused unit tests for frame timing, fade/reset, and malformed atlases.
- `tests/test_building_art_assets.gd` — exact 42-file contract, dimensions, alpha, and fixed-anchor content checks.
- `tests/test_building_instance.gd` — integration tests for layer composition and state-driven activity.
- `tests/run_building_system_tests.gd` — registers the new focused test.
- `tests/visual/production_building_gallery.gd`, `tests/visual/production_building_gallery.tscn` — deterministic gallery of all seven completed and staged buildings.
- `tests/capture_production_buildings.gd` — captures completed, construction, idle, and active visual sheets.

## Task 1: Add explicit art profiles and anchor math

**Files:**
- Modify: `scripts/data/building_data.gd`
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `tests/test_building_data.gd`
- Modify: `tests/test_building_instance.gd`

- [ ] **Step 1: Write failing art-profile tests**

Add assertions for all seven IDs:

```gdscript
const PAINTED_PRODUCTION_IDS := [
	"stone_kiln", "furnace", "food_workshop", "textile_machine",
	"lumberyard", "quarry", "mine",
]

for building_id in PAINTED_PRODUCTION_IDS:
	var definition := BuildingData.from_dictionary(GameData.get_building(building_id))
	assertions.equal(definition.ground_anchor_uv, Vector2(0.5, 0.9375), "%s uses the shared ground anchor" % building_id)
	assertions.truthy(definition.activity_fps >= 3.0 and definition.activity_fps <= 6.0, "%s has restrained activity timing" % building_id)
```

Add a pure anchor-position test:

```gdscript
assertions.near(
	BuildingInstance.anchored_center_y(2.0, Vector2(0.5, 0.9375)),
	0.875,
	0.0001,
	"explicit art anchor maps to world ground"
)
```

- [ ] **Step 2: Run the focused suite and verify RED**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: FAIL because `ground_anchor_uv`, `activity_fps`, and `anchored_center_y()` do not exist.

- [ ] **Step 3: Add metadata and anchor calculation**

Add exported fields and authoritative maps to `BuildingData`:

```gdscript
const PAINTED_PRODUCTION_IDS := [
	"stone_kiln", "furnace", "food_workshop", "textile_machine",
	"lumberyard", "quarry", "mine",
]
const GROUND_ANCHORS := {
	"stone_kiln": Vector2(0.5, 0.9375), "furnace": Vector2(0.5, 0.9375),
	"food_workshop": Vector2(0.5, 0.9375), "textile_machine": Vector2(0.5, 0.9375),
	"lumberyard": Vector2(0.5, 0.9375), "quarry": Vector2(0.5, 0.9375),
	"mine": Vector2(0.5, 0.9375),
}
const ACTIVITY_FPS := {
	"stone_kiln": 4.0, "furnace": 5.0, "food_workshop": 4.0,
	"textile_machine": 6.0, "lumberyard": 6.0, "quarry": 3.0, "mine": 3.0,
}

@export var ground_anchor_uv := Vector2(0.5, 1.0)
@export var activity_fps := 4.0
```

Populate both fields in `from_dictionary()` using the building ID maps. Add:

```gdscript
static func anchored_center_y(world_height: float, ground_anchor_uv: Vector2) -> float:
	return (clampf(ground_anchor_uv.y, 0.0, 1.0) - 0.5) * world_height
```

Use this value in `_configure_sprite()` for only the configured building data; default `(0.5, 1.0)` preserves all existing buildings.

- [ ] **Step 4: Run the focused suite and verify GREEN**

Run the building suite. Expected: PASS with the existing check count plus new art-profile checks.

- [ ] **Step 5: Commit**

```powershell
git add scripts/data/building_data.gd scripts/buildings/building_instance.gd tests/test_building_data.gd tests/test_building_instance.gd
git commit -m "feat: add anchored production building art profiles"
```

## Task 2: Build the isolated activity visual

**Files:**
- Create: `scripts/buildings/building_activity_visual.gd`
- Create: `tests/test_building_activity_visual.gd`
- Modify: `tests/run_building_system_tests.gd`

- [ ] **Step 1: Write the failing component tests**

Cover valid configuration, frame stepping, fade-in, fade-out/reset, invalid FPS fallback, missing texture, and malformed texture size. The core assertions are:

```gdscript
var visual := BuildingActivityVisual.new()
visual.configure(valid_activity_texture, Vector2(2.0, 2.0), Vector2(0.5, 0.9375), 4.0)
assertions.equal(visual.hframes, 4, "activity atlas exposes four frames")
assertions.equal(visual.frame, 0, "activity starts at frame zero")
visual.set_active(true)
visual.advance_animation(0.26)
assertions.equal(visual.frame, 1, "activity advances at configured fps")
visual.set_active(false)
visual.advance_animation(0.2)
assertions.equal(visual.frame, 0, "inactive activity resets")
assertions.equal(visual.visible, false, "inactive activity hides after fade")
```

- [ ] **Step 2: Run and verify RED**

Run the building suite. Expected: parser/preload failure because `BuildingActivityVisual` is absent.

- [ ] **Step 3: Implement the minimal component**

Create a `Sprite3D` class with constants `FRAME_COUNT := 4`, `FADE_DURATION := 0.15`, and `FALLBACK_FPS := 4.0`. `configure()` must reject textures whose size is not 2048×512, set `hframes = 4`, billboard, alpha cut, fixed world width, anchored vertical position, and reset hidden. `set_active()` only changes the target state; `advance_animation(delta)` owns frame accumulation and alpha interpolation so headless tests remain deterministic.

Expose read-only helpers:

```gdscript
func is_configured() -> bool
func is_active() -> bool
func get_effective_fps() -> float
```

Never read inventory, production systems, scene groups, or save data from this component.

- [ ] **Step 4: Run and verify GREEN**

Run the building suite. Expected: PASS, including malformed-atlas and fade/reset cases.

- [ ] **Step 5: Commit**

```powershell
git add scripts/buildings/building_activity_visual.gd tests/test_building_activity_visual.gd tests/run_building_system_tests.gd
git commit -m "feat: add production building activity visual"
```

## Task 3: Integrate activity state into BuildingInstance

**Files:**
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `tests/test_building_instance.gd`
- Modify: `tests/test_building_construction_state.gd`

- [ ] **Step 1: Write failing integration tests**

Assert that every building has `VisualRoot/ActivityLayer`, that it sorts between back and front, and that state gating is exact:

```gdscript
assertions.equal(back.sorting_offset, -0.1, "back remains behind activity")
assertions.equal(activity.sorting_offset, 0.0, "activity sits between painted layers")
assertions.equal(front.sorting_offset, 0.1, "front occludes activity")

stone_kiln.producer_state.jobs = [{
	"recipe_id": "charcoal", "batches": 1,
	"remaining_minutes": 180, "status": "running",
}]
stone_kiln.sync_activity_visual()
assertions.truthy(activity.is_active(), "running crafting job activates the kiln")
stone_kiln.set_economy_indicator("maintenance")
assertions.equal(activity.is_active(), false, "maintenance stops crafting activity")

lumberyard.producer_state.outputs = {}
lumberyard.sync_activity_visual()
assertions.truthy(resource_activity.is_active(), "available passive output building works")
lumberyard.set_economy_indicator("full")
assertions.equal(resource_activity.is_active(), false, "full passive output building stops")
```

Also assert construction, preview, `deactivate()`, and hidden states stop activity.

- [ ] **Step 2: Run and verify RED**

Run the building suite. Expected: FAIL because the node and state bridge are absent.

- [ ] **Step 3: Integrate without adding persistent state**

Preload `BuildingActivityVisual`, create `ActivityLayer` in `_ensure_nodes()`, load `<id>_activity.png` in `_configure_visuals()`, and configure it from `BuildingData`.

Add public deterministic bridge methods:

```gdscript
func should_play_activity() -> bool:
	if data == null or _preview_mode or not is_construction_complete() or not visible:
		return false
	if _economy_indicator_kind in ["full", "maintenance"]:
		return false
	if data.effect_type == "crafting":
		return producer_state != null and producer_state.jobs.any(
			func(job: Dictionary) -> bool: return str(job.get("status", "")) == "running"
		)
	if data.effect_type == "resource_output":
		return producer_state != null
	return false

func sync_activity_visual() -> void:
	var activity := get_node_or_null("VisualRoot/ActivityLayer") as BuildingActivityVisual
	if activity != null:
		activity.set_active(should_play_activity())
```

Call the bridge after configuration, preview changes, construction stage changes, indicator changes, and on `_process()`. Advance the component with the same `delta`. Do not serialize animation state.

- [ ] **Step 4: Run and verify GREEN**

Run the building suite. Expected: PASS with all state combinations covered.

- [ ] **Step 5: Commit**

```powershell
git add scripts/buildings/building_instance.gd tests/test_building_instance.gd tests/test_building_construction_state.gd
git commit -m "feat: drive painted building activity from production state"
```

## Task 4: Author and import the seven painted building sets

**Files:**
- Create: `assets/buildings/painted/{stone_kiln,furnace,food_workshop,textile_machine,lumberyard,quarry,mine}/*.png`
- Create: `assets/buildings/construction/{stone_kiln,furnace,food_workshop,textile_machine,lumberyard,quarry,mine}/*.png`
- Modify: `tests/test_building_art_assets.gd`

- [ ] **Step 1: Extend the asset contract and verify RED**

Move the seven IDs into the full `IDS` set and add activity validation:

```gdscript
const ACTIVITY_SIZE := Vector2(2048, 512)

for id in PAINTED_PRODUCTION_IDS:
	_validate_texture(texture_path(id, "back"), assertions)
	_validate_texture(texture_path(id, "front"), assertions)
	for stage in CONSTRUCTION_STAGES:
		_validate_texture(construction_texture_path(id, stage), assertions)
	_validate_texture(texture_path(id, "activity"), assertions, ACTIVITY_SIZE)
```

For all five static images per building, scan a narrow band around the authored anchor and assert that at least one opaque pixel exists near the ground contact. For each activity frame, assert visible pixels exist but cover less than 35% of the frame so the atlas cannot accidentally repeat the whole building.

Run the building suite. Expected: FAIL listing all missing production-building assets.

- [ ] **Step 2: Generate consistent source sheets with image generation**

Use the existing barn, windmill, workbench, and greenhouse PNGs as style references. For each building, use its exact Section 4 description from the design spec and this fixed contract in the prompt:

```text
Hand-painted cozy isometric game building asset matching the supplied Villa references.
Transparent background, warm brown wood, gray-brown stone, muted metal, golden highlights,
visible brush texture, slightly exaggerated readable silhouette, no text, no border, no UI,
no ground rectangle, no character. Keep the structural ground contact at x=50%, y=93.75%.
The same building design must remain consistent across completed, construction, and activity art.
```

Generate one approved completed composition, one three-stage construction sheet, and one four-frame activity sheet per building. Use the completed composition as the reference for its own construction and activity calls.

- [ ] **Step 3: Normalize and export exact runtime assets**

Export final layers at 1024×1024 RGBA. The completed back contains the structure; the completed front contains only foreground occluders and contact details. Export the three construction panels as separate 1024×1024 files. Export the activity strip as 2048×512 RGBA with four 512×512 frames. Align every output to the exact normalized anchor `(0.5, 0.9375)` without scaling individual frames by their used rectangle.

Inspect every exported PNG before moving on; reject sheets with opaque backgrounds, labels, inconsistent structures, clipped smoke, or changing ground contact.

- [ ] **Step 4: Import and run asset tests**

Run:

```powershell
godot_console --headless --editor --quit --path .
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: Godot imports all PNGs; the building suite passes dimensions, alpha, visible-pixel, activity-coverage, and fallback assertions.

- [ ] **Step 5: Commit**

```powershell
git add assets/buildings/painted assets/buildings/construction tests/test_building_art_assets.gd
git commit -m "art: add painted production building sets"
```

## Task 5: Add deterministic gallery capture and visually tune

**Files:**
- Create: `tests/visual/production_building_gallery.gd`
- Create: `tests/visual/production_building_gallery.tscn`
- Create: `tests/capture_production_buildings.gd`
- Modify: `tests/test_building_visual_scene.gd`

- [ ] **Step 1: Write the gallery contract test**

Instantiate all seven scenes in a 4×2 grid using their real `BuildingData`, force completed status, and assert each has visible painted back/front layers, hidden fallback meshes, and a configured activity layer. Add a second row that forces foundation, frame, and half-built states for the currently selected building.

- [ ] **Step 2: Run and verify RED**

Run `godot_console --headless --path . --script res://tests/test_building_visual_scene.gd`.

Expected: FAIL because the new gallery scene is absent.

- [ ] **Step 3: Implement the gallery and capture script**

Create an orthographic camera, neutral hand-painted ground plane, fixed warm directional light, and labels outside the building silhouettes. `capture_production_buildings.gd` must save:

```text
.godot/production-buildings-complete.png
.godot/production-buildings-construction.png
.godot/production-buildings-idle.png
.godot/production-buildings-active.png
```

The active capture advances every activity layer to a representative nonzero frame; the idle capture asserts all activity layers are hidden.

- [ ] **Step 4: Capture and inspect all four sheets**

Run:

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility --script res://tests/capture_production_buildings.gd
```

Inspect all four PNGs. Tune only asset placement, visual-size metadata, anchor application, animation FPS, and activity-layer ordering needed to satisfy the design. Re-run the capture after every tuning change.

- [ ] **Step 5: Run visual contract tests and commit**

```powershell
godot_console --headless --path . --script res://tests/test_building_visual_scene.gd
git add tests/visual tests/capture_production_buildings.gd tests/test_building_visual_scene.gd scripts/data/building_data.gd assets/buildings
git commit -m "test: add painted production building gallery"
```

## Task 6: Full regression verification and documentation status

**Files:**
- Modify: `docs/superpowers/specs/2026-08-08-painted-production-buildings-design.md`
- Modify: `docs/superpowers/plans/2026-08-08-painted-production-buildings.md`

- [ ] **Step 1: Run parser/import verification**

```powershell
godot_console --headless --editor --quit --path .
```

Expected: exit 0 with no GDScript parse errors or failed resource imports.

- [ ] **Step 2: Run focused and regression suites**

```powershell
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
godot_console --headless --path . --script res://tests/run_production_chain_tests.gd
godot_console --headless --path . --script res://tests/run_economy_system_tests.gd
godot_console --headless --path . --script res://tests/run_tests.gd
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: all suites exit 0; known deliberate invalid-save warnings may remain, but there are no new script/runtime errors or missing production-building art warnings.

- [ ] **Step 3: Run the game smoke test**

```powershell
godot_console --headless --path . --quit-after 10
```

Expected: the main scene starts and exits without parser, resource-load, or null-node errors.

- [ ] **Step 4: Update status and check the diff**

Set the design status to `已实现`, mark completed plan checkboxes, then run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors and only intended code, art, tests, capture scripts, and documentation are modified.

- [ ] **Step 5: Commit final verification**

```powershell
git add docs/superpowers/specs/2026-08-08-painted-production-buildings-design.md docs/superpowers/plans/2026-08-08-painted-production-buildings.md
git commit -m "docs: mark painted production buildings implemented"
```
