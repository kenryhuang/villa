# Hand-Painted Player Character Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blue capsule player visual with a hand-painted young farmer and drive two-frame idle plus six-frame walking loops across eight world directions.

**Architecture:** Keep `PlayerController` responsible for physics and add a focused `PlayerVisual` `AnimatedSprite3D` component for direction quantization, animation state, frame construction, and validation. Store all 64 frames in one transparent 8×8 atlas, with rows ordered N, NE, E, SE, S, SW, W, NW and columns ordered idle 0–1 then walk 0–5.

**Tech Stack:** Godot 4.7 GDScript, `AnimatedSprite3D`, `SpriteFrames`, `AtlasTexture`, PNG RGBA art, built-in image generation with local chroma-key removal, the existing headless GDScript assertion harness.

---

## File Structure

- Create `assets/characters/player/player_farmer_atlas.png`: final transparent 8×8 runtime atlas.
- Create `assets/characters/player/player_farmer_atlas.png.import`: Godot texture import metadata.
- Create `scripts/visual/player_visual.gd`: animation construction, validation, direction mapping, and state selection.
- Create `scripts/visual/player_visual.gd.uid`: Godot script UID generated during import.
- Modify `scenes/actors/player.tscn`: replace the capsule mesh with `PlayerVisual` while preserving collision and tool/action nodes.
- Modify `scripts/actors/player.gd`: stop rotating the root and synchronize actual motion state to `PlayerVisual` after physics movement.
- Create `tests/test_player_visual.gd`: focused unit and scene contract checks.
- Modify `tests/run_tests.gd`: include the new focused test.
- Optionally create `tests/visual/player_animation_verification.tscn` and `.gd` only if gameplay capture cannot show all directions compactly; these files are not required by runtime.

### Task 1: Define the visual contract with failing tests

**Files:**
- Create: `tests/test_player_visual.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Add the visual behavior test**

Define expectations for direction constants and `direction_from_velocity(Vector2)` using the eight cardinal/diagonal vectors. Verify zero speed returns the supplied previous direction, `idle_<direction>` and `walk_<direction>` names are stable, expected FPS values are 2/8/12, and jump state pauses animation.

- [ ] **Step 2: Add the player scene contract test**

Instantiate `res://scenes/actors/player.tscn` and assert that `PlayerVisual` is an `AnimatedSprite3D`, no direct child named `Mesh` or capsule `MeshInstance3D` remains, the collision capsule still has radius `0.35` and height `1.3`, collision layer/mask stay `2/21`, and `ActionController` plus `ToolSwingVisual` paths remain valid.

- [ ] **Step 3: Add atlas and frame contract checks**

Assert `res://assets/characters/player/player_farmer_atlas.png` loads as `Texture2D`, has nonzero alpha transparency, dimensions divisible by eight, and that every `idle_*` animation has two frames while every `walk_*` animation has six frames.

- [ ] **Step 4: Register the test in the core runner**

Preload `test_player_visual.gd` in `tests/run_tests.gd` and run it immediately after `PlayerLogicTest`.

- [ ] **Step 5: Run RED verification**

Run:

```powershell
& $godot --headless --path $worktree --script tests/run_tests.gd
```

Expected: failure because `scripts/visual/player_visual.gd`, `PlayerVisual`, and the player atlas do not exist.

- [ ] **Step 6: Commit the contract**

```powershell
git add tests/test_player_visual.gd tests/run_tests.gd
git commit -m "test: define hand-painted player visual contract"
```

### Task 2: Generate and validate the hand-painted 8×8 atlas

**Files:**
- Create: `assets/characters/player/player_farmer_atlas.png`
- Create after import: `assets/characters/player/player_farmer_atlas.png.import`

- [ ] **Step 1: Generate a consistent source sheet**

Use the built-in image generation tool with current hand-painted buildings as style references. Request a perfectly regular 8×8 sprite atlas on flat `#ff00ff` chroma key. The same young male farmer appears in every cell with a straw hat, beige shirt, blue overalls, and brown boots. Rows are N, NE, E, SE, S, SW, W, NW; columns are idle A, idle B, then six walking phases. Require fixed feet anchor, equal cell padding, no labels, no shadow, no floor, no watermark, and no magenta on the character.

- [ ] **Step 2: Remove chroma key locally**

Copy the generated source under `tmp/imagegen/`, then run the installed imagegen helper with border auto-key, soft matte, despill, and edge contraction if needed. Save the final alpha PNG at `assets/characters/player/player_farmer_atlas.png`.

- [ ] **Step 3: Normalize and inspect the sheet**

Confirm the final atlas is square and divisible by eight, corners are transparent, all 64 cells contain meaningful opaque pixels, cell bounding boxes stay inside their cell, and foot baselines have only small variance. If the model output is not a strict grid, post-process only cropping, padding, chroma removal, and atlas assembly; do not redraw the character procedurally.

- [ ] **Step 4: Import through Godot**

Run:

```powershell
& $godot --headless --path $worktree --editor --quit
```

Expected: exit 0 and a generated `.png.import` file using the standard texture importer with alpha preserved.

- [ ] **Step 5: Commit the artwork**

```powershell
git add assets/characters/player/player_farmer_atlas.png assets/characters/player/player_farmer_atlas.png.import
git commit -m "art: add hand-painted farmer animation atlas"
```

### Task 3: Implement the focused PlayerVisual component

**Files:**
- Create: `scripts/visual/player_visual.gd`
- Create after import: `scripts/visual/player_visual.gd.uid`
- Test: `tests/test_player_visual.gd`

