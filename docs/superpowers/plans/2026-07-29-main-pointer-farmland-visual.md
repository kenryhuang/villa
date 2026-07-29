# Main Pointer Farmland Visual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make slot 1 show a terrain-aligned hover cell under the real macOS pointer and turn a successful left click into a persistent, hand-painted individual farmland tile.

**Architecture:** `PlayerActionController` keeps the latest logical mouse-event position and uses it for both hover and click rays. `GridSystem` remains the authoritative state owner and synchronizes a focused `FarmlandTile` visual for every `FARMLAND` or `PLANTED` cell. A single authored hand-painted texture is shared by all tiles, while each tile generates a four-corner terrain-following mesh.

**Tech Stack:** Godot 4.7.1, GDScript, ArrayMesh/SurfaceTool, StandardMaterial3D, PNG raster asset, existing custom SceneTree test runners.

## Global Constraints

- Target Godot version is `4.7.1`.
- The project logical canvas remains `3000×2000`; do not change window or stretch settings.
- macOS Retina and resized windows must use the mouse event's logical `position` for hover and click.
- Farmland tiles are independent one-cell visuals; adjacent tiles are not merged.
- Visual style must match the existing hand-painted terrain, trees, grain crops, and buildings.
- A tile is visible for `FARMLAND` and `PLANTED`, and absent for every other grid state.
- World tool interaction remains limited to the player's horizontal `interaction_range` of `2.5m`.
- Tool stamina is consumed only after a state-changing action succeeds.
- No third-party Godot addons or external game assets.

## File Map

| File | Responsibility |
|---|---|
| `scripts/actors/player_action_controller.gd` | Preserve mouse-event logical position and use it for hover/click rays. |
| `tests/test_main_pointer_farming.gd` | Exercise real main-scene pointer hover, hoe, and seed flow. |
| `tests/run_main_gameplay_integration_tests.gd` | Register the async pointer regression. |
| `assets/terrain/farmland-soil-hand-painted.png` | Shared hand-painted soil and furrow surface. |
| `scripts/visual/farmland_tile.gd` | Build one terrain-conforming farmland mesh and material. |
| `scenes/systems/grid_system.tscn` | Author the `FarmlandVisuals` container. |
| `scripts/systems/grid_system.gd` | Synchronize tile visuals with authoritative cell state. |
| `tests/test_farmland_tile.gd` | Verify mesh, metadata, material, and terrain fitting. |
| `tests/test_grid_system_complete.gd` | Verify state-to-visual lifecycle and save restoration. |
| `tests/run_grid_system_tests.gd` | Register the farmland visual unit test. |
| `tests/capture_main_pointer_farmland.gd` | Produce final main-scene visual acceptance capture. |

---

### Task 1: Use Real Mouse-Event Coordinates for Hover and Click

**Files:**
- Modify: `scripts/actors/player_action_controller.gd`
- Create: `tests/test_main_pointer_farming.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

**Interfaces:**
- Consumes: `Camera3D.project_ray_origin(Vector2)`, `Camera3D.project_ray_normal(Vector2)`, `GridSystem.highlight_cell(int, int, Color)`.
- Produces: `_pointer_position: Variant`, `_input(InputEvent)`, `_camera_ray(pointer_position: Variant = null) -> Dictionary`.

- [ ] **Step 1: Extend the failing main pointer test to cover hover**

In `tests/test_main_pointer_farming.gd`, instantiate `main.tscn` with `load_save_on_start = false`, await four process and physics frames, find the nearest farmable cell within `2.5m`, and project its `world_position_3d()` through the active camera.

Select slot `0`, then send a real mouse motion event before the existing hoe and seed clicks:

```gdscript
main.action_controller.select_slot(0)
var motion := InputEventMouseMotion.new()
motion.position = camera.unproject_position(cell.world_position_3d())
motion.global_position = motion.position
main.action_controller._input(motion)
main.action_controller._process(0.0)

