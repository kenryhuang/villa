# Production Yard Painted Ground Redesign

**Date:** 2026-08-11  
**Status:** Approved for implementation  
**Branch:** `feature/painted-production-buildings-polish`

## Objective

Replace production-building perimeter fences with seamless, walkable, semi-transparent hand-painted ground areas. Each production yard must read as part of its building rather than as a separate geometric enclosure, while production output placement, collection, save compatibility, preview feedback, and building-body collision remain intact.

## Confirmed Direction

The user selected the following behavior:

- remove fences completely, including all fence visuals and perimeter collision;
- provide three ground-art families rather than one asset per building;
- show the completed ground immediately when the initial building frame is placed;
- render one seamless patch across the full 3×3 or 4×4 footprint, without visible cell seams;
- allow the player to walk across the painted ground;
- keep only the building structure itself physically impassable;
- use hand-painted semi-transparent material rather than procedural noise;
- use approximately 70%–80% opacity for the main surface, 85%–95% for selected details, and feather the outside edge to zero alpha.

## Material Families

Three square transparent raster assets remain authoritative:

| Family | Buildings | Ground language |
|---|---|---|
| Timber | workbench, windmill, food_workshop, textile_machine, chicken_coop, beehive, lumberyard | Compacted warm earth, sawdust, wood chips, short worn planks, restrained grass contact |
| Masonry | stone_kiln, quarry | Aged irregular stone slabs, brick chips, loose stones, thin moss and soil seams |
| Industrial | furnace, mine | Dark compacted gravel, coal dust, slag, restrained rust-colored ore fragments |

Each asset is a `1024×1024` transparent PNG. One asset scales uniformly to either a 3×3 or a 4×4 square footprint. The center beneath the building has lower detail density so it does not compete with the building foundation. The front collection zone has enough readable surface detail to visually support product piles without reducing their contrast.

The painted shape reaches every occupied cell but has an irregular organic silhouette. Decorative marks may extend at most 0.1 grid cell beyond the authoritative footprint. The primary surface uses 70%–80% alpha, high-value fragments use 85%–95%, and the edge transitions smoothly to zero alpha. No opaque rectangular background, baked checkerboard, label, border, or repeated cell grid is permitted.

## Rendering Architecture

The existing `BuildingProductionYard` class and `ProductionYard` node name remain for API and save compatibility. Internally, the component becomes a production-area ground adapter:

- it loads the family ground texture;
- it creates one ground-projected visual sized to the complete footprint;
- it retains the existing output-slot calculation and public accessors;
- it no longer creates fence segments, fence construction transitions, or perimeter collision bodies.

The ground uses a terrain-projected decal so the painted surface follows the current heightmap instead of floating above slopes or cutting into the grass mesh. The terrain mesh receives a dedicated visual layer in addition to its existing render layer, and the decal cull mask targets only that terrain layer. This prevents the ground art from projecting onto the building, products, actors, crops, or UI feedback.

The decal is centered on the production footprint. Its X/Z size equals the configured 3×3 or 4×4 yard size plus only the small allowance required by the painted feathered edge. Its projection depth is shallow and centered around the local ground plane. It has no collision shape, physics layer, input ray-pickability, or interaction callback.

## Lifecycle and State

The complete ground appears during `configure`, including building preview and the initial construction frame. It does not change atlas frame or crossfade when construction advances. The compatibility method `set_construction_stage()` continues to store the normalized stage but has no visual effect.

Preview state applies a restrained green or red color multiplication to the ground while preserving its source alpha. After placement, the texture returns to its original color. Maintenance warning, overdue, broken, and repairing states do not tint the ground; maintenance feedback remains on the building entity.

Building activation creates the ground and output slots. Deactivation and immediate cleanup release the decal without waiting for a tween. The existing structure collision remains authoritative, so only the painted building body is impassable; the surrounding production ground is walkable.

Output pile positions remain inside the footprint, in the front collection zone. Piles keep their independent hover labels, pointer detection, collection animation, and inventory transfer behavior.

## Compatibility and Failure Handling

The `ProductionYard` node name, output-slot API, footprint mapping, building-family mapping, and save schema remain unchanged. No save migration is required because the ground is derived from building data at runtime.

If a ground PNG is missing, fails to load, or has invalid dimensions, the component warns once per family and omits only the ground visual. Output slots, production, collection, building-body collision, construction, maintenance, and save behavior continue normally. It does not create a procedural color plane or restore retired fence art as fallback.

The old fence PNG atlases and their import metadata are deleted only after runtime code and tests no longer reference them.

## Verification

Automated checks must verify:

- the timber, masonry, and industrial ground PNGs exist and import as `Texture2D` resources;
- every asset is exactly `1024×1024`, preserves alpha, has transparent corners, and has a feathered outer edge;
- the main painted region contains semi-transparent pixels in the selected opacity range rather than being fully opaque;
- every configured production yard owns exactly one ground visual and no fence sprites;
- 3×3 and 4×4 visuals use the expected footprint dimensions and family texture;
- the ground has no collision body, physics layer, pointer input, or interaction callback;
- building structure collision remains enabled after construction;
- construction-stage changes do not replace or animate the ground visual;
- preview tint preserves texture alpha and maintenance changes leave the ground color unchanged;
- output slots remain inside the footprint and product piles remain independently collectible;
- missing or malformed textures do not disable production-area gameplay;
- no runtime or test code references retired fence assets;
- building, production, economy, save, and main gameplay test suites remain green.

## Acceptance Criteria

The redesign is complete when every production building sits on one seamless hand-painted ground area matching its timber, masonry, or industrial family; the underlying grass remains visible through the semi-transparent material; edges fade naturally without a square outline; no fence or invisible perimeter wall remains; players can walk across the ground while the building body still blocks movement; output piles remain clear and collectible; and existing lifecycle and persistence behavior does not regress.
