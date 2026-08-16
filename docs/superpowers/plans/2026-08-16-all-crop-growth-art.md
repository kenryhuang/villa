# All-Crop Growth Art Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the 14 non-grain crops the same four-stage, three-variant, front/back hand-painted presentation and low-poly fallback contract as grain.

**Architecture:** Existing `CropSpriteCluster` remains the shared renderer. Every crop stage is a stable scene resource that lists three paired textures, a stage-specific world height, and crop-shaped fallback meshes. Art is produced and reviewed by seven visual archetypes before expanding to related crops; automated contracts verify every final path, alpha image, pairing, fallback, and deterministic variant.

**Tech Stack:** Godot 4.7.1, GDScript, `Sprite3D`, 1024x1024 RGBA PNG, built-in image generation, chroma-key cleanup, existing headless visual capture scripts.

**Prerequisite:** Complete `2026-08-16-seed-crop-economy-ui.md`. Before any generation or edit-generation call, load and follow the `imagegen` skill.

**Design source:** `docs/superpowers/specs/2026-08-16-seed-crop-lifecycle-design.md`, sections 10.3, 11, 14.6, and 15.

## Global Constraints

- Do not regenerate or restyle the approved grain assets.
- Deliver exactly 336 new PNGs and 56 new stage scenes for the other 14 crops.
- Each final PNG is 1024x1024 RGBA with transparent corners, at least 6% visual padding, and the shared ground baseline.
- `back` and `front` are depth layers in the same camera view, not opposite views.
- All four stages of one cell use the same deterministic variant index.
- Every scene retains a visible, crop-specific low-poly fallback when either selected texture is missing.
- Do not add separate dormant or withered texture groups.

## Asset Matrix

Prototype crops, in approval order:

```text
carrot, tomato, pumpkin, strawberry, sunflower, apple, grape
```

Expansion crops after their prototype passes:

```text
potato<-carrot, watermelon<-pumpkin, blueberry<-strawberry,
lavender<-sunflower, rose<-sunflower, peach<-apple, lemon<-apple
```

World heights by archetype and stage 0-3:

```text
root:        0.35, 0.45, 0.65, 0.80
tomato:      0.40, 0.52, 0.85, 1.05
ground_vine: 0.35, 0.42, 0.55, 0.65
bush:        0.38, 0.52, 0.75, 0.95
flower:      0.40, 0.52, 0.85, 1.15
tree:        0.55, 0.82, 1.20, 1.55
grape:       0.45, 0.68, 0.95, 1.25
```

Stage prompt matrix; use these phrases verbatim for `{STAGE_TEXT}` in the generation prompts:

| Crop | Stage 0 | Stage 1 | Stage 2 | Stage 3 |
| --- | --- | --- | --- | --- |
| carrot | tiny seeds or a breaking-soil point | two or three fine seed leaves | full feathery leaf fan | denser leaf fan with a small orange root shoulder above soil |
| potato | seed potato close to the soil | short stem with young leaves | lush green leaves over a slight soil ridge | heavier canopy with a subtle mature tuber cue at the ridge edge |
| tomato | seeds with a few small soil crumbs | cotyledon seedling | branching green plant with yellow flowers | red tomatoes distributed through front and back foliage |
| strawberry | tiny seeds or a breaking-soil bud | three-leaf seedling | low leafy crown with white flowers | red strawberries hanging at the crown edge |
| blueberry | tiny seeds or a breaking-soil bud | slender branching seedling | rounded shrub with flowers | clear blue berry clusters around the crown edge |
| watermelon | flat seeds | two-leaf crawling seedling | spreading vines with yellow flowers | striped watermelons resting near the soil among vines |
| sunflower | sunflower seeds | broad-leaf seedling | tall stem with a closed flower bud | open yellow flower disk as the primary silhouette |
| lavender | tiny seeds | short gray-green seedling | many-branched gray-green foliage | purple flower spikes clearly above the foliage |
| pumpkin | flat seeds | broad-leaf seedling | thick vines, broad leaves, and yellow flowers | orange pumpkins resting between vines |
| rose | seeds or a breaking-soil bud | small compound-leaf seedling | thorny branches and closed buds | open rose blossoms distributed at branch tips |
| apple | newly planted apple sapling | forked young tree | complete green crown with no fruit | red apples evenly visible in front and back crown layers |
| peach | newly planted peach sapling | slender-branched young tree | open green crown with no fruit | pink-orange peaches hanging at the outer foliage edge |
| grape | grape cutting or seedling | short climbing vine | leafy vine covering a stable trellis, no ripe clusters | purple grape clusters hanging in front of trellis and leaves |
| lemon | newly planted lemon sapling | slender-branched young tree | evergreen crown with no fruit | yellow lemons forming clear high-contrast mature cues |

