# Player Side-Walk 9-Frame Reduction Design

## Goal

Reduce the east/west player walk from twelve frames to nine by removing visually unnecessary poses, while preserving the approved leg sequence, corrected 151-pixel scale, dark-denim palette, baseline, and exact west mirroring.

## Approved frame selection

The new east row is assembled from these existing approved source indices, in order:

`[00, 02, 04, 05, 06, 08, 09, 10, 11]`

The removed source frames are:

- `01`, because `00 -> 02` communicates the same opening movement without the intermediate pose.
- `03`, because `02 -> 04` preserves the crossing-to-support transition without the extra near-standing pose.
- `07`, because `06` already shows the left leg extending and `08` already shows left-foot support; `07` adds an unnecessary contact pose between them.

After reduction, the retained source indices are relabeled sequentially as new frames `00-08`. No pose is repainted or anatomically altered in this change.

## Raster and assembly contract

- The side-walk atlas becomes `1728x384`.
- Each cell remains `192x192`.
- Row 0 contains nine east-facing frames.
- Row 1 contains nine exact horizontal mirrors for west-facing movement.
- Every painted character remains exactly 151 pixels tall.
- Every frame remains aligned to baseline y=184.
- The existing reference-derived denim correction remains unchanged.
- The assembler reads only the nine approved source indices and applies the corresponding horizontal offsets from their original poses.

## Runtime timing

East and west use the same base FPS as every other walk direction:

- Normal walk: `6 FPS`.
- Sprint: `speed_scale = 1.5`, producing `9 FPS`.

Because east/west contain nine frames, a normal side-walk cycle lasts 1.5 seconds. The other directions retain six frames at 6 FPS and therefore retain their existing 1-second cycle. This longer side cycle is intentional and approved; matching FPS takes priority over matching cycle duration.

## Runtime integration

`PlayerVisual` validates the new `1728x384` atlas, registers nine frames for `walk_e` and `walk_w`, and retains all existing direction selection and sprint speed-scale behavior. Idle animations remain in the original player atlas and are unchanged.

## Test and capture coverage

Automated tests will assert:

- exactly nine east and nine west walk frames;
- atlas dimensions of `1728x384`;
- exact 151-pixel height and y=184 baseline for all side frames;
- reference-aligned denim channels and luminance;
- exact east/west mirroring;
- distinct adjacent silhouettes through the nine-frame loop;
- side walk base FPS of 6 and sprint speed scale of 1.5.

The deterministic capture tool will render nine-frame east and west strips, updated runtime samples, and an updated direction scale/color comparison. The final review must confirm that the reduced sequence still reads as alternating left/right support without a repeated contact pose.

## Scope

This change only reduces the approved side-walk sequence and synchronizes its runtime/test/documentation contracts. It does not repaint frames, change movement velocity, alter non-side animations, or modify gameplay behavior.
