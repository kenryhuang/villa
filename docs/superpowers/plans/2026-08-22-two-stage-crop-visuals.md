# Two-Stage Crop Visuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Replace tomato, potato, rose and lavender with one hand-painted seed pair and one mature pair per crop while preserving four logical growth stages.

**Architecture:** CropData keeps four stage slots for save compatibility, but target crops map slots 0–2 to one seed scene and slot 3 to one mature scene. Each scene uses CropSpriteCluster with exactly one front/back painted pair and no procedural crop model. Asset tests define the exact 16-PNG contract before generation.

**Tech Stack:** Godot 4.7, GDScript resources/scenes, imagegen raster generation, PNG 1024×1024 with alpha.

---

### Task 1: Define the two-stage asset contract in tests

**Files:**
- Modify: tests/test_multi_crop_art_assets.gd
- Modify: tests/test_multi_crop_models.gd
- Modify: tests/run_multi_crop_art_tests.gd
- Modify: tests/run_multi_crop_model_tests.gd

- [ ] **Step 1: Write failing target-crop asset assertions**

Split crop IDs into TWO_STAGE_CROP_IDS and LEGACY_FOUR_STAGE_CROP_IDS. Keep the existing 4×3×2 contract for legacy crops. For each target crop require only:

~~~gdscript
const TWO_STAGE_CROP_IDS := ["potato", "tomato", "lavender", "rose"]
const TWO_STAGE_SCENES := [
    {"stage": 0, "suffix": "seed"},
    {"stage": 3, "suffix": "mature"},
]

for crop_id in TWO_STAGE_CROP_IDS:
    for stage in [0, 3]:
        for layer in ["back", "front"]:
            var path := texture_path(crop_id, stage, 0, layer)
            assertions.truthy(ResourceLoader.exists(path), "%s two-stage texture exists" % path)
            var texture := load(path) as Texture2D
            assertions.equal(texture.get_size(), Vector2(1024, 1024), "%s is 1024 square" % path)
            assertions.truthy(texture.get_image().detect_alpha(), "%s has alpha" % path)
    for removed_stage in [1, 2]:
        assertions.truthy(not ResourceLoader.exists(stage_scene_path(crop_id, removed_stage)), "%s has no intermediate scene" % crop_id)
~~~

Model tests require each target scene to use CropSpriteCluster, contain one back path and one front path, select variant index zero, create visible BackLayer/FrontLayer, and contain no MeshInstance3D.

- [ ] **Step 2: Run both target runners and verify RED**

Expected: intermediate scenes and multiple variants still exist; existing target art does not meet the approved contract.

- [ ] **Step 3: Commit tests only**

~~~powershell
git add tests/test_multi_crop_art_assets.gd tests/test_multi_crop_models.gd tests/run_multi_crop_art_tests.gd tests/run_multi_crop_model_tests.gd
git commit -m "test: require two-stage painted crop assets"
~~~

### Task 2: Generate the 16 approved PNG assets

**Files:**
- Replace: assets/crops/{tomato,potato,rose,lavender}/painted/stage_0/variant_0_{front,back}.png
- Replace: assets/crops/{tomato,potato,rose,lavender}/painted/stage_3/variant_0_{front,back}.png

- [ ] **Step 1: Load the imagegen skill and reference art**

Read the imagegen skill completely. Inspect grain stage_0 and stage_3 front/back references at original resolution before generating. Use imagegen for every raster generation or correction.

- [ ] **Step 2: Generate seed-state pairs**

For each crop and direction, use the matching grain seed front/back PNG as a referenced image and this fixed prompt:

“Create one isolated hand-painted farming-game crop sprite on a fully transparent 1024×1024 canvas. Match the reference's soft painterly brushwork, warm natural highlights, clean readable silhouette, camera angle, ground contact and centered bottom anchor. Show only [SUBJECT] resting on a few small crumbs of soil. No sprout, stem, leaves, pot, label, border, shadow box, scenery, text or black background. Preserve generous transparent padding. This is the [front/back] view.”