---

### Task 1: Generalize the complete crop-art contract

**Files:**
- Create: `tests/test_all_crop_art_assets.gd`
- Create: `tests/test_all_crop_stage_scenes.gd`
- Modify: `tests/run_farming_system_tests.gd`
- Modify: `scripts/main.gd`

**Interfaces:**
- Test helpers `texture_path(crop_id, stage, variant, layer)` and `scene_path(crop_id, stage)` implement the exact design paths.
- Every production `CropData.stage_scenes` contains four resource paths in seed/sprout/growing/mature order.

- [ ] **Step 1: Write the failing 360-image contract**

Loop through all 15 crops, four stages, three variants, and two layers. For every image assert resource existence, `Texture2D` import, exact 1024 square dimensions, alpha detection, all four transparent corners, and a transparent-pixel ratio greater than 10%. This includes the existing 24 grain PNGs and 336 new PNGs.

- [ ] **Step 2: Write the failing 60-scene contract**

For all crops/stages, assert the stage scene exists, instantiates, uses `CropSpriteCluster`, has exactly three back paths and three front paths, all pairs use the expected crop/stage path, `canvas_world_height` matches the matrix, and at least one recursive `MeshInstance3D` exists as fallback.

Configure seeds 0, 1, and 2; with complete textures each scene must select that variant, show both sprites, and hide fallback meshes. Add one isolated cluster fixture with a deliberately missing selected front texture; both sprites must hide, all fallback meshes must show, and exactly one expected fallback warning is produced.

- [ ] **Step 3: Register tests and confirm missing assets/scenes fail**

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
```

Expected: failures name non-grain paths beginning with `res://assets/crops/carrot/...`.

- [ ] **Step 4: Assign all stage scene paths in crop data**

In `Main.default_crop_definitions()`, generate the four exact paths from each crop ID and the fixed suffixes. Do not special-case grain. Keep registration validation strict so a crop with a missing stage path is invalid after this art plan is complete.

- [ ] **Step 5: Commit tests and data contract**

The focused suite remains red because assets do not yet exist; commit the intentional test-first boundary:

```powershell
git add tests/test_all_crop_art_assets.gd tests/test_all_crop_stage_scenes.gd tests/run_farming_system_tests.gd scripts/main.gd
git commit -m "test: define all crop growth art contract"
```

---

### Task 2: Build deterministic crop-specific fallback scenes

**Files:**
- Create: `scripts/tools/generate_crop_stage_scenes.gd`
- Create: `assets/crops/{carrot,tomato,pumpkin,strawberry,sunflower,apple,grape}/materials/*.tres`
- Create: 28 prototype stage scenes under `assets/crops/{carrot,tomato,pumpkin,strawberry,sunflower,apple,grape}/`
- Modify: `tests/test_all_crop_stage_scenes.gd`

**Interfaces:**
- Headless generator usage: `godot --headless --path . --script res://scripts/tools/generate_crop_stage_scenes.gd`.
- Generator owns exact crop-to-archetype, height, material-color, mesh-count, and stage-name tables and refuses unknown entries.

- [ ] **Step 1: Extend scene tests with prototype silhouette requirements**

Require increasing non-empty bounds across stages and these minimum fallback cues:

```text
root: low leaf fans; stage 3 includes a root-shoulder mesh
tomato: upright stems/branches; stage 2 flower cues; stage 3 round fruit meshes
ground_vine: horizontal stems/leaves; stage 3 ground fruit mesh
bush: radial leaf crown; stage 2 flower cues; stage 3 berry meshes
flower: vertical stem/leaves; stage 2 bud; stage 3 open flower head
tree: trunk plus crown; stage 3 fruit meshes
grape: stable trellis plus vine; stage 3 hanging cluster meshes
```

