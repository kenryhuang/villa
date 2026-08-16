# Player Side Walk 9-Frame Validation

Revalidated on 2026-08-16 in the `feature/painted-production-buildings` worktree.

## Shipped asset and runtime

- Final atlas: `assets/characters/player/player_farmer_side_walk.png`
- Atlas size: `1728x384`
- Cell size: `192x192`
- Row 0: nine east-facing frames (`walk_e`)
- Row 1: nine deterministic horizontal mirrors (`walk_w`)
- Retained source indices: `[00, 02, 04, 05, 06, 08, 09, 10, 11]`
- Removed source indices: `[01, 03, 07]`
- Side walk playback: 6 FPS, matching every other walk direction
- Side sprint playback: 9 FPS through `speed_scale = 1.5`
- A normal side cycle lasts 1.5 seconds because it contains nine frames at 6 FPS.

The deterministic assembler selects the approved non-contiguous east sources, independently normalizes each pose, applies the existing reference-derived denim correction, and mirrors each result into the west row. No pose was repainted for this reduction.

## Scale, color, and gait measurements

The final metrics report produced:

- East heights: `[151, 151, 151, 151, 151, 151, 151, 151, 151]`
- East baselines: `[184, 184, 184, 184, 184, 184, 184, 184, 184]`
- Original east denim mean RGB: `(40.91, 65.52, 98.50)`
- Revised east denim mean RGB: `(44.11, 68.84, 102.09)`
- Original east denim luminance: `62.67/255`
- Revised east denim luminance: `65.98/255`
- Luminance difference: `3.31/255`, inside the `4/255` tolerance
- Adjacent lower-body differences: `[104, 91, 52, 85, 68, 112, 96, 73, 97]`
- Adjacent boot differences: `[72, 61, 33, 59, 50, 82, 56, 38, 43]`
- Opposite-leg phase-pair differences: `[96, 98, 87, 124]`

The retained sequence removes the two early intermediate poses and the redundant old frame 07 contact pose. Visual inspection confirms that new frame 04 extends the left leg into new frame 05 left-foot support, after which frames 06-08 carry the right leg through and close the loop.

## Automated checks

- PASS: 2,006 focused player checks
- PASS: 1,273 main gameplay integration checks
- PASS: 106 grid system checks
- PASS: 578 farming system checks
- PASS: 3,456 building system checks
- PASS: 129 economy UI integration checks
- `git diff --check`: PASS

The focused suite verifies nine east/west frames, shared 6 FPS timing, 1.5 sprint scaling, exact dimensions, 151-pixel height, y=184 baseline, denim alignment, exact west mirroring, distinct adjacent silhouettes, and the four reviewed opposite-leg phase pairs.

Godot emits the existing focused-suite shutdown messages about four leaked `ObjectDB` instances and one resource still in use. The building suite exercises expected missing-art fallback warnings. No assertion or script failure is present in the final runs.

## Deterministic visual captures

Generated with:

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility -s res://tests/capture_player_side_walk.gd
```

Outputs are generated locally and intentionally not committed:

- `.godot/player-side-walk-validation/east-strip.png` - `1728x240`
- `.godot/player-side-walk-validation/west-strip.png` - `1728x240`
- `.godot/player-side-walk-validation/half-cycle-pairs.png` - `768x438`
- `.godot/player-side-walk-validation/runtime-walk-sprint.png` - `1152x920`
- `.godot/player-side-walk-validation/direction-scale-color.png` - `1152x690`

The east/west strips show all nine sequential poses. The phase-pair sheet verifies alternating support legs despite the odd frame count. The live runtime sheet distinguishes 6 FPS walk from 9 FPS sprint, and the direction sheet confirms the side scale and denim remain aligned with the established player art.

