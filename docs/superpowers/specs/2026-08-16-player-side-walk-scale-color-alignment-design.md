# Player Side-Walk Scale and Color Alignment Design

## Goal

Make east/west walking match the existing player atlas when changing direction. Every side-walk frame must use the same apparent character height as the established directional walk art and must return the overalls to the original dark-blue side-view palette.

## Measured Baseline

- Existing directional walk frames: approximately 151 pixels tall in every direction.
- Current twelve-frame side walk: 177-182 pixels tall, averaging 178.2 pixels.
- Existing east/west denim luminance: 63.2 under the player visual test mask.
- Current twelve-frame east denim luminance: 103.3 on average.
- All frames use a 192 by 192 cell and a planted-foot baseline at y=184.

The runtime uses the same `pixel_size` for every direction, so the discrepancy originates in the side-walk raster and its assembler rather than direction-specific runtime scaling.

## Chosen Approach

Apply deterministic scale normalization and denim color transfer in `scripts/tools/assemble_player_side_walk.gd`. Preserve all approved poses and their order. Do not regenerate or repaint limbs.

### Scale Normalization

- Normalize every east-facing side-walk source to exactly 151 painted pixels in height.
- Preserve each frame's aspect ratio.
- Align the resulting frame to the existing y=184 baseline.
- Remove the special p0 pixel-identity exception and the p5 1.02 scale adjustment because both conflict with a direction-independent 151-pixel height.
- Retain only horizontal offsets that remain necessary after normalization, recalibrating them for the smaller scale if continuity metrics require it.
- Derive west frames by exact horizontal mirroring after all east-frame transformations.

The p0 pose, silhouette, and limb ownership remain unchanged, but its pixels are resampled to the shared scale. The old requirement that p0 remain byte-identical is replaced by a semantic anchor requirement.

### Denim Color Transfer

Use the six original east-facing walk frames in `player_farmer_atlas.png` as the side-view color reference.

- Select denim pixels with a deterministic blue-channel mask that excludes skin, shirt, hat, boots, hair, and outlines.
- Measure the reference denim channel means and luminance from the original east walk.
- For each new side-walk frame, apply a bounded per-channel gain to masked denim pixels so its mean color approaches the reference.
- Preserve local highlights, shadows, seams, and painted texture by scaling channels rather than replacing pixels with a flat color.
- Clamp gain and output channels to prevent clipping or unstable frame-to-frame flashes.
- Apply the transfer before final downscaling so the 151-pixel result receives consistent antialiasing.

## Runtime and Asset Boundaries

- Keep `PlayerVisual.PIXEL_SIZE` unchanged.
- Keep all movement speeds, animation frame counts, FPS values, direction mapping, and collision behavior unchanged.
- Keep the atlas at 2304 by 384 with twelve east frames and twelve exact west mirrors.
- Do not modify the approved gait poses, anatomical leg ownership, arm swing, or loop timing.

## Validation

Add failing visual-contract checks before changing the assembler:

1. Every east and west side-walk frame has a painted height of exactly 151 pixels and ends at baseline y=184.
2. Side-walk denim luminance and channel means stay within a small tolerance of the original east-facing reference.
3. East/west mirroring remains pixel-exact.
4. Existing adjacent-pose, boot progression, half-cycle, alpha, and runtime FPS checks continue to pass.
5. A deterministic direction-comparison capture shows south walk, original east reference, and revised twelve-frame east walk in identical 192 by 192 cells.

Run the focused player suite, main gameplay integration suite, wider grid/farming/building/economy UI regressions, anchor semantics, visual captures, and `git diff --check` before completion.

## Non-Goals

- No new walk poses or image generation.
- No changes to up/down or diagonal art.
- No runtime shader, per-direction sprite scale, or global player tint.
- No attempt to redesign clothing, proportions, facial features, or animation timing.