- [ ] **Step 1: Define direction and atlas constants**

Create `class_name PlayerVisual extends AnimatedSprite3D` with direction strings `n`, `ne`, `e`, `se`, `s`, `sw`, `w`, `nw`; atlas grid size `Vector2i(8, 8)`; idle columns `0..1`; walk columns `2..7`; default direction `s`; idle/walk/run FPS `2.0/8.0/12.0`; and a small movement threshold.

- [ ] **Step 2: Implement pure direction quantization**

Add `static func direction_from_velocity(planar_velocity: Vector2, previous_direction: String = "s") -> String`. Zero/near-zero input returns the validated previous direction. Nonzero input uses `atan2(planar_velocity.x, planar_velocity.y)` and rounds into eight 45-degree sectors matching Godot world X/Z semantics.

- [ ] **Step 3: Build SpriteFrames from AtlasTexture regions**

At `_ready`, load the atlas, validate divisibility by eight, create `idle_*` and `walk_*` animations for every row, and insert `AtlasTexture` regions using exact cell rectangles. Set loop mode true, base FPS values, default direction south, billboard enabled, alpha transparency enabled, fixed-size false, a stable vertical offset above the capsule center, and an appropriate pixel size for the current world scale.

- [ ] **Step 4: Implement state synchronization**

Add `sync_motion(planar_velocity: Vector2, sprinting: bool, on_floor: bool)`. It updates the last direction only above the threshold. Off-floor state pauses the current walk frame. Moving state plays `walk_*` with custom speed `1.0` or `1.5`; stopped state plays `idle_*` at base speed. Avoid restarting an animation when its name and play state already match.

- [ ] **Step 5: Add explicit validation failures**

If the atlas, grid, frames, or animation counts are invalid, call `push_error` with the exact missing contract and keep the sprite invisible. Do not create any capsule or geometric fallback.

- [ ] **Step 6: Run GREEN verification for the focused tests**

Run the core suite and expect all direction, animation, atlas, and validation checks to pass.

- [ ] **Step 7: Commit the visual component**

```powershell
git add scripts/visual/player_visual.gd scripts/visual/player_visual.gd.uid tests/test_player_visual.gd
git commit -m "feat: add eight-direction player visual"
```

### Task 4: Integrate the visual with PlayerController and the player scene

**Files:**
- Modify: `scenes/actors/player.tscn`
- Modify: `scripts/actors/player.gd`
- Test: `tests/test_player_visual.gd`
- Test: `tests/test_player_logic.gd`

- [ ] **Step 1: Replace the capsule visual in the scene**

Remove `BlueMaterial`, `PlayerMesh`, and the `Mesh` node. Add `PlayerVisual` as an `AnimatedSprite3D` with `player_visual.gd`. Preserve the root collision configuration and every existing functional child node.

- [ ] **Step 2: Remove root rotation from movement**

Delete the movement-facing `rotation.y = lerp_angle(...)` block from `PlayerController`. This keeps tool offsets and world-space tool swing calculations stable.

- [ ] **Step 3: Synchronize after movement resolution**

Cache the `PlayerVisual` node and call `sync_motion(Vector2(velocity.x, velocity.z), _is_sprinting, is_on_floor())` after `move_and_slide()` and world clamping so both manual movement and auto paths use actual resolved velocity.

- [ ] **Step 4: Verify the player contract and regressions**

Run:

```powershell
& $godot --headless --path $worktree --script tests/run_tests.gd
& $godot --headless --path $worktree --script tests/run_player_action_controller_tests.gd
& $godot --headless --path $worktree --script tests/run_main_gameplay_integration_tests.gd
```

Expected: all pass, with unchanged player collision and tool/action paths.

- [ ] **Step 5: Commit integration**

```powershell
git add scenes/actors/player.tscn scripts/actors/player.gd tests/test_player_logic.gd tests/test_player_visual.gd
git commit -m "feat: animate player movement with painted farmer"
```

### Task 5: Visual verification and final regression

**Files:**
- Modify only if a defect is found: player atlas, visual component, player scene, or focused tests.

- [ ] **Step 1: Capture normal gameplay**

Launch or capture the main scene at the standard 2.5D camera angle. Inspect player scale, feet contact, transparency edges, depth sorting, and contrast against grass and buildings.

- [ ] **Step 2: Exercise all eight directions**

Drive or programmatically preview N, NE, E, SE, S, SW, W, NW. Confirm no mirrored direction, stable foot anchor, continuous six-frame loops, retained facing during idle, and visibly faster sprint playback.

- [ ] **Step 3: Exercise tool compatibility**

Select axe and pickaxe targets on both sides of the player. Confirm the tool pivot, swing direction, and layering are unchanged and the root no longer rotates beneath `ToolSwingVisual`.

- [ ] **Step 4: Run full relevant regression**

Run core, player action, building, production, maintenance, and main gameplay suites. Then run editor parse/import with `--editor --quit` and `git diff --check`.

- [ ] **Step 5: Request code review**

Review for direction math, animation restart behavior, asset validation, node-path compatibility, accidental capsule fallback, and generated-art quality. Resolve all Critical and Important findings.

- [ ] **Step 6: Commit final corrections**

```powershell
git add assets/characters/player scripts/visual/player_visual.gd scenes/actors/player.tscn scripts/actors/player.gd tests docs/superpowers/plans/2026-08-13-hand-painted-player-character.md
git commit -m "fix: polish hand-painted player animation"
```
