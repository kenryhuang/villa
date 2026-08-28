# Visible Agent NPC Character Art Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three Agent NPC capsules with role-specific, hand-painted, four-direction static sprites while preserving all existing interaction and dialogue behavior.

**Architecture:** Each NPC owns one two-by-two transparent direction atlas and shares a focused `NpcVisual` Sprite3D component. `Main` maps Agent IDs to atlas paths, `Npc` controls capsule fallback and forwards motion, and `NpcVisual` validates the atlas and selects a camera-relative static direction without playing animation.

**Tech Stack:** Godot 4.7, GDScript, Sprite3D atlas regions, GL Compatibility renderer, image generation for PNG assets, custom Godot test runners.

---

### Task 1: Generate and inspect the three four-direction atlases

**Files:**
- Create: `assets/characters/npcs/farmer_ahe/farmer_ahe_directions.png`
- Create: `assets/characters/npcs/lao_li/lao_li_directions.png`
- Create: `assets/characters/npcs/xuezhe_lin/xuezhe_lin_directions.png`

- [ ] **Step 1: Generate Ahe's atlas**

Use the image generation tool with this prompt and save its PNG output at the exact farmer path:

```text
Create a transparent-background 2x2 orthographic character direction atlas for a cozy hand-painted farming game. The same young adult woman farmer named Ahe appears once in each equal cell, full body, neutral standing pose, identical scale and ground alignment. Cell order: top-left back view, top-right right-facing profile, bottom-left front view, bottom-right left-facing profile. She wears a warm green headscarf, cream work shirt, brown-green apron, sturdy brown boots, and a small seed satchel. Earthy green, wheat, cream, and brown palette. Practical, dependable, friendly expression. Lightly chibi proportions matching a polished hand-painted isometric farm-game character. No held tools, no walking pose, no animation smear, no text, no labels, no borders, no grid lines, no shadows outside the character, and no scenery. Preserve real transparency everywhere outside the four figures. Keep generous separation between cells and keep every figure fully inside its cell.
```

- [ ] **Step 2: Generate Lao Li's atlas**

Use this prompt and save its PNG output at the exact merchant path:

```text
Create a transparent-background 2x2 orthographic character direction atlas for a cozy hand-painted farming game. The same middle-aged male merchant named Lao Li appears once in each equal cell, full body, neutral standing pose, identical scale and ground alignment. Cell order: top-left back view, top-right right-facing profile, bottom-left front view, bottom-right left-facing profile. He has a neat small moustache and wears a chestnut vest over a cream shirt, dark trousers, practical shoes, a waist ledger, and a coin pouch. Chestnut, burgundy, brass, cream, and charcoal palette. Slightly broad silhouette, friendly but shrewd expression. Lightly chibi proportions matching a polished hand-painted isometric farm-game character. No held items, no walking pose, no animation smear, no text, no labels, no borders, no grid lines, no shadows outside the character, and no scenery. Preserve real transparency everywhere outside the four figures. Keep generous separation between cells and keep every figure fully inside its cell.
```

- [ ] **Step 3: Generate Scholar Lin's atlas**

Use this prompt and save its PNG output at the exact explorer path:

```text
Create a transparent-background 2x2 orthographic character direction atlas for a cozy hand-painted farming game. The same young adult male explorer-scholar named Scholar Lin appears once in each equal cell, full body, neutral standing pose, identical scale and ground alignment. Cell order: top-left back view, top-right right-facing profile, bottom-left front view, bottom-right left-facing profile. He wears a teal-blue short field coat, round glasses, dark practical trousers, leather boots, a light backpack, a rolled map secured to the pack, and a small notebook pouch. Teal, navy, parchment, leather brown, and muted gold palette. Slim field-ready silhouette, curious but careful expression. Lightly chibi proportions matching a polished hand-painted isometric farm-game character. No held items, no walking pose, no animation smear, no text, no labels, no borders, no grid lines, no shadows outside the character, and no scenery. Preserve real transparency everywhere outside the four figures. Keep generous separation between cells and keep every figure fully inside its cell.
```

- [ ] **Step 4: Inspect all atlases**

Open each PNG at original detail and verify: true transparent background; exactly four complete figures; specified cell order; consistent scale and ground line; no text, border, grid, scenery, cropped limbs, or animation pose. Regenerate only the failing atlas if any requirement is violated.

- [ ] **Step 5: Commit the art assets**

