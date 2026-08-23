# Remaining Crops Two-Stage Painted Visuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the remaining nine legacy crop models with recognizable two-stage hand-painted PNG visuals while preserving all farming behavior.

**Architecture:** Keep the existing `CropSpriteCluster` runtime and four logical growth states, but map each migrated crop to only its stage-0 and stage-3 scenes. Each retained scene owns one front and one back transparent sprite; all intermediate scenes, extra variants, procedural meshes, and now-unused materials are removed in bounded crop batches.

**Tech Stack:** Godot 4.7 GDScript and `.tscn` resources, built-in image generation, PNG alpha normalization, PowerShell, Git.

---

## File Map

- `scripts/main.gd`: owns the runtime list that maps four logical growth states onto two visual scenes.
- `tests/test_multi_crop_art_assets.gd`: enforces exact scene/texture presence, 1024-square size, and real alpha.
- `tests/test_multi_crop_models.gd`: enforces `CropSpriteCluster`, zero procedural meshes, one front/back sprite, and logical-stage mapping.
- `tests/capture_farming_visual.gd`: renders the complete two-stage crop gallery from front and back.
- `assets/crops/apple/`, `assets/crops/peach/`, `assets/crops/lemon/`, `assets/crops/grape/`: fruit-tree and vine assets.
- `assets/crops/blueberry/`, `assets/crops/strawberry/`: berry assets.
- `assets/crops/watermelon/`, `assets/crops/pumpkin/`, `assets/crops/sunflower/`: ground-vine and tall-flower assets.

The existing user-owned untracked `.playwright-cli/` and `output/` directories are never staged.

## Shared Asset Contract

Every migrated crop must end with these exact retained PNG paths:

```text
assets/crops/apple/painted/stage_0/variant_0_front.png
assets/crops/apple/painted/stage_0/variant_0_back.png
assets/crops/apple/painted/stage_3/variant_0_front.png
assets/crops/apple/painted/stage_3/variant_0_back.png
assets/crops/peach/painted/stage_0/variant_0_front.png
assets/crops/peach/painted/stage_0/variant_0_back.png
assets/crops/peach/painted/stage_3/variant_0_front.png
assets/crops/peach/painted/stage_3/variant_0_back.png
assets/crops/lemon/painted/stage_0/variant_0_front.png
assets/crops/lemon/painted/stage_0/variant_0_back.png
assets/crops/lemon/painted/stage_3/variant_0_front.png
assets/crops/lemon/painted/stage_3/variant_0_back.png
assets/crops/grape/painted/stage_0/variant_0_front.png
assets/crops/grape/painted/stage_0/variant_0_back.png
assets/crops/grape/painted/stage_3/variant_0_front.png
assets/crops/grape/painted/stage_3/variant_0_back.png
assets/crops/blueberry/painted/stage_0/variant_0_front.png
assets/crops/blueberry/painted/stage_0/variant_0_back.png
assets/crops/blueberry/painted/stage_3/variant_0_front.png
assets/crops/blueberry/painted/stage_3/variant_0_back.png
assets/crops/strawberry/painted/stage_0/variant_0_front.png
assets/crops/strawberry/painted/stage_0/variant_0_back.png
assets/crops/strawberry/painted/stage_3/variant_0_front.png
assets/crops/strawberry/painted/stage_3/variant_0_back.png
assets/crops/watermelon/painted/stage_0/variant_0_front.png
assets/crops/watermelon/painted/stage_0/variant_0_back.png
assets/crops/watermelon/painted/stage_3/variant_0_front.png
assets/crops/watermelon/painted/stage_3/variant_0_back.png
assets/crops/pumpkin/painted/stage_0/variant_0_front.png
assets/crops/pumpkin/painted/stage_0/variant_0_back.png
assets/crops/pumpkin/painted/stage_3/variant_0_front.png
assets/crops/pumpkin/painted/stage_3/variant_0_back.png
assets/crops/sunflower/painted/stage_0/variant_0_front.png
assets/crops/sunflower/painted/stage_0/variant_0_back.png
assets/crops/sunflower/painted/stage_3/variant_0_front.png
assets/crops/sunflower/painted/stage_3/variant_0_back.png
```