var highlight := main.grid_system.get_node(
	"GridCells/CellHighlight"
) as MeshInstance3D
assertions.truthy(
	highlight.visible,
	"slot one shows a hover grid at the mouse event position"
)
```

Keep the existing assertions that the click changes exactly that cell to `FARMLAND`, a seed click changes it to `PLANTED`, and the seed count decreases by one.

Project a reachable road or already cultivated cell through the same event path and assert that `CellHighlight.material_override.albedo_color.r` is greater than its green channel. This catches removal of the red invalid-target feedback without coupling the test to an exact color constant.

- [ ] **Step 2: Run the pointer regression and verify RED**

Run:

```bash
godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: FAIL at `slot one shows a hover grid at the mouse event position` because `_process()` still reads `Viewport.get_mouse_position()` instead of the motion event position.

- [ ] **Step 3: Implement one shared logical pointer position**

In `PlayerActionController`, add:

```gdscript
var _pointer_position: Variant


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer_position = event.position


func _effective_pointer_position(override_position: Variant = null) -> Variant:
	if override_position is Vector2:
		return override_position
	if _pointer_position is Vector2:
		return _pointer_position
	return get_viewport().get_mouse_position()
```

Change `_process()` to call:

```gdscript
var ground_point = _raycast_to_ground(_effective_pointer_position())
```

Keep the click path passing `event.position` into `_perform_pointer_action(event.position)`. Change `_camera_ray()` to resolve the supplied position through `_effective_pointer_position(pointer_position)` before projecting the ray.

Do not change action priority, tool range, tool stamina, or planting rules.

- [ ] **Step 4: Run the main pointer regression and verify GREEN**

Run:

```bash
godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: `PASS: 96 main gameplay integration checks` or greater, including hover, hoe, seed planting, and inventory consumption.

- [ ] **Step 5: Commit the pointer fix**

```bash
git add \
  scripts/actors/player_action_controller.gd \
  tests/test_main_pointer_farming.gd \
  tests/test_main_pointer_farming.gd.uid \
  tests/run_main_gameplay_integration_tests.gd
git commit -m "fix: use mouse event coordinates for farming"
```

---

### Task 2: Build the Hand-Painted Terrain-Following Farmland Tile

**Files:**
- Create: `assets/terrain/farmland-soil-hand-painted.png`
- Create: `scripts/visual/farmland_tile.gd`
- Create: `tests/test_farmland_tile.gd`
- Modify: `tests/run_grid_system_tests.gd`

**Interfaces:**
- Consumes: `GridCell.gx`, `GridCell.gz`, `TerrainBuilder.get_height_at(float, float)`, `GridSystem` origin and cell-size values passed as arguments.
- Produces: `FarmlandTile.configure(GridCell, TerrainBuilder, float, float, float) -> bool`.

- [ ] **Step 1: Write the failing farmland tile contract**

Create `tests/test_farmland_tile.gd`:

```gdscript
extends RefCounted

const FarmlandTileScript = preload("res://scripts/visual/farmland_tile.gd")
const TerrainBuilderScript = preload("res://scripts/world/terrain_builder.gd")


func run(assertions: TestAssert) -> void:
	assertions.truthy(
		ResourceLoader.exists(
			"res://assets/terrain/farmland-soil-hand-painted.png"
		),
		"farmland hand-painted texture exists"
	)
	var terrain := TerrainBuilderScript.new()
	assertions.truthy(terrain.build(), "farmland test terrain builds")
	var cell := GridCell.new()
	cell.gx = 4
	cell.gz = 6
	var tile = FarmlandTileScript.new()
	assertions.truthy(
		tile.configure(cell, terrain, -18.0, -14.0, 1.0),
		"farmland tile configures"
	)
	assertions.equal(tile.get_meta("gx"), 4, "tile records grid x")
	assertions.equal(tile.get_meta("gz"), 6, "tile records grid z")
	assertions.truthy(tile.mesh is ArrayMesh, "tile uses an ArrayMesh")
	assertions.equal(tile.mesh.get_surface_count(), 1, "tile has one surface")
	assertions.truthy(
		tile.material_override is StandardMaterial3D,
		"tile uses a standard hand-painted material"
	)
	tile.free()
	terrain.free()