SUBJECT values:

- tomato: a small cluster of pale cream flattened tomato seeds.
- potato: two small seed-potato tubers with visible eyes.
- rose: a small cluster of tan-brown rose achenes.
- lavender: a small cluster of tiny dark brown lavender seeds.

- [ ] **Step 3: Generate mature-state pairs**

Use the matching grain mature front/back PNG and this fixed prompt:

“Create one isolated mature [CROP] plant sprite on a fully transparent 1024×1024 canvas for a cozy hand-painted farming game. Match the reference's soft painterly brushwork, warm natural highlights, clean outline, camera angle, ground contact, centered bottom anchor and occupied height. Show one readable compact plant cluster, not a scientific diagram. No pot, label, border, shadow box, scenery, text or black background. This is the [front/back] view.”

CROP descriptions:

- tomato: leafy compact plant with several ripe red tomatoes.
- potato: low broad green potato foliage with a few small pale blossoms.
- rose: compact rose bush with several open deep-red flowers.
- lavender: compact clump of upright purple flower spikes and narrow green leaves.

- [ ] **Step 4: Inspect and correct every output**

Use view_image at original resolution. Reject outputs with opaque corners, clipped leaves, inconsistent anchor, words, scenery, wrong crop anatomy or large front/back scale differences. Correct rejected images through imagegen edits, not local painting scripts.

- [ ] **Step 5: Import and verify dimensions**

Launch Godot once to import files, then run the multi-crop art runner. Expected failures after this step are limited to old intermediate/variant files and scene contracts, not the 16 replacement PNGs.

- [ ] **Step 6: Commit the generated source PNGs**

~~~powershell
git add assets/crops/tomato/painted/stage_0/variant_0_front.png assets/crops/tomato/painted/stage_0/variant_0_back.png assets/crops/tomato/painted/stage_3/variant_0_front.png assets/crops/tomato/painted/stage_3/variant_0_back.png
git add assets/crops/potato/painted/stage_0/variant_0_front.png assets/crops/potato/painted/stage_0/variant_0_back.png assets/crops/potato/painted/stage_3/variant_0_front.png assets/crops/potato/painted/stage_3/variant_0_back.png
git add assets/crops/rose/painted/stage_0/variant_0_front.png assets/crops/rose/painted/stage_0/variant_0_back.png assets/crops/rose/painted/stage_3/variant_0_front.png assets/crops/rose/painted/stage_3/variant_0_back.png
git add assets/crops/lavender/painted/stage_0/variant_0_front.png assets/crops/lavender/painted/stage_0/variant_0_back.png assets/crops/lavender/painted/stage_3/variant_0_front.png assets/crops/lavender/painted/stage_3/variant_0_back.png
git commit -m "art: repaint four crops as two-stage sprites"
~~~

### Task 3: Map four logical stages to two visual scenes