Each crop also retains its named stage-0 and stage-3 scene. This concrete Apple stage-0 scene shows the complete root-only structure; the task tables provide the exact node name, crop path, and height for every other retained scene:

```gdscript
[gd_scene load_steps=2 format=3]

[ext_resource path="res://scripts/visual/crop_sprite_cluster.gd" type="Script" id="1"]

[node name="AppleStage0Seed" type="Node3D"]
script = ExtResource("1")
back_texture_paths = Array[String](["res://assets/crops/apple/painted/stage_0/variant_0_back.png"])
front_texture_paths = Array[String](["res://assets/crops/apple/painted/stage_0/variant_0_front.png"])
canvas_world_height = 0.75
```

Do not retain any `sub_resource`, material reference, or `MeshInstance3D` node in any migrated retained scene.

For every generated image, use built-in image generation and preserve its original at the concrete `output_hint` path returned by that call. Copy only the accepted final into the project. Inspect source outputs before use. If an accepted image is not 1024 square or has a baked neutral checker/white background, normalize it deterministically to a 1024×1024 `Format32bppArgb` PNG, preserving the subject and converting only the neutral background to alpha. Re-run Godot headless editor import after copying.

### Task 1: Fruit Trees and Grape Contract

**Files:**
- Modify: `tests/test_multi_crop_art_assets.gd:10-16`
- Modify: `tests/test_multi_crop_models.gd:6-12`
- Modify: `scripts/main.gd:48`

- [ ] **Step 1: Write the failing two-stage contract**

Use these exact arrays in both crop test files:

```gdscript
const TWO_STAGE_CROP_IDS: Array[String] = [
	"potato", "tomato", "lavender", "rose", "carrot",
	"apple", "peach", "lemon", "grape",
]
const LEGACY_FOUR_STAGE_CROP_IDS: Array[String] = [
	"strawberry", "blueberry",
	"watermelon", "sunflower", "pumpkin",
]
```

Use this exact runtime list in `scripts/main.gd`:

```gdscript
const TWO_STAGE_CROP_IDS: Array[String] = [
	"potato", "tomato", "lavender", "rose", "carrot",
	"apple", "peach", "lemon", "grape",
]
```

- [ ] **Step 2: Run the contract tests and verify RED**

Run:

```powershell
godot_console --headless --path . --script tests/run_multi_crop_art_tests.gd
godot_console --headless --path . --script tests/run_multi_crop_model_tests.gd
```

Expected: both commands exit nonzero. Failures must name extra stage-1/stage-2 scenes or variants and procedural meshes for apple, peach, lemon, and grape.

- [ ] **Step 3: Inspect reference images before generation**

Inspect at original resolution:

```text
assets/crops/grain/painted/stage_0/variant_0_front.png
assets/crops/grain/painted/stage_0/variant_0_back.png
assets/crops/grain/painted/stage_3/variant_0_front.png
assets/crops/grain/painted/stage_3/variant_0_back.png
assets/crops/carrot/painted/stage_3/variant_0_front.png
assets/crops/carrot/painted/stage_3/variant_0_back.png
```

Expected: the references establish painted edges, warm top-left lighting, transparent padding, and front/back camera treatment.

- [ ] **Step 4: Generate the fruit-tree and vine sprites**

Issue one built-in generation call for each row and each view. Append the view clause exactly as shown:

```text
Front clause: front three-quarter view, fruit and primary silhouette facing the camera
Back clause: rear three-quarter view of the same species and growth stage, rear branches and foliage visible, not a mirrored front image
```

Use this shared prompt prefix for all sixteen calls:

```text
Use case: stylized-concept
Asset type: transparent game crop sprite for a Godot farming game
Primary request: create one cohesive hand-painted crop cutout matching the warm, readable painted style of the supplied grain reference
Style/medium: polished hand-painted 2D game sprite, natural botanical structure, moderately saturated color, clean readable silhouette
Composition/framing: centered square composition with generous transparent padding and the plant grounded at the bottom center
Lighting/mood: warm soft daylight from upper left
Constraints: truly transparent background; no checkerboard; no white backdrop; no text; no watermark; no border; no pot; no UI; no cropped leaves or fruit; one coherent plant cluster
```

Use these exact subjects:

| Crop | Stage 0 subject | Stage 3 subject |
|---|---|---|
| apple | a young apple sapling with a thin brown trunk, several fresh green leaves, no flowers and no fruit | a compact mature apple tree with a visible trunk, rounded leafy canopy, and clearly readable red apples |
| peach | a young peach sapling with a thin trunk and narrow lance-shaped leaves, no flowers and no fruit | a compact mature peach tree with a visible trunk, airy narrow-leaf canopy, and clearly readable warm pink-orange peaches |
| lemon | a young lemon sapling with a thin trunk and glossy oval leaves, no flowers and no fruit | a compact mature lemon tree with a visible trunk, glossy deep-green canopy, and clearly readable yellow lemons |
| grape | a young grape vine emerging from soil with a short curling stem, two to four lobed leaves, and one small tendril, no grapes and no support structure | a mature grape vine trained on a simple low wooden support, broad lobed leaves, curling tendrils, and several clearly visible purple grape clusters |

For each crop, generate stage 0 front, stage 0 back, stage 3 front, and stage 3 back by combining the shared prefix, exact subject, and exact view clause.

- [ ] **Step 5: Normalize and install the sixteen accepted PNGs**

Save accepted outputs to the exact `variant_0_front.png` and `variant_0_back.png` paths under stage 0 and stage 3 for apple, peach, lemon, and grape. Verify each with `System.Drawing.Bitmap`:

```powershell
Add-Type -AssemblyName System.Drawing
$targets = @(
  'assets/crops/apple/painted/stage_0/variant_0_front.png',
  'assets/crops/apple/painted/stage_0/variant_0_back.png',
  'assets/crops/apple/painted/stage_3/variant_0_front.png',
  'assets/crops/apple/painted/stage_3/variant_0_back.png',
  'assets/crops/peach/painted/stage_0/variant_0_front.png',
  'assets/crops/peach/painted/stage_0/variant_0_back.png',
  'assets/crops/peach/painted/stage_3/variant_0_front.png',
  'assets/crops/peach/painted/stage_3/variant_0_back.png',
  'assets/crops/lemon/painted/stage_0/variant_0_front.png',
  'assets/crops/lemon/painted/stage_0/variant_0_back.png',
  'assets/crops/lemon/painted/stage_3/variant_0_front.png',
  'assets/crops/lemon/painted/stage_3/variant_0_back.png',
  'assets/crops/grape/painted/stage_0/variant_0_front.png',
  'assets/crops/grape/painted/stage_0/variant_0_back.png',
  'assets/crops/grape/painted/stage_3/variant_0_front.png',
  'assets/crops/grape/painted/stage_3/variant_0_back.png'
)
foreach ($target in $targets) {
  $bitmap = [System.Drawing.Bitmap]::FromFile((Resolve-Path $target))
  try {
    if ($bitmap.Width -ne 1024 -or $bitmap.Height -ne 1024) { throw "$target has wrong dimensions" }
    if (-not $bitmap.PixelFormat.ToString().Contains('Argb')) { throw "$target has no alpha pixel format" }
    if ($bitmap.GetPixel(0, 0).A -ne 0) { throw "$target has an opaque corner" }
    Write-Output "PASS $target"
  } finally {
    $bitmap.Dispose()
  }
}
```

Expected: all sixteen report 1024×1024 ARGB and a transparent corner.

- [ ] **Step 6: Replace retained scenes with pure sprite clusters**

Use these exact node names and heights:

| Crop | Stage 0 node / height | Stage 3 node / height |
|---|---|---|
| apple | `AppleStage0Seed` / `0.75` | `AppleStage3Mature` / `1.50` |
| peach | `PeachStage0Seed` / `0.75` | `PeachStage3Mature` / `1.50` |
| lemon | `LemonStage0Seed` / `0.75` | `LemonStage3Mature` / `1.50` |
| grape | `GrapeStage0Seed` / `0.75` | `GrapeStage3Mature` / `1.15` |

Expected: each scene follows the shared asset contract and has no procedural nodes.

- [ ] **Step 7: Remove bounded legacy assets**

Resolve and print the four exact crop roots first. Under only `assets/crops/apple`, `assets/crops/peach`, `assets/crops/lemon`, and `assets/crops/grape`, remove:

```text
*_stage_1_sprout.tscn
*_stage_2_growing.tscn
materials/*.tres
painted/stage_0/variant_1_*.png and matching .import
painted/stage_0/variant_2_*.png and matching .import
painted/stage_1/variant_0_*.png through variant_2_*.png and matching .import
painted/stage_2/variant_0_*.png through variant_2_*.png and matching .import
painted/stage_3/variant_1_*.png and matching .import
painted/stage_3/variant_2_*.png and matching .import
```

Before deletion, use `rg` to prove no references exist outside the bounded candidate set. Pass a hardcoded explicit path list to `git rm --`; do not use recursive deletion or unresolved globs.

- [ ] **Step 8: Import and verify GREEN**

Run:

```powershell
godot_console --headless --editor --path . --quit
godot_console --headless --path . --script tests/run_multi_crop_art_tests.gd
godot_console --headless --path . --script tests/run_multi_crop_model_tests.gd
```

Expected: editor import exits 0 and both crop suites print `PASS` with zero failed checks.

- [ ] **Step 9: Commit the fruit-tree and vine batch**

```powershell
git diff --check
git add -A -- scripts/main.gd tests/test_multi_crop_art_assets.gd tests/test_multi_crop_models.gd assets/crops/apple assets/crops/peach assets/crops/lemon assets/crops/grape
git commit -m "feat: repaint fruit trees and grape as two-stage crops"
```

### Task 2: Blueberry and Strawberry

**Files:**
- Modify: `tests/test_multi_crop_art_assets.gd:10-16`
- Modify: `tests/test_multi_crop_models.gd:6-12`
- Modify: `scripts/main.gd:48`
- Replace/delete within: `assets/crops/blueberry/`
- Replace/delete within: `assets/crops/strawberry/`

- [ ] **Step 1: Extend the failing contract to both berries**

Use this exact final arrangement in both test files and the first array in `scripts/main.gd`:

```gdscript
const TWO_STAGE_CROP_IDS: Array[String] = [
	"potato", "tomato", "lavender", "rose", "carrot",
	"apple", "peach", "lemon", "grape",
	"blueberry", "strawberry",
]
```

The test-only legacy list becomes:

```gdscript
const LEGACY_FOUR_STAGE_CROP_IDS: Array[String] = [
	"watermelon", "sunflower", "pumpkin",
]
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
godot_console --headless --path . --script tests/run_multi_crop_art_tests.gd
godot_console --headless --path . --script tests/run_multi_crop_model_tests.gd
```

Expected: failures name blueberry and strawberry legacy stages, variants, and procedural meshes; the Task 1 crops remain green.

- [ ] **Step 3: Generate eight berry sprites**

Issue one built-in generation call per stage and view. Use this exact shared prompt prefix:

```text
Use case: stylized-concept
Asset type: transparent game crop sprite for a Godot farming game
Primary request: create one cohesive hand-painted crop cutout matching the warm, readable painted style of the supplied grain reference
Style/medium: polished hand-painted 2D game sprite, natural botanical structure, moderately saturated color, clean readable silhouette
Composition/framing: centered square composition with generous transparent padding and the plant grounded at the bottom center
Lighting/mood: warm soft daylight from upper left
Constraints: truly transparent background; no checkerboard; no white backdrop; no text; no watermark; no border; no pot; no UI; no cropped leaves or fruit; one coherent plant cluster
```

Append exactly one of these view clauses:

```text
Front clause: front three-quarter view, fruit and primary silhouette facing the camera
Back clause: rear three-quarter view of the same species and growth stage, rear branches and foliage visible, not a mirrored front image
```

Use these exact subjects:

| Crop | Stage 0 subject | Stage 3 subject |
|---|---|---|
| blueberry | a small scattered cluster of tiny matte tan blueberry seeds, clearly seeds rather than berries, no sprout and no leaves | a compact mature blueberry bush with branching stems, oval green leaves, and many clearly visible dusty-blue berries |
| strawberry | a small scattered cluster of tiny pale golden strawberry seeds, clearly loose seeds rather than a fruit surface, no sprout and no leaves | a low mature strawberry plant with trifoliate serrated leaves, white blossoms, runners, and several clearly visible red strawberries near the soil |

