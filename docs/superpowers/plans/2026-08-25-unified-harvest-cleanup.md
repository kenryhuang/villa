# Unified Harvest Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the “点击收割” world-space hint and make every successful crop harvest clear the crop while leaving an empty cultivated `FARMLAND` cell ready for replanting.

**Architecture:** `PlayerActionController` keeps mature-crop action priority and gold hover highlighting, but no longer produces hover text. `GridSystem` returns to a single reusable tile highlight with no `Label3D`. `FarmingSystem.preview_harvest()` remains the authoritative source of post-harvest state and now emits one uniform cleanup snapshot for every supported lifecycle type; the existing atomic transaction applies that snapshot and removes the visual only after storage and farming operations can commit together.

**Tech Stack:** Godot 4.4, GDScript, Godot scenes, custom headless test runners.

---

## File map

- `tests/test_grid_system_complete.gd`: require the grid scene to contain no harvest text node while preserving tile highlighting.
- `tests/test_player_action_controller.gd`: require no controller hover-text API while preserving mature-crop priority in P mode.
- `scenes/systems/grid_system.tscn`: remove the `CellHint` `Label3D`.
- `scripts/systems/grid_system.gd`: remove hint parameters and visibility management from the highlight API.
- `scripts/actors/player_action_controller.gd`: stop generating or passing “点击收割”.
- `tests/test_crop_economy.gd`: replace regrowth expectations with uniform crop removal, visual removal, transaction coherence, and save/load coverage.
- `scripts/systems/farming_system.gd`: make every supported lifecycle preview resolve to empty `FARMLAND`.

### Task 1: Remove harvest hover text

**Files:**
- Modify: `tests/test_grid_system_complete.gd`
- Modify: `tests/test_player_action_controller.gd`
- Modify: `scenes/systems/grid_system.tscn`
- Modify: `scripts/systems/grid_system.gd`
- Modify: `scripts/actors/player_action_controller.gd`

- [ ] **Step 1: Replace hint-presence tests with hint-absence contracts**

In the grid highlight test, retain all `CellHighlight` assertions and replace the `CellHint` display/reuse/hide assertions with:

```gdscript
assertions.truthy(
	not grid.has_node("GridCells/CellHint"),
	"grid scene contains no harvest text hint",
)
```

In the controller test, replace calls to `cell_hover_hint()` with:

```gdscript
assertions.truthy(
	not controller.has_method("cell_hover_hint"),
	"controller exposes no harvest text hint",
)
```

- [ ] **Step 2: Verify the new contracts fail against the current implementation**

Run:

```powershell
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_player_action_controller_tests.gd
```

Expected: the grid suite reports that `CellHint` still exists and the controller suite reports that `cell_hover_hint()` still exists.

- [ ] **Step 3: Remove the hint implementation without changing mature-crop selection**

Delete the `CellHint` node from `grid_system.tscn`. Change the grid method back to:

```gdscript
func highlight_cell(gx: int, gz: int, color: Color) -> bool:
```

Delete its `hint_text` handling and the `CellHint` block in `clear_highlights()`. In `PlayerActionController._process()`, call:

```gdscript
grid_system.highlight_cell(cell.gx, cell.gz, _highlight_color(cell, ground_point))
```

Delete `cell_hover_hint()`. Preserve `_is_mature()`, the gold `_highlight_color()`, no-slot P-mode scanning, and mature harvest priority.

- [ ] **Step 4: Verify hint removal**

Run the two commands from Step 2. Expected: the grid suite passes; the controller suite returns to its existing passing baseline.

- [ ] **Step 5: Commit**

```powershell
git add scenes/systems/grid_system.tscn scripts/systems/grid_system.gd scripts/actors/player_action_controller.gd tests/test_grid_system_complete.gd tests/test_player_action_controller.gd
git commit -m "fix: remove harvest hover text"
```

### Task 2: Make every successful harvest clear the crop

**Files:**
- Modify: `tests/test_crop_economy.gd`
- Modify: `scripts/systems/farming_system.gd`

