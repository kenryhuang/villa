# Player Side-Walk Leg Identity Revision

## Goal

Replace user-facing frames 6-12 (`east-05` through `east-11`) without changing user-facing frames 1-5 (`east-00` through `east-04`). The revised frames must preserve anatomical left/right identity through the hip and must not infer leg identity from trouser brightness or boot position.

## Locked Anatomy

- User frame 5 (`east-04`) is the immutable pose reference.
- The character's right leg is the foreground leg.
- The character's left leg is the background leg.
- Foreground/background ownership remains fixed for every generated frame.
- Occlusion at the hip, thigh, knee, shin, and boot must agree with that ownership.

## Pose Sequence

- Frame 5 (`east-04`): foreground right leg bears weight; background left leg is about to cross.
- Frame 6 (`east-05`): foreground right foot remains planted; only the background left leg moves and crosses behind the right shin.
- Frame 7 (`east-06`): background left leg steps forward and contacts the ground; right leg remains anatomically foreground.
- Frame 8 (`east-07`): weight transfers to the left leg; foreground right heel begins to lift.
- Frame 9 (`east-08`): foreground right leg lifts behind the supporting left leg.
- Frame 10 (`east-09`): foreground right leg crosses forward while retaining foreground ownership.
- Frame 11 (`east-10`): foreground right leg advances beyond the left leg.
- Frame 12 (`east-11`): foreground right foot reaches forward contact and leads into frame 1 (`east-00`).

## Arm Sequence

- Beginning in frame 6, the foreground right arm swings forward while the background left arm swings backward.
- The arm motion remains opposite the stepping leg: the right arm advances as the left leg advances and accepts weight.
- After the left foot lands and bears weight, the arms continue smoothly as the right foot begins its crossing half-cycle.
- Arm ownership follows the same fixed depth rule as the legs: right arm foreground, left arm background.
- The second half-cycle reuses the timing of `east-00` through `east-04` with the stepping legs exchanged, without copying or swapping anatomical depth.

## Generation Workflow

1. Generate only frame 6 (`east-05`) from frame 5 (`east-04`) using a high-fidelity image edit.
2. Lock the torso, face, arms, foreground right thigh, right shin, right boot, scale, silhouette, lighting, and transparent background.
3. Move only the background left leg into the behind-shin crossing pose.
4. Review frame 6 at enlarged scale. Reject it if the hip connection, occlusion order, or supporting foot indicates a left/right swap.
5. Generate frames 7-12 (`east-06` through `east-11`) sequentially only after frame 6 is accepted, carrying the same anatomical ownership into every prompt and review.

## Validation

- Human review is authoritative for anatomical identity and occlusion.
- Automated checks continue to enforce atlas size, frame count, east/west mirroring, nonduplicate boot motion, transition bounds, and p0 anchor identity.
- The final atlas remains `2304x384`, with east on row 0 and deterministic mirrored west on row 1.

## Scope

- Preserve `east-00` through `east-04` exactly.
- Replace `east-05` through `east-11` only.
- Do not relax transition thresholds to accept an anatomically incorrect frame.
- Do not commit changes unless explicitly requested.
