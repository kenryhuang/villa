# Remaining Crops Two-Stage Painted Visuals Design

## Goal

Replace the remaining legacy crop visuals with the same compact, painted PNG pipeline used by carrot. The result must be visually recognizable, use only two display stages, and remove redundant procedural geometry and texture variants.

## Scope

Migrate these nine crops:

- apple
- peach
- lemon
- grape
- blueberry
- strawberry
- watermelon
- pumpkin
- sunflower

Grain remains unchanged and serves as the reference for brushwork, lighting, saturation, transparent cutout treatment, and soil presentation. Carrot, tomato, potato, rose, and lavender already use the target two-stage structure and are not regenerated.

## Asset Structure

Each migrated crop keeps only these scenes:

- `<crop>_stage_0_seed.tscn`
- `<crop>_stage_3_mature.tscn`

Each stage references exactly one front and one back texture:

- `painted/stage_0/variant_0_front.png`
- `painted/stage_0/variant_0_back.png`
- `painted/stage_3/variant_0_front.png`
- `painted/stage_3/variant_0_back.png`

Every texture must be a 1024 by 1024 PNG with genuine transparency. The root scene uses `CropSpriteCluster`; migrated scenes contain no `MeshInstance3D` nodes or procedural mesh/material resources.

The migration removes:

- stage 1 and stage 2 scenes and painted assets;
- stage 0 and stage 3 variants 1 and 2;
- crop-specific materials that are no longer referenced;
- procedural mesh nodes and subresources from the retained scenes.

## Stage Semantics

Stage 0 depends on crop category:

- Apple, peach, and lemon show distinct young saplings.
- Grape shows a young vine.
- Blueberry, strawberry, watermelon, pumpkin, and sunflower show recognizable real seeds.

Stage 3 shows the mature plant in its characteristic growth habit:

- fruit trees have a trunk, canopy, and clearly visible fruit;
- grape uses a restrained wooden support and visible grape clusters;
- blueberry and strawberry use recognizable low bush forms;
- watermelon and pumpkin use ground-running vines and visible fruit;
- sunflower uses mature flowering stalks.

No crop image includes pots, labels, UI text, borders, watermarks, or decorative props unrelated to its growth habit. The grape support is the sole structural prop because it materially improves recognition.

## Visual Direction

All assets use a cohesive hand-painted game-sprite style derived from the grain reference:

- warm natural light from a consistent direction;
- readable silhouettes at gameplay scale;
- moderately saturated colors and painted texture rather than photorealism;
- a compact subject centered within transparent padding;
- compatible front and back views with no obvious mirroring artifacts;
- a small soil base only where needed to ground a mature plant.

Approximate `canvas_world_height` ranges:

- seeds: 0.4 to 0.5;
- saplings and the young vine: 0.65 to 0.8;
- mature herbs, vines, and berry plants: 0.9 to 1.15;
- mature fruit trees: 1.3 to 1.55.

These values may be tuned within their category after gallery inspection. Visual height changes do not modify grid footprint, collision, farming rules, or placement behavior.

## Runtime Integration

Add all nine crop IDs to `TWO_STAGE_CROP_IDS`. Existing growth progress maps to the retained visual stages: the pre-mature portion uses stage 0 and maturity uses stage 3.

Do not change planting, watering, harvesting, inventory, save data, or debug-day advancement. The migration is limited to visual-stage mapping, scene references, asset cleanup, tests, and the development gallery.

## Generation and Normalization

Use built-in image generation, one asset per requested front/back view. Prompts must identify the crop, category-specific stage semantics, game-sprite use, hand-painted grain-compatible style, and true transparent background.

After generation, inspect every output. If the generator returns a non-standard canvas or baked light background, perform deterministic export normalization only: resize to 1024 by 1024 and convert the connected neutral background to alpha without redesigning the subject. Preserve the original generated file in the Codex generated-images directory and copy the normalized final into the project.

## Verification

Use test-first migration:

1. Move the nine crop IDs from the legacy four-stage test lists into the two-stage lists and confirm the old asset structure fails the new contract.
2. Generate and wire each crop batch.
3. Confirm every migrated scene contains no procedural meshes, references one texture per view, and has only stages 0 and 3.
4. Confirm every final PNG is 1024 square and has true alpha.
5. Extend the two-stage crop gallery to include all migrated crops and inspect both camera directions for scale, cropping, silhouette, and consistency.
6. Run crop art, crop model, farming interaction, runtime UI, and main gameplay integration checks.

The main gameplay integration suite has two known pre-existing failures concerning automatic grain-seed mapping and initial contract delivery. They must be reported separately; the migration must introduce no additional failures.

## Commit Strategy

Commit in reviewable batches:

1. design and implementation plan;
2. fruit trees and grape;
3. berries;
4. melons, pumpkin, and sunflower;
5. gallery and final verification adjustments.

Tracked source and asset changes must be clean at handoff. Existing user-owned untracked `.playwright-cli/` and `output/` directories remain untouched and uncommitted.
