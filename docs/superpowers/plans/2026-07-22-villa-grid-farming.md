# Villa Grid and Farming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the 36 by 28 terrain-aware GridSystem and deterministic daily FarmingSystem with crop visuals, using only the Core Foundation public contracts.
**Architecture:** GridSystem owns sparse GridCell storage, world conversion, terrain slope checks, state transitions, and visual markers. FarmingSystem owns daily crop progression and calls GridSystem for authoritative state changes; it never owns cells itself. CropVisual is a per-cell scene child that changes a simple phase-colored mesh now and can later replace it with Sprite3D assets.
**Tech Stack:** Godot 4.7, GDScript, Jolt Physics, Node3D/MeshInstance3D, headless GDScript tests.

## Global Constraints
- Execute core-foundation before this plan. Consume only GridCell, CropData, CropInstance, EventBus, GameData, GameState, SeasonSystem public interfaces declared there.
- Use world size 36.0 by 28.0, cell size 1.0, origin (-18.0,-14.0), valid coordinates gx 0..35 and gz 0..27, and grid center gx-17.5/gz-13.5.
- Store cells in GridSystem dictionary key gx * 1000 + gz. Create cells lazily; no 1008-node visual grid is allowed.
- GridCell state transition is WASTELAND to FARMLAND to PLANTED to FARMLAND. BUILDING, ROAD, WATER, DECORATION are unavailable to farming.
- A slope greater than 0.35 is not farmable. Use terrain heights at center, +0.5 X, +0.5 Z exactly as detailed-design §1.2.
- plant requires FARMLAND and a non-null CropData. harvest requires a mature PLANTED cell. water requires FARMLAND or PLANTED.
- Farming advances only on EventBus.day_changed. Watered crops add `1.5` growth progress; unwatered crops add `1.0`, then all cell/crop water flags reset. Seasons outside CropData.seasons block growth; empty seasons permit growth.
- Emit cell_state_changed, cell_watered, crop_planted, crop_grew, crop_matured, crop_harvested exactly once per accepted change.
- Crop stage color is seed brown, sprout green, growing yellow-green, mature gold. Visual updates are event-driven, never a per-frame grid scan.
- This plan does not create SaveManager or serialization; a later save plan owns persistence.
---

## File Structure
| Path | Responsibility |
|---|---|
| scripts/systems/grid_system.gd | Sparse cell data, coordinate/slope/state operations. |
| scripts/systems/farming_system.gd | Daily progression, plant/harvest/water orchestration. |
| scripts/world/crop_visual.gd | Event-driven per-crop phase mesh. |
| scenes/world/crop_visual.tscn | Reusable visual scene. |
| scenes/main.tscn | Systems container with SeasonSystem, GridSystem, and FarmingSystem. |
| scripts/main.gd | Supplies World/Terrain and system dependencies after world initialization. |
| tests/test_grid_system.gd | Pure conversion/slope/state tests. |
| tests/test_farming_system.gd | Daily growth, seasonal, reward tests. |
| tests/test_crop_visual.gd | Phase/color update tests. |
### Task 1: Grid conversion, sparse cells, and terrain farming gate
**Files:**
- Create: scripts/systems/grid_system.gd
- Modify: scripts/main.gd
- Modify: scenes/main.tscn
- Create: tests/test_grid_system.gd
- Modify: tests/run_tests.gd
**Interfaces:**
- Consumes TerrainBuilder.get_height_at(x: float, z: float) -> float and GridCell.
- Produces world_to_grid(wx,wz) -> Vector2i, grid_to_world(gx,gz) -> Vector2, get_cell, get_cell_at_world, get_cells_in_rect, `get_terrain_height_at_cell(gx, gz) -> float`, get_slope_at_cell, can_farm_at, is_cell_available.
- [ ] **Step 1: Write the failing grid test**
~~~
assertions.equal(grid.world_to_grid(-18.0, -14.0), Vector2i(0, 0), "world origin maps first cell")
assertions.equal(grid.world_to_grid(17.999, 13.999), Vector2i(35, 27), "upper edge maps final cell")
assertions.equal(grid.grid_to_world(0, 0), Vector2(-17.5, -13.5), "grid center maps world")
assertions.equal(grid.get_cells_in_rect(34, 26, 2, 2).size(), 4, "rect includes valid corner cells")
assertions.truthy(not steep_grid.can_farm_at(3, 4), "slope above 0.35 blocks farming")
~~~
- [ ] **Step 2: Run RED**
Run: godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
Expected: FAIL because grid_system.gd is absent.
- [ ] **Step 3: Implement sparse coordinate and slope methods**
~~~
static func cell_key(gx: int, gz: int) -> int:
	return gx * 1000 + gz