Generate stage 0 front/back and stage 3 front/back separately for both crops.

- [ ] **Step 4: Install images and replace retained scenes**

Use exact node names and heights:

| Crop | Stage 0 node / height | Stage 3 node / height |
|---|---|---|
| blueberry | `BlueberryStage0Seed` / `0.45` | `BlueberryStage3Mature` / `1.05` |
| strawberry | `StrawberryStage0Seed` / `0.45` | `StrawberryStage3Mature` / `1.00` |

Normalize all eight PNGs to the shared contract and replace both retained scenes with root-only `CropSpriteCluster` scenes.

- [ ] **Step 5: Remove berry legacy assets safely**

Resolve and print exactly `assets/crops/blueberry` and `assets/crops/strawberry`. Under only those roots, remove both stage-1 and stage-2 scenes, all `.tres` files in each crop's `materials` directory, stage-0 and stage-3 variants 1 and 2 with matching `.import` files, and every stage-1/stage-2 variant 0 through 2 with matching `.import` files. Before deletion, use `rg` to prove no references exist outside the bounded candidate set. Pass a hardcoded explicit path list to `git rm --`; do not use recursive deletion or unresolved globs.

- [ ] **Step 6: Import, verify, and commit**

```powershell
godot_console --headless --editor --path . --quit
godot_console --headless --path . --script tests/run_multi_crop_art_tests.gd
godot_console --headless --path . --script tests/run_multi_crop_model_tests.gd
git diff --check
git add -A -- scripts/main.gd tests/test_multi_crop_art_assets.gd tests/test_multi_crop_models.gd assets/crops/blueberry assets/crops/strawberry
git commit -m "feat: repaint berries as two-stage crops"
```

Expected: both suites pass before the commit succeeds.

### Task 3: Watermelon, Pumpkin, and Sunflower

**Files:**
- Modify: `tests/test_multi_crop_art_assets.gd:10-16`
- Modify: `tests/test_multi_crop_models.gd:6-12`
- Modify: `scripts/main.gd:48`
- Replace/delete within: `assets/crops/watermelon/`
- Replace/delete within: `assets/crops/pumpkin/`
- Replace/delete within: `assets/crops/sunflower/`

- [ ] **Step 1: Move the final crops into the two-stage contract**

Use this exact final array in both test files and `scripts/main.gd`:

```gdscript
const TWO_STAGE_CROP_IDS: Array[String] = [
	"potato", "tomato", "lavender", "rose", "carrot",
	"apple", "peach", "lemon", "grape",
	"blueberry", "strawberry",
	"watermelon", "pumpkin", "sunflower",
]
```

Use an empty test-only legacy list:

```gdscript
const LEGACY_FOUR_STAGE_CROP_IDS: Array[String] = []
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
godot_console --headless --path . --script tests/run_multi_crop_art_tests.gd
godot_console --headless --path . --script tests/run_multi_crop_model_tests.gd
```

Expected: failures name only watermelon, pumpkin, and sunflower legacy structures; previously migrated crops remain green.

- [ ] **Step 3: Generate twelve sprites**

Issue one built-in generation call per stage and view. Use this exact shared prompt prefix:

```text
Use case: stylized-concept
Asset type: transparent game crop sprite for a Godot farming game
Primary request: create one cohesive hand-painted crop cutout matching the warm, readable painted style of the supplied grain reference
Style/medium: polished hand-painted 2D game sprite, natural botanical structure, moderately saturated color, clean readable silhouette
Composition/framing: centered square composition with generous transparent padding and the plant grounded at the bottom center
Lighting/mood: warm soft daylight from upper left
Constraints: truly transparent background; no checkerboard; no white backdrop; no text; no watermark; no border; no pot; no UI; no cropped leaves or fruit; one coherent plant cluster
```

Append exactly one of these view clauses:

```text
Front clause: front three-quarter view, fruit and primary silhouette facing the camera
Back clause: rear three-quarter view of the same species and growth stage, rear branches and foliage visible, not a mirrored front image
```

Use these exact subjects:

| Crop | Stage 0 subject | Stage 3 subject |
|---|---|---|
| watermelon | a small scattered cluster of flat oval dark brown-black watermelon seeds with subtle highlights, no sprout and no leaves | a mature ground-running watermelon vine with broad lobed leaves, curling tendrils, yellow flowers, and two or three clearly visible striped green watermelons resting on soil |
| pumpkin | a small scattered cluster of flat oval pale cream pumpkin seeds with natural ridges, no sprout and no leaves | a mature ground-running pumpkin vine with large rough leaves, curling tendrils, yellow blossoms, and two or three clearly visible orange pumpkins resting on soil |
| sunflower | a small scattered cluster of elongated charcoal-and-cream striped sunflower seeds, no sprout and no leaves | a compact group of three mature sunflower stalks with broad leaves and large golden flower heads with dark brown centers, grounded in a small soil base |

Generate stage 0 front/back and stage 3 front/back separately for all three crops.

- [ ] **Step 4: Install images and replace retained scenes**

Use exact node names and heights:

| Crop | Stage 0 node / height | Stage 3 node / height |
|---|---|---|
| watermelon | `WatermelonStage0Seed` / `0.45` | `WatermelonStage3Mature` / `1.00` |
| pumpkin | `PumpkinStage0Seed` / `0.45` | `PumpkinStage3Mature` / `1.00` |
| sunflower | `SunflowerStage0Seed` / `0.45` | `SunflowerStage3Mature` / `1.15` |

Normalize all twelve PNGs and replace retained scenes with the shared root-only structure.

- [ ] **Step 5: Remove the last legacy assets safely**

Resolve and print exactly `assets/crops/watermelon`, `assets/crops/pumpkin`, and `assets/crops/sunflower`. Under only those roots, remove all three stage-1/stage-2 scenes, all `.tres` files in the three `materials` directories, stage-0 and stage-3 variants 1 and 2 with matching `.import` files, and every stage-1/stage-2 variant 0 through 2 with matching `.import` files. Before deletion, use `rg` to prove no references exist outside the bounded candidate set. Pass a hardcoded explicit path list to `git rm --`; do not use recursive deletion or unresolved globs.

- [ ] **Step 6: Import, verify, and commit**

```powershell
godot_console --headless --editor --path . --quit
godot_console --headless --path . --script tests/run_multi_crop_art_tests.gd
godot_console --headless --path . --script tests/run_multi_crop_model_tests.gd
git diff --check
git add -A -- scripts/main.gd tests/test_multi_crop_art_assets.gd tests/test_multi_crop_models.gd assets/crops/watermelon assets/crops/pumpkin assets/crops/sunflower
git commit -m "feat: repaint vines and sunflower as two-stage crops"
```

Expected: both crop suites pass with no legacy crop failures.

### Task 4: Complete Two-Stage Gallery

**Files:**
- Modify: `tests/capture_farming_visual.gd`
- Output only, do not stage: `output/farming/two_stage_front.png`
- Output only, do not stage: `output/farming/two_stage_back.png`

- [ ] **Step 1: Extend the gallery crop registry**

Use these exact arrays:

```gdscript
const CROPS := [
	"tomato", "potato", "rose", "lavender", "carrot", "apple", "peach",
	"lemon", "grape", "blueberry", "strawberry", "watermelon", "pumpkin", "sunflower",
]
const CROP_NAMES := [
	"番茄", "土豆", "玫瑰", "薰衣草", "胡萝卜", "苹果", "桃",
	"柠檬", "葡萄", "蓝莓", "草莓", "西瓜", "南瓜", "向日葵",
]
```

- [ ] **Step 2: Lay out two seven-crop bands**

Replace the single-row positioning with:

```gdscript
const GALLERY_COLUMNS := 7

var band := crop_index / GALLERY_COLUMNS
var column := crop_index % GALLERY_COLUMNS
var stage := 0 if stage_index == 0 else 3
var position := Vector3(
	-9.0 + column * 3.0,
	0.0,
	4.4 - band * 5.8 - stage_index * 2.25
)
```

Set `root.size = Vector2i(1920, 1080)`, camera size to `12.5`, front camera position to `Vector3(0.0, 9.0, 15.5)`, and back camera position to `Vector3(0.0, 9.0, -15.5)`. Keep `look_at(Vector3.ZERO)`.

- [ ] **Step 3: Capture and inspect both views**

