# Production Yard Fence Art Redesign

**Date:** 2026-08-10  
**Status:** Approved for implementation  
**Branch:** `feature/painted-production-buildings-polish`

## Objective

Replace the flat geometric production-yard fence art with low hand-painted fence segments that visually belong to the existing building entities. The new fences must preserve the completed production-yard layout, collision, output pickup, construction, preview, maintenance, and save behavior.

## Diagnosed Mismatch

The current fence atlases are SVG drawings with uniform strokes, flat fills, simple geometric rails, and generic drop shadows. The building entities are transparent raster paintings with irregular silhouettes, material facets, warm highlights, cool occlusion, soft edge treatment, dense surface detail, and ground dressing. Color changes alone cannot reconcile those pipelines.

The replacement therefore uses newly painted transparent PNG atlases. SVG and procedural geometry are excluded from the final visual solution.

## Scope

Three material families remain authoritative:

| Family | Buildings | Primary references | Fence language |
|---|---|---|---|
| Timber | workbench, windmill, food_workshop, textile_machine, chicken_coop, beehive, lumberyard | lumberyard, workbench, chicken coop | Thick amber timber, stone feet, nails, rope, grass |
| Masonry | stone_kiln, quarry | stone kiln, quarry | Irregular warm-gray stone piers, brick chips, aged timber rails |
| Industrial | furnace, mine | mine, furnace | Dark mine timber, rubble base, rusted brackets, restrained rail details |

The redesign does not change production-yard membership, 3×3/4×4 footprints, production recipes, output capacity, interaction range, maintenance prices, or save schema.

## Visual Direction

All three families use the same low overall fence height selected by the user. The fences must read as physical objects without hiding products in the front collection zone.

Shared rules:

- Match the buildings' three-quarter elevated camera angle.
- Use uneven hand-painted contours instead of uniform black strokes.
- Use warm top-facing highlights and cooler, darker occluded planes.
- Paint wood grain, stone facets, metal wear, fasteners, and local color variation.
- Include restrained ground contact details such as grass, soil, chips, or small stones.
- Keep transparent negative space between rails so buildings and products remain readable.
- Use a consistent baseline and occupied pixel envelope across every construction frame to prevent root drift.
- Avoid modern fencing, clean vector gradients, flat gray metal, and repeated geometric modules.

## Asset Contract

Create these atlases:

- `assets/buildings/yards/timber_yard_fence.png`
- `assets/buildings/yards/masonry_yard_fence.png`
- `assets/buildings/yards/industrial_yard_fence.png`

Each atlas is `1024×2048`, arranged as two columns by four rows. Every frame is `512×512` with transparent background:

| Column | Meaning |
|---|---|
| 0 | Front/back-facing grid edge segment |
| 1 | Side-facing grid edge segment |

| Row | Construction stage |
|---|---|
| 0 | Foundation marks and feet |
| 1 | Installed posts |
| 2 | Partial rails and material details |
| 3 | Completed low fence |

All frames share the same ground baseline, lateral span, light direction, and visual center. The import configuration must preserve alpha, avoid filtering artifacts that blur the painted edges, and expose the atlas as a normal `Texture2D`.

## Rendering and Composition

`BuildingProductionYard` remains responsible for assembly. It will load PNG atlases, use `512×512` atlas regions, and place 12 perimeter segments for 3×3 yards or 16 for 4×4 yards.

The existing back, side, and front layer structure remains. The new segment scale and vertical position are calibrated against the building sprites so that:

- completed rails remain low on every side;
- the building foundation remains visible;
- the front output slots remain visible and independently clickable;
- adjacent segments overlap slightly enough to avoid seams without producing doubled posts;
- front and side perspectives meet cleanly at corners.

The structure collision and grid occupancy remain authoritative. Fence sprites never receive pointer interaction layers, so they cannot intercept product pickup.

## Construction and State Transitions

Fence construction stage follows the building construction stage. A fence-stage change uses the same approximate two-second crossfade principle as building construction art: the outgoing frame fades down while the incoming frame fades up. Repeated or interrupted stage updates must leave only the latest frame visible.

Preview state applies a restrained green or red wash while retaining texture detail and alpha. Maintenance warning, overdue, and repairing states use mild desaturation and value reduction; they must not flatten the art into solid gray.

Deactivation immediately removes fence visuals and disables perimeter collision, matching the existing building lifecycle.

## Failure Handling

- Missing PNG atlas: emit one warning for the family and keep yard collision active; do not replace it with the rejected geometric SVG art.
- Invalid atlas dimensions: reject visual configuration, warn once, and retain physical yard behavior.
- Invalid family name or footprint: preserve the existing data validation failure.
- A construction transition interrupted by deactivation must release both outgoing and incoming sprites.

## Verification

Automated checks must verify:

- all three PNG atlases exist and are exactly `1024×2048`;
- all retired SVG paths are no longer referenced by runtime code;
- every atlas has meaningful alpha and non-empty content in all eight frames;
- frame baselines and opaque bounds remain within an allowed tolerance;
- three families load the correct texture and retain their expected material mapping;
- 3×3 and 4×4 segment counts, output slots, collision layers, preview state, maintenance state, and deactivation behavior remain correct;
- construction stage transitions finish without duplicate visual children;
- the full building, production, economy, save, and main gameplay suites remain green.

## Acceptance Criteria

The work is complete when the three material families appear as low, high-detail hand-painted raster entities that match their referenced buildings in perspective, lighting, edge quality, surface texture, and ground contact; no flat SVG fence is used at runtime; products remain visible and collectible; the yard remains physically closed; construction and maintenance states remain coherent; and no existing production-yard behavior regresses.
