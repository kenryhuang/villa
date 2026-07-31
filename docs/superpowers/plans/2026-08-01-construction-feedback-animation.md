# Construction Strike Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the upper-right sine-swing SVG hammer with a hand-painted bottom strike animation and add a continuously filling transparent circular construction progress indicator.

**Architecture:** A focused `ConstructionFeedback` Node3D owns the hammer pivot, hand-painted Sprite3D, progress Sprite3D, radial shader state, animation phase, visibility, and asset warnings. `BuildingInstance` remains authoritative for construction timing and forwards size/progress/lifecycle state to the component, which lives outside `VisualRoot` so preview tint, occlusion fading, stage cross-fades, physics, and saves cannot affect it.

**Tech Stack:** Godot 4.7, typed GDScript, Sprite3D, spatial shader, generated transparent PNG, SceneTree test runners, existing building visual verification scene.

---

## File Map

- Create `scripts/buildings/construction_feedback.gd`: construction feedback node factory, layout, visibility, progress material, and piecewise strike animation.
- Create `assets/buildings/construction/construction_progress.gdshader`: transparent ring and clockwise radial fill.
- Create `assets/buildings/construction/construction_hammer_painted.png`: 512×512 transparent hand-painted hammer with the handle end at bottom center.
- Create `tests/test_construction_feedback.gd`: deterministic curve, pivot, shader progress, and lifecycle tests.
- Modify `tests/run_building_system_tests.gd`: run the focused feedback tests.
- Modify `scripts/buildings/building_instance.gd`: replace direct SVG hammer ownership with `ConstructionFeedback` delegation.
- Modify `tests/test_building_construction_state.gd`: exercise delegated feedback and isolation through a real building.
- Modify `tests/test_building_art_assets.gd`: enforce PNG dimensions, transparency, and shader availability.
- Modify `tests/test_building_visual_scene.gd`: require both the bottom hammer and upper-right progress indicator.
- Modify `tests/visual/building_system_verification.gd`: expose feedback progress and visibility in the interactive visual contract.
- Delete `assets/buildings/construction/construction_hammer.svg`: remove the superseded runtime asset after the PNG imports successfully.

### Task 1: Deterministic Construction Feedback Component

**Files:**
- Create: `tests/test_construction_feedback.gd`
- Modify: `tests/run_building_system_tests.gd`
- Create: `scripts/buildings/construction_feedback.gd`
- Create: `assets/buildings/construction/construction_progress.gdshader`

- [ ] **Step 1: Add the failing component test to the building runner**

Create `tests/test_construction_feedback.gd` with the following focused contract:

```gdscript
extends RefCounted

const FeedbackScript = preload("res://scripts/buildings/construction_feedback.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.near(rad_to_deg(FeedbackScript.strike_angle_for_phase(0.0)), 25.0, 0.01, "strike starts raised")
	assertions.near(rad_to_deg(FeedbackScript.strike_angle_for_phase(0.25)), 25.0, 0.01, "raised hold ends at 25 percent")
	assertions.near(rad_to_deg(FeedbackScript.strike_angle_for_phase(0.48)), 105.0, 0.01, "hammer reaches the base at 48 percent")
	assertions.near(rad_to_deg(FeedbackScript.strike_angle_for_phase(0.55)), 105.0, 0.01, "impact pause keeps the contact angle")
	assertions.near(rad_to_deg(FeedbackScript.strike_angle_for_phase(1.0)), 25.0, 0.01, "rebound returns to raised angle")

	var feedback := FeedbackScript.new()
	tree.root.add_child(feedback)
	feedback.configure(Vector2(3.0, 2.4))
	feedback.update_state(1.0 / 3.0, false, false, true)
	var pivot := feedback.get_node("HammerPivot") as Node3D
	var progress := feedback.get_node("Progress") as Sprite3D
	var fixed_pivot := pivot.position
	feedback.advance_animation(0.43)
	assertions.equal(pivot.position, fixed_pivot, "hammer handle end remains the fixed pivot")
	assertions.truthy(pivot.rotation.z > deg_to_rad(25.0), "strike rotates the head down toward the base")
	assertions.truthy(feedback.visible, "active unfinished construction shows feedback")
	var progress_material := progress.material_override as ShaderMaterial
	assertions.truthy(progress_material != null, "progress uses a shader material")
	assertions.near(float(progress_material.get_shader_parameter("progress")), 1.0 / 3.0, 0.001, "progress shader receives total progress")
	feedback.update_state(2.0 / 3.0, false, false, true)
	assertions.near(float(progress_material.get_shader_parameter("progress")), 2.0 / 3.0, 0.001, "progress continues across construction frames")
	feedback.update_state(0.5, true, false, true)
	assertions.truthy(not feedback.visible, "preview hides construction feedback")
	feedback.update_state(1.0, false, true, true)
	assertions.truthy(not feedback.visible, "completion hides construction feedback")
	feedback.update_state(0.5, false, false, false)
	assertions.truthy(not feedback.visible, "deactivation hides construction feedback")
	feedback.free()
```