```powershell
git add -- assets/characters/npcs/farmer_ahe/farmer_ahe_directions.png assets/characters/npcs/lao_li/lao_li_directions.png assets/characters/npcs/xuezhe_lin/xuezhe_lin_directions.png
git commit -m "feat: add role-specific Agent NPC art"
```

### Task 2: Build the static four-direction visual component with TDD

**Files:**
- Create: `scripts/visual/npc_visual.gd`
- Create: `tests/test_npc_visual.gd`
- Modify: `tests/run_agent_system_tests.gd`

- [ ] **Step 1: Add a failing component-contract test**

Create `tests/test_npc_visual.gd` with a dynamic script load so a missing implementation produces an assertion failure rather than a parser error:

```gdscript
extends RefCounted

const SCRIPT_PATH := "res://scripts/visual/npc_visual.gd"


func run(assertions: TestAssert) -> void:
	var visual_script := load(SCRIPT_PATH) as Script
	assertions.truthy(visual_script != null, "NpcVisual script exists")
	if visual_script == null:
		return
	var visual = visual_script.new()
	assertions.truthy(visual.has_method("configure"), "NpcVisual exposes atlas configuration")
	assertions.truthy(visual.has_method("sync_motion"), "NpcVisual exposes static direction synchronization")
	assertions.truthy(visual.has_method("get_last_direction"), "NpcVisual exposes its last direction")
	visual.free()
```

Preload and run it from `tests/run_agent_system_tests.gd`:

```gdscript
const NpcVisualTest = preload("res://tests/test_npc_visual.gd")
```

```gdscript
	var npc_visual_test := NpcVisualTest.new()
	npc_visual_test.run(assertions)
```

- [ ] **Step 2: Run the suite and verify the missing-component failure**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: FAIL only the new `NpcVisual script exists` assertion.

- [ ] **Step 3: Add the minimal component contract**

Create `scripts/visual/npc_visual.gd`:

```gdscript
class_name NpcVisual
extends Sprite3D

const DEFAULT_DIRECTION := "s"

var _last_direction := DEFAULT_DIRECTION


func configure(_atlas: Texture2D) -> bool:
	return false


func sync_motion(_planar_velocity: Vector2) -> void:
	pass


func get_last_direction() -> String:
	return _last_direction
```

- [ ] **Step 4: Run the suite and verify the contract passes**

Run the Agent suite. Expected: PASS with four additional component-contract checks.

- [ ] **Step 5: Extend the test with failing atlas and direction behavior**

Append helpers and assertions to `tests/test_npc_visual.gd`:

```gdscript
func _texture(width: int, height: int) -> ImageTexture:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
```

Before freeing `visual`, assert:

```gdscript
	assertions.truthy(not visual.configure(null), "NpcVisual rejects a missing atlas")
	assertions.truthy(not visual.configure(_texture(401, 400)), "NpcVisual rejects a non-divisible atlas")
	assertions.truthy(visual.configure(_texture(400, 400)), "NpcVisual accepts a two-by-two atlas")
	assertions.equal(visual.get_last_direction(), "s", "NpcVisual begins facing front")
	assertions.equal(visual.region_rect, Rect2(0, 200, 200, 200), "front uses the bottom-left cell")
	visual.sync_motion(Vector2(1.0, 0.0))
	assertions.equal(visual.get_last_direction(), "e", "rightward motion faces east")
	assertions.equal(visual.region_rect, Rect2(200, 0, 200, 200), "east uses the top-right cell")
	visual.sync_motion(Vector2(-1.0, 0.0))
	assertions.equal(visual.get_last_direction(), "w", "leftward motion faces west")
	assertions.equal(visual.region_rect, Rect2(200, 200, 200, 200), "west uses the bottom-right cell")
	visual.sync_motion(Vector2(0.0, -1.0))
	assertions.equal(visual.get_last_direction(), "n", "upward motion faces north")
	assertions.equal(visual.region_rect, Rect2(0, 0, 200, 200), "north uses the top-left cell")
	visual.sync_motion(Vector2.ZERO)
	assertions.equal(visual.get_last_direction(), "n", "stopping preserves the last direction")
	assertions.truthy(visual.visible, "valid configuration shows the sprite")
```

- [ ] **Step 6: Run the suite and verify behavior assertions fail**

Run the Agent suite. Expected: FAIL because `configure` still returns false and direction/region state is not implemented.

- [ ] **Step 7: Implement atlas validation and static direction selection**

Replace `scripts/visual/npc_visual.gd` with:

```gdscript
class_name NpcVisual
extends Sprite3D

const DEFAULT_DIRECTION := "s"
const GRID_SIZE := Vector2i(2, 2)
const TARGET_CELL_WORLD_HEIGHT := 1.35
const MOVEMENT_THRESHOLD_SQUARED := 0.0025
const DIRECTION_CELLS := {
	"n": Vector2i(0, 0),
	"e": Vector2i(1, 0),
	"s": Vector2i(0, 1),
	"w": Vector2i(1, 1),
}

var _configured := false
var _last_direction := DEFAULT_DIRECTION
var _cell_size := Vector2i.ZERO


func configure(atlas: Texture2D) -> bool:
	_configured = false
	visible = false
	texture = null
	if atlas == null or atlas.get_width() <= 0 or atlas.get_height() <= 0:
		return false
	if atlas.get_width() % GRID_SIZE.x != 0 or atlas.get_height() % GRID_SIZE.y != 0:
		return false
	_cell_size = Vector2i(atlas.get_width() / GRID_SIZE.x, atlas.get_height() / GRID_SIZE.y)
	texture = atlas
	region_enabled = true
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaded = false
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	pixel_size = TARGET_CELL_WORLD_HEIGHT / float(_cell_size.y)
	centered = true
	_last_direction = DEFAULT_DIRECTION
	_apply_direction()
	_configured = true
	visible = true
	return true


func sync_motion(planar_velocity: Vector2) -> void:
	if not _configured or planar_velocity.length_squared() <= MOVEMENT_THRESHOLD_SQUARED:
		return
	if absf(planar_velocity.x) > absf(planar_velocity.y):
		_last_direction = "e" if planar_velocity.x > 0.0 else "w"
	else:
		_last_direction = "s" if planar_velocity.y > 0.0 else "n"
	_apply_direction()


func get_last_direction() -> String:
	return _last_direction


func is_configured() -> bool:
	return _configured


func _apply_direction() -> void:
	var cell := DIRECTION_CELLS[_last_direction] as Vector2i
	region_rect = Rect2(Vector2(cell * _cell_size), Vector2(_cell_size))
```

- [ ] **Step 8: Run the focused suite**

Run the Agent suite. Expected: PASS with all new atlas and direction checks.

### Task 3: Integrate role art while preserving capsule fallback

**Files:**
- Modify: `scenes/actors/npc.tscn`
- Modify: `scripts/actors/npc.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_visible_agent_npc_dialogue.gd`

- [ ] **Step 1: Add failing integration assertions**

In `tests/test_visible_agent_npc_dialogue.gd`, assert exact binding paths and, after `_setup_npcs()`, assert each configured NPC has a visible `NpcVisual`, hidden placeholder mesh, and matching texture resource path:

```gdscript
	var expected_visual_paths := {
		"farmer_ahe": "res://assets/characters/npcs/farmer_ahe/farmer_ahe_directions.png",
		"lao_li": "res://assets/characters/npcs/lao_li/lao_li_directions.png",
		"xuezhe_lin": "res://assets/characters/npcs/xuezhe_lin/xuezhe_lin_directions.png",
	}
	for binding_value in bindings.values():
		var binding := binding_value as Dictionary
		var visual_path := str(binding.get("visual_path", ""))
		assertions.equal(
			visual_path,
			str(expected_visual_paths.get(str(binding.agent_id), "")),
			"%s maps to its role art" % binding.agent_id
		)
		var atlas := load(visual_path) as Texture2D
		assertions.truthy(atlas != null, "%s role atlas loads" % binding.agent_id)
		if atlas != null:
			assertions.equal(atlas.get_width() % 2, 0, "%s atlas width divides into two cells" % binding.agent_id)
			assertions.equal(atlas.get_height() % 2, 0, "%s atlas height divides into two cells" % binding.agent_id)
```

```gdscript
	for npc in [farmer, merchant, explorer]:
		var visual := npc.get_node_or_null("NpcVisual") as Sprite3D
		assertions.truthy(visual != null and visual.visible, "%s role sprite is visible" % npc.villager_id)
		assertions.truthy(not (npc.get_node("Mesh") as MeshInstance3D).visible, "%s capsule is hidden" % npc.villager_id)
		if visual != null and visual.texture != null:
			assertions.equal(visual.texture.resource_path, str(expected_visual_paths[npc.villager_id]), "%s loads its own atlas" % npc.villager_id)

	var fallback_npc = NpcScene.instantiate()
	tree.root.add_child(fallback_npc)
	assertions.truthy(fallback_npc.has_method("configure_agent_visual"), "NPC exposes visual fallback configuration")
	if fallback_npc.has_method("configure_agent_visual"):
		assertions.truthy(not fallback_npc.configure_agent_visual(null), "missing atlas rejects role art")
		assertions.truthy((fallback_npc.get_node("Mesh") as MeshInstance3D).visible, "missing atlas keeps capsule fallback visible")
	fallback_npc.free()
```