```

Register `FarmlandTileTest` in `tests/run_grid_system_tests.gd`.

- [ ] **Step 2: Run the grid tests and verify RED**

Run:

```bash
godot --headless --path . --script res://tests/run_grid_system_tests.gd
```

Expected: FAIL because the texture and `farmland_tile.gd` do not exist.

- [ ] **Step 3: Generate and inspect the shared painted soil texture**

Use the `imagegen` skill and image generation tool to create a square PNG with:

```text
Seamless square hand-painted tilled farm soil texture for a cozy 2.5D
village management game. Warm medium-brown earth, three to four gently
curved dark furrows, small soft clods and ochre highlights, painterly
brush texture, soft slightly irregular edges, orthographic top-down
surface, no plants, no tools, no stones, no text, no border, no
photorealism, transparent outside the soil patch. Match warm watercolor
storybook tree, grain crop, and rustic building assets.
```

Save the selected result as:

```text
assets/terrain/farmland-soil-hand-painted.png
```

Inspect it with the local image viewer. Reject results with photographic detail, hard UI-like borders, plants, text, or a mismatched cold palette.

- [ ] **Step 4: Implement `FarmlandTile`**

Create `scripts/visual/farmland_tile.gd`:

```gdscript
class_name FarmlandTile
extends MeshInstance3D

const TEXTURE_PATH := "res://assets/terrain/farmland-soil-hand-painted.png"
const SURFACE_LIFT := 0.042


