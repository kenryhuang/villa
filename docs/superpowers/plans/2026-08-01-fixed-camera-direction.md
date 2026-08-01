# Fixed Camera Direction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lock the game camera to its existing isometric direction while preserving target following and wheel zoom, and turn middle-mouse dragging into zoom-aware map panning.

**Architecture:** `CameraRig` remains the only input and camera-transform owner. Its existing `yaw` stays fixed for compatibility, a world-space `pan_offset` is added to the followed target position, and a pure helper converts screen drag deltas into ground-plane movement for deterministic testing.

**Tech Stack:** Godot 4.7, GDScript, SceneTree contract tests

---

## File Map

- Modify `scripts/camera/camera_rig.gd`: stop consuming Q/E rotation, add pan offset conversion, and follow target plus pan offset.
- Modify `tests/test_camera_math.gd`: verify fixed yaw, middle-drag panning, zoom-scaled pan math, retained target following, and unchanged wheel zoom.

### Task 1: Fixed direction and middle-drag panning

**Files:**
- Modify: `tests/test_camera_math.gd`
- Modify: `scripts/camera/camera_rig.gd`

- [ ] **Step 1: Add failing camera behavior tests**

Extend `tests/test_camera_math.gd` after the camera rig is added to the scene tree:

```gdscript
var fixed_yaw: float = rig.yaw
Input.action_press("camera_right")
rig._process(0.25)
Input.action_release("camera_right")
assertions.near(rig.yaw, fixed_yaw, 0.0001, "Q/E input cannot rotate the fixed camera")

var has_pan_offset := _has_property(rig, "pan_offset")
var has_pan_helper := CameraRigScript.has_method("pan_delta_for")
assertions.truthy(has_pan_offset, "camera exposes a retained planar pan offset")
assertions.truthy(has_pan_helper, "camera exposes deterministic zoom-aware pan conversion")
if has_pan_offset and has_pan_helper:
	var expected_pan: Vector3 = CameraRigScript.call(
		"pan_delta_for",
		Vector2(80.0, -40.0),
		rig.orthographic_size,
		1000.0,
		rig.get_planar_right(),
		rig.get_planar_forward()
	)
	assertions.near(
		expected_pan.distance_to(
			-rig.get_planar_right() * 0.8 - rig.get_planar_forward() * 0.4
		),
		0.0,
		0.0001,
		"pan conversion follows fixed camera axes and orthographic scale"
	)
	var middle_down := InputEventMouseButton.new()
	middle_down.button_index = MOUSE_BUTTON_MIDDLE
	middle_down.pressed = true
	rig._unhandled_input(middle_down)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(80.0, -40.0)
	rig._unhandled_input(drag)
	assertions.near(rig.yaw, fixed_yaw, 0.0001, "middle drag cannot rotate the camera")
	var drag_pan: Vector3 = CameraRigScript.call(
		"pan_delta_for",
		drag.relative,
		rig.orthographic_size,
		float(rig.get_viewport().get_visible_rect().size.y),
		rig.get_planar_right(),
		rig.get_planar_forward()
	)
	assertions.near(
		rig.pan_offset.distance_to(drag_pan),
		0.0,
		0.0001,
		"middle drag pans in the camera ground plane"
	)

if has_pan_offset:
	var target := Node3D.new()
	scene_tree.root.add_child(target)
	target.global_position = Vector3(4.0, 0.0, 6.0)
	rig.set_target(target)
	rig._process(10.0)
	assertions.near(
		rig.global_position.distance_to(target.global_position + rig.pan_offset),
		0.0,
		0.0001,
		"camera follows the player while retaining pan offset"
	)
	target.free()
```

Also send wheel-up and wheel-down `InputEventMouseButton` events and assert the existing `0.6` zoom step and `CameraMath.clamp_size()` limits remain unchanged.

Add this helper at the bottom of the test file so missing properties fail as assertions instead of parse errors:

```gdscript
static func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false
```

- [ ] **Step 2: Run the camera suite and verify the new contracts fail**

Run:

