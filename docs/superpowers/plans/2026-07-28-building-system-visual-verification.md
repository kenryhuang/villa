# BuildingSystem Visual Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement detailed-design section 1.4 as a footprint-safe BuildingSystem with nine hand-painted 2.5D building scenes and an interactive standalone visual verifier.

**Architecture:** Trusted GameData dictionaries are adapted into typed BuildingData resources. BuildingSystem owns preview and atomic grid/economy orchestration, while BuildingInstance owns an individual building’s painted layers, collision, interaction, camera occlusion, and exact previous-cell records. Each authored scene is a thin BuildingInstance root keyed by building ID, so the shared runtime component builds a consistent node contract.

**Tech Stack:** Godot 4.7.1, GDScript, Sprite3D, StaticBody3D, Area3D, PNG alpha assets, built-in image generation with chroma-key removal, existing script-based test harness.

## Global Constraints

- Implement all nine GameData buildings and keep their IDs and costs unchanged.
- Keep one fixed visual orientation per building.
- Match the existing hand-painted semi-realistic terrain, tree, and crop style with upper-left lighting.
- Preserve BuildUI’s building-ID entry point; do not trust UI-provided costs or scene paths.
- Only WASTELAND and FARMLAND cells may be built on.
- Placement failures must not spend resources or leave partial BUILDING cells.
- Removal restores each occupied cell’s recorded previous state and does not refund resources.
- Building collision uses layers `16 | 64`, interaction uses `64 | 256`, and camera occlusion uses layer `32`.
- Do not implement building gameplay effects, rotation, interiors, upgrades, movement, refunds, or construction animation.

---

### Task 1: Add typed BuildingData and the nine-building catalog adapter

**Files:**
- Create: `scripts/data/building_data.gd`
- Create: `tests/test_building_data.gd`
- Create: `tests/run_building_system_tests.gd`

**Interfaces:**
- Consumes: `GameData.get_building(id: String) -> Dictionary`.
- Produces: `BuildingData.from_dictionary(source: Dictionary) -> BuildingData`, `BuildingData.is_valid() -> bool`, and trusted scene/visual metadata for all nine IDs.

- [ ] **Step 1: Write the failing BuildingData test**

Create `tests/test_building_data.gd` with checks for all nine IDs, dictionary-to-resource field mapping, deep-copied costs, exact footprints, scene paths, visual sizes, and invalid empty dictionaries.

Core assertions:

```gdscript
extends RefCounted

const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const IDS := ["barn", "greenhouse", "windmill", "chicken_coop", "beehive", "well", "workbench", "lamp", "fence"]


func run(assertions: TestAssert) -> void:
	for id in IDS:
		var source: Dictionary = GameData.get_building(id)
		var data = BuildingDataScript.from_dictionary(source)
		assertions.truthy(data.is_valid(), "%s converts to valid BuildingData" % id)
		assertions.equal(data.building_id, id, "%s preserves id" % id)
		assertions.equal(data.cost, source.cost, "%s preserves trusted cost" % id)
		assertions.truthy(ResourceLoader.exists(data.scene_path), "%s scene path exists" % id)
	var barn = BuildingDataScript.from_dictionary(GameData.get_building("barn"))
	assertions.equal(barn.footprint, Vector2i(2, 2), "barn footprint is 2x2")
	var empty = BuildingDataScript.from_dictionary({})
	assertions.equal(empty.is_valid(), false, "empty dictionary is invalid")
```

Create `tests/run_building_system_tests.gd` as a SceneTree runner using `tests/test_assert.gd`.

- [ ] **Step 2: Run RED**

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa \
  --script res://tests/run_building_system_tests.gd
```

Expected: parse/preload failure because `building_data.gd` does not exist.

- [ ] **Step 3: Implement BuildingData**

Create a Resource with the exact fields from the specification and these trusted maps:

```gdscript
const SCENE_PATHS := {
	"barn": "res://scenes/buildings/barn.tscn",
	"greenhouse": "res://scenes/buildings/greenhouse.tscn",
	"windmill": "res://scenes/buildings/windmill.tscn",
	"chicken_coop": "res://scenes/buildings/chicken_coop.tscn",
	"beehive": "res://scenes/buildings/beehive.tscn",
	"well": "res://scenes/buildings/well.tscn",
	"workbench": "res://scenes/buildings/workbench.tscn",
	"lamp": "res://scenes/buildings/lamp.tscn",
	"fence": "res://scenes/buildings/fence.tscn",
}

