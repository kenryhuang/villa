# Hand-Painted Grain Crop Visuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four grain growth-stage low-poly visuals with deterministic, layered, hand-painted 2.5D crop clusters that match the existing terrain and tree art while retaining the current models as a safe fallback.

**Architecture:** Each existing grain stage scene remains at its current resource path and gains a shared `CropSpriteCluster` script plus front/back `Sprite3D` layers. `FarmingSystem` passes a stable seed derived from grid coordinates and crop ID before the stage scene enters the tree; the component chooses one of three texture pairs and hides the retained low-poly fallback only after both textures load successfully.

**Tech Stack:** Godot 4.7.1, GDScript, `Sprite3D`, PNG alpha textures, built-in image generation with chroma-key removal, existing script-based Godot tests.

## Global Constraints

- Do not change planting, growth, watering, season, greenhouse, harvest, inventory, or save behavior.
- Keep all four paths under `res://assets/crops/grain/grain_stage_*.tscn` unchanged.
- Produce three variants per stage and two transparent 1024×1024 PNG layers per variant.
- Match the existing hand-painted, semi-realistic tree art with upper-left lighting and natural muted colors.
- Use Billboard, opaque prepass alpha cutting, no realtime shadow casting, a shared root anchor, and deterministic variation.
- Missing or invalid painted textures must leave the existing low-poly stage model visible.
- Do not add wind animation or modify terrain and tree assets.

---

### Task 1: Create and validate the 24 painted grain textures

**Files:**
- Create: `tests/test_grain_crop_art_assets.gd`
- Modify: `tests/run_farming_system_tests.gd`
- Create: `assets/crops/grain/painted/stage_0/variant_{0,1,2}_{back,front}.png`
- Create: `assets/crops/grain/painted/stage_1/variant_{0,1,2}_{back,front}.png`
- Create: `assets/crops/grain/painted/stage_2/variant_{0,1,2}_{back,front}.png`
- Create: `assets/crops/grain/painted/stage_3/variant_{0,1,2}_{back,front}.png`

**Interfaces:**
- Consumes: Existing style reference `assets/vegetation/tree-oak-large.png`; built-in `image_gen`; `$CODEX_HOME/skills/.system/imagegen/scripts/remove_chroma_key.py`.
- Produces: `TestGrainCropArtAssets.run(assertions: TestAssert) -> void`; 24 importable PNG resources with transparent corners.

- [ ] **Step 1: Write the failing asset-contract test**

Create `tests/test_grain_crop_art_assets.gd`:

```gdscript
extends RefCounted

const STAGE_COUNT := 4
const VARIANT_COUNT := 3
const LAYERS := ["back", "front"]


static func texture_path(stage: int, variant: int, layer: String) -> String:
	return "res://assets/crops/grain/painted/stage_%d/variant_%d_%s.png" % [
		stage, variant, layer
	]


func run(assertions: TestAssert) -> void:
	for stage in STAGE_COUNT:
		for variant in VARIANT_COUNT:
			for layer in LAYERS:
				var path := texture_path(stage, variant, layer)
				assertions.truthy(ResourceLoader.exists(path), "%s exists" % path)
				if not ResourceLoader.exists(path):
					continue
				var texture := load(path) as Texture2D
				assertions.truthy(texture != null, "%s imports as Texture2D" % path)
				if texture == null:
					continue
				assertions.equal(texture.get_size(), Vector2(1024, 1024), "%s is 1024 square" % path)
				var image := texture.get_image()
				assertions.truthy(image.detect_alpha(), "%s contains alpha" % path)
				assertions.equal(image.get_pixel(0, 0).a, 0.0, "%s has a transparent corner" % path)
```

Add it to `tests/run_farming_system_tests.gd`:

```gdscript
const GrainCropArtAssetsTest = preload("res://tests/test_grain_crop_art_assets.gd")
```

and call it immediately before `GrainCropModelsTest`:

```gdscript
GrainCropArtAssetsTest.new().run(assertions)
```