- [ ] **Step 2: Run the focused suite and verify integration failures**

Run the Agent suite. Expected: FAIL because bindings lack `visual_path`, the scene lacks `NpcVisual`, and capsules remain visible.

- [ ] **Step 3: Add the visual node and fallback control**

In `scenes/actors/npc.tscn`, add the script resource, increase `load_steps`, and add:

```gdscript
[ext_resource path="res://scripts/visual/npc_visual.gd" type="Script" id="3_npc_visual"]

[node name="NpcVisual" type="Sprite3D" parent="."]
visible = false
position = Vector3(0, 0.66, 0)
script = ExtResource("3_npc_visual")
```

In `scripts/actors/npc.gd`, add onready references and focused configuration:

```gdscript
@onready var placeholder_mesh: MeshInstance3D = get_node_or_null("Mesh")
@onready var npc_visual: NpcVisual = get_node_or_null("NpcVisual")
```

```gdscript
func configure_agent_visual(atlas: Texture2D) -> bool:
	var configured := npc_visual != null and npc_visual.configure(atlas)
	if placeholder_mesh != null:
		placeholder_mesh.visible = not configured
	return configured
```

At the end of `_physics_process`, forward camera-relative motion:

```gdscript
	_sync_visual_motion()
```

```gdscript
func _sync_visual_motion() -> void:
	if npc_visual == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_right := camera.global_basis.x
	camera_right.y = 0.0
	var camera_forward := -camera.global_basis.z
	camera_forward.y = 0.0
	if camera_right.length_squared() <= 0.0001 or camera_forward.length_squared() <= 0.0001:
		return
	camera_right = camera_right.normalized()
	camera_forward = camera_forward.normalized()
	npc_visual.sync_motion(Vector2(
		velocity.dot(camera_right),
		-velocity.dot(camera_forward)
	))
```

- [ ] **Step 4: Map and configure the three atlases in Main**

Add `visual_path` to each `AGENT_NPC_BINDINGS` entry in `scripts/main.gd` using the exact paths from Step 1. After visual priority configuration, add:

```gdscript
		var atlas := load(str(binding.visual_path)) as Texture2D
		if not bool(npc.call("configure_agent_visual", atlas)):
			push_error("Unable to configure visual for Agent NPC %s" % agent_id)
```

Do not `continue` after a visual failure: Agent routing and body-click dialogue must remain available through the capsule fallback.

- [ ] **Step 5: Run the focused Agent suite**

Run the Agent suite. Expected: PASS with all role-asset and fallback integration checks.

- [ ] **Step 6: Commit runtime integration**

```powershell
git add -- scripts/visual/npc_visual.gd scripts/actors/npc.gd scripts/main.gd scenes/actors/npc.tscn tests/test_npc_visual.gd tests/test_visible_agent_npc_dialogue.gd tests/run_agent_system_tests.gd
git commit -m "feat: render role-specific Agent NPCs"
```

### Task 4: Verify behavior and rendered output

**Files:**
- Modify: `docs/superpowers/plans/2026-08-28-visible-agent-npc-character-art.md`

- [ ] **Step 1: Run the focused Agent suite fresh**

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: all Agent checks pass.

- [ ] **Step 2: Run the full suite against the recorded baseline**

```powershell
godot_console --headless --path . --script res://tests/run_tests.gd
```

Expected: no failures beyond the recorded baseline of four checks: three economy order/contract state checks and one villager-count check.

- [ ] **Step 3: Capture initial and four-direction views**

Use a temporary non-headless Godot probe to capture all three NPCs in the initial scene, then move each NPC in camera-relative front, back, left, and right directions long enough to select its static direction. Confirm role silhouettes, scale, transparency, grounding, nameplate clearance, dialogue prompt clearance, and direction correctness. Delete the probe before completion.

- [ ] **Step 4: Verify repository state**

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors and only the implementation-plan completion update remains uncommitted.

- [ ] **Step 5: Commit the completed plan record**

```powershell
git add -- docs/superpowers/plans/2026-08-28-visible-agent-npc-character-art.md
git commit -m "docs: record Agent NPC art implementation"
```
