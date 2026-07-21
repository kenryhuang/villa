# Tree Collision and Camera Occlusion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every runtime tree a trunk obstacle and make every tree between the camera and player fade smoothly to 30% opacity.

**Architecture:** Replace standalone vegetation sprites with focused `TreeInstance` roots that own rendering, trunk collision, canopy query volume, and fade state. `VegetationBuilder` remains responsible for deterministic placement, while `CameraRig` performs layer-32 ray queries and only tells tree instances whether they are occluded.

**Tech Stack:** Godot 4.7, GDScript, Jolt Physics, Sprite3D billboards, headless GDScript tests.

## Global Constraints

- Keep terrain on layer `1`, player on `2`, NPCs on `4`, projectiles on `8`, tree trunks on `16`, and camera occluders on `32`.
- Player, NPC, and projectile masks must include tree trunks without losing existing contacts.
- Trunk collision must not cover the full painted canopy.
- Occluded trees fade to `0.30`; clear trees restore to `1.0` with exponential rate `10.0`.
- Camera occlusion queries inspect only layer `32`, include areas, exclude bodies, and support at most eight aligned trees.
- Do not change authored tree placement, tree art, player speed, camera orbit controls, or terrain geometry.

---

### Task 1: TreeInstance dimensions and fade state

**Files:**
- Create: `scripts/world/tree_instance.gd`
- Create: `tests/test_tree_instance.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `TreeInstance.trunk_radius_for(clearance: float) -> float`
- Produces: `TreeInstance.trunk_height_for(tree_height: float) -> float`
- Produces: `TreeInstance.occluder_dimensions(tree_size: Vector2) -> Vector2`
- Produces: `TreeInstance.opacity_step(current: float, target: float, delta: float) -> float`
- Produces: `TreeInstance.vertical_scale_for(texture_size: Vector2, target_size: Vector2) -> float`
- Produces: `configure(tree_data: Dictionary, texture: Texture2D, terrain_height: float) -> void`
- Produces: `set_camera_occluded(value: bool) -> void`

- [ ] **Step 1: Write the failing deterministic helper tests**

```gdscript
const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")

assertions.near(TreeInstanceScript.trunk_radius_for(0.5), 0.24, 0.001, "small trunks clamp to minimum radius")
assertions.near(TreeInstanceScript.trunk_radius_for(2.0), 0.46, 0.001, "large trunks clamp to maximum radius")
assertions.near(TreeInstanceScript.trunk_height_for(2.0), 0.84, 0.001, "trunk height follows authored height")
assertions.near(TreeInstanceScript.opacity_step(1.0, 0.3, 0.1), 0.5575, 0.001, "occluded opacity approaches target")
```

- [ ] **Step 2: Run tests and verify RED**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 2 --script res://tests/run_tests.gd`

Expected: preload failure because `tree_instance.gd` does not exist.

- [ ] **Step 3: Implement TreeInstance**

Create a Node3D script with `Sprite3D`, layer-16 `StaticBody3D`/`CylinderShape3D`, and layer-32 `Area3D`/`CapsuleShape3D` children. Use these exact helpers:

```gdscript
static func trunk_radius_for(clearance: float) -> float:
    return clampf(clearance * 0.36, 0.24, 0.46)

static func trunk_height_for(tree_height: float) -> float:
    return clampf(tree_height * 0.42, 0.65, 1.10)

static func opacity_step(current: float, target: float, delta: float) -> float:
    return lerpf(current, target, 1.0 - exp(-10.0 * delta))
```

`configure` creates all children, applies explicit sprite width/height scale through `vertical_scale_for`, sets alpha cut to `OPAQUE_PREPASS`, adds the root to group `tree_instance`, and places collision shapes relative to the root at terrain height. `_process` moves sprite opacity toward `0.30` or `1.0`.

- [ ] **Step 4: Run tests and verify GREEN**

Expected: all assertions pass with exit `0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/world/tree_instance.gd tests/test_tree_instance.gd tests/run_tests.gd
git commit -m "feat: add runtime tree instances"
```

### Task 2: Build tree obstacles and update collision masks

**Files:**
- Modify: `scripts/world/vegetation_builder.gd`
- Modify: `scenes/actors/player.tscn`
- Modify: `scenes/actors/npc.tscn`
- Modify: `scenes/combat/projectile.tscn`
- Modify: `tests/test_vegetation_builder.gd`

**Interfaces:**
- Consumes: `TreeInstance.configure(tree_data, texture, terrain_height)`
- Produces: 28 runtime tree roots containing `TrunkBody` and `CameraOccluder`.

- [ ] **Step 1: Add failing structure and mask tests**

Extend `test_vegetation_builder.gd` to instantiate one configured tree and assert:

```gdscript
assertions.equal(tree.get_node("TrunkBody").collision_layer, 16, "tree trunk uses obstacle layer")
assertions.equal(tree.get_node("CameraOccluder").collision_layer, 32, "canopy uses camera layer")
assertions.equal(tree.get_node("TrunkBody/CollisionShape3D").shape is CylinderShape3D, true, "tree has cylinder trunk")
```

Load actor scenes and assert masks `21`, `19`, and `21` for Player, NPC, and Projectile.

- [ ] **Step 2: Run tests and verify RED**

Expected: tree children are missing and actor masks retain their old values.

- [ ] **Step 3: Replace sprite-only construction**

Preload `tree_instance.gd` in `VegetationBuilder`, instantiate one root per placement, set its name to the placement id, call `configure`, and add it as a child. Remove direct Sprite3D construction and move the existing `vertical_scale_for` assertion to `test_tree_instance.gd` so sizing has a single owner.

Set scene masks exactly:

```text
Player collision_mask = 21
NPC collision_mask = 19
Projectile collision_mask = 21
```

- [ ] **Step 4: Run tests and verify GREEN**

Expected: all tests pass and the built world still reports 28 vegetation children.

- [ ] **Step 5: Commit**

```bash
git add scripts/world/vegetation_builder.gd scenes/actors/player.tscn scenes/actors/npc.tscn scenes/combat/projectile.tscn tests/test_vegetation_builder.gd
git commit -m "feat: add tree trunk obstacles"
```

### Task 3: Multi-tree camera occlusion and acceptance

**Files:**
- Modify: `scripts/camera/camera_rig.gd`
- Modify: `tests/test_camera_math.gd`
- Modify: `tests/smoke_test.gd`
- Modify: `tests/capture_scene.gd`

**Interfaces:**
- Consumes: layer-32 `CameraOccluder` areas whose parent implements `set_camera_occluded(bool)`.
- Produces: `CameraRig.update_tree_occlusion() -> void` and smooth multi-tree fading.
- Produces: `CameraRig.apply_occlusion_state(trees: Array[Node], occluded: Array[Node]) -> void`.

- [ ] **Step 1: Add failing occlusion reset test**

Create two TreeInstance nodes, mark both occluded, call `CameraRig.apply_occlusion_state([tree_a, tree_b], [])`, and assert both instances have `occlusion_target == 1.0`. Then call it with `[tree_a]` and assert only `tree_a.occlusion_target == 0.30`. Add a smoke assertion that the main world contains 28 nodes in group `tree_instance`.

- [ ] **Step 2: Run tests and verify RED**

Expected: the new camera helper/group contract does not exist.

- [ ] **Step 3: Implement repeated layer-32 ray queries**

Implement the state helper exactly as:

```gdscript
static func apply_occlusion_state(trees: Array[Node], occluded: Array[Node]) -> void:
    for tree in trees:
        if is_instance_valid(tree) and tree.has_method("set_camera_occluded"):
            tree.set_camera_occluded(tree in occluded)
```

In `CameraRig._process`, after positioning the camera, collect all live `tree_instance` nodes. Raycast from `camera.global_position` to `target.global_position + Vector3.UP * 0.55` with:

```gdscript
query.collision_mask = 32
query.collide_with_areas = true
query.collide_with_bodies = false
```

Repeat up to eight hits, excluding each hit RID. Resolve `hit.collider.get_parent()` into an `occluded` array, then call `apply_occlusion_state(trees, occluded)` once so previously faded trees restore automatically.

- [ ] **Step 4: Verify tests, import, and clean main launch**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 120
```

Expected: all assertions pass, imports exit `0`, and the main scene runs without warnings or errors.

- [ ] **Step 5: Perform visual acceptance**

Capture the main scene and verify tree roots remain grounded with no alpha halos. Launch the macOS window and exercise walking into trunks, moving behind single and aligned trees, Q/E rotation, middle-drag rotation, and moving clear until every faded tree restores.

- [ ] **Step 6: Commit**

```bash
git add scripts/camera/camera_rig.gd tests/test_camera_math.gd tests/smoke_test.gd tests/capture_scene.gd
git commit -m "feat: fade trees that occlude the player"
```

### Task 4: Final verification

**Files:**
- Verify only; no planned production changes.

**Interfaces:**
- Consumes the complete tree collision and camera occlusion feature.
- Produces a clean verified `main` branch.

- [ ] **Step 1: Re-run all tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`

Expected: exit `0`, no failed checks, no leaked objects.

- [ ] **Step 2: Re-run main scene**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 120`

Expected: exit `0` with no parse, resource, collision, or runtime errors.

- [ ] **Step 3: Confirm repository state**

Run: `git status --short && git log -5 --oneline`

Expected: clean status and commits for the design, plan, tree instances, trunk obstacles, and camera occlusion.
