# Building Utility Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make greenhouse planting, waterwheel irrigation, and resource-building output visible, functional, collectible, and save-safe.

**Architecture:** Keep greenhouse crops on the authoritative world grid, publish waterwheel coverage as a persistent farming environment, and drive all `resource_output` buildings from the existing authoritative game-minute clock. Store resource-cycle progress in `ProductionSystem` and expose typed snapshots to the existing building status UI.

**Tech Stack:** Godot 4.7, GDScript, existing RefCounted test runners, `GridSystem`, `FarmingSystem`, `ProductionSystem`, Control-based economy UI.

---

### Task 1: Persistent waterwheel irrigation

**Files:**
- Modify: `tests/test_farming_system.gd`
- Modify: `tests/test_production_system.gd`
- Modify: `scripts/systems/farming_system.gd`
- Modify: `scripts/systems/production_system.gd`

- [ ] **Step 1: Write failing farming tests**

Add assertions that `set_automatic_irrigation_cells([Vector2i(...)])` gives a planted crop `1.5x` minute growth before and after `on_day_changed()`, while removing the cell restores `1.0x` growth.

- [ ] **Step 2: Run the farming suite and verify RED**

Run: `godot_console --headless --path . --script res://tests/run_farming_system_tests.gd`

Expected: failure because automatic irrigation APIs do not exist.

- [ ] **Step 3: Implement the farming environment**

Add an automatic-irrigation key set to `FarmingSystem`, public setter/query methods, and use it in the continuous growth multiplier:

```gdscript
var multiplier := 1.5 if (
    cell.watered
    or instance.is_watered_today
    or is_automatically_irrigated_cell(cell)
) else 1.0
```

- [ ] **Step 4: Write failing production coverage tests**

Cover active waterside waterwheels, invalid water placement, maintenance pause, repair, removal, and verify `apply_daily_effects()` no longer writes ordinary water flags.

- [ ] **Step 5: Implement authoritative coverage publication**

Build and publish all active waterwheel coverage positions from `ProductionSystem` whenever building/environment state changes. Keep `get_irrigated_cells()` as the filtered UI view.

- [ ] **Step 6: Run focused suites and verify GREEN**

Run both farming and production test runners. Expected: zero failures in both focused suites.

### Task 2: Game-minute resource production cycles

**Files:**
- Modify: `scripts/core/game_data.gd`
- Modify: `scripts/systems/production_system.gd`
- Modify: `tests/test_production_system.gd`

- [ ] **Step 1: Write failing cycle tests**

Add exact boundary tests for lumberyard/quarry 180 minutes and mine 240 minutes, multi-cycle advancement, every-third-cycle bonuses, maintenance pause, output-full pause, and collection recovery.

- [ ] **Step 2: Run production tests and verify RED**

Run: `godot_console --headless --path . --script res://tests/run_production_system_tests.gd`

Expected: cycle snapshot or cycle output assertions fail.

- [ ] **Step 3: Add cycle configuration and runtime state**

Replace daily resource output configuration with `cycle_minutes`, `cycle_output`, and `bonus_every_cycles`. Add:

```gdscript
var resource_cycle_progress: Dictionary = {}
var resource_completed_cycles: Dictionary = {}
```

Advance resource cycles from `advance_minutes()`, validate storage per completion, emit `production_output_changed`, `production_job_completed`, and transition-only `production_output_blocked` events.

- [ ] **Step 4: Remove duplicate daily resource settlement**

Keep daily passive settlement for beehives and chicken coops only. Resource buildings must never also produce through `finish_daily_outputs()`.

- [ ] **Step 5: Run production tests and verify GREEN**

Expected: exact cycle and existing recipe/passive tests pass.

### Task 3: Save and restore resource cycles

**Files:**
- Modify: `scripts/systems/production_system.gd`
- Modify: `tests/test_production_system.gd`
- Modify: `tests/test_economy_save_integration.gd`

- [ ] **Step 1: Write failing serialization tests**

Require deterministic version-3 `resource_cycles` records, exact restoration, v1/v2 zero-state migration, and atomic rejection of duplicate keys, negative values, non-integers, or progress at/above the configured safe maximum.

- [ ] **Step 2: Run focused tests and verify RED**

Expected: version and missing field assertions fail.

- [ ] **Step 3: Implement version-3 serialization**

Serialize stable records:

```gdscript
{
    "building_key": key,
    "progress_minutes": int(resource_cycle_progress[key]),
    "completed_cycles": int(resource_completed_cycles[key]),
}
```

Accept versions 1–2 with empty cycle dictionaries and version 3 with strict validation. Clear orphaned keys during building removal/reset.

- [ ] **Step 4: Verify save and production suites**

Run production and economy-save integration runners; compare the latter against its recorded 45/1507 baseline.

### Task 4: Greenhouse and resource status UI

**Files:**
- Modify: `scripts/ui/world_range_overlay.gd`
- Modify: `scripts/ui/building_status_panel.gd`
- Modify: `scenes/ui/economy/building_status_panel.tscn`
- Modify: `scripts/ui/building_economy_ui.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_building_economy_ui.gd`

- [ ] **Step 1: Write failing typed-view and interaction tests**

Require greenhouse plot counts (`tilled`, `planted`, `mature`), waterwheel `growth_multiplier`, resource `cycle_status/progress/remaining`, greenhouse range preview, and a `planting_requested` signal that closes the modal and selects the hoe in farming mode.

- [ ] **Step 2: Run the economy UI suite and verify RED**

Expected: new fields and greenhouse action are absent.

- [ ] **Step 3: Expose runtime snapshots**

Add `ProductionSystem.get_greenhouse_plot_snapshot()` and `get_resource_cycle_snapshot()` so UI rendering never reimplements authority rules.

- [ ] **Step 4: Implement reusable panel actions**

Allow `WorldRangeOverlay.show_cells()` to take a supplied color. Let the status panel use range preview for both waterwheel and greenhouse, add a greenhouse “开始种植” button/signal, and render resource progress/status clearly in a scroll-safe layout.

- [ ] **Step 5: Wire Main gameplay transition**

On greenhouse planting request, close the modal while retaining a short-lived greenhouse overlay, call:

```gdscript
action_controller.switch_mode(PlayerActionController.ActionMode.FARMING)
action_controller.select_mode_slot(0)
```

Then publish a HUD message explaining that the highlighted eight cells must be hoed before sowing.

- [ ] **Step 6: Run UI and gameplay integration suites**

Expected: new tests pass; preserve the recorded unrelated contract-delivery baseline if it remains.

### Task 5: Final verification and documentation

**Files:**
- Modify: `docs/validation/building-geography-fishing-validation.md`

- [ ] **Step 1: Run focused regressions**

Run production, farming, building-system, economy-UI, main-gameplay integration, and editor import checks.

- [ ] **Step 2: Check runtime startup**

Run: `godot_console --headless --path . --quit-after 3`

Expected: main scene initializes without new script errors.

- [ ] **Step 3: Record exact evidence**

Append commands, pass counts, and any unchanged known baselines to the validation document.

- [ ] **Step 4: Inspect final diff**

Confirm no generated captures, save files, import debris, or unrelated changes are staged.