- [ ] **Step 1: Rewrite lifecycle tests around one post-harvest invariant**

Update the all-crop roster contract so every preview asserts:

```gdscript
assertions.equal(
	int(harvest_preview.get("post_cell_state", -1)),
	GridCell.State.FARMLAND,
	"%s harvest leaves cultivated farmland" % crop_id,
)
assertions.equal(harvest_preview.get("post_crop"), null, "%s harvest clears its crop" % crop_id)
assertions.equal(harvest_preview.get("regrowing", true), false, "%s harvest does not retain regrowth" % crop_id)
```

Replace the tomato regrowth test with a deterministic-yield-and-cleanup test: keep exact tomato yield and experience checks, then assert `FARMLAND`, `crop_instance == null`, and that a second harvest is unavailable until replanting.

Replace the harvested-regrowing-crop save/load test with a cleanup round trip: after harvesting tomato, serialize and restore the grid, then assert the restored cell is `FARMLAND` with no crop data or crop instance.

Update the atomic controller success-path observer and assertions so committed state means `FARMLAND`, no crop instance, and no crop visual. Keep every injected failure assertion unchanged: failures must retain the mature crop and its visual.

Update the perennial and visual tests so apple, peach, grape, lemon, and the visual fixture all assert no regrowth, empty `FARMLAND`, and removed visuals. Rename helper methods and their calls where their old names claim regrowth.

- [ ] **Step 2: Verify the updated farming contract fails on retained crop types**

Run:

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
```

Expected: new failures for `annual_regrow`, `bush`, `tree`, and `vine` cleanup assertions in addition to the three recorded unrelated seed quick-slot baseline failures.

- [ ] **Step 3: Simplify the authoritative post-harvest preview**

Keep the supported lifecycle guard in `FarmingSystem.preview_harvest()`, but remove its regrowth branch. Return these values for every supported mature crop:

```gdscript
"regrowing": false,
"post_growth_progress": 0.0,
"post_lifecycle_state": null,
"post_cell_state": GridCell.State.FARMLAND,
"post_harvest_count": instance.harvest_count + 1,
"post_crop": null,
```

Do not change crop definitions, planting rules, yield calculation, storage routing, or rollback snapshots. The existing publication path will take the non-regrowing branch and remove the crop visual.

- [ ] **Step 4: Verify focused behavior and recorded baselines**

Run:

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_player_action_controller_tests.gd
godot --headless --path . --script res://tests/run_grid_system_tests.gd
```

Expected: no new harvest-related failure. The farming runner may retain only its three recorded unrelated seed quick-slot failures; controller and grid runners pass.

- [ ] **Step 5: Commit**

```powershell
git add scripts/systems/farming_system.gd tests/test_crop_economy.gd
git commit -m "fix: clear all crops after harvest"
```

### Task 3: Final regression and handoff

**Files:**
- Verify only

- [ ] **Step 1: Run integration and full regression checks**

```powershell
godot --headless --path . --script res://tests/run_inventory_storage_ui_tests.gd
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path . --script res://tests/run_tests.gd
git diff --check
git status --short --branch
```

Expected: the change introduces no harvest regressions. Compare any failures with the recorded branch baselines: economy/save `45/1507` plus three existing script errors, main `2/1778`, and full runner `3/3055`. `git diff --check` must produce no output and the implementation worktree must be clean after the two implementation commits.

- [ ] **Step 2: Review the committed diff against the approved design**

Run:

```powershell
git log --oneline -3
git diff HEAD~2..HEAD -- scenes/systems/grid_system.tscn scripts/systems/grid_system.gd scripts/actors/player_action_controller.gd scripts/systems/farming_system.gd tests/test_grid_system_complete.gd tests/test_player_action_controller.gd tests/test_crop_economy.gd
```

Confirm the diff changes only hover text and post-harvest cleanup, preserves transaction rollback behavior, and leaves crop lifecycle metadata intact.
