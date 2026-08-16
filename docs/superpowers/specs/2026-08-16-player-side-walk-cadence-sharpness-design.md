# Player Side-Walk Cadence and Sharpness Design

## Goal

Make the nine-frame east/west walk keep pace with player movement and remove the runtime softness at transparent painted edges without repainting the approved poses.

## Root cause

The nine-frame side sequence currently runs at the shared numeric rate of 6 FPS. That creates a 1.5-second side gait cycle, while every six-frame non-side direction completes its cycle in one second. At the normal movement speed of 3 units per second, the player travels 4.5 units during one side cycle instead of 3 units during a non-side cycle, so the supporting-leg exchange visibly lags behind movement.

The side PNG is not intrinsically less detailed than the original directional atlas. Pixel measurements show equal or higher internal luminance contrast. Runtime softness comes from the rendering/import boundary:

- `PlayerVisual` does not explicitly select the codebase's non-mipmap linear texture filter.
- `player_farmer_side_walk.png.import` has `process/fix_alpha_border=false`.
- The original player atlas uses `process/fix_alpha_border=true`.

Linear sampling across transparent pixels therefore blends the side artwork against unprepared transparent border colors, creating a soft fringe during movement.

## Cadence contract

Keep all nine approved side poses and restore the same cycle durations as the other directions:

- Normal side walk: 9 FPS, producing a 1-second cycle.
- Side sprint: 13.5 FPS, producing a 2/3-second cycle.
- Normal movement remains 3 units per second.
- Sprint movement remains 5 units per second.
- Non-side animation rates remain 6 FPS walk and 9 FPS run.

Matching cycle duration and traveled distance per gait cycle takes priority over matching the raw FPS number because the side animation contains three more poses.

## Sharpness contract

- Set `PlayerVisual.texture_filter` explicitly to `BaseMaterial3D.TEXTURE_FILTER_LINEAR`.
- Keep painted anti-aliasing; do not use nearest-neighbor runtime filtering.
- Set the side atlas import option `process/fix_alpha_border=true`, matching the original atlas.
- Keep mipmap generation disabled.
- Do not sharpen, redraw, recolor, or resize the nine approved raster frames.

## Verification

Automated tests will assert:

- nine side frames at 9 FPS;
- side sprint target of 13.5 FPS and runtime `speed_scale = 1.5`;
- equal normal and sprint cycle durations between side and non-side directions;
- explicit non-mipmap linear filtering on configured `PlayerVisual`;
- matching alpha-border import processing between the side and original atlases;
- all existing scale, baseline, denim, mirror, gait, and runtime contracts.

A real display-driver capture will be regenerated and visually inspected at native cell scale. Focused, main gameplay, grid, farming, building, and economy UI suites must pass before completion.

## Scope

This correction changes animation timing and texture sampling/import behavior only. It does not change player movement speed, frame selection, atlas dimensions, painted pixels, direction mapping, or gameplay behavior.