**Files:**
- Modify: scripts/main.gd
- Replace: assets/crops/{tomato,potato,rose,lavender}/*_stage_0_seed.tscn
- Replace: assets/crops/{tomato,potato,rose,lavender}/*_stage_3_mature.tscn
- Modify: tests/test_multi_crop_models.gd
- Modify: tests/test_farming_system_complete.gd

- [ ] **Step 1: Add failing mapping assertions**

For target definitions require:

~~~gdscript
assertions.equal(crop.stage_scenes, [seed_path, seed_path, seed_path, mature_path], "%s aliases immature visuals" % crop.crop_id)
assertions.equal(crop.stage_textures, [seed_front, seed_front, seed_front, mature_front], "%s exposes real selector icons" % crop.crop_id)
~~~

Create/load CropInstance fixtures at logical stages 0, 1, 2 and 3 and require the first three to instantiate the same seed scene path while stage 3 instantiates mature.

- [ ] **Step 2: Run and verify RED**

Expected: default_crop_definitions still assigns four unique scenes and placeholder texture names.

- [ ] **Step 3: Implement target-specific definitions**

In default_crop_definitions(), use a TWO_STAGE_CROP_IDS constant. Assign target stage_scenes as seed/seed/seed/mature and target stage_textures as the real stage_0 front path repeated three times plus stage_3 front. Keep the existing four-scene mapping for all other crops.

- [ ] **Step 4: Replace target scenes**

Each scene has only a Node3D root with CropSpriteCluster script, one back path, one front path and an approved canvas_world_height. Do not include procedural materials or MeshInstance3D children.

- [ ] **Step 5: Add safe sprite fallback reporting**

Modify CropSpriteCluster so _show_fallback creates a small magenta/cream checker ImageTexture on FrontLayer instead of revealing procedural meshes, emits painted_asset_failed(reason), and still push_warning(). FarmingSystem connects each instantiated cluster with the stage scene path it already resolved, then relays visual_asset_failed(stage_scene_path, reason). Main publishes that exact path and reason as a debug HudMessageBus record when the bus exists.

- [ ] **Step 6: Run and verify GREEN**

Run multi-crop model, farming system and main gameplay runners. Expected: target mapping tests pass; existing unrelated farming baseline failures are recorded separately.

- [ ] **Step 7: Commit**

~~~powershell
git add scripts/main.gd scripts/visual/crop_sprite_cluster.gd scripts/systems/farming_system.gd tests/test_multi_crop_models.gd tests/test_farming_system_complete.gd
git add assets/crops/tomato/*_stage_0_seed.tscn assets/crops/tomato/*_stage_3_mature.tscn
git add assets/crops/potato/*_stage_0_seed.tscn assets/crops/potato/*_stage_3_mature.tscn
git add assets/crops/rose/*_stage_0_seed.tscn assets/crops/rose/*_stage_3_mature.tscn
git add assets/crops/lavender/*_stage_0_seed.tscn assets/crops/lavender/*_stage_3_mature.tscn
git commit -m "feat: map four crops to two visual stages"
~~~

### Task 4: Remove obsolete target assets and verify visuals

**Files:**
- Delete: stage_1 and stage_2 scene files for tomato, potato, rose and lavender
- Delete: target stage_0/stage_3 variant_1 and variant_2 PNGs
- Delete: all target stage_1/stage_2 painted PNGs
- Delete: target material resources after reference audit proves they are unused
- Modify: tests/capture_farming_visual.gd

- [ ] **Step 1: Resolve and audit the exact deletion list**

Use rg to prove every candidate path is referenced only by the old target scenes/tests being replaced. Resolve every absolute target under the four named crop directories before deletion. Do not use globs for the destructive operation and do not touch grain or any other crop.

- [ ] **Step 2: Delete the audited obsolete files**

Remove exactly 80 superseded target PNGs, eight intermediate target scenes, and only material files with zero remaining references. Report the exact count after deletion.

- [ ] **Step 3: Run asset and model tests**

Run run_multi_crop_art_tests.gd and run_multi_crop_model_tests.gd. Expected: all two-stage and legacy four-stage contracts pass.

- [ ] **Step 4: Capture a four-crop gallery**

Update capture_farming_visual.gd to place seed and mature visuals for tomato, potato, rose and lavender, front and back camera orientations. Capture at gameplay camera distance and inspect anchor, size, transparency and crop identity.

- [ ] **Step 5: Run compatibility regressions**

Run seed selector, farming system, main gameplay and core runners. New two-stage assertions must pass; known baseline failures must be listed without being hidden.

- [ ] **Step 6: Commit cleanup**

~~~powershell
git add -A assets/crops/tomato assets/crops/potato assets/crops/rose assets/crops/lavender tests/test_multi_crop_art_assets.gd tests/test_multi_crop_models.gd tests/capture_farming_visual.gd
git commit -m "chore: remove obsolete crop stage assets"
~~~