func world_to_grid(wx: float, wz: float) -> Vector2i:
	return Vector2i(floori(wx + 18.0), floori(wz + 14.0))
func grid_to_world(gx: int, gz: int) -> Vector2:
	return Vector2(float(gx) - 17.5, float(gz) - 13.5)
func get_slope_at_cell(gx: int, gz: int) -> float:
	var point := grid_to_world(gx, gz)
	var center := terrain.get_height_at(point.x, point.y)
	var sx := absf(terrain.get_height_at(point.x + 0.5, point.y) - center) / 0.5
	var sz := absf(terrain.get_height_at(point.x, point.y + 0.5) - center) / 0.5
	return sqrt(sx * sx + sz * sz)
~~~
Return null for out-of-bounds get_cell/get_cell_at_world. get_cells_in_rect returns only valid cells, ordered gz then gx. Lazily create a cell with height/slope once. can_farm_at requires in-bounds, slope <=0.35, and state not WATER/BUILDING/ROAD/DECORATION. Main creates a single `Systems` parent containing `SeasonSystem` and `GridSystem`, then calls `grid_system.configure(world.terrain)` only after terrain build succeeds.
`get_terrain_height_at_cell` returns the cached cell height and returns `NAN` for an invalid coordinate; BuildingSystem rejects non-finite heights.
- [ ] **Step 4: Run GREEN**
Run standard tests. Expected: coordinate boundary, key uniqueness, rect order, lazy height, and slope tests pass.
- [ ] **Step 5: Commit**
~~~
git add scripts/systems/grid_system.gd scripts/main.gd scenes/main.tscn tests/test_grid_system.gd tests/run_tests.gd
git commit -m "feat: add terrain-aware farming grid"
~~~
### Task 2: Grid state mutation and event contract
**Files:**
- Modify: scripts/systems/grid_system.gd
- Create: tests/test_grid_mutation.gd
- Modify: tests/run_tests.gd
**Interfaces:**
- Produces set_cell_state(gx,gz,state) -> bool, plant_crop(gx,gz,crop) -> CropInstance, harvest_crop(gx,gz) -> Dictionary, water_cell(gx,gz) -> bool, highlight_cell(gx,gz,color), clear_highlights().
- Consumes EventBus cell/crop signals and CropData/CropInstance.
- [ ] **Step 1: Write the failing state/event test**
~~~
assertions.truthy(grid.set_cell_state(2, 2, GridCellScript.State.FARMLAND), "cultivates wasteland")
assertions.truthy(not grid.set_cell_state(2, 2, GridCellScript.State.PLANTED), "cannot skip planting")
var crop = grid.plant_crop(2, 2, crop_data)
assertions.truthy(crop != null, "planting returns instance")
assertions.truthy(grid.water_cell(2, 2), "planting can be watered")
assertions.equal(grid.get_cell(2, 2).state, GridCellScript.State.PLANTED, "cell remains planted")
~~~
- [ ] **Step 2: Run RED**
Run standard tests. Expected: FAIL because mutation APIs/transition checks do not exist.
- [ ] **Step 3: Implement validated transitions and marker lifecycle**
~~~
func set_cell_state(gx: int, gz: int, next_state: GridCell.State) -> bool:
	var cell := get_cell(gx, gz)
	if cell == null or not _transition_allowed(cell.state, next_state): return false
	cell.state = next_state
	EventBus.cell_state_changed.emit(cell)
	return true
func plant_crop(gx: int, gz: int, crop: CropData) -> CropInstance:
	if crop == null or not is_cell_available(gx, gz, GridCell.State.FARMLAND): return null
	var cell := get_cell(gx, gz)
	cell.crop_instance = CropInstance.new(); cell.crop_instance.crop_data = crop; cell.crop_instance.cell = cell
	cell.state = GridCell.State.PLANTED
	EventBus.cell_state_changed.emit(cell); EventBus.crop_planted.emit(cell, crop)
	return cell.crop_instance