func configure(
	cell: GridCell,
	terrain: TerrainBuilder,
	origin_x: float,
	origin_z: float,
	cell_size: float
) -> bool:
	if cell == null or terrain == null or cell_size <= 0.0:
		return false
	name = "FarmlandVisual_%d_%d" % [cell.gx, cell.gz]
	set_meta("gx", cell.gx)
	set_meta("gz", cell.gz)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var x0 := origin_x + float(cell.gx) * cell_size
	var z0 := origin_z + float(cell.gz) * cell_size
	var x1 := x0 + cell_size
	var z1 := z0 + cell_size
	var points := [
		Vector3(x0, terrain.get_height_at(x0, z0) + SURFACE_LIFT, z0),
		Vector3(x1, terrain.get_height_at(x1, z0) + SURFACE_LIFT, z0),
		Vector3(x1, terrain.get_height_at(x1, z1) + SURFACE_LIFT, z1),
		Vector3(x0, terrain.get_height_at(x0, z1) + SURFACE_LIFT, z1),
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
	for index in points.size():
		surface.set_uv(uvs[index])
		surface.add_vertex(points[index])
	for index in [0, 2, 1, 0, 3, 2]:
		surface.add_index(index)
	surface.generate_normals()
	mesh = surface.commit()

	var material := StandardMaterial3D.new()
	material.albedo_texture = load(TEXTURE_PATH) as Texture2D
	material.albedo_color = Color(0.9, 0.82, 0.7)
	material.roughness = 0.96
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material_override = material
	return material.albedo_texture != null
```

- [ ] **Step 5: Run grid tests and verify GREEN**

Run:

```bash
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/run_grid_system_tests.gd
```

Expected: editor import exit `0`; grid tests pass with the new tile checks.

- [ ] **Step 6: Commit the tile and texture**

```bash
git add \
  assets/terrain/farmland-soil-hand-painted.png \
  assets/terrain/farmland-soil-hand-painted.png.import \
  scripts/visual/farmland_tile.gd \
  scripts/visual/farmland_tile.gd.uid \
  tests/test_farmland_tile.gd \
  tests/test_farmland_tile.gd.uid \
  tests/run_grid_system_tests.gd
git commit -m "feat: add hand-painted farmland tile"
```

---

### Task 3: Synchronize Farmland Visuals with Grid State

**Files:**
- Modify: `scenes/systems/grid_system.tscn`
- Modify: `scripts/systems/grid_system.gd`
- Modify: `tests/test_grid_system_complete.gd`

**Interfaces:**
- Consumes: `FarmlandTile.configure(GridCell, TerrainBuilder, float, float, float) -> bool`.
- Produces: `get_farmland_visual(int, int) -> FarmlandTile`, `rebuild_farmland_visuals() -> void`.

- [ ] **Step 1: Write failing state-to-visual lifecycle assertions**

In `tests/test_grid_system_complete.gd`, after selecting a farmable cell:

```gdscript
assertions.truthy(
	grid.set_cell_state(
		farm_cell.gx,
		farm_cell.gz,
		GridCell.State.FARMLAND
	),
	"farmable cell cultivates"
)
var farmland_visual = grid.get_farmland_visual(farm_cell.gx, farm_cell.gz)
assertions.truthy(farmland_visual != null, "cultivation creates farmland visual")

var crop := CropData.new()
crop.crop_id = "visual_lifecycle_crop"
crop.growth_days = 1
assertions.truthy(
	grid.plant_crop(farm_cell.gx, farm_cell.gz, crop) != null,
	"test crop plants"
)
assertions.equal(
	grid.get_farmland_visual(farm_cell.gx, farm_cell.gz),
	farmland_visual,
	"planted cell retains its farmland visual"
)

farm_cell.crop_instance.growth_progress = 1.0
grid.harvest_crop(farm_cell.gx, farm_cell.gz)
assertions.truthy(
	grid.get_farmland_visual(farm_cell.gx, farm_cell.gz) != null,
	"harvested farmland retains its visual"
)
```

After restoring serialized grid data:

```gdscript
assertions.truthy(
	restored.get_farmland_visual(farm_cell.gx, farm_cell.gz) != null,
	"save restore rebuilds farmland visual"
)
```

Also transition a separate farmland cell to `BUILDING` and assert its visual becomes `null`.

- [ ] **Step 2: Run grid tests and verify RED**

Run:

```bash
godot --headless --path . --script res://tests/run_grid_system_tests.gd
```

Expected: FAIL because `get_farmland_visual()` does not exist.

- [ ] **Step 3: Author the visual container**

Add to `scenes/systems/grid_system.tscn`:

```text
[node name="FarmlandVisuals" type="Node3D" parent="GridCells"]
```

Keep `CellHighlight` as a sibling so hover feedback and persistent soil have independent lifecycles.

- [ ] **Step 4: Implement visual synchronization**

In `grid_system.gd`, preload the tile script and add:

```gdscript
const FarmlandTileScript = preload("res://scripts/visual/farmland_tile.gd")


func get_farmland_visual(gx: int, gz: int) -> FarmlandTile:
	var container := get_node_or_null("GridCells/FarmlandVisuals")
	if container == null:
		return null
	return container.get_node_or_null(
		"FarmlandVisual_%d_%d" % [gx, gz]
	) as FarmlandTile


func _sync_farmland_visual(cell: GridCell) -> void:
	if cell == null:
		return
	var visual := get_farmland_visual(cell.gx, cell.gz)
	var needs_visual := cell.state in [
		GridCell.State.FARMLAND,
		GridCell.State.PLANTED,
	]
	if not needs_visual:
		if visual:
			visual.free()
		return
	if visual:
		return
	var container := get_node_or_null("GridCells/FarmlandVisuals")
	if container == null:
		return
	visual = FarmlandTileScript.new()
	if visual.configure(
		cell,
		terrain,
		WORLD_ORIGIN_X,
		WORLD_ORIGIN_Z,
		CELL_SIZE
	):
		container.add_child(visual)
	else:
		visual.free()


func rebuild_farmland_visuals() -> void:
	var container := get_node_or_null("GridCells/FarmlandVisuals")
	if container == null:
		return
	for child in container.get_children():
		child.free()
	for cell in _cells.values():
		_sync_farmland_visual(cell)
```

Call `_sync_farmland_visual(cell)` after successful changes in `set_cell_state()`, `plant_crop()`, and `harvest_crop()`. Call `rebuild_farmland_visuals()` once at the end of `from_dict()`.

When `highlight_cell()` succeeds, record the target for regression diagnostics:

```gdscript
highlight.set_meta("gx", gx)
highlight.set_meta("gz", gz)
```

- [ ] **Step 5: Run lifecycle and subsystem regression**

Run:

```bash
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: every command exits `0`; planted and harvested cells keep the soil base; building transitions remove it.

- [ ] **Step 6: Commit grid lifecycle integration**

```bash
git add \
  scenes/systems/grid_system.tscn \
  scripts/systems/grid_system.gd \
  tests/test_grid_system_complete.gd
git commit -m "feat: render farmland from grid state"
```

---

### Task 4: Visual Acceptance and Complete Verification

**Files:**
- Create: `tests/capture_main_pointer_farmland.gd`

**Interfaces:**
- Consumes: main scene `action_controller`, `grid_system`, `farming_system`, active `Camera3D`.
- Produces: `/private/tmp/villa-main-pointer-farmland.png`.

- [ ] **Step 1: Create the visual acceptance capture**

Create `tests/capture_main_pointer_farmland.gd` as a `SceneTree` script. It must:

1. Instantiate `main.tscn` with `load_save_on_start = false`.
2. Find four nearby valid cells.
3. Use slot 1 and projected event coordinates to hoe all three.
4. Use slot 6 and a projected event coordinate to plant one cell.
5. Move the pointer to a fourth valid cell and call `_process(0.0)` so the green highlight remains visible.
6. Focus the camera on the player and prepared cells.
7. Save a 1600×1000 PNG.
8. Assert before capture that there are three farmland visuals, one crop visual, and one visible highlight.

The success output must be:

```gdscript
print(
	"CAPTURED: %s farmland=%d crops=%d highlight=%s"
	% [
		OUTPUT_PATH,
		main.grid_system.get_farmland_visual_count(),
		main.farming_system.get_visual_count(),
		str(highlight.visible),
	]
)
```

Add `get_farmland_visual_count() -> int` to `GridSystem` only if the capture and tests need a public count; it returns the child count of `GridCells/FarmlandVisuals`.

- [ ] **Step 2: Run and inspect the capture**

Run:

```bash
godot --path . --script res://tests/capture_main_pointer_farmland.gd
```

Expected: exit `0` and `/private/tmp/villa-main-pointer-farmland.png` at 1600×1000.

Inspect the PNG with the local image viewer. Confirm:

- The hover square is clearly visible and aligned to one grid cell.
- Empty tilled cells read as warm hand-painted soil with furrows.
- The planted cell retains the same soil base.
- Soil does not float, clip, or show severe z-fighting.
- Palette and brush texture fit nearby terrain, vegetation, and grain.

If the capture fails visual criteria, adjust only farmland texture tint, UV orientation, alpha scissor threshold, or surface lift; rerun the capture after each single change.

- [ ] **Step 3: Run fresh complete verification**

Run:

```bash
godot --headless --editor --path . --quit
godot --headless --path . \
  --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/test_player_grid_binding.gd
godot --headless --path . --script res://tests/test_runtime_ui_scenes.gd
godot --headless --path . --script res://tests/run_tests.gd
godot --path . --quit-after 5
```

Expected: all commands exit `0`. The complete test runner may print its existing intentional duplicate-crop error and resource-leak warnings, but must report `PASS` and exit `0`.

- [ ] **Step 4: Commit visual acceptance**

```bash
git add \
  scripts/systems/grid_system.gd \
  tests/capture_main_pointer_farmland.gd \
  tests/capture_main_pointer_farmland.gd.uid
git commit -m "test: verify main farmland interaction visuals"
```

- [ ] **Step 5: Review final diff**

Run:

```bash
git status --short
git diff --check HEAD~4..HEAD
git log --oneline --decorate -6
```

Expected: clean worktree, no whitespace errors, and four focused implementation commits after the design and plan commits.