Run:

```powershell
godot_console --path . --script tests/capture_farming_visual.gd
```

Expected: exit 0 and two 1920×1080 captures. Inspect both at original resolution. Every crop must be fully visible, correctly labeled, recognizable at gallery scale, and visually consistent; no checkerboard or opaque rectangle may appear.

- [ ] **Step 4: Tune only category heights if needed**

If a crop is materially too small, too tall, or clipped, adjust only its retained scene's `canvas_world_height` within the approved range. Re-import and recapture after each adjustment. Do not redraw an asset solely for a scale issue.

- [ ] **Step 5: Verify and commit the gallery**

```powershell
godot_console --headless --path . --script tests/run_multi_crop_art_tests.gd
godot_console --headless --path . --script tests/run_multi_crop_model_tests.gd
git diff --check
git add -- tests/capture_farming_visual.gd
git add -- assets/crops/apple/apple_stage_0_seed.tscn assets/crops/apple/apple_stage_3_mature.tscn assets/crops/peach/peach_stage_0_seed.tscn assets/crops/peach/peach_stage_3_mature.tscn assets/crops/lemon/lemon_stage_0_seed.tscn assets/crops/lemon/lemon_stage_3_mature.tscn assets/crops/grape/grape_stage_0_seed.tscn assets/crops/grape/grape_stage_3_mature.tscn assets/crops/blueberry/blueberry_stage_0_seed.tscn assets/crops/blueberry/blueberry_stage_3_mature.tscn assets/crops/strawberry/strawberry_stage_0_seed.tscn assets/crops/strawberry/strawberry_stage_3_mature.tscn assets/crops/watermelon/watermelon_stage_0_seed.tscn assets/crops/watermelon/watermelon_stage_3_mature.tscn assets/crops/pumpkin/pumpkin_stage_0_seed.tscn assets/crops/pumpkin/pumpkin_stage_3_mature.tscn assets/crops/sunflower/sunflower_stage_0_seed.tscn assets/crops/sunflower/sunflower_stage_3_mature.tscn
git commit -m "test: expand the two-stage crop gallery"
```

Only stage files actually tuned in Step 4 will be staged; `output/` remains untracked.

### Task 5: Final Regression Verification

**Files:**
- Verify: all changed source, test, scene, and PNG files

- [ ] **Step 1: Run the focused verification suites in parallel**

Run:

```powershell
godot_console --headless --path . --script tests/run_multi_crop_art_tests.gd
godot_console --headless --path . --script tests/run_multi_crop_model_tests.gd
godot_console --headless --path . --script tests/run_action_mode_debug_day_regression_tests.gd
godot_console --headless --path . --script tests/test_runtime_ui_scenes.gd
```

Expected: all four commands exit 0 and print `PASS`. The action-mode runner may emit its known exit-time ObjectDB/resource warnings after reporting all checks passed.

- [ ] **Step 2: Run the main gameplay integration suite**

```powershell
godot_console --headless --path . --script tests/run_main_gameplay_integration_tests.gd
```

Expected baseline: exactly two failures out of the full check count:

```text
auto seed map discovers and maps the seed in inventory: expected grain_seed, got
stored crop initially enables contract delivery: expected true
```

Any additional failure is a regression and must be fixed before handoff.

- [ ] **Step 3: Audit deleted assets and remaining references**

Run:

```powershell
rg -n "stage_[12]|variant_[12]|materials/" assets/crops/apple assets/crops/peach assets/crops/lemon assets/crops/grape assets/crops/blueberry assets/crops/strawberry assets/crops/watermelon assets/crops/pumpkin assets/crops/sunflower scripts tests
git diff --check
git status --short
git log --oneline -8
```

Expected: no migrated scene/code references to deleted stage-1/stage-2, variant-1/variant-2, or crop material resources. Git shows no tracked modifications; only the preserved user-owned `.playwright-cli/` and `output/` paths may remain untracked.

- [ ] **Step 4: Report generated asset provenance**

In the handoff, report:

- built-in image generation mode was used;
- the complete prompt set in Tasks 1 through 3;
- the final project paths for all 36 PNGs;
- the nine deleted legacy asset groups are recoverable from Git history;
- focused verification results and the exact two baseline integration failures.