~~~
Allow WASTELAND→FARMLAND, FARMLAND→PLANTED, PLANTED→FARMLAND, WASTELAND/FARMLAND→BUILDING, BUILDING→WASTELAND/FARMLAND, and any state to itself. The building transitions are reserved for validated BuildingSystem placement/removal and preserve no hidden state; BuildingInstance owns the prior-state records. Harvest rejects non-mature, returns {"items":[crop_data.crop_id], "exp":crop_data.exp_reward}, clears crop/water, moves state to FARMLAND, and emits crop_harvested then cell_state_changed. water accepts FARMLAND/PLANTED, sets cell.watered and CropInstance.is_watered_today, emits cell_watered once. Highlights instantiate at most one CellMarker per key under GridCells and clear_highlights queue_frees all markers.
- [ ] **Step 4: Run GREEN**
Run standard tests. Expected: invalid transition, emissions, mature-only harvest, water flags, and marker replacement tests pass.
- [ ] **Step 5: Commit**
~~~
git add scripts/systems/grid_system.gd tests/test_grid_mutation.gd tests/run_tests.gd
git commit -m "feat: manage grid crop states"
~~~
### Task 3: Daily FarmingSystem and crop visuals
**Files:**
- Create: scripts/systems/farming_system.gd
- Create: scripts/world/crop_visual.gd
- Create: scenes/world/crop_visual.tscn
- Modify: scenes/main.tscn
- Create: tests/test_farming_system.gd
- Create: tests/test_crop_visual.gd
- Modify: tests/run_tests.gd
**Interfaces:**
- Consumes GridSystem plant_crop/harvest_crop/water_cell, injected SeasonSystem.current_season, injected GameState.add_exp, EventBus.day_changed.
- Produces `configure(grid_system: GridSystem, season_system: SeasonSystem, game_state: Node) -> void`, plant(grid_cell,crop) -> CropInstance, harvest(grid_cell) -> Dictionary, water(grid_cell) -> bool, on_day_changed(day), get_all_planted_cells() -> Array[GridCell].
- Produces CropVisual.set_stage(stage: int, total_stages: int) -> void.
- [ ] **Step 1: Write the failing daily-growth test**
~~~
farming.plant(grid.get_cell(1, 1), crop_data)
farming.water(grid.get_cell(1, 1))
farming.on_day_changed(2)
assertions.near(grid.get_cell(1, 1).crop_instance.growth_progress, 1.5, 0.001, "watered daily growth")
assertions.truthy(not grid.get_cell(1, 1).watered, "cell water resets")
farming.on_day_changed(3)
assertions.truthy(grid.get_cell(1, 1).crop_instance.is_mature, "matures at crop days")
assertions.equal(farming.harvest(grid.get_cell(1, 1)).exp, crop_data.exp_reward, "harvest returns xp")
~~~
- [ ] **Step 2: Run RED**
Run standard tests. Expected: FAIL because FarmingSystem and CropVisual are absent.
- [ ] **Step 3: Implement daily loop and visual update**
~~~
func on_day_changed(_day: int) -> void:
	for cell in get_all_planted_cells():
		var instance := cell.crop_instance
		if not _can_grow(instance.crop_data): _clear_water(cell); continue
		var old_stage := instance.get_current_stage()
		var became_mature := instance.advance_growth()
		_clear_water(cell)
		if instance.get_current_stage() != old_stage: EventBus.crop_grew.emit(cell, instance.get_current_stage())
		if became_mature: EventBus.crop_matured.emit(cell, instance.crop_data)
		_update_visual(cell)
func _can_grow(data: CropData) -> bool:
	return data.seasons.is_empty() or season_system.current_season in data.seasons
~~~
Add FarmingSystem under the existing Main/Systems node and call `configure(grid_system, season_system, GameState)` from Main. Connect day_changed in _ready. plant delegates only to GridSystem and creates CropVisual at cell.world_position_3d; water delegates; harvest delegates then calls injected `game_state.add_exp(result.exp)` and removes visual. CropVisual contains one MeshInstance3D/BoxMesh and set_stage assigns colors brown, green, yellow-green, gold for stage 0,1,2,final. No process function is permitted in FarmingSystem or CropVisual.
- [ ] **Step 4: Run GREEN and scene import**
~~~
godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
~~~
Expected: exit 0; daily, seasonal block, one-time mature signal, harvest XP, and visual color tests pass.
- [ ] **Step 5: Commit**
~~~
git add scripts/systems/farming_system.gd scripts/world/crop_visual.gd scenes/world/crop_visual.tscn scenes/main.tscn scripts/main.gd tests/test_farming_system.gd tests/test_crop_visual.gd tests/run_tests.gd
git commit -m "feat: grow and harvest grid crops"
~~~
### Task 4: Grid/Farming completion gate
**Files:**
- Verify only.
**Interfaces:**
- Produces GridSystem/FarmingSystem contracts for tools, inventory, and later SaveManager.
- [ ] **Step 1: Run full verification**
~~~
godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 120
git diff --check
~~~
Expected: every command exits 0; no 1008-cell visual allocation, and no save file is created.
- [ ] **Step 2: Commit verification record**
~~~
git status --short
git log -3 --oneline
~~~
Expected: Task 1–3 commits are visible; verification creates no commit.
