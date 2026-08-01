# Fixed Camera Direction Design

## Goal

Keep the current hand-painted 2.5D presentation stable by locking the camera to its existing default isometric direction. Preserve player following and wheel zoom, and convert middle-mouse dragging from orbit rotation into map panning.

## Current Behavior and Root Cause

`CameraRig` currently changes `yaw` from the `camera_left` and `camera_right` actions (Q/E) and from horizontal middle-mouse dragging. Buildings, trees, crops, construction feedback, and progress sprites use camera-facing billboards. When the camera orbits, these sprites turn to face it, which makes the world appear to rotate even though the world nodes keep their transforms.

## Approaches Considered

1. **Lock the camera and provide middle-drag panning — selected.** This matches the existing single-view hand-painted assets, keeps navigation useful, and requires no new art.
2. Keep camera rotation and add four-direction sprite variants. This would preserve Q/E, but every rotatable building, tree, crop, and construction stage would need additional coordinated artwork.
3. Replace billboard visuals with true 3D models. This supports arbitrary camera angles, but is a much larger art and rendering change and is outside the current scope.

## Interaction Design

- Camera direction remains fixed at the current default yaw, `-PI / 4`.
- Q and E no longer change camera direction.
- Holding the middle mouse button and dragging pans the map in the camera ground plane.
- Panning uses grab-map behavior: the world follows the cursor while dragging.
- The pan offset is relative to the followed player. Player movement continues to move the camera while preserving the user's current pan offset.
- Mouse-wheel zoom remains unchanged, including the existing zoom limits.
- Releasing the middle mouse button stops panning.
- No new reset-pan shortcut, map-bound clamp, inertia, or easing is added in this change.

## Architecture

`CameraRig` remains the sole owner of camera input and transform calculation.

- Keep a fixed `yaw` value for camera basis calculations and compatibility with existing capture scripts.
- Remove runtime mutations of `yaw` from `_process()` and middle-mouse motion.
- Add a planar `pan_offset` maintained in world X/Z coordinates.
- `_process()` follows `target.global_position + pan_offset` instead of only `target.global_position`.
- Convert mouse motion into a world-space planar delta using `get_planar_right()`, `get_planar_forward()`, viewport height, and current orthographic size so panning sensitivity remains consistent across zoom levels and resolutions.
- `_apply_camera_transform()` continues to place the camera at the fixed orbit offset and look at the rig center.

No billboard, building, tree, crop, save, or construction code changes are required.

## Testing

Add camera-focused regression checks that verify:

- Q/E input no longer changes `yaw` or the camera orbit direction.
- Middle-mouse motion changes only `pan_offset`, not `yaw`.
- Pan conversion follows the fixed camera's planar right/forward axes and scales with orthographic size.
- Target following uses the target position plus the retained pan offset.
- Wheel zoom behavior and clamping remain unchanged.
- Existing camera math, grid, building, farming, and main integration suites remain green.

Run a gameplay capture after implementation and visually confirm that the hand-painted world no longer appears to rotate while normal follow, zoom, and middle-drag navigation remain available.

## Scope Boundaries

- Input map entries for `camera_left` and `camera_right` may remain defined for future use; they will have no runtime consumer in `CameraRig`.
- This change does not create directional sprite variants or 3D replacements.
- This change does not alter player movement direction calculations; they continue to use the fixed camera basis.