- [ ] **Step 2: Run the test and verify the missing assets fail**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/run_farming_system_tests.gd
```

Expected: non-zero exit with failures naming `res://assets/crops/grain/painted/stage_0/...`.

- [ ] **Step 3: Generate each stage and variant using the tree as a style reference**

Use the built-in image-generation tool once for each requested layer. Reference `assets/vegetation/tree-oak-large.png` as a style-only input. Use magenta because green is part of the crop artwork.

Back-layer prompt template:

```text
Use case: stylized-concept
Asset type: transparent 2.5D Godot crop sprite, BACK layer
Input image: tree-oak-large.png is a style, brushwork, palette, outline, and upper-left-lighting reference only
Primary request: hand-painted semi-realistic grain crop cluster, growth stage {STAGE_DESCRIPTION}, variation {VARIANT}
Subject: only the taller rear plants; natural height, bend, and spacing differences; include a subtle painted soil contact shadow at the roots
Composition: centered on a square canvas, shared root anchor at 82% canvas height, generous transparent-removal padding, game camera sees the plants from an elevated three-quarter view
Palette: muted natural greens or wheat golds appropriate to the stage; never neon
Backdrop: perfectly flat solid #ff00ff chroma-key background
Constraints: opaque crop artwork, crisp soft-painted edges, no front plants, no square soil tile, no text, no watermark
Avoid: photorealism, plastic 3D rendering, black outlines, scenery, sky, horizon, pots, tools, characters
```

Front-layer prompt template:

```text
Use case: stylized-concept
Asset type: transparent 2.5D Godot crop sprite, FRONT layer
Input images: tree-oak-large.png is the style reference; the selected matching back layer is a palette and scale reference
Primary request: complementary shorter foreground plants for the same grain cluster, growth stage {STAGE_DESCRIPTION}, variation {VARIANT}
Subject: only the shorter front plants; leave open gaps so the back plants remain visible; no cast or contact shadow
Composition: centered on a square canvas, same root anchor at 82% canvas height and same elevated three-quarter view as the back layer
Backdrop: perfectly flat solid #ff00ff chroma-key background
Constraints: match the back layer's brushwork, lighting, scale, and natural muted palette; no duplicated rear plants, no text, no watermark
Avoid: photorealism, plastic 3D rendering, scenery, square background, pots, tools, characters
```

Use these stage descriptions:

```text
0: three to five ochre grain seeds, partly buried, close to the ground
1: five to seven tender yellow-green shoots, about 30% of mature height
2: seven to nine olive-green stalks and leaves with pale green young heads, about 70% of mature height
3: seven to nine mature wheat stalks with full ochre-gold heads, mixed straw-yellow, brown, and a few remaining green leaves
```

- [ ] **Step 4: Remove chroma key and normalize every selected output**

Copy generated sources into `tmp/imagegen/grain/`, then run the installed helper for every layer:

```bash
python "${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/scripts/remove_chroma_key.py" \
  --input tmp/imagegen/grain/stage_0_variant_0_back_source.png \
  --out assets/crops/grain/painted/stage_0/variant_0_back.png \
  --auto-key border \
  --soft-matte \
  --transparent-threshold 12 \
  --opaque-threshold 220 \
  --despill
```

If a visible magenta fringe remains, rerun that asset once with `--edge-contract 1`. Normalize every final file:

```bash
sips --resampleHeightWidth 1024 1024 \
  assets/crops/grain/painted/stage_0/variant_0_back.png \
  --out assets/crops/grain/painted/stage_0/variant_0_back.png
```

Repeat with the exact destination names defined by `texture_path()`.

- [ ] **Step 5: Inspect all final alpha images**

Create a contact sheet for inspection without editing the project assets:

```bash
mkdir -p tmp/imagegen/grain/contact
sips --resampleHeightWidth 256 256 assets/crops/grain/painted/stage_*/*.png \
  --out tmp/imagegen/grain/contact
```

Open representative files with the image viewer. Reject and regenerate any image with magenta fringe, clipped leaves, inconsistent root position, unexpected text, a square soil patch, or a visual style that does not match the reference tree.