const VISUAL_SIZES := {
	"barn": Vector2(2.3, 2.2),
	"greenhouse": Vector2(3.2, 2.2),
	"windmill": Vector2(2.2, 3.4),
	"chicken_coop": Vector2(2.1, 1.8),
	"beehive": Vector2(0.9, 1.15),
	"well": Vector2(1.15, 1.35),
	"workbench": Vector2(1.1, 0.9),
	"lamp": Vector2(0.65, 1.8),
	"fence": Vector2(1.05, 0.85),
}
```

`from_dictionary()` maps only trusted fields, duplicates `cost`, and looks up scene/visual metadata by ID. `is_valid()` requires non-empty ID/name/scene, positive footprint and visual dimensions, and an existing scene path.

- [ ] **Step 4: Add minimal authored scene roots**

Create the nine scene files as `Node3D` roots with `authored_building_id` metadata temporarily. These roots become BuildingInstance scenes in Task 2, but their existence lets BuildingData validate now.

- [ ] **Step 5: Run GREEN and commit**

Expected: BuildingData checks pass with all nine resources.

```bash
git add scripts/data/building_data.gd scenes/buildings tests/test_building_data.gd tests/run_building_system_tests.gd
git commit -m "feat: add typed building data catalog"
```

---

### Task 2: Implement BuildingInstance scene contract

**Files:**
- Create: `scripts/buildings/building_instance.gd`
- Modify: `scenes/buildings/*.tscn`
- Create: `tests/test_building_instance.gd`
- Modify: `tests/run_building_system_tests.gd`

**Interfaces:**
- Consumes: `BuildingData`.
- Produces: `configure(data, gx, gz, cells)`, `set_preview_mode(value)`, `set_preview_valid(value)`, `set_camera_occluded(value)`, `get_interaction_area()`, `interact(player)`, and `to_dict()`.

- [ ] **Step 1: Write failing instance-contract tests**

For every scene, instantiate it, configure it, add it to the SceneTree, and assert:

```gdscript
assertions.truthy(instance is BuildingInstance, "%s root is BuildingInstance" % id)
assertions.truthy(instance.has_node("VisualRoot/BackLayer"), "%s has back layer" % id)
assertions.truthy(instance.has_node("VisualRoot/FrontLayer"), "%s has front layer" % id)
assertions.equal(instance.get_node("Collision").collision_layer, 16 | 64, "%s collision layers" % id)
assertions.equal(instance.get_node("InteractionArea").collision_layer, 64 | 256, "%s interaction layers" % id)
assertions.equal(instance.get_node("CameraOccluder").collision_layer, 32, "%s occluder layer" % id)
assertions.equal(instance.to_dict().building_id, id, "%s serializes id" % id)
```

Also test opacity stepping and preview mode disabling all three physics nodes.

- [ ] **Step 2: Run RED**

Expected: scenes are plain Node3D roots and do not implement the contract.

- [ ] **Step 3: Implement BuildingInstance**

The shared script dynamically ensures this tree in `_ready()`:

```text
VisualRoot
├── BackLayer (Sprite3D)
└── FrontLayer (Sprite3D)
Collision (StaticBody3D)
└── CollisionShape3D
InteractionArea (Area3D)
└── CollisionShape3D
CameraOccluder (Area3D)
└── CollisionShape3D
```

It loads:

```gdscript
"res://assets/buildings/painted/%s/%s_back.png" % [building_id, building_id]
"res://assets/buildings/painted/%s/%s_front.png" % [building_id, building_id]
```

When images are not yet present, create a two-mesh stylized fallback under `VisualRoot`; Task 4 replaces it as normal output. Configure Sprite3D Billboard, opaque prepass, no shadow, pixel size from `visual_height`, back tint, front offset, and root baseline. Configure footprint-sized collision/areas. Add root to `building_instance`.

Preview mode disables collision/monitoring/occlusion and applies green/red alpha to every GeometryInstance3D under VisualRoot. Normal camera occlusion lerps alpha to `0.3`.

- [ ] **Step 4: Convert the nine authored roots**

Each scene becomes:

```text
[ext_resource path="res://scripts/buildings/building_instance.gd" type="Script" id="1"]
[node name="<Name>" type="Node3D"]
script = ExtResource("1")
authored_building_id = "<id>"
```

- [ ] **Step 5: Run GREEN and commit**

```bash
git add scripts/buildings/building_instance.gd scenes/buildings tests/test_building_instance.gd tests/run_building_system_tests.gd
git commit -m "feat: add interactive building instances"
```

---

### Task 3: Replace the placeholder BuildingSystem with atomic placement

**Files:**
- Replace: `scripts/systems/building_system.gd`
- Create: `scenes/systems/building_system.tscn`
- Create: `tests/test_building_system_complete.gd`
- Modify: `tests/run_building_system_tests.gd`
- Modify: `scripts/main.gd`

**Interfaces:**
- Consumes: GridSystem, EconomySystem-compatible resource methods, BuildingData, BuildingInstance.
- Produces: every BuildingSystem interface and signal defined in the approved specification.

- [ ] **Step 1: Write failing lifecycle tests**

Use real GridSystem cells without terrain configuration and an EconomyDouble:

```gdscript
class EconomyDouble:
	var available := true
	var spend_calls := 0
	func has_resources(_cost: Dictionary) -> bool:
		return available
	func spend_resources(_cost: Dictionary) -> bool:
		if not available:
			return false
		spend_calls += 1
		return true
```

Test mixed 2×2 WASTELAND/FARMLAND placement, occupied/out-of-bounds rejection, failed spend rollback, exact previous-state restoration, typed return, query by effect, preview marker count, and green/red preview state.

- [ ] **Step 2: Run RED**

Expected: current ID/bool/index APIs fail the typed lifecycle contract.

- [ ] **Step 3: Implement atomic lifecycle**

Replace the file with the approved interface. Use:

```gdscript
func _resolve_data(building: Variant) -> BuildingData:
	if building is BuildingData:
		return building
	if building is String:
		return BuildingData.from_dictionary(GameData.get_building(building))
	return null
```

`can_place()` validates every cell and resource before mutation. `place_building()` instantiates first, snapshots states, applies BUILDING, spends, rolls back on either failure, configures/positions/tracks on success, emits signals, then exits preview. Position X/Z is the average of the first and last footprint cell centers; Y is the average cached terrain height.

`remove_building()` restores only cells still in BUILDING state. `clear_buildings()` iterates a duplicate tracking array.

Preview instantiates a configured BuildingInstance under VisualProxy, calls `set_preview_mode(true)`, reuses one marker per footprint cell, and records `preview_grid` plus `preview_can_place`.

- [ ] **Step 4: Add the reusable BuildingSystem scene**

Create the exact scene tree from the specification. `_ready()` resolves `BuildingPreview/VisualProxy`, `BuildingPreview/FootprintMarkers`, and default `BuildingInstances`.

- [ ] **Step 5: Update main integration**

Preload and instantiate `building_system.tscn`, pass `buildings_container` as the third configure argument, and replace private-field access with:

```gdscript
building_system.place_selected_building(grid_pos.x, grid_pos.y)
```

Mouse motion while building calls `update_preview_position(hit_point.x, hit_point.z)`.

- [ ] **Step 6: Run building, grid, farming, and player-binding tests**

Expected: all commands exit zero.

- [ ] **Step 7: Commit**

```bash
git add scripts/systems/building_system.gd scenes/systems/building_system.tscn scripts/main.gd tests
git commit -m "feat: implement atomic building placement"
```

---

### Task 4: Generate and validate eighteen painted building layers

**Files:**
- Create: `assets/buildings/painted/<id>/<id>_{back,front}.png`
- Create: `tests/test_building_art_assets.gd`
- Modify: `tests/run_building_system_tests.gd`

**Interfaces:**
- Consumes: existing tree and painted crop images as style-only references; image generation built-in mode; chroma-removal helper.
- Produces: eighteen 1024×1024 transparent PNGs with common root baselines.

- [ ] **Step 1: Write the failing asset test**

For all nine IDs and both layers, assert resource existence, `Texture2D`, exact 1024 square size, alpha detection, and transparent corner.

- [ ] **Step 2: Run RED**

Expected: eighteen missing-resource failures.

- [ ] **Step 3: Generate one 2-panel sheet per building**

Use built-in image generation with `tree-oak-large.png`, `tree-yellow.png`, and a mature painted grain image as style-only references. Generate a wide 2:1 sheet on uniform `#ff00ff`:

- left panel: complete back/body layer with contact shadow;
- right panel: matching foreground detail layer without cast shadow;
- identical scale, three-quarter isometric angle, and root baseline;
- no divider, text, watermark, square terrain tile, characters, sky, or scenery.

Exact subject briefs:

```text
barn: ochre-red timber barn, stone foundation, mossy dark shingle roof
greenhouse: warm wooden frame, opaque celadon painted glass highlights, visible leafy silhouettes
windmill: pale stone tower, dark wood cap, large static timber sails
chicken_coop: warm plank coop, small red-brown roof, ramp and short foreground fence
beehive: crafted wood hive boxes, honey-gold accents, tiny foreground wildflowers
well: circular natural-stone well, aged timber frame, small weathered tile roof
workbench: thick timber bench, hand tools, stone feet, wood shavings
lamp: dark wrought support, warm amber lantern, small mossy stone footing
fence: irregular aged timber rails, moss and a small foreground vine
```

- [ ] **Step 4: Remove chroma and split**

Create an owned temporary directory with `mktemp -d /tmp/villa-building-imagegen.XXXXXX`. For each sheet:

```bash
python /Users/huanggui/.codex/skills/.system/imagegen/scripts/remove_chroma_key.py \
  --input /tmp/villa-building-imagegen.<suffix>/<id>_source.png \
  --out /tmp/villa-building-imagegen.<suffix>/<id>_alpha.png \
  --auto-key border --soft-matte \
  --transparent-threshold 12 --opaque-threshold 220 \
  --despill --edge-contract 2

ffmpeg -loglevel error -y -i /tmp/villa-building-imagegen.<suffix>/<id>_alpha.png \
  -vf "crop=iw/2:ih:0:0,scale=1024:1024:force_original_aspect_ratio=decrease:flags=lanczos,pad=1024:1024:(ow-iw)/2:(oh-ih)/2:color=0x00000000" \
  assets/buildings/painted/<id>/<id>_back.png

ffmpeg -loglevel error -y -i /tmp/villa-building-imagegen.<suffix>/<id>_alpha.png \
  -vf "crop=iw/2:ih:iw/2:0,scale=1024:1024:force_original_aspect_ratio=decrease:flags=lanczos,pad=1024:1024:(ow-iw)/2:(oh-ih)/2:color=0x00000000" \
  assets/buildings/painted/<id>/<id>_front.png
```

After all final assets are copied and inspected, remove only this exact owned temporary directory.

- [ ] **Step 5: Reimport, inspect, and run GREEN**

Reject any layer with key-color fringe, clipped geometry, mismatched scale, duplicated whole building, or incorrect style. Run editor import and the building suite.

- [ ] **Step 6: Commit**

```bash
git add assets/buildings/painted tests/test_building_art_assets.gd tests/run_building_system_tests.gd
git commit -m "art: add painted building collection"
```

---

### Task 5: Complete collision, interaction, and camera occlusion integration

**Files:**
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `scripts/camera/camera_rig.gd`
- Modify: `scripts/actors/player.gd`
- Modify: `tests/test_building_instance.gd`
- Create: `tests/test_building_camera_integration.gd`
- Modify: `tests/run_building_system_tests.gd`

**Interfaces:**
- Consumes: BuildingInstance group and physics node contract.
- Produces: player/NPC blocking, interaction parent lookup, and shared tree/building occlusion.

- [ ] **Step 1: Add failing integration tests**

Assert `CameraRig.apply_occlusion_state()` can fade BuildingInstance nodes, trees remain supported, and player interaction ancestor lookup returns the BuildingInstance from InteractionArea or Collision.

- [ ] **Step 2: Run RED**

Expected: CameraRig only enumerates `tree_instance`, and Player does not walk up from child collider.

- [ ] **Step 3: Generalize occlusion**

Rename local `trees` concepts to `occluders` while preserving the static helper signature compatibility. Gather both groups:

```gdscript
var occluders: Array[Node] = []
occluders.append_array(get_tree().get_nodes_in_group("tree_instance"))
occluders.append_array(get_tree().get_nodes_in_group("building_instance"))
```

Ray hits layer 32 Area3D and walks to the first ancestor implementing `set_camera_occluded()`.

- [ ] **Step 4: Make player interaction resolve ancestors**

Enable `query.collide_with_areas = true`. Add:

```gdscript
static func find_interaction_target(node: Node) -> Node:
	var current := node
	while current:
		if current.has_method("interact") or current.has_method("start_dialogue") or current.has_method("collect"):
			return current
		current = current.get_parent()
	return null
```

Use the returned target for interaction dispatch.

- [ ] **Step 5: Run GREEN and commit**

```bash
git add scripts/buildings/building_instance.gd scripts/camera/camera_rig.gd scripts/actors/player.gd tests
git commit -m "feat: integrate building collision and occlusion"
```

---

### Task 6: Build the standalone interactive visual verifier

**Files:**
- Create: `tests/visual/building_system_verification.tscn`
- Create: `tests/visual/building_system_verification.gd`
- Create: `tests/test_building_visual_scene.gd`
- Create: `tests/capture_building_visual.gd`

**Interfaces:**
- Consumes: real World, GridSystem, BuildingSystem, all nine BuildingData/scene assets.
- Produces: nine-building gallery, interactive preview pad, live verification status, and 1600×1000 capture.

- [ ] **Step 1: Write the failing scene contract**

Assert the scene exists, root script loads, required nodes exist, nine IDs are exposed, all gallery buildings are BuildingInstance, and every status contract can be evaluated after `_ready()`.

- [ ] **Step 2: Run RED**

Expected: missing visual verification scene.

- [ ] **Step 3: Implement verifier**

Use real World/GridSystem/BuildingSystem and a local verification economy with:

```gdscript
var materials_available := true
var spend_calls := 0
func has_resources(_cost: Dictionary) -> bool:
	return materials_available
func spend_resources(_cost: Dictionary) -> bool:
	if not materials_available:
		return false
	spend_calls += 1
	return true
```

Reset initializes the grid, places all nine gallery buildings at fixed non-overlapping coordinates, enters preview for selection 1, and records expected occupied cells. Controls are exactly `1–9`, arrows, `P`/Enter, `X`, `B`, `M`, `R`, Escape.

Status panel checks shared GridSystem, 9/9 scene/model/physics contracts, footprint count, preview validity, resource rejection, and removal restoration. Inspector shows selected ID/name/footprint/cost/grid/can-place.

- [ ] **Step 4: Capture and inspect**

Run the scene contract, headless runtime, and graphical capture. Inspect nine identities, sizes, grounding, alpha edges, front/back sorting, labels, and panel layout.

- [ ] **Step 5: Commit**

```bash
git add tests/visual/building_system_verification.* tests/test_building_visual_scene.gd tests/capture_building_visual.gd
git commit -m "test: add building system visual verification"
```

---

### Task 7: Final regression, merged-main verification, and cleanup

**Files:**
- Verify all files from Tasks 1–6.

**Interfaces:**
- Produces fresh completion evidence and a clean merged main branch.

- [ ] **Step 1: Run editor parse**

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --editor --path /Users/huanggui/UnrealEngine/villa --quit
```

- [ ] **Step 2: Run targeted suites**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_building_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_farming_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_grid_system_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/test_player_grid_binding.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/test_building_visual_scene.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/test_farming_visual_scene.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/test_grid_visual_scene.gd
```

- [ ] **Step 3: Run visual and main scenes**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa res://tests/visual/building_system_verification.tscn --quit-after 3
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 4
```

- [ ] **Step 4: Capture final screenshot and check repository**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/huanggui/UnrealEngine/villa --script res://tests/capture_building_visual.gd
git diff --check
git status --short
```

Expected: all commands exit zero, screenshot is 1600×1000, no temporary image-generation sources are staged, and worktree is clean.

- [ ] **Step 5: Merge the verified feature branch**

Fast-forward merge to main, rerun BuildingSystem, GridSystem, visual contract, and main runtime from the merged root, then remove the owned `.worktrees/building-system-visual` worktree and delete the merged feature branch.
