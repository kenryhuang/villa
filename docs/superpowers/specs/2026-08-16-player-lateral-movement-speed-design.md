# Player Lateral Movement Speed Design

## Goal

Reduce east/west world movement so its screen-space travel matches the foreshortened north/south movement, while keeping the approved nine-frame animation at 9 FPS walk and 13.5 FPS sprint.

## Root cause

The orthographic camera views the ground from an elevated angle. Movement along camera forward is foreshortened to roughly two thirds of its world distance on screen, while movement along camera right retains nearly its full screen distance. At the same world speed, lateral movement therefore crosses substantially more screen pixels per second and produces visible motion softness that does not appear during north/south movement.

## Movement contract

- Add a pure lateral movement multiplier of `0.67`.
- Keep pure forward/back movement at `1.0`.
- Interpolate continuously from `1.0` to `0.67` using the absolute camera-right component of the intended planar direction.
- Apply the multiplier uniformly to the final speed, preserving the requested direction instead of bending diagonal input.
- Apply the same calculation to manual movement and automatic path movement.
- Pure lateral walk speed becomes `2.01` from the existing `3.0`.
- Pure lateral sprint speed becomes `3.35` from the existing `5.0`.

## Animation contract

- Keep side walk at 9 FPS.
- Keep side sprint at 13.5 FPS.
- Keep `speed_scale = 1.0` for walk and `1.5` for sprint.
- Do not alter side frames, atlas dimensions, filtering, colors, scale, or baselines.

## Implementation boundary

Expose a deterministic static speed-scale helper on `PlayerController`. It accepts the intended world direction and camera-right vector, handles empty/invalid vectors by returning `1.0`, and returns a scalar in `[0.67, 1.0]`. The physics loop multiplies its existing walk/sprint speed by this scalar before calculating target velocity and acceleration.

## Verification

Tests will cover pure lateral, pure forward, diagonal, zero-direction, and zero-camera-right cases. Player visual tests will continue asserting 9/13.5 FPS. Focused player, player logic, main gameplay, grid, farming, building, and economy UI runners must pass before completion.