- [ ] **Step 6: Reimport and run the asset-contract test**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --editor --path /Users/huanggui/UnrealEngine/villa --quit
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/run_farming_system_tests.gd
```

Expected: all 24 resource, size, alpha, and transparent-corner checks pass; pre-existing farming tests remain green.

- [ ] **Step 7: Commit the validated artwork**

```bash
git add assets/crops/grain/painted tests/test_grain_crop_art_assets.gd tests/run_farming_system_tests.gd
git commit -m "art: add painted grain growth stages"
```

---

### Task 2: Implement the reusable layered crop sprite component

**Files:**
- Create: `scripts/visual/crop_sprite_cluster.gd`
- Create: `tests/test_crop_sprite_cluster.gd`
- Modify: `tests/run_farming_system_tests.gd`

**Interfaces:**
- Consumes: Arrays of three back texture paths and three front texture paths.
- Produces: `CropSpriteCluster.configure_variant_seed(seed: int) -> void`, `CropSpriteCluster.get_variant_index() -> int`, and `CropSpriteCluster.variant_index_for_seed(seed: int, count: int) -> int`.

- [ ] **Step 1: Write the failing component test**

Create `tests/test_crop_sprite_cluster.gd`:

```gdscript
extends RefCounted

const ClusterScript = preload("res://scripts/visual/crop_sprite_cluster.gd")


func _paths(stage: int, layer: String) -> Array[String]:
	var result: Array[String] = []
	for variant in 3:
		result.append(
			"res://assets/crops/grain/painted/stage_%d/variant_%d_%s.png"
			% [stage, variant, layer]
		)
	return result