Add to `tests/run_building_system_tests.gd`:

```gdscript
const ConstructionFeedbackTest = preload("res://tests/test_construction_feedback.gd")
```

Call it immediately before `BuildingConstructionStateTest`:

```gdscript
ConstructionFeedbackTest.new().run(assertions, self)
```

- [ ] **Step 2: Run the building suite and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: FAIL because `construction_feedback.gd` does not exist.

- [ ] **Step 3: Create the radial progress shader**

Create `assets/buildings/construction/construction_progress.gdshader`:

```glsl
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(1.0, 0.95, 0.78, 0.34);
uniform vec4 fill_color : source_color = vec4(1.0, 0.68, 0.20, 0.56);

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float radius = length(centered);
	float ring = 1.0 - smoothstep(0.455, 0.49, radius);
	ring *= smoothstep(0.405, 0.445, radius);
	float inside = 1.0 - smoothstep(0.40, 0.43, radius);
	float clockwise = mod(atan(centered.x, -centered.y) / 6.28318530718 + 1.0, 1.0);
	float sector = (1.0 - step(progress, clockwise)) * inside * step(0.0001, progress);
	vec4 color = ring_color * ring + fill_color * sector;
	ALBEDO = color.rgb;
	ALPHA = clamp(color.a, 0.0, 1.0);
}
```

- [ ] **Step 4: Implement the minimal feedback component**

Create `scripts/buildings/construction_feedback.gd` with `class_name ConstructionFeedback`, these constants, state, and interface:

```gdscript
class_name ConstructionFeedback
extends Node3D

const HAMMER_TEXTURE_PATH := "res://assets/buildings/construction/construction_hammer_painted.png"
const PROGRESS_SHADER_PATH := "res://assets/buildings/construction/construction_progress.gdshader"
const STRIKE_PERIOD := 0.9
const RAISED_ANGLE := deg_to_rad(25.0)
const IMPACT_ANGLE := deg_to_rad(105.0)

var _phase := 0.0
var _configured := false
var _asset_warnings := {}


static func strike_angle_for_phase(phase: float) -> float:
	var normalized := clampf(phase, 0.0, 1.0)
	if normalized <= 0.25:
		return RAISED_ANGLE
	if normalized <= 0.48:
		var fall_t := inverse_lerp(0.25, 0.48, normalized)
		return lerpf(RAISED_ANGLE, IMPACT_ANGLE, fall_t * fall_t * fall_t)
	if normalized <= 0.55:
		return IMPACT_ANGLE
	var rebound_t := inverse_lerp(0.55, 1.0, normalized)
	var eased := 1.0 - pow(1.0 - rebound_t, 3.0)
	return lerpf(IMPACT_ANGLE, RAISED_ANGLE, eased)
```