Tests should identify cues by node-group metadata such as `fallback_role`, not by brittle node names.

- [ ] **Step 2: Implement the scene generator**

Use Godot mesh resources (`CylinderMesh`, `SphereMesh`, `QuadMesh`, and `BoxMesh`) and simple crop-specific `StandardMaterial3D` resources. Build each archetype from reusable functions, scale branch count and bounds by stage, tag semantic cue nodes, attach `CropSpriteCluster`, populate six exact texture paths, set the matrix height, and save with `PackedScene.pack()` plus `ResourceSaver.save()`.

The generator may overwrite only the 56 paths listed in this plan. It must exit non-zero if packing or saving any scene fails. It remains checked in so fallback scenes are reproducible.

- [ ] **Step 3: Generate the seven prototype scene sets**

Limit the generator's checked-in crop table initially to the seven prototypes, run it, then run the scene test. Asset tests remain red; scene structure tests for prototypes must pass.

```powershell
godot --headless --path . --script res://scripts/tools/generate_crop_stage_scenes.gd
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/run_farming_system_tests.gd
```

- [ ] **Step 4: Inspect fallback-only captures**

Temporarily instantiate each scene with invalid texture paths in a test-only capture scene and render the 28 prototype stages. Reject scenes whose bounds decrease, contact point floats, mature cue is absent, or neighboring cell centers are obscured. Restore valid paths before committing.

- [ ] **Step 5: Commit prototype fallbacks**

```powershell
git add scripts/tools/generate_crop_stage_scenes.gd assets/crops/carrot assets/crops/tomato assets/crops/pumpkin assets/crops/strawberry assets/crops/sunflower assets/crops/apple assets/crops/grape tests/test_all_crop_stage_scenes.gd
git commit -m "art: add prototype crop stage fallbacks"
```

---

### Task 3: Generate and approve the seven prototype crops

**Files:**
- Create: 168 PNGs under the seven prototype `painted/stage_*` directories
- Create: `scripts/tools/build_crop_contact_sheet.gd`
- Create: `tests/capture_all_crop_stages.gd`
- Modify: `tests/test_all_crop_art_assets.gd`

**Generation contract:** Make one image-generation call per final layer: `7 crops x 4 stages x 3 variants x 2 layers = 168` calls. Use `assets/vegetation/tree-oak-large.png` and the matching grain stage/layer as style references only.

- [ ] **Step 1: Create the contact-sheet and capture tools before artwork**

`build_crop_contact_sheet.gd` loads final PNGs and writes one 6-column by 4-row sheet per crop: each row is a stage, columns are variant 0 back/front through variant 2 back/front. Label only the sheet margin, never alter source images. `capture_all_crop_stages.gd` instantiates all four stages on real farm cells under the gameplay camera and accepts arguments such as `--crop=carrot --output=tmp/imagegen/crops/carrot/gameplay.png`.

- [ ] **Step 2: Use the fixed layer prompts**

Back prompt:

```text
Use case: stylized-concept. Create a hand-painted semi-realistic 2.5D Godot crop sprite BACK depth layer for {CROP}, growth stage {STAGE_TEXT}, variant {VARIANT}. Match the supplied villa tree and grain references for soft brushwork, warm upper-left lighting, muted natural color, clean soft silhouette, and elevated three-quarter game view. Draw only rear or partly occluded stems, branches, leaves, and rear harvest structures. Shared root/contact anchor at 82% canvas height; at least 6% safe padding. Perfectly flat #ff00ff background. No front-layer duplicate, no square soil tile, no broad shadow, no scenery, pot, tool, character, text, watermark, black outline, photorealism, or plastic 3D rendering.
```

Front prompt:

```text
Use case: stylized-concept. Create the matching FRONT depth layer for the supplied {CROP} back layer, growth stage {STAGE_TEXT}, variant {VARIANT}. Match its scale, root anchor, plant count, lighting, palette, branch continuity, and maturity exactly. Draw only foreground leaves, defining silhouette, and front harvest structures; leave openings that reveal the back layer. Shared contact anchor at 82% canvas height; at least 6% safe padding. Perfectly flat #ff00ff background. No duplicated complete plant, cast shadow, square soil tile, scenery, pot, tool, character, text, watermark, black outline, photorealism, or plastic 3D rendering.
```

