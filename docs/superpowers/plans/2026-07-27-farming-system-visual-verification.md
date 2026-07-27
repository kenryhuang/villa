# FarmingSystem Visual Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans and implement each task with RED/GREEN verification.

**Goal:** Complete FarmingSystem 1.3 and add an independently runnable visual verifier.

**Architecture:** A reusable FarmingSystem scene owns CropVisuals and operates on the production GridSystem. A targeted runner validates lifecycle behavior; a standalone scene drives four real crop cells through growth, season, greenhouse, watering and harvest states.

**Tech Stack:** Godot 4.7.1, GDScript, existing TerrainBuilder/GridSystem/SeasonSystem.

## Constraints

- Preserve the completed GridSystem contract.
- Use Phase 1 mesh visuals because no crop stage textures exist.
- Do not implement building models or inventory seed consumption in this task.
- Do not commit unless explicitly requested.

### Task 1: RED lifecycle contract

- Create `tests/test_farming_system_complete.gd`.
- Create `tests/run_farming_system_tests.gd`.
- Assert maturity clamping, one-time maturity, greenhouse growth, reusable visual nodes and rebuild behavior.
- Run the isolated runner and confirm failure.

### Task 2: Production FarmingSystem

- Create `scenes/systems/farming_system.tscn`.
- Modify `scripts/data/crop_instance.gd`.
- Modify `scripts/systems/farming_system.gd`.
- Implement safe configure, greenhouse cells, mature guard, stage visuals and visual rebuild.
- Run the isolated runner and confirm all checks pass.

### Task 3: Main integration

- Modify `scripts/main.gd` to instantiate the reusable FarmingSystem scene.
- Rebuild visuals after successful save load.
- Extend runtime binding test to verify GridSystem sharing and CropVisuals.
- Run targeted tests and Main headless launch.

### Task 4: Visual verifier

- Write failing `tests/test_farming_visual_scene.gd`.
- Create `tests/visual/farming_system_verification.tscn` and script.
- Create `tests/capture_farming_visual.gd`.
- Run scene contract, graphical capture and inspect the screenshot.

### Task 5: Final verification

- Run editor parse, farming tests, grid regression tests, runtime binding tests, visual scene tests, graphical Main launch and `git diff --check`.
- Report unrelated legacy full-suite failures separately.
