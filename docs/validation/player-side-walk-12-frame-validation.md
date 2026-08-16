# Player Side Walk 12-Frame Validation

Revalidated on 2026-08-16 in the `feature/painted-production-buildings` worktree.

## Shipped asset and runtime

- Final atlas: `assets/characters/player/player_farmer_side_walk.png`
- Atlas size: `2304x384`
- Cell size: `192x192`
- Row 0: twelve east-facing frames (`walk_e`)
- Row 1: twelve deterministic horizontal mirrors (`walk_w`)
- Walk playback: 12 FPS (`speed_scale = 1.0`)
- Side sprint playback: 18 FPS (`speed_scale = 1.5`)
- Idle remains in the original player atlas and is not part of the side-walk loop.

The final atlas is assembled by `scripts/tools/assemble_player_side_walk.gd`. Each approved east-facing source is independently normalized to an exact 151-pixel painted height, aligned to baseline y=184, and given a bounded denim-only RGB correction derived from the six original east walk frames. The west row is then generated as an exact pixel mirror. The p0 pose and gait meaning are unchanged, but p0 is resampled with the rest of the sequence to satisfy the shared 151-pixel contract; it is no longer byte-identical to the earlier anchor file.

## Scale and color measurements

The final deterministic metrics report produced:

- East heights: `[151, 151, 151, 151, 151, 151, 151, 151, 151, 151, 151, 151]`
- East baselines: `[184, 184, 184, 184, 184, 184, 184, 184, 184, 184, 184, 184]`
- Original east denim mean RGB: `(40.91, 65.52, 98.50)`
- Revised east denim mean RGB: `(43.88, 68.64, 101.94)`
- Original east denim luminance: `62.67/255`
- Revised east denim luminance: `65.78/255`
- Luminance difference: `3.11/255`, inside the `4/255` contract tolerance

The revised side walk now uses the same 151-pixel painted height as the established directional walk art. Its denim remains within `10/255` of the original east reference on every RGB channel.

## Automated gait checks

`godot --headless --path . -s res://tests/run_tests.gd`

- PASS: 2,056 checks
- Confirmed exact 151-pixel height and y=184 baseline for all 24 side cells
- Confirmed reference-aligned denim luminance and RGB channels
- Confirmed 12 frames for `walk_e` and `walk_w`
- Confirmed exact east/west mirroring
- Confirmed one connected painted character per cell and transparent frame gutters
- Confirmed distinct adjacent silhouettes, frame 11-to-0 closure, and opposite-leg half-cycle pairs
- Confirmed east/west walk speed scale 1.0 and sprint speed scale 1.5

Final east and west adjacent lower-body differences are `[70, 88, 83, 32, 52, 85, 41, 55, 112, 96, 73, 97]`. Boot-only differences are `[55, 51, 52, 15, 33, 59, 34, 40, 82, 56, 38, 43]`. Opposite half-cycle differences are `[96, 107, 98, 83, 87, 124]`. These measurements retain a distinct transition at every frame after the scale reduction.

`godot --headless --path . -s res://tests/run_main_gameplay_integration_tests.gd`

- PASS: 1,273 main gameplay integration checks

## Deterministic visual captures

Generated with:

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility -s res://tests/capture_player_side_walk.gd
```

Outputs are generated locally and intentionally not committed:

- `.godot/player-side-walk-validation/east-strip.png` - `2304x240`
- `.godot/player-side-walk-validation/west-strip.png` - `2304x240`
- `.godot/player-side-walk-validation/half-cycle-pairs.png` - `1152x438`
- `.godot/player-side-walk-validation/runtime-walk-sprint.png` - `1152x920`
- `.godot/player-side-walk-validation/direction-scale-color.png` - `1152x690`

The direction comparison places south walk, original east reference, and revised east samples in identical 192-pixel cells. Inspection confirms matching character height and a dark-denim character consistent with the original art while retaining the approved leg and arm sequence. The east and west strips confirm the complete 12-frame gait and exact mirror behavior.

The runtime sheet samples live `PlayerVisual` playback every 1/6 second. The captured east/west walk sequence is `0, 2, 4, 6, 8, 10` at 12 FPS; the sprint sequence is `0, 2, 5, 8, 11, 2` at 18 FPS. The differing sequences and runtime speed assertions verify both cadence paths.

## Wider regression results

- PASS: 106 grid system checks
- PASS: 578 farming system checks
- PASS: 3,456 building system checks
- PASS: 129 economy UI integration checks
- PASS: 1,273 main gameplay integration checks
- `git diff --check`: PASS

Godot emits the existing focused-suite shutdown messages about four leaked `ObjectDB` instances and one resource still in use. The building suite also exercises expected missing-art fallback warnings. All six test runners exit 0 with no assertion or script failure.
