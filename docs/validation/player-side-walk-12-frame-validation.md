# Player Side Walk 12-Frame Validation

Revalidated on 2026-08-16 in the `feature/painted-production-buildings` worktree.

## Shipped asset and runtime

- Final atlas: `assets/characters/player/player_farmer_side_walk.png`
- Atlas size: `2304×384`
- Cell size: `192×192`
- Row 0: twelve east-facing frames (`walk_e`)
- Row 1: twelve deterministic horizontal mirrors (`walk_w`)
- Walk playback: 12 FPS (`speed_scale = 1.0`)
- Side sprint playback: 18 FPS (`speed_scale = 1.5`)
- Idle remains in the original player atlas and is not part of the side-walk loop.

The final atlas is assembled by `scripts/tools/assemble_player_side_walk.gd`. It validates twelve independent transparent east-facing inputs, preserves p0 pixel-for-pixel without rescaling, applies a common scale with deterministic per-frame alignment corrections to the generated poses, aligns all feet to baseline y=184, and mirrors the east row pixel-for-pixel into the west row. User frame 6 (`east-05`) uses the restored `east-05-left-behind-v1.png`; the later knee composites are intentionally excluded. User frames 7-12 use the separately reviewed continuation poses.

## Automated gait checks

`godot --path . --headless -s res://tests/run_tests.gd`

- PASS: 2,027 checks
- Confirmed 12 frames for `walk_e` and `walk_w`
- Confirmed exact east/west mirroring
- Confirmed stable baseline and transparent frame gutters
- Confirmed one connected painted character per cell
- Confirmed distinct adjacent silhouettes, including frame 11→0
- Confirmed distinct opposite-leg half-cycle pairs 0/6 through 5/11
- Confirmed east/west walk speed scale 1.0 and sprint speed scale 1.5

Final east and west adjacent lower-body differences are `[90, 102, 97, 49, 60, 108, 52, 80, 153, 105, 88, 112]`. Boot-only differences are `[73, 71, 61, 18, 38, 68, 38, 63, 112, 65, 54, 55]` in both rows. Opposite half-cycle differences are `[122, 148, 114, 102, 106, 146]`. General lower-body transitions remain inside 12-115 and boot transitions remain inside 18-80. The reviewed left-support-to-right-lift transition at frame 8->9 has separate limits of 160 and 120 because it includes the deliberate weight drop and leg release. Opposite half-cycle differences remain 20 or greater. A separate pixel comparison confirms final p0 is byte-for-byte identical to its locked anchor image.

`godot --path . --headless -s res://tests/run_main_gameplay_integration_tests.gd`

- PASS: 1,273 main gameplay integration checks

## Deterministic visual captures

Generated with:

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility -s res://tests/capture_player_side_walk.gd
```

Outputs (generated locally and intentionally not committed):

- `.godot/player-side-walk-validation/east-strip.png` — `2304×240`
- `.godot/player-side-walk-validation/west-strip.png` — `2304×240`
- `.godot/player-side-walk-validation/half-cycle-pairs.png` — `1152×438`
- `.godot/player-side-walk-validation/runtime-walk-sprint.png` — `1152×920`

Original-resolution review accepted the final semantic chain: p4 anchors the foreground right leg as the support leg; restored p5 keeps that right foot planted while the background left leg crosses; p6 extends the left leg; p7 reaches left-foot contact; p8 transfers weight to the left leg; p9 releases the right foot; p10 carries the foreground right leg past the left support leg; and p11 extends the right leg before the loop closes at p0. The accepted sheet keeps a common character scale and baseline, preserves anatomical leg identity through both half-cycles, limits soft-alpha edge pixels, and retains the hand-painted farmer identity. The west strip is the exact mirror of the east strip.

The runtime sheet samples the live `PlayerVisual` every 1/6 second instead of selecting predetermined frame indices. The captured east/west walk sequence is `0, 2, 4, 6, 8, 10` at 12 FPS; the sprint sequence is `0, 2, 5, 8, 11, 2` at 18 FPS. The differing sequences, together with runtime `speed_scale` assertions of 1.0 and 1.5, verify both cadence paths.

## Wider regression results

- PASS: 106 grid system checks
- PASS: 578 farming system checks
- PASS: 3,456 building system checks
- PASS: 129 economy UI integration checks
- PASS: 1,273 main gameplay integration checks
- `git diff --check`: PASS

The full economy runner reports four existing hive/flower failures out of 64,700 checks. The same four failures reproduce in an isolated `BuildingEconomyEffectsTest` run (4 of 229): mature-flower radius count, boosted hive output, same-day hive settlement, and full-storage pausing. The side-walk change set contains no economy, hive, flower, crop, or production files, so this regression is recorded separately and was not modified as part of the player animation work.

Godot also emits the existing shutdown message `1 resources still in use at exit` after several otherwise-passing headless suites. No new script error is present.
