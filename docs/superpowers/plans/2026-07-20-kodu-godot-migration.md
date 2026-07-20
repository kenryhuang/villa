# Kodu Godot Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable macOS Godot 4.7 migration of the Kodu Babylon.js prototype with terrain, road, trees, player, NPCs, projectiles, HUD, and an orbiting orthographic follow camera.

**Architecture:** Keep deterministic geometry/gameplay calculations in `RefCounted` utility scripts and construct runtime presentation through focused Godot nodes and scenes. `Main` composes `World`, actors, projectiles, camera, and HUD through signals; Godot physics replaces the browser prototype's manual collision loop.

**Tech Stack:** Godot 4.7, GDScript, GL Compatibility renderer, Jolt Physics, PNG runtime assets, headless GDScript tests.

## Global Constraints

- Target platform is macOS desktop only.
- Preserve `/Users/huanggui/workspace/kodu`; copy only selected runtime PNG assets.
- Do not add third-party Godot plugins.
- Use the existing GL Compatibility renderer and Jolt Physics settings.
- Camera always follows the player; middle-drag/Q/E rotate and wheel zoom.
- This phase excludes building placement, economy, saves, final character art, animation, and audio.
- `/Users/huanggui/UnrealEngine/villa` is not a Git repository; skip commit steps rather than initializing Git without permission.

---

### Task 1: Project skeleton, input map, and test runner

**Files:**
- Modify: `project.godot`
- Create: `tests/test_assert.gd`
- Create: `tests/run_tests.gd`
- Create: `scripts/shared/combat_math.gd`
- Create: `tests/test_combat_math.gd`

**Interfaces:**
- Produces: `CombatMath.apply_damage(current: int, amount: int) -> int`
- Produces: `TestAssert` helpers and a headless runner used by later tasks.

- [ ] **Step 1: Add a failing combat test and runner**

```gdscript
# tests/test_combat_math.gd
extends RefCounted
const CombatMath = preload("res://scripts/shared/combat_math.gd")

func run(assertions) -> void:
    assertions.equal(CombatMath.apply_damage(5, 2), 3, "damage subtracts health")
    assertions.equal(CombatMath.apply_damage(1, 5), 0, "health never drops below zero")
```

- [ ] **Step 2: Run the test and verify RED**

Run: `godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd`
Expected: non-zero exit because `scripts/shared/combat_math.gd` does not exist.

- [ ] **Step 3: Implement the minimal combat helper and input actions**

```gdscript
class_name CombatMath
extends RefCounted

static func apply_damage(current: int, amount: int) -> int:
    return maxi(0, current - maxi(0, amount))
```

Add `move_left`, `move_right`, `move_forward`, `move_back`, `jump`, `camera_left`, and `camera_right` to `project.godot`; set `run/main_scene` once Task 7 creates it.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd`
Expected: `PASS` and exit 0.

- [ ] **Step 5: Git checkpoint**

Skip: target is not a Git repository.

### Task 2: Deterministic road sampling and tree scatter

**Files:**
- Create: `scripts/world/road_math.gd`
- Create: `scripts/world/tree_scatter.gd`
- Create: `tests/test_road_math.gd`
- Create: `tests/test_tree_scatter.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `RoadMath.sample_route(route: Array[Dictionary], steps_per_segment: int) -> Array[Dictionary]`
- Produces: `RoadMath.distance_to_route(point: Vector2, clearance: float, route: Array[Dictionary]) -> float`
- Produces: `TreeScatter.generate(route: Array[Dictionary], seed: int = 0x4b4f4455) -> Array[Dictionary]`

- [ ] **Step 1: Write failing tests**

```gdscript
func run(assertions) -> void:
    var route = [{"x": 0.0, "z": 0.0, "width": 2.0}, {"x": 4.0, "z": 0.0, "width": 2.0}]
    var samples = RoadMath.sample_route(route, 4)
    assertions.equal(samples.size(), 5, "road contains both endpoints")
    assertions.near(samples[0].x, 0.0, 0.001, "road starts at first point")
    assertions.near(samples[-1].x, 4.0, 0.001, "road ends at last point")
```

Tree tests compare two runs with the same seed, require 28 placements, and assert every placement clears the road and other trees.