Use the exact English stage phrase from the Stage Prompt Matrix above. Stage 0 trees are newly planted saplings and grape is a cutting/seedling; stage 1 has no flowers or fruit; stage 2 has no mature harvest item; stage 3 makes the harvest item readable at gameplay scale.

- [ ] **Step 3: Generate in archetype order with a gate after each crop**

For each of `carrot`, `tomato`, `pumpkin`, `strawberry`, `sunflower`, `apple`, and `grape`:

1. Generate 24 source layers into that crop's directory under `tmp/imagegen/crops/`, for example `tmp/imagegen/crops/carrot/stage_0_variant_0_back_source.png`, using the loaded `imagegen` skill.
2. Process every source with:

```powershell
python "$env:CODEX_HOME\skills\.system\imagegen\scripts\remove_chroma_key.py" --input tmp/imagegen/crops/carrot/stage_0_variant_0_back_source.png --out assets/crops/carrot/painted/stage_0/variant_0_back.png --auto-key border --soft-matte --transparent-threshold 12 --opaque-threshold 220 --despill
```

3. If any magenta fringe remains, rerun that layer once with `--edge-contract 1`.
4. Resize only when needed to exact 1024 square with an alpha-preserving image tool; never stretch non-square selected artwork.
5. Reimport in Godot and build its contact sheet.
6. Capture the four stages in-game before starting the next crop.

Reject a crop batch if any layer has clipped pixels, halo/background box, inconsistent baseline, duplicated front/back plant, broken branch continuity, wrong stage maturity, fruit in stage 2, absent harvest cue in stage 3, or style/scale mismatch against grain.

- [ ] **Step 4: Verify prototype contracts**

```powershell
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/run_farming_system_tests.gd
```

Expected: all prototype image and scene assertions pass; failures remain only for the seven expansion crops.

- [ ] **Step 5: Commit each approved prototype separately**

For each crop, stage only that crop's 24 PNGs and any crop-specific scene/material refinements. Run one iteration after that crop passes review:

```powershell
$crop = 'carrot' # then tomato, pumpkin, strawberry, sunflower, apple, grape
git add "assets/crops/$crop"
git commit -m "art: add painted $crop growth stages"
```

Commit the reusable capture/contact tools with the first approved prototype.

---

### Task 4: Expand fallback scenes to the seven related crops

**Files:**
- Modify: `scripts/tools/generate_crop_stage_scenes.gd`
- Create: `assets/crops/{potato,watermelon,blueberry,lavender,rose,peach,lemon}/materials/*.tres`
- Create: 28 expansion stage scenes under `assets/crops/{potato,watermelon,blueberry,lavender,rose,peach,lemon}/`
- Modify: `tests/test_all_crop_stage_scenes.gd`

- [ ] **Step 1: Add all expansion crops to exact generator tables**

Map archetypes and heights exactly as the Asset Matrix. Give each crop a distinct material palette and mature fallback cue: potato tuber shoulder, striped watermelon, blue berry clusters, purple lavender spikes, rose heads, pink-orange peaches, and yellow lemons.

- [ ] **Step 2: Generate and test all 56 scenes**

```powershell
godot --headless --path . --script res://scripts/tools/generate_crop_stage_scenes.gd
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/run_farming_system_tests.gd
```

Expected: all 60 scene contracts including grain pass; image contract still names only missing expansion PNGs.

- [ ] **Step 3: Inspect expansion fallback captures and commit**

Use the same fallback capture criteria as Task 2. Compare each expansion crop beside its approved prototype at all four stages.

```powershell
git add scripts/tools/generate_crop_stage_scenes.gd assets/crops/potato assets/crops/watermelon assets/crops/blueberry assets/crops/lavender assets/crops/rose assets/crops/peach assets/crops/lemon tests/test_all_crop_stage_scenes.gd
git commit -m "art: add remaining crop stage fallbacks"
```

---

### Task 5: Generate and approve the seven expansion crops

**Files:**
- Create: 168 PNGs under the seven expansion `painted/stage_*` directories

