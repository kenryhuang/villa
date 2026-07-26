# GridSystem Complete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the production GridSystem contract and provide an independently runnable visual verification scene.

**Architecture:** A reusable GridSystem scene owns one ArrayMesh grid overlay and one reusable cell highlight while its script owns all 1008 GridCell data objects. Main and the verifier inject the real TerrainBuilder, road route, and explicit blocked regions. An isolated test runner validates grid behavior without loading unrelated broken legacy tests.

**Tech Stack:** Godot 4.7.1, GDScript, ArrayMesh/SurfaceTool, existing TerrainBuilder and RoadBuilder.

## Global Constraints

- Preserve existing staged canvas and MapUI changes.
- Do not create one render node per grid cell.
- Do not change unrelated Player, Inventory, AI NPC, or legacy full-suite interfaces.
- Use production GridSystem code in both Main and the visual verifier.
- Do not commit unless the user explicitly asks.

---

### Task 1: Isolated Grid Contract Tests

**Files:**
- Create: `tests/test_grid_system_complete.gd`
- Create: `tests/run_grid_system_tests.gd`
- Modify: `tests/test_grid_system.gd`
- Modify: `tests/test_grid_mutation.gd`

**Interfaces:**
- Consumes: `TerrainBuilder.build()`, `RoadBuilder.MAIN_ROUTE`, existing GridCell states.
- Produces: an isolated command returning zero only when the complete grid contract passes.

- [ ] **Step 1: Write the failing complete-contract test**

Add assertions for `configure()` returning true, 1008 initialized cells, ROAD and explicit WATER classification, slope enforcement, `GridOverlay`, `highlight_cell()`, `clear_highlights()`, and `to_dict()/from_dict()`.

- [ ] **Step 2: Create the isolated runner**

The runner loads only grid/core data tests and prints `PASS: grid system checks`.

- [ ] **Step 3: Verify RED**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless \
  --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/run_grid_system_tests.gd
```

Expected: FAIL because the production scene and complete interfaces do not exist.

---

### Task 2: Production Grid Data, Rules, and Visuals

**Files:**
- Create: `scenes/systems/grid_system.tscn`
- Modify: `scripts/systems/grid_system.gd`

**Interfaces:**
- Produces:

```gdscript
func configure(
    terrain_node: TerrainBuilder,
    road_route: Array[Dictionary] = [],
    blocked_regions: Array[Dictionary] = []
) -> bool
func set_grid_visible(value: bool) -> void
func highlight_cell(gx: int, gz: int, color: Color) -> bool
func clear_highlights() -> void
func to_dict() -> Dictionary
func from_dict(data: Dictionary) -> bool
```

- [ ] **Step 1: Add the reusable GridSystem scene**

Create `GridOverlay`, `GridCells/CellHighlight`, and `GridData`; add the root to group `grid_system`.

- [ ] **Step 2: Initialize and classify all 1008 cells**

On configure, sample terrain height/slope for every cell, classify road distance and explicit Rect2 blocked regions, and safely rebuild on repeated configure.

- [ ] **Step 3: Enforce farming and lifecycle rules**

Make WASTELAND→FARMLAND call `can_farm_at()`. Make harvest check maturity without calling `advance_growth()`.

- [ ] **Step 4: Build single-mesh visuals**

Use one ArrayMesh for all terrain-following lines and one reusable four-corner mesh for selected-cell highlight.

- [ ] **Step 5: Add serialization**

Save changed cell fields and restore them only after base terrain/road classification exists.

- [ ] **Step 6: Verify GREEN**

Run the isolated runner and require zero failures.

---

### Task 3: Main and Save Integration

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scripts/core/save_manager.gd`
- Test: `tests/test_player_grid_binding.gd`
- Test: `tests/test_grid_system_complete.gd`

**Interfaces:**
- Consumes: `res://scenes/systems/grid_system.tscn`, GridSystem group and serialization methods.
- Produces: one shared runtime instance injected into Player, FarmingSystem, BuildingSystem and ToolSystem.

- [ ] **Step 1: Write failing integration assertions**

Assert Main uses the reusable GridSystem scene, it contains the visual nodes, has 1008 cells, and SaveManager finds it through the `grid_system` group.

- [ ] **Step 2: Verify RED**

Run `test_player_grid_binding.gd` and the isolated grid runner.

- [ ] **Step 3: Integrate the reusable scene**

Instantiate the packed scene in Main, configure it with `RoadBuilder.MAIN_ROUTE`, and retain the existing dependency injection.

- [ ] **Step 4: Replace SaveManager private/path access**

Use `get_tree().get_first_node_in_group("grid_system")`, `to_dict()`, and `from_dict()`.

- [ ] **Step 5: Verify GREEN**

Run both targeted commands and a four-second headless Main launch.

---

### Task 4: Independent Visual Verification

**Files:**
- Create: `tests/visual/grid_system_verification.tscn`
- Create: `tests/visual/grid_system_verification.gd`
- Create: `tests/test_grid_visual_scene.gd`

**Interfaces:**
- Consumes: production World, GridSystem scene, RoadBuilder route and public grid APIs.
- Produces: a standalone visual scene with hover inspection, state overlay, keyboard actions and on-screen pass/fail checks.

- [ ] **Step 1: Write the failing scene-contract test**

Assert the scene exists and has World, GridSystem, VerificationStateOverlay, Camera3D, light, StatusPanel, CellInspector and Instructions.

- [ ] **Step 2: Verify RED**

Run `test_grid_visual_scene.gd`; expect a missing-scene failure.

- [ ] **Step 3: Build the visual verifier**

Create the scene and script. Configure real terrain/grid, inject WATER and DECORATION rectangles, render state overlay, raycast hover, update inspector, and implement H/P/W/G/S/R/Esc controls.

- [ ] **Step 4: Verify GREEN**

Run the visual scene contract and isolated grid runner.

- [ ] **Step 5: Run graphical acceptance**

Launch:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /Users/huanggui/UnrealEngine/villa \
  res://tests/visual/grid_system_verification.tscn
```

Confirm the terrain, 36×28 grid, state colors, selected-cell highlight and inspector are visible with no GDScript errors.

- [ ] **Step 6: Final verification**

Run `git diff --check`, targeted tests, Main graphical launch and the verifier graphical launch. Report unrelated legacy full-suite failures separately.
