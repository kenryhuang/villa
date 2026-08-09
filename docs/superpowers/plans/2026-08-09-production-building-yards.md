# Production Building Yards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert every output-producing building into a fenced 3×3 or 4×4 production yard whose outputs remain inside the yard and whose full footprint blocks traversal.

**Architecture:** `GameData` and `BuildingData` own the authoritative yard and original-structure dimensions. A focused `BuildingProductionYard` component renders staged painted fences, exposes deterministic interior output slots, and owns perimeter-only physics. `BuildingInstance` coordinates the yard with preview, construction, maintenance, collision, output, and save restoration while the existing `BuildingSystem` continues to own grid occupancy.

**Tech Stack:** Godot 4.7, GDScript, Sprite3D SVG assets, StaticBody3D/CollisionShape3D, existing headless GDScript test runners.

---

### Task 1: Production-yard data contract

**Files:**
- Modify: `scripts/core/game_data.gd`
- Modify: `scripts/data/building_data.gd`
- Modify: `tests/test_building_data.gd`
- Modify: `tests/test_building_catalog.gd`

- [x] **Step 1: Write failing data tests**

Add the exact 11-building mapping and assert that output-producing buildings expose valid yard profiles while excluded buildings do not:

```gdscript
const EXPECTED_YARDS := {
    "workbench": [Vector2i(3, 3), Vector2i(1, 1), "timber", 6],
    "stone_kiln": [Vector2i(3, 3), Vector2i(2, 2), "masonry", 6],
    "furnace": [Vector2i(3, 3), Vector2i(2, 2), "industrial", 6],
    "windmill": [Vector2i(3, 3), Vector2i(2, 2), "timber", 6],
    "food_workshop": [Vector2i(4, 4), Vector2i(3, 2), "timber", 8],
    "textile_machine": [Vector2i(3, 3), Vector2i(2, 2), "timber", 6],
    "chicken_coop": [Vector2i(3, 3), Vector2i(2, 2), "timber", 6],
    "beehive": [Vector2i(3, 3), Vector2i(1, 1), "timber", 6],
    "lumberyard": [Vector2i(4, 4), Vector2i(3, 2), "timber", 8],
    "quarry": [Vector2i(4, 4), Vector2i(3, 3), "masonry", 8],
    "mine": [Vector2i(4, 4), Vector2i(3, 3), "industrial", 8],
}
```

Also assert malformed styles, mismatched authoritative footprints, non-negative offsets, and insufficient slot counts are rejected by `BuildingData.is_valid()`.

- [x] **Step 2: Run the building suite and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: FAIL because `BuildingData` has no `production_yard`, `structure_footprint`, or yard helpers and the catalog still exposes the old footprints.

- [x] **Step 3: Implement the data contract**

Add exported data and helpers:

```gdscript
@export var production_yard: Dictionary = {}

func has_production_yard() -> bool:
    return not production_yard.is_empty()

func structure_footprint() -> Vector2i:
    return production_yard.get("structure_footprint", footprint)

func production_yard_style() -> String:
    return str(production_yard.get("style", ""))
```

Parse a deep copy in `from_dictionary`, validate styles against `timber`, `masonry`, and `industrial`, and require `production_yard.size == footprint`. Update the 11 `GameData.BUILDINGS` records with their confirmed yard footprint and profile without changing costs, effects, stations, or output capacities.

- [x] **Step 4: Run the building suite and require GREEN**

- [x] **Step 5: Commit**

```powershell
git add scripts/core/game_data.gd scripts/data/building_data.gd tests/test_building_data.gd tests/test_building_catalog.gd
git commit -m "feat: define production building yards"
```

### Task 2: Painted fence assets and yard component

**Files:**
- Create: `assets/buildings/yards/timber_yard_fence.svg`
- Create: `assets/buildings/yards/masonry_yard_fence.svg`
- Create: `assets/buildings/yards/industrial_yard_fence.svg`
- Create: `scripts/buildings/building_production_yard.gd`
- Create: `tests/test_building_production_yard.gd`
- Modify: `tests/run_building_system_tests.gd`
- Modify: `tests/test_building_art_assets.gd`