**Generation contract:** Make one call per layer, using the approved matching prototype crop plus grain/tree as references. Keep the prototype's height, baseline, density, brushwork, and front/back division; change only the crop-specific botany and palette.

- [ ] **Step 1: Generate by prototype pair**

Use this exact order and do not begin a pair until its reference prototype passed Task 3:

```text
carrot -> potato
pumpkin -> watermelon
strawberry -> blueberry
sunflower -> lavender
sunflower -> rose
apple -> peach
apple -> lemon
```

For every crop, repeat Task 3's 24-call, chroma-key, reimport, contact-sheet, real-camera capture, and rejection workflow. Use the exact phrases from the Stage Prompt Matrix; do not merely recolor the prototype.

- [ ] **Step 2: Check environment-specific readability**

Capture lemon in a working greenhouse. Capture peach/apple side by side outdoors. Capture low crops in adjacent cells to confirm watermelon/pumpkin vines do not hide neighboring centers. Capture rose/lavender/sunflower together so mature flower silhouettes remain distinct.

- [ ] **Step 3: Run the complete asset contract after each crop**

```powershell
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/run_farming_system_tests.gd
```

The missing-file count must decrease by exactly 24 after each crop. After lemon, the complete farming suite exits 0 with no painted-resource fallback warnings.

- [ ] **Step 4: Commit each crop separately**

```powershell
$crop = 'potato' # then watermelon, blueberry, lavender, rose, peach, lemon
git add "assets/crops/$crop"
git commit -m "art: add painted $crop growth stages"
```

---

### Task 6: Verify lifecycle treatments and deterministic staging

**Files:**
- Modify: `tests/test_crop_visual.gd`
- Modify: `tests/test_crop_sprite_cluster.gd`
- Modify: `tests/capture_all_crop_stages.gd`

- [ ] **Step 1: Add deterministic four-stage variant tests**

For every crop, plant at one fixed cell, force stages 0-3, and assert `get_variant_index()` never changes. Rebuild visuals and save/load the grid; assert the same variant and root transform remain. Adjacent cells must produce deterministic indices from their own cell/crop seeds.

- [ ] **Step 2: Add dormant/withered visual tests**

Assert dormant crops instantiate stage 2, never stage 3 fruit art, and apply the approved lower-saturation/lower-brightness modulate. Assert withered crops use the current silhouette with dry-yellow treatment and no output interaction. Returning from dormancy restores the progress-derived stage without changing variant.

- [ ] **Step 3: Capture state comparison sheets**

Produce real-camera captures for outdoor active, greenhouse active, dormant, withered, and mature-storage-blocked states. A storage-blocked mature crop must remain on stage 3. Inspect billboard depth order, black/white/magenta fringes, z-fighting, root float, and overlap.

- [ ] **Step 4: Run and commit**

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
git add tests/test_crop_visual.gd tests/test_crop_sprite_cluster.gd tests/capture_all_crop_stages.gd
git commit -m "test: verify crop art lifecycle states"
```

---

### Task 7: Final art and gameplay verification

- [ ] **Step 1: Count exact deliverables**

```powershell
$pngs = Get-ChildItem assets/crops -Recurse -Filter 'variant_*_*.png'
$scenes = Get-ChildItem assets/crops -Recurse -Filter '*_stage_*.tscn'
$pngs.Count
$scenes.Count
```

Expected totals: `360` painted PNGs including grain and `60` stage scenes including grain. Also assert each non-grain crop contributes exactly 24 PNGs and four scenes; do not accept only aggregate totals.

- [ ] **Step 2: Run all relevant suites**

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_economy_system_tests.gd
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: every command exits 0; no unexpected fallback warning appears.

- [ ] **Step 3: Run visual review at desktop and mobile-sized viewports**

Start the game and capture representative mixed plots at the existing desktop and mobile test sizes. Verify nonblank rendering, consistent framing, no text/control overlap from the new seed/storage UI, and no crop art hiding interaction markers or neighboring mature cues.

- [ ] **Step 4: Inspect repository state**

```powershell
git diff --check
git status --short
git log --oneline --decorate -25
```

Expected: no whitespace errors; all planned art commits present; only the user's pre-existing `tmp/` remains untracked. Do not add generated sources, contact sheets, or captures from `tmp/`.