```powershell
godot --headless --path . --script res://tests/run_tests.gd
```

Expected: failures report that Q/E changes `yaw`, `pan_delta_for`/`pan_offset` are missing, and middle drag rotates instead of panning.

- [ ] **Step 3: Implement fixed direction and pan conversion**

In `scripts/camera/camera_rig.gd`, keep `yaw := -PI / 4.0`, add `pan_offset`, and replace the rotation constants with no runtime yaw mutation:

```gdscript
var target: Node3D
var yaw := -PI / 4.0
var orthographic_size := CameraMathScript.DEFAULT_SIZE
var pan_offset := Vector3.ZERO
var dragging := false

static func pan_delta_for(
	relative: Vector2,
	view_size: float,
	viewport_height: float,
	planar_right: Vector3,
	planar_forward: Vector3
) -> Vector3:
	var world_per_pixel := view_size / maxf(viewport_height, 1.0)
	return (
		-planar_right * relative.x
		+ planar_forward * relative.y
	) * world_per_pixel
```

Update target placement and following:

```gdscript
func set_target(value: Node3D) -> void:
	target = value
	if target:
		global_position = target.global_position + pan_offset

func _process(delta: float) -> void:
	if target:
		var desired_position := target.global_position + pan_offset
		global_position = global_position.lerp(desired_position, 1.0 - exp(-8.0 * delta))
	_apply_camera_transform()
	update_occlusion()
```

Replace middle-motion yaw mutation in `_unhandled_input()`:

```gdscript
elif event is InputEventMouseMotion and dragging:
	var viewport_height := float(get_viewport().get_visible_rect().size.y)
	pan_offset += pan_delta_for(
		event.relative,
		orthographic_size,
		viewport_height,
		get_planar_right(),
		get_planar_forward()
	)
```

Delete `KEY_ROTATION_SPEED`, `DRAG_SENSITIVITY`, and the `Input.get_axis("camera_left", "camera_right")` block. Leave the input actions defined but unused.

- [ ] **Step 4: Run the focused tests and verify green**

Run:

```powershell
godot --headless --path . --script res://tests/run_tests.gd
```

Expected: all core tests pass, including fixed direction, map panning, following, and zoom checks.

- [ ] **Step 5: Commit the camera behavior**

```powershell
git add scripts/camera/camera_rig.gd tests/test_camera_math.gd
git commit -m "fix: lock camera direction and pan map"
```

### Task 2: Regression and integration

**Files:**
- Verify only; no production file changes expected.

- [ ] **Step 1: Run editor import and the full regression suite**

Run:

```powershell
godot --headless --editor --quit --path .
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path . --script res://tests/test_player_grid_binding.gd
godot --headless --path . --script res://tests/test_building_visual_scene.gd
```

Expected: every command exits `0`; existing missing-construction-art fixture warnings are allowed.

- [ ] **Step 2: Capture and inspect gameplay visuals**

Run:

```powershell
godot --path . --audio-driver Dummy --script res://tests/capture_main_gameplay_integration.gd
```

Inspect the output image and confirm the fixed isometric composition remains correct. Automated input tests provide the proof that Q/E is ignored and middle drag pans without changing `yaw`.

- [ ] **Step 3: Verify repository hygiene**

Run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors and a clean feature worktree.

### Task 3: Review and integrate

- [ ] **Step 1: Request code review of the exact feature range**

Review from the implementation-plan commit through feature `HEAD`, focusing on input semantics, drag direction, zoom scaling, target-follow behavior, and regression coverage.

- [ ] **Step 2: Apply accepted Critical/Important findings with TDD**

For each accepted behavior defect, add a focused failing assertion to `tests/test_camera_math.gd`, run `tests/run_tests.gd` to verify red, apply the smallest fix, rerun green, and commit.

- [ ] **Step 3: Merge locally into `main`**

After a fresh full verification, fast-forward `main`, rerun `tests/run_tests.gd` and `tests/run_main_gameplay_integration_tests.gd` on merged `main`, then remove the owned worktree and feature branch. Do not push.