Its `_ensure_nodes()` must create `HammerPivot/HammerSprite` and `Progress`; `configure()` must place the pivot at `Vector3(visual_size.x * 0.38, 0.12, 0.16)`, place progress at `Vector3(visual_size.x * 0.52, visual_size.y * 1.03, 0.18)`, load the texture and shader, use a generated 128×128 white ImageTexture for the shader carrier, and size both sprites with clamped values. Set both sprites to billboard, unshaded/no-depth-test presentation and set the hammer sprite local position so its bottom-center handle end coincides with the parent origin:

```gdscript
var hammer_height := clampf(minf(visual_size.x, visual_size.y) * 0.32, 0.38, 0.72)
hammer_sprite.pixel_size = hammer_height / float(hammer_texture.get_height())
hammer_sprite.position.y = hammer_height * 0.5
var disk_size := clampf(minf(visual_size.x, visual_size.y) * 0.22, 0.28, 0.48)
progress.pixel_size = disk_size / 128.0
```

`update_state()` must clamp and pass progress to the material, set root visibility from `active and not preview and not complete`, and set each visual child's visibility from root visibility plus that child's resource validity. `advance_animation()` must ignore non-positive delta and a hidden hammer, wrap phase with `fmod`, and assign `HammerPivot.rotation.z = strike_angle_for_phase(_phase)`. Missing resources must hide only the failed visual and emit one warning per path.

- [ ] **Step 5: Import and run the component tests until GREEN**

Run:

```powershell
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: component curve, fixed pivot, shader progress, and lifecycle assertions pass; the existing suite may still fail only where it expects the old `VisualRoot/ConstructionHammer` path.

- [ ] **Step 6: Commit the deterministic component**

```powershell
git add scripts/buildings/construction_feedback.gd assets/buildings/construction/construction_progress.gdshader tests/test_construction_feedback.gd tests/run_building_system_tests.gd
git commit -m "feat: add construction strike feedback component"
```

### Task 2: Hand-Painted Hammer Asset

**Files:**
- Create: `assets/buildings/construction/construction_hammer_painted.png`
- Modify: `tests/test_building_art_assets.gd`
- Delete: `assets/buildings/construction/construction_hammer.svg`

- [ ] **Step 1: Change the asset contract and verify RED**

Change `HAMMER_ICON_PATH` to the PNG path and add `PROGRESS_SHADER_PATH`. After loading the hammer, add:

```gdscript
assertions.equal(hammer_texture.get_size(), Vector2(512, 512), "painted hammer is 512 square")
var hammer_image := hammer_texture.get_image()
assertions.truthy(hammer_image.detect_alpha(), "painted hammer contains alpha")
for corner in [Vector2i(0, 0), Vector2i(511, 0), Vector2i(0, 511), Vector2i(511, 511)]:
	assertions.equal(hammer_image.get_pixelv(corner).a, 0.0, "painted hammer corner is transparent")