- [x] **Step 1: Write failing component and asset tests**

Assert each atlas exists, is an SVG with the documented 4-row × 2-column stage/orientation contract, and the component can:

```gdscript
var yard := BuildingProductionYard.new()
yard.configure(Vector2i(3, 3), "timber", Vector3(0, 0, -0.35))
assert(yard.get_fence_segment_count() == 12)
assert(yard.get_output_slots().size() == 6)
assert(yard.all_output_slots_inside_bounds())
yard.set_construction_stage(BuildingInstance.ConstructionStage.FRAME)
assert(yard.get_construction_stage() == BuildingInstance.ConstructionStage.FRAME)
```

Test 4×4 segment count, style validation, back/side/front layers, preview tint, maintenance tint, collision-layer isolation, and immediate cleanup.

- [x] **Step 2: Run and verify RED**

Expected: preload failures for the missing component and SVG assets.

- [x] **Step 3: Create the three painted SVG atlases**

Use hand-drawn uneven outlines, warm shadows, and style-specific palettes. Each atlas supplies front and side variants for foundation, frame, half-built, and complete states. Do not use plain untextured geometry as the completed visual.

- [x] **Step 4: Implement `BuildingProductionYard`**

The component must expose:

```gdscript
func configure(size: Vector2i, style: String, structure_offset: Vector3) -> bool
func set_preview_state(active: bool, valid: bool) -> void
func set_construction_stage(stage: int) -> void
func set_maintenance_state(state: String) -> void
func set_interaction_enabled(enabled: bool) -> void
func get_output_slots() -> Array[Vector3]
func get_fence_segment_count() -> int
func has_enabled_collisions() -> bool
func clear_immediately() -> void
```

Generate perimeter-only box collisions on the player/world layer. Fence bodies must not use output interaction layer 128 or building interaction layer 64. Produce six front-zone slots for 3×3 and eight for 4×4, all inside the fence boundary and clear of the shifted structure footprint.

- [x] **Step 5: Run component and building tests and require GREEN**

- [x] **Step 6: Commit**

```powershell
git add assets/buildings/yards scripts/buildings/building_production_yard.gd tests/test_building_production_yard.gd tests/run_building_system_tests.gd tests/test_building_art_assets.gd
git commit -m "feat: add painted production yard fences"
```

### Task 3: Integrate yards with building lifecycle and physics

**Files:**
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `scripts/buildings/construction_feedback.gd`
- Modify: `scripts/buildings/building_maintenance_visual.gd`
- Modify: `tests/test_building_instance.gd`
- Modify: `tests/test_building_construction_state.gd`
- Modify: `tests/test_building_maintenance_visual.gd`

- [x] **Step 1: Write failing lifecycle tests**

Instantiate each production building and assert it owns `ProductionYard`; excluded buildings do not. Verify:

```gdscript
assert(building.get_node("ProductionYard") is BuildingProductionYard)
assert(building.data.footprint == Vector2i(3, 3))
assert(building.get_structure_footprint() == Vector2i(1, 1))
assert(building.get_node("Collision/CollisionShape3D").shape.size.x < 2.0)
```

Assert preview tint propagates, every construction stage propagates, the whole grid footprint is blocked from placement time, perimeter collisions enable outside preview, removal clears them, and maintenance/construction feedback remains anchored to the shifted structure rather than the yard corner.

- [x] **Step 2: Run and verify RED**

- [x] **Step 3: Integrate the component**

Create/configure `ProductionYard` in `_ensure_nodes()` and `configure()`. Shift `VisualRoot`, activity, maintenance, construction art, and feedback together by `building_offset_z`. Change `_configure_physics()` to size `Collision`, `InteractionArea`, and `CameraOccluder` from `data.structure_footprint()` while the yard owns perimeter collisions. Forward preview, construction, maintenance, visibility, deactivate, and cleanup state to the yard.

- [x] **Step 4: Preserve repair economics**

Change `EconomyProgressionSystem.get_maintenance_quote()` to use `building.get_structure_footprint()` and extend its tests so a former 1×1 workbench still receives the 1–2-cell quote after becoming a 3×3 yard.

- [x] **Step 5: Run building and progression suites and require GREEN**