func run(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.equal(ClusterScript.variant_index_for_seed(4, 3), 1, "seed selects variant by positive modulo")
	assertions.equal(ClusterScript.variant_index_for_seed(-1, 3), 2, "negative seed is normalized")
	var cluster := ClusterScript.new()
	cluster.back_texture_paths = _paths(2, "back")
	cluster.front_texture_paths = _paths(2, "front")
	cluster.configure_variant_seed(4)
	tree.root.add_child(cluster)
	assertions.equal(cluster.get_variant_index(), 1, "configured seed is applied on ready")
	assertions.truthy(cluster.get_node("BackLayer").texture != null, "back texture is loaded")
	assertions.truthy(cluster.get_node("FrontLayer").texture != null, "front texture is loaded")
	assertions.equal(cluster.get_node("BackLayer").billboard, BaseMaterial3D.BILLBOARD_ENABLED, "back layer billboards")
	assertions.equal(cluster.get_node("FrontLayer").alpha_cut, SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS, "front alpha uses opaque prepass")
	cluster.free()
```

Preload and run it from `tests/run_farming_system_tests.gd`, passing `self` as the second argument.

- [ ] **Step 2: Run the component test and verify it fails**

Run the farming test command from Task 1.

Expected: parse or preload failure because `scripts/visual/crop_sprite_cluster.gd` does not exist.

- [ ] **Step 3: Implement the component**

Create `scripts/visual/crop_sprite_cluster.gd`:

```gdscript
class_name CropSpriteCluster
extends Node3D

@export var back_texture_paths: Array[String] = []
@export var front_texture_paths: Array[String] = []
@export var canvas_world_height := 1.15
@export var front_offset := Vector3(0.025, 0.0, 0.025)
@export var back_modulate := Color(0.9, 0.9, 0.9, 1.0)

var _variant_seed := 0
var _variant_index := -1
var _configured := false


static func variant_index_for_seed(seed: int, count: int) -> int:
	return posmod(seed, count) if count > 0 else -1


func configure_variant_seed(seed: int) -> void:
	_variant_seed = seed
	_configured = true
	if is_inside_tree():
		_apply_variant()


func get_variant_index() -> int:
	return _variant_index


func _ready() -> void:
	_ensure_layers()
	_apply_variant()


func _ensure_layers() -> void:
	if get_node_or_null("BackLayer") == null:
		var back := Sprite3D.new()
		back.name = "BackLayer"
		add_child(back)
	if get_node_or_null("FrontLayer") == null:
		var front := Sprite3D.new()
		front.name = "FrontLayer"
		add_child(front)


func _apply_variant() -> void:
	_ensure_layers()
	var count := mini(back_texture_paths.size(), front_texture_paths.size())
	var index := variant_index_for_seed(_variant_seed if _configured else 0, count)
	if index < 0:
		_show_fallback("no complete painted variants")
		return
	var back := _load_texture(back_texture_paths[index])
	var front := _load_texture(front_texture_paths[index])
	if back == null or front == null:
		_show_fallback("missing painted texture pair at variant %d" % index)
		return
	_variant_index = index
	_configure_sprite($BackLayer, back, Vector3.ZERO, back_modulate, -0.1)
	_configure_sprite($FrontLayer, front, front_offset, Color.WHITE, 0.1)
	_set_fallback_visible(false)


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _configure_sprite(
	sprite: Sprite3D,
	texture: Texture2D,
	offset: Vector3,
	color: Color,
	sort_offset: float
) -> void:
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.pixel_size = canvas_world_height / float(texture.get_height())
	sprite.position = Vector3(offset.x, canvas_world_height * 0.5 + offset.y, offset.z)
	sprite.modulate = color
	sprite.sorting_offset = sort_offset
	sprite.visible = true


func _show_fallback(reason: String) -> void:
	_variant_index = -1
	$BackLayer.visible = false
	$FrontLayer.visible = false
	_set_fallback_visible(true)
	push_warning("CropSpriteCluster fallback: %s" % reason)


func _set_fallback_visible(value: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = value
```

- [ ] **Step 4: Run tests and verify the component contract passes**

Run the farming test command.

Expected: the new deterministic-selection, texture-loading, Billboard, and alpha-cut checks pass.

- [ ] **Step 5: Commit the component**

```bash
git add scripts/visual/crop_sprite_cluster.gd tests/test_crop_sprite_cluster.gd tests/run_farming_system_tests.gd
git commit -m "feat: add layered crop sprite component"
```

---

### Task 3: Convert the four stage scenes and pass stable grid seeds

**Files:**
- Modify: `assets/crops/grain/grain_stage_0_seed.tscn`
- Modify: `assets/crops/grain/grain_stage_1_sprout.tscn`
- Modify: `assets/crops/grain/grain_stage_2_growing.tscn`
- Modify: `assets/crops/grain/grain_stage_3_mature.tscn`
- Modify: `scripts/systems/farming_system.gd`
- Modify: `tests/test_grain_crop_models.gd`

**Interfaces:**
- Consumes: `CropSpriteCluster.configure_variant_seed(seed: int)`.
- Produces: `FarmingSystem.crop_visual_seed(cell: GridCell, crop_id: String) -> int`; each stage scene configures three texture pairs and retains all existing direct-child `MeshInstance3D` nodes as fallback.

- [ ] **Step 1: Extend the grain integration test**

Change the test signature to accept the active `SceneTree`:

```gdscript
func run(assertions: TestAssert, tree: SceneTree) -> void:
```

Change the runner call to:

```gdscript
GrainCropModelsTest.new().run(assertions, self)
```

Then add these checks to `tests/test_grain_crop_models.gd`:

```gdscript
const ClusterScript = preload("res://scripts/visual/crop_sprite_cluster.gd")

# Inside the stage-scene loop, after instantiation:
assertions.truthy(model is CropSpriteCluster, "grain stage %d uses CropSpriteCluster" % index)
model.configure_variant_seed(7)
tree.root.add_child(model)
assertions.equal(model.get_variant_index(), 1, "grain stage %d selects painted variant" % index)
assertions.truthy(model.get_node("BackLayer").visible, "grain stage %d shows back layer" % index)
assertions.truthy(model.get_node("FrontLayer").visible, "grain stage %d shows front layer" % index)
for mesh_instance in meshes:
	assertions.falsy(mesh_instance.visible, "grain stage %d hides fallback model" % index)
model.get_parent().remove_child(model)
model.free()
```

After planting, assert a stable variant:

```gdscript
var first_variant := visual.get_variant_index()
farming.rebuild_visuals()
visual = farming.get_crop_visual(cell)
assertions.equal(visual.get_variant_index(), first_variant, "rebuild preserves grid-based variant")
assertions.equal(
	visual.get_meta("visual_seed"),
	FarmingSystem.crop_visual_seed(cell, crop.crop_id),
	"visual stores deterministic seed"
)
```

- [ ] **Step 2: Run tests and verify the stage-scene contract fails**

Run the farming test command.

Expected: failures show that the current stage roots are plain `Node3D` and do not expose painted layers.

- [ ] **Step 3: Attach the shared script and texture arrays to each stage**

For each `grain_stage_*.tscn`, add:

```text
[ext_resource path="res://scripts/visual/crop_sprite_cluster.gd" type="Script" id="CropSpriteClusterScript"]
```

Set the root:

```text
script = ExtResource("CropSpriteClusterScript")
back_texture_paths = Array[String]([
  "res://assets/crops/grain/painted/stage_N/variant_0_back.png",
  "res://assets/crops/grain/painted/stage_N/variant_1_back.png",
  "res://assets/crops/grain/painted/stage_N/variant_2_back.png"
])
front_texture_paths = Array[String]([
  "res://assets/crops/grain/painted/stage_N/variant_0_front.png",
  "res://assets/crops/grain/painted/stage_N/variant_1_front.png",
  "res://assets/crops/grain/painted/stage_N/variant_2_front.png"
])
```

Use these `canvas_world_height` values:

```text
stage 0: 0.28
stage 1: 0.48
stage 2: 0.86
stage 3: 1.15
```

Do not remove or rename the existing `MeshInstance3D` nodes; they are the visual fallback.

- [ ] **Step 4: Add and pass the deterministic visual seed**

Add to `scripts/systems/farming_system.gd`:

```gdscript
static func crop_visual_seed(cell: GridCell, crop_id: String) -> int:
	if cell == null:
		return crop_id.hash()
	return GridSystemScript.cell_key(cell.gx, cell.gz) ^ crop_id.hash()
```

In `_instantiate_stage_visual()`, immediately after instantiation and before `add_child()`:

```gdscript
var visual_seed := crop_visual_seed(cell, instance.crop_data.crop_id)
if visual.has_method("configure_variant_seed"):
	visual.call("configure_variant_seed", visual_seed)
visual.set_meta("visual_seed", visual_seed)
```

- [ ] **Step 5: Run the farming and grid tests**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/run_farming_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/run_grid_system_tests.gd
```

Expected: both suites pass; existing low-poly mesh-count tests still pass because the fallback meshes remain in each scene.

- [ ] **Step 6: Commit the stage integration**

```bash
git add assets/crops/grain/grain_stage_*.tscn scripts/systems/farming_system.gd tests/test_grain_crop_models.gd
git commit -m "feat: render grain stages as painted sprite clusters"
```

---

### Task 4: Expand the visual verifier to show all stage variants

**Files:**
- Modify: `tests/visual/farming_system_verification.gd`
- Modify: `tests/test_farming_visual_scene.gd`
- Modify: `tests/capture_farming_visual.gd` only if camera framing must change for a 12-plot capture.

**Interfaces:**
- Consumes: Four stage scenes with three deterministic variants.
- Produces: A 12-plot visual matrix with four stage columns and three variation rows.

- [ ] **Step 1: Strengthen the visual-scene contract test**

Add checks to `tests/test_farming_visual_scene.gd`:

```gdscript
assertions.equal(scene_script.PLOT_COORDS.size(), 12, "visual verifier contains twelve crop plots")
assertions.equal(scene_script.STAGE_NAMES.size(), 4, "visual verifier labels four stages")
```

The scene contract must also instantiate the scene, collect `CropVisuals` after `_ready()`, and assert that each stage has three distinct `get_variant_index()` values across its row/column sample.

- [ ] **Step 2: Run the scene test and verify it fails at four plots**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/test_farming_visual_scene.gd
```

Expected: failure reports `4 != 12`.

- [ ] **Step 3: Build the 4×3 verification layout**

Replace `PLOT_COORDS` with:

```gdscript
const PLOT_COORDS: Array[Vector2i] = [
	Vector2i(10, 18), Vector2i(11, 18), Vector2i(12, 18), Vector2i(13, 18),
	Vector2i(10, 19), Vector2i(11, 19), Vector2i(12, 19), Vector2i(13, 19),
	Vector2i(10, 20), Vector2i(11, 20), Vector2i(12, 20), Vector2i(13, 20),
]
```

When initializing crops, derive the stage from the column:

```gdscript
var stage_index := index % STAGE_NAMES.size()
crop.growth_progress = float(stage_index)
```

Build one label per stage column above the back row, change the UI check to:

```gdscript
["手绘分层谷物：12 / 12", _count_grain_models() == 12],
["稳定视觉变体：3 / 阶段", _all_stages_show_three_variants()],
```

Implement:

```gdscript
func _all_stages_show_three_variants() -> bool:
	for stage in STAGE_NAMES.size():
		var variants := {}
		for index in range(stage, _cells.size(), STAGE_NAMES.size()):
			var visual := farming_system.get_crop_visual(_cells[index])
			if visual and visual.has_method("get_variant_index"):
				variants[visual.call("get_variant_index")] = true
		if variants.size() != 3:
			return false
	return true
```

Adjust camera focus and orthographic size only enough to keep all 12 plots, labels, and panels inside the 1600×1000 capture.

- [ ] **Step 4: Run and capture the verifier**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/test_farming_visual_scene.gd
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/capture_farming_visual.gd
```

Expected: scene test passes and the capture script prints the PNG path.

- [ ] **Step 5: Inspect the screenshot against the visual acceptance checklist**

Verify:

- twelve clusters fit the matching grid cells and touch the ground;
- all four stages are immediately recognizable;
- each stage visibly contains three variations;
- no magenta fringe or square backdrop is present;
- front/back layers do not flicker or sort incorrectly;
- palette, upper-left lighting, and brushwork fit the map and tree art;
- stage 3 is natural straw/ochre rather than saturated yellow.

If one criterion fails, change one prompt/art parameter or one sprite placement parameter, regenerate only the affected asset, and repeat the capture.

- [ ] **Step 6: Commit the verifier**

```bash
git add tests/visual/farming_system_verification.gd tests/test_farming_visual_scene.gd tests/capture_farming_visual.gd
git commit -m "test: showcase painted crop variants"
```

---

### Task 5: Run final parsing, regression, and runtime verification

**Files:**
- Verify: all files changed in Tasks 1–4.

**Interfaces:**
- Consumes: Completed painted crop visual pipeline.
- Produces: Fresh evidence for editor parsing, farming behavior, grid integration, visual scene contracts, runtime startup, formatting, and repository state.

- [ ] **Step 1: Run a full editor parse**

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --editor --path /Users/huanggui/UnrealEngine/villa --quit
```

Expected: exit code 0 with no GDScript parse errors or missing resources.

- [ ] **Step 2: Run targeted automated suites**

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/run_farming_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/run_grid_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/test_player_grid_binding.gd
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/test_farming_visual_scene.gd
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/test_grid_visual_scene.gd
```

Expected: every command exits 0 and prints its PASS summary.

- [ ] **Step 3: Run the verifier and main scene**

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  res://tests/visual/farming_system_verification.tscn --quit-after 3
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 4
```

Expected: both commands exit 0 without runtime errors.

- [ ] **Step 4: Check the diff and repository state**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; no temporary chroma-key sources or contact sheets are staged.

- [ ] **Step 5: Commit any final verification-only corrections**

If verification required a code, test, scene, or final artwork correction:

```bash
git add <only-the-corrected-project-files>
git commit -m "fix: polish painted crop visual integration"
```

If no project files changed after the previous commits, do not create an empty commit.
