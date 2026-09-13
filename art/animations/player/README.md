# Player locomotion source

Gameplay speed is fixed at **3 m/s** for ordinary movement and **6 m/s** with Shift.
The current ordinary movement uses a restrained light jog instead of speeding up
the former slow walk to 2.77 times its authored rate.

Pose source: [Quaternius Universal Animation Library 1 Standard v3.0](https://quaternius.itch.io/universal-animation-library),
under CC0 1.0. See [QUATERNIUS_LICENSE.txt](QUATERNIUS_LICENSE.txt).
The official Standard download supplies `Unreal-Godot/UAL1_Standard.glb`.
`quaternius_locomotion.json` contains 61 rest-space samples of Walk_Loop,
Jog_Fwd_Loop and Sprint_Loop. It does not contain the reference mannequin.

To re-extract, run Blender in background mode with
`scripts/tools/extract_player_locomotion.py -- path/to/UAL1_Standard.glb`.
The normal player rebuild reads the JSON locally; no download is needed.

`scripts/tools/player_locomotion.py` retargets the animation through the existing
bone hierarchy. Ordinary locomotion mixes relaxed walk upper-body motion with the
jog, reduces the source's vertical pelvis displacement, and adapts contact timing,
reach and heel roll for the farmer's proportions and boots. Sprint uses the sprint
clip with reduced bounce. Finger curls are softened. Neither motion adds a separate
push-off bounce. Source limb timing is retained through the recovery-time remap;
leg IK maintains forward knee poles and correct boot clearance.

The authored clips remain Walk = 1.2 s and Run = 0.8 s. Their measured contact speed
references are 1.73 and 4.34 m/s, giving default playback rates of 1.73 and 1.38.
These are animation calibration values, not changes to gameplay movement speed.

The player now bakes and imports at 120 Hz (Walk 144 intervals, Run 96), with
a short periodic 24 ms pose filter to soften IK/clamp velocity changes and the
loop seam. Rotation samples use consistent quaternion signs and are normalized.
Idle and Work keep their original 3 s / 1 s durations. The added continuity
regression checks sample the imported model, including velocity across the seam;
the full gait suite now has 477 checks. The previous library-based version is
backed up in `tmp/player-smooth-baseline/`.

The [smoothing comparison](../../concepts/player/player-smoothing-compare.gif)
uses the same cadence on both sides and an exact number of complete cycles,
avoiding the extra loop hitch caused by the earlier fixed two-second GIF cut.

The pre-change 3/6 m/s source, model, scripts and gait tests are backed up locally
in `tmp/player-speed36-baseline/`. Capture previews with
`tests/capture_player_revision.gd -- --motion`, then encode them with
`scripts/tools/encode_player_motion.py`. Capture manifests prevent older leftover
PNG frames from being appended to a new shorter animation.