- [x] **Step 6: Commit**

```powershell
git add scripts/buildings scripts/systems/economy_progression_system.gd tests/test_building_instance.gd tests/test_building_construction_state.gd tests/test_building_maintenance_visual.gd tests/test_economy_progression.gd
git commit -m "feat: integrate production yard lifecycle"
```

### Task 4: Keep every output pile inside the fenced collection zone

**Files:**
- Modify: `scripts/buildings/building_output_display.gd`
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `tests/test_building_output_display.gd`
- Modify: `tests/test_building_instance.gd`
- Modify: `tests/test_building_economy_ui.gd`
- Modify: `tests/test_main_farming_building_integration.gd`

- [x] **Step 1: Write failing output-layout tests**

Replace exterior-position expectations with yard-slot expectations. Assert stable sorted assignment, all slots are inside the front half, no two slots overlap, stone-kiln charcoal and bricks both receive hover text and collection, and an artificial ninth output is retained in producer state without producing an overlapping pile in a 4×4 yard.

- [x] **Step 2: Run building UI and building suites and verify RED**

- [x] **Step 3: Route layout through the yard**

Add `configure_for_yard(slots, building_id)` to `BuildingOutputDisplay`. Use the supplied local positions directly and cap visual pile creation to slot count. Keep `_positive_item_ids()` sorted, preserve hidden output inventory, and leave collection signals and animations unchanged.

`BuildingInstance._sync_output_display_state()` supplies `ProductionYard.get_output_slots()` for yard buildings and retains the existing layout only for non-yard buildings.

- [x] **Step 4: Run affected suites and require GREEN**

- [x] **Step 5: Commit**

```powershell
git add scripts/buildings/building_output_display.gd scripts/buildings/building_instance.gd tests/test_building_output_display.gd tests/test_building_instance.gd tests/test_building_economy_ui.gd tests/test_main_farming_building_integration.gd
git commit -m "feat: place outputs inside production yards"
```

### Task 5: Enforce the incompatible layout save version

**Files:**
- Modify: `scripts/core/save_manager.gd`
- Modify: `tests/test_economy_save_integration.gd`
- Modify: `tests/test_building_save_integration.gd`

- [ ] **Step 1: Write failing save tests**

Assert new saves contain `building_layout_version == 2`. Assert a complete payload with grid/buildings but a missing, fractional, negative, or non-2 version is rejected atomically. Assert a version-2 save round-trips complete yard `occupied_cells`, queued jobs, outputs, and maintenance repair state.

- [ ] **Step 2: Run focused save tests and verify RED**

```powershell
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
```

- [ ] **Step 3: Implement version validation**

Add `const BUILDING_LAYOUT_VERSION := 2`, serialize it whenever grid/building snapshots are emitted, and require the exact integer version before validating either snapshot. Reject legacy layout data before mutating runtime state.

- [ ] **Step 4: Run save, production-chain, and main integration suites and require GREEN**

- [ ] **Step 5: Commit**

```powershell
git add scripts/core/save_manager.gd tests/test_economy_save_integration.gd tests/test_building_save_integration.gd
git commit -m "feat: version production yard saves"
```

### Task 6: End-to-end production-yard verification

**Files:**
- Modify only when an in-scope verification failure identifies a defect.
- Modify: `docs/superpowers/plans/2026-08-09-production-building-yards.md` for checkbox tracking.

- [ ] **Step 1: Run formatting and repository checks**

```powershell
git diff --check
git status --short
```

- [ ] **Step 2: Run all affected suites with full output**

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_production_system_tests.gd
godot --headless --path . --script res://tests/run_economy_progression_tests.gd
godot --headless --path . --script res://tests/run_building_economy_ui_tests.gd
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
godot --headless --path . --script res://tests/run_production_chain_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

- [ ] **Step 3: Review every acceptance criterion**

Confirm all 11 buildings, exact sizes, three painted styles, staged construction, full traversal blocking, interior output interaction, unchanged economics, version-2 save rejection, and complete lifecycle behavior.

- [ ] **Step 4: Commit final corrections**

```powershell
git add -A
git commit -m "fix: complete production building yards"
```