assertions.truthy(ResourceLoader.exists(PROGRESS_SHADER_PATH), "construction progress shader exists")
assertions.truthy(load(PROGRESS_SHADER_PATH) is Shader, "construction progress imports as Shader")
```

Run the building suite. Expected: FAIL because the PNG is missing.

- [ ] **Step 2: Generate the style-matched transparent hammer**

Load the `imagegen` skill before generating. Inspect `assets/buildings/painted/barn/barn_back.png`, `assets/buildings/painted/barn/barn_front.png`, and `assets/buildings/construction/barn/barn_frame.png` as style references, then generate one transparent square image using this prompt:

```text
Create a single hand-painted 2D game construction hammer sprite matching the attached cozy isometric farm-building artwork. Transparent background, 512 by 512. Warm brown wood handle with visible painterly grain, slightly worn dark forged-iron hammer head, warm upper-left lighting, soft painted edges, same saturation and brush texture as the barn. Show the entire hammer with no cropping. Orient it vertically: hammer head centered near the upper third, straight handle descending to a clearly visible rounded handle end at bottom center. Leave generous transparent padding around all sides. No person, hand, text, ground, platform, shadow ellipse, extra tools, UI, border, or scenery.
```

Save the accepted output exactly as `assets/buildings/construction/construction_hammer_painted.png`. Use an alpha-preserving crop/resize only if needed to produce exactly 512×512 while keeping the handle end at bottom center.

- [ ] **Step 3: Import, inspect, and verify the asset contract**

Run the editor import and building suite, then inspect the PNG at original resolution. Expected: 512×512 RGBA, all four corners fully transparent, no cropped head/handle, and clear bottom-center pivot alignment.

- [ ] **Step 4: Remove the old SVG and commit the painted asset**

Delete `assets/buildings/construction/construction_hammer.svg` with `apply_patch`; let Godot discard/recreate import metadata as appropriate. Then commit:

```powershell
git add -A -- assets/buildings/construction tests/test_building_art_assets.gd
git commit -m "art: replace construction hammer with painted sprite"
```

### Task 3: BuildingInstance Delegation and Isolation

**Files:**
- Modify: `tests/test_building_construction_state.gd`
- Modify: `scripts/buildings/building_instance.gd`

- [ ] **Step 1: Rewrite the integration assertions for the new feedback tree**

Replace old hammer paths/calls with:

```gdscript
var feedback := instance.get_node_or_null("ConstructionFeedback") as ConstructionFeedback
var hammer := instance.get_node_or_null("ConstructionFeedback/HammerPivot") as Node3D
var hammer_sprite := instance.get_node_or_null("ConstructionFeedback/HammerPivot/HammerSprite") as Sprite3D
var progress_disk := instance.get_node_or_null("ConstructionFeedback/Progress") as Sprite3D
assertions.truthy(feedback != null, "construction creates independent feedback component")
assertions.truthy(hammer != null and hammer_sprite != null, "feedback creates bottom hammer pivot and sprite")
assertions.truthy(progress_disk != null, "feedback creates upper-right progress disk")
```

Advance animation through `feedback.advance_animation(0.43)`. After advancing construction to 10 seconds, assert the shader `progress` is `1.0 / 3.0`; after occlusion processing, assert both feedback sprites retain alpha 1.0. Assert preview, completion, and `deactivate()` hide the whole feedback node. Also assert `not instance._visual_geometry().has(hammer_sprite)` and `not instance._visual_geometry().has(progress_disk)`.

- [ ] **Step 2: Run the building suite and verify RED**

Expected: FAIL because `BuildingInstance` still creates `VisualRoot/ConstructionHammer` and never creates/configures the new component.

- [ ] **Step 3: Replace direct hammer ownership with delegation**

In `building_instance.gd`:

- preload `construction_feedback.gd`;
- remove the old hammer constants, `_hammer_phase`, `_configure_construction_hammer()`, `_update_construction_hammer_visibility()`, and `_animate_construction_hammer()`;
- stop creating `VisualRoot/ConstructionHammer`;
- create a direct child named `ConstructionFeedback` in `_ensure_nodes()`;
- call `feedback.configure(data.visual_size)` from `_configure_visuals()`;
- add `_sync_construction_feedback(active := true)` that calls `feedback.update_state(get_construction_progress(), _preview_mode, is_construction_complete(), active)`;
- call the sync method after construction start/restore/stage apply/preview changes and every `_process()` after time advancement;
- call `feedback.advance_animation(delta)` every `_process()`;
- call `_sync_construction_feedback(false)` in `deactivate()` before disabling processing;
- remove the `ConstructionHammer` name exception from `_collect_visual_geometry()` because feedback is outside `VisualRoot`.

Do not change the existing 10-second thresholds, 30-second duration, stage art transitions, save dictionary, signals, or physics state.

- [ ] **Step 4: Run the focused and building suites until GREEN**

Run the editor parse/import and building suite. Expected: the new component tests and real-building lifecycle/isolation tests pass with no old hammer path remaining under `scripts/` or `tests/`.

- [ ] **Step 5: Commit delegation**

```powershell
git add scripts/buildings/building_instance.gd tests/test_building_construction_state.gd
git commit -m "refactor: delegate building construction feedback"
```

### Task 4: Visual Contract and Capture

**Files:**
- Modify: `tests/test_building_visual_scene.gd`
- Modify: `tests/visual/building_system_verification.gd`
- Modify: `tests/capture_building_visual.gd` only if a second close-up capture is required for readable inspection.

- [ ] **Step 1: Make visual tests require both feedback elements**

Replace `VisualRoot/ConstructionHammer` with these required paths:

```gdscript
"ConstructionFeedback",
"ConstructionFeedback/HammerPivot",
"ConstructionFeedback/Progress",
```

For the FRAME demo, require visible feedback, require a pivot `y` position below 20% of `building.data.visual_size.y`, require progress `x > 0` and `y >= building.data.visual_size.y`, and require its shader value to match `building.get_construction_progress()`. Temporarily hiding feedback must make `_construction_contract_passes()` return false.

- [ ] **Step 2: Run the visual test and verify RED**

Run `godot --headless --path . --script res://tests/test_building_visual_scene.gd`. Expected: FAIL until the verifier contract uses the new component.

