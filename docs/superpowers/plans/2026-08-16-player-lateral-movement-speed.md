# Player Lateral Movement Speed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scale pure camera-lateral movement to 67 percent while leaving animation cadence and forward/back movement unchanged.

**Architecture:** Add a deterministic direction-to-speed-scale helper on `PlayerController`, test its camera-relative behavior first, then multiply the existing walk/sprint speed by that result before target velocity and acceleration are calculated. The scale is uniform for each intended direction, so diagonal paths do not bend.

**Tech Stack:** Godot 4.7 GDScript, `CharacterBody3D`, custom `TestAssert`.

---

### Task 1: Add the Failing Directional Speed Contract

**Files:**
- Modify: `tests/test_player_logic.gd`
- Test: `scripts/actors/player.gd`

- [x] Add assertions that `movement_speed_scale(Vector3.RIGHT, Vector3.RIGHT)` is `0.67`, forward is `1.0`, diagonal lies strictly between them, and zero direction or zero camera-right returns `1.0`.
- [x] Run `godot --headless --path . --log-file .godot\lateral-speed-red.log -s res://tests/run_tests.gd` and verify RED because the helper does not exist.
- [x] Commit the failing test as `test: require slower lateral movement`.

### Task 2: Apply the Lateral Multiplier

**Files:**
- Modify: `scripts/actors/player.gd`
- Test: `tests/test_player_logic.gd`
- Test: `tests/test_player_visual.gd`

- [x] Add `const LATERAL_MOVEMENT_SPEED_SCALE := 0.67`.
- [x] Add `static func movement_speed_scale(direction: Vector3, camera_right: Vector3) -> float` that returns `1.0` for unusable vectors, computes `abs(direction.normalized().dot(camera_right.normalized()))`, and returns `lerpf(1.0, LATERAL_MOVEMENT_SPEED_SCALE, lateral_weight)`.
- [x] In `_physics_process`, multiply the selected base walk/sprint speed by the helper result whenever a camera rig is available. Use the existing intended `direction`, so manual and auto movement share the same calculation.
- [x] Run the focused suite and verify all player logic and unchanged 9/13.5 FPS animation contracts pass.
- [x] Commit as `fix: slow lateral player movement`.

### Task 3: Revalidate the Integrated Movement

**Files:**
- Modify: `docs/validation/player-side-walk-9-frame-validation.md`
- Modify: `docs/superpowers/plans/2026-08-16-player-lateral-movement-speed.md`

- [x] Run focused and main gameplay suites.
- [x] Run grid, farming, building, and economy UI regressions.
- [x] Confirm `git diff --check` passes.
- [x] Record pure lateral walk `2.01`, sprint `3.35`, unchanged 9/13.5 FPS, and final test counts.
- [x] Commit validation as `docs: validate lateral movement speed`.
- [x] Preserve the current branch and worktree without merging or pushing.