- [ ] **Step 2: Run tests and verify RED**

Expected: preload failure for the missing world math scripts.

- [ ] **Step 3: Implement Catmull-Rom sampling and deterministic scatter**

Port the nine authored road control points and the ten weighted tree variants from `src/game/world/atlasTreeScatter.ts`. Use `RandomNumberGenerator.seed`, reject candidates inside radius `2.35`, require road clearance `0.45`, and stop after 4000 attempts.

- [ ] **Step 4: Run tests and verify GREEN**

Expected: deterministic road and tree tests pass with exit 0.

- [ ] **Step 5: Git checkpoint**

Skip: target is not a Git repository.

### Task 3: Copy assets and construct the world

**Files:**
- Create: `assets/terrain/heightmap-valley.png`
- Create: `assets/terrain/grass-seamless-blended.png`
- Create: `assets/terrain/road-ribbon-seamless.png`
- Create: `assets/vegetation/tree-*.png` (10 selected atlas trees)
- Create: `scripts/world/terrain_builder.gd`
- Create: `scripts/world/road_builder.gd`
- Create: `scripts/world/vegetation_builder.gd`
- Create: `scripts/world/world.gd`
- Create: `scenes/world/world.tscn`
- Create: `tests/test_terrain_builder.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `World.get_height_at(world_x: float, world_z: float) -> float`
- Produces: `World.get_bounds() -> Rect2`
- Produces: runtime child nodes `Terrain`, `Road`, and `Vegetation`.

- [ ] **Step 1: Add failing height sampling tests**

Test that UV corners clamp, center sampling is deterministic, and returned heights remain within `[-0.12, 0.9]`.

- [ ] **Step 2: Run and verify RED**

Expected: preload failure for `terrain_builder.gd`.

- [ ] **Step 3: Copy the selected PNG assets**

Copy the heightmap, blended grass, seamless road ribbon, and ten tree atlas PNGs from Kodu into the exact `villa/assets` paths above.

- [ ] **Step 4: Implement world builders**

`TerrainBuilder` loads the 128×128 heightmap, samples a 97×97 grid, builds an `ArrayMesh`, and creates a `HeightMapShape3D` from the same float samples. `RoadBuilder` creates seven cross vertices per sampled row, adds a small crown, queries terrain height, and maps repeating UVs. `VegetationBuilder` instantiates billboard `Sprite3D` nodes from `TreeScatter.generate`.

- [ ] **Step 5: Verify GREEN and headless import**

Run tests, then run: `godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit`
Expected: tests pass and editor import exits 0 without parse errors.

- [ ] **Step 6: Git checkpoint**

Skip: target is not a Git repository.

### Task 4: Orthographic orbit-follow camera

**Files:**
- Create: `scripts/camera/camera_math.gd`
- Create: `scripts/camera/camera_rig.gd`
- Create: `scenes/camera/camera_rig.tscn`
- Create: `tests/test_camera_math.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `CameraMath.clamp_size(value: float) -> float`
- Produces: `CameraRig.set_target(node: Node3D) -> void`
- Produces: `CameraRig.get_planar_forward() -> Vector3` and `get_planar_right() -> Vector3`.

- [ ] **Step 1: Write failing zoom clamp tests**

```gdscript
assertions.near(CameraMath.clamp_size(2.0), 5.0, 0.001, "minimum zoom")
assertions.near(CameraMath.clamp_size(20.0), 12.0, 0.001, "maximum zoom")
```

- [ ] **Step 2: Verify RED**

Expected: missing `camera_math.gd` preload.

- [ ] **Step 3: Implement camera rig**

Use an orthographic `Camera3D`, yaw default `-PI/4`, pitch `-0.72`, size default `8.0`, range `[5.0, 12.0]`, middle-button drag sensitivity `0.008`, Q/E rotation speed `1.6`, and exponential target smoothing.

- [ ] **Step 4: Verify GREEN and scene parse**

Run the test runner and Godot editor import command; both must exit 0.

- [ ] **Step 5: Git checkpoint**

Skip: target is not a Git repository.

### Task 5: Player movement, jump, aiming, and fire requests