- [ ] **Step 3: Update the interactive verifier contract**

In `_construction_contract_passes()`, replace the old hammer lookup with:

```gdscript
var feedback := _active_construction.get_node("ConstructionFeedback") as ConstructionFeedback
var progress := feedback.get_node("Progress") as Sprite3D
```

Require `not feedback.visible` on completion. For unfinished construction require `feedback.visible`, a non-null progress material, and shader `progress` equal to `_active_construction.get_construction_progress()` within `0.001`.

- [ ] **Step 4: Run the visual contract and capture a fresh image**

Run:

```powershell
godot --headless --path . --script res://tests/test_building_visual_scene.gd
godot --path . --script res://tests/capture_building_visual.gd
```

Expected: visual contract exits 0 and `.godot/villa-building-system-verification.png` is regenerated.

- [ ] **Step 5: Inspect visual acceptance at original resolution**

Confirm the hammer handle end stays at the barn's right-front base, the hammer head is captured traveling left/down toward the base, the circular indicator is at upper-right without ticks, the fill begins at 12 o'clock and reads approximately one-third for the FRAME sample, and completed gallery buildings show neither element. If framing makes either element unreadable, adjust only component size/offset or capture framing and repeat Steps 4–5.

- [ ] **Step 6: Commit visual coverage**

```powershell
git add tests/test_building_visual_scene.gd tests/visual/building_system_verification.gd tests/capture_building_visual.gd
git commit -m "test: verify construction strike visuals"
```

### Task 5: Full Regression and Integration

**Files:**
- Modify only if a reproduced regression requires a scoped correction.

- [ ] **Step 1: Parse and import the complete project**

Run `godot --headless --editor --path . --quit`. Expected: exit 0 with no script parse or resource import error.

- [ ] **Step 2: Run subsystem and integration suites**

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path . --script res://tests/test_player_grid_binding.gd
```

Expected: each command exits 0 and reports PASS.

- [ ] **Step 3: Check stale references and repository integrity**

```powershell
rg -n "construction_hammer\.svg|VisualRoot/ConstructionHammer|_animate_construction_hammer|_hammer_phase" scripts tests assets
git diff --check
git status --short
```

Expected: `rg` finds no stale runtime/test references, `git diff --check` is empty, and status contains only an intentionally regenerated screenshot if that file is tracked.

- [ ] **Step 4: Commit only a verified final correction**

If regression or visual validation required a scoped correction, stage only those files, inspect `git diff --cached --name-only`, and commit `fix: finalize construction strike feedback`. If no correction was needed, do not create an empty commit.

- [ ] **Step 5: Review and integrate**

Use `requesting-code-review`, address verified findings, run `verification-before-completion`, then use `finishing-a-development-branch` to integrate the feature branch into local `main` and re-run the building suite plus visual contract after the merge.