**Files:**
- Create: `scripts/actors/player.gd`
- Create: `scenes/actors/player.tscn`
- Create: `tests/test_player_logic.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces signals: `fire_requested(origin: Vector3, direction: Vector3)` and `health_changed(value: int)`.
- Consumes: camera planar axes and mouse ray projection.
- Produces: `take_damage(amount: int) -> void`.

- [ ] **Step 1: Add failing tests for camera-relative movement and damage**

Test that forward input follows the supplied camera forward vector and that two damage calls clamp health at zero.

- [ ] **Step 2: Verify RED**

Expected: missing player script.

- [ ] **Step 3: Implement Player**

Use `CharacterBody3D`, speed `4.5`, jump velocity `5.2`, project gravity, five health, a `0.28` second fire cooldown, map bounds clamping, and a ray from the active camera through the mouse position. Fall back to the y=0 plane if the world ray misses.

- [ ] **Step 4: Verify GREEN and scene parse**

Run tests and editor import; both exit 0.

- [ ] **Step 5: Git checkpoint**

Skip: target is not a Git repository.

### Task 6: NPC and projectile combat loop

**Files:**
- Create: `scripts/actors/npc.gd`
- Create: `scenes/actors/npc.tscn`
- Create: `scripts/combat/projectile.gd`
- Create: `scenes/combat/projectile.tscn`
- Create: `tests/test_npc_logic.gd`
- Create: `tests/test_projectile_logic.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- NPC: `set_target(node: Node3D)`, `take_hit(damage: int, impulse: Vector3)`, signal `defeated`.
- Projectile: `launch(origin: Vector3, direction: Vector3)`, signal `expired`.

- [ ] **Step 1: Write failing NPC death and projectile lifetime tests**

Verify NPC health clamps at zero and death is emitted once; verify a projectile reports expiry only after its lifetime is exhausted.

- [ ] **Step 2: Verify RED**

Expected: missing NPC/projectile scripts.

- [ ] **Step 3: Implement combat actors**

NPC speed is `1.4`, max health `3`, hit flash `0.12` seconds, and knockback decays toward zero. Projectile speed is `10.0`, damage `1`, lifetime `2.0`, and its mask includes world/NPC but excludes player.

- [ ] **Step 4: Verify GREEN and scene parse**

Run tests and editor import; both exit 0.

- [ ] **Step 5: Git checkpoint**

Skip: target is not a Git repository.

### Task 7: Main scene, HUD, integration, and macOS acceptance

**Files:**
- Create: `scripts/main.gd`
- Create: `scenes/main.tscn`
- Create: `scripts/ui/hud.gd`
- Create: `scenes/ui/hud.tscn`
- Modify: `project.godot`
- Create: `tests/smoke_test.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- `Main` connects Player, NPC, Projectile, CameraRig, World, and HUD.
- HUD consumes `{health, state, npc_count, projectile_count}` through focused setter methods.

- [ ] **Step 1: Add a failing headless smoke test**

Instantiate `scenes/main.tscn`, add it to the tree, wait two frames, and assert `World`, `Actors/Player`, `CameraRig`, and `HUD` exist.

- [ ] **Step 2: Verify RED**

Expected: missing `main.tscn`.

- [ ] **Step 3: Implement Main and HUD**

Main spawns the player at the center, three NPCs at authored positions, connects fire/death signals, instances projectiles, assigns camera and NPC targets, and updates HUD counts. HUD uses a top-left translucent panel plus a bottom-left controls label.

- [ ] **Step 4: Set the main scene and verify GREEN**

Set `run/main_scene="res://scenes/main.tscn"`. Run the complete test runner, editor import, and `godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 5`.

- [ ] **Step 5: Run macOS visual acceptance**

Launch `godot --path /Users/huanggui/UnrealEngine/villa`, verify terrain/road/28 trees/blue player/three red NPCs/HUD, then exercise WASD, Space, click fire, middle drag, Q/E, wheel, and window resize.

- [ ] **Step 6: Final verification**

Re-run all headless tests and confirm zero parse errors, zero failed assertions, and no missing resource errors.

- [ ] **Step 7: Git checkpoint**

Skip: target is not a Git repository.
