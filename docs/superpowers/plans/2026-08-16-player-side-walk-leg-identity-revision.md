# Player Side-Walk Leg Identity Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace user frames 6-12 (`east-05` through `east-11`) with a walk sequence that keeps the right leg anatomically foreground and the left leg anatomically background, beginning with a user-approved frame 6 where the left leg crosses behind the planted right leg.

**Architecture:** Treat user frame 5 (`east-04`) as the immutable anatomical anchor and use one high-fidelity image edit per new frame. Stop after user frame 6 (`east-05`) for visual approval; only then continue frames 7-12 (`east-06` through `east-11`), normalize the accepted outputs, assemble the deterministic east/west atlas, and run focused and integration validation.

**Tech Stack:** Built-in image generation/editing, Godot 4.7 GDScript image tools, PNG sprite atlas validation, browser visual companion.

---

### Task 1: Generate and Review the Frame 6 Anatomy Checkpoint

**Files:**
- Read: `tmp/player-side-walk/revision/frames/east-04.png`
- Create: `tmp/player-side-walk/revision/candidates/east-05-left-behind-v1.png`
- Preserve: `assets/characters/player/player_farmer_side_walk.png`

- [x] **Step 1: Inspect user frame 5 at enlarged scale**

Use the local image viewer on `tmp/player-side-walk/revision/frames/east-04.png` and identify the foreground right hip, thigh, shin, and planted boot as one connected limb. Identify the background left leg as the only movable limb.

- [x] **Step 2: Generate one user-frame-6 candidate from frame 5**

Use the built-in image edit tool with `east-04.png` as the edit target and this complete prompt:

```text
Use case: precise-object-edit
Asset type: single transparent 2D game walk-animation frame, user frame 6 / atlas east-05
Primary request: create the immediate next pose after this exact user-frame-5 / east-04 reference. Keep the anatomical RIGHT leg in the FOREGROUND and fully weight-bearing. Keep its hip connection, thigh, knee, shin, and boot planted in the same place. Move only the anatomical LEFT leg, which must remain in the BACKGROUND, so it crosses behind the right shin and begins passing forward.
Style/medium: preserve the exact hand-painted farmer sprite style, proportions, face, hat, clothing, lighting, and edge treatment.
Composition/framing: same east-facing side profile, same canvas scale, same baseline, full body visible.
Constraints: right leg is foreground; left leg is background; right shin occludes part of the crossing left shin; right boot stays flat on the ground; do not reconnect or swap the legs at the pelvis; do not move the torso, head, arms, or right leg; transparent background; one character; no text; no labels; no watermark.
Avoid: left leg bearing weight, right leg swinging forward, crossed pelvis wiring, duplicated feet, merged boots, camera changes, style changes.
```

- [x] **Step 3: Save the candidate without changing the atlas**

Copy the generated PNG to `tmp/player-side-walk/revision/candidates/east-05-left-behind-v1.png`. Do not replace `frames/east-05.png` and do not run the atlas assembler.

- [x] **Step 4: Reject or accept user frame 6 by anatomy**

Show user frame 5 (`east-04`) and candidate frame 6 (`east-05`) side by side at enlarged scale. Accept only when all four statements are visibly true:

```text
1. The right leg remains connected to the foreground side of the pelvis.
2. The right shin is in front of and occludes the crossing left shin.
3. The right boot remains planted and weight-bearing.
4. The left leg is the only leg moving forward behind the right leg.
```

Expected: the user explicitly approves frame 6 before Task 2 starts.

---

### Task 2: Generate User Frames 7-12 Sequentially

**Files:**
- Create: `tmp/player-side-walk/revision/candidates/east-06-left-contact.png`
- Create: `tmp/player-side-walk/revision/candidates/east-07-left-support.png`
- Create: `tmp/player-side-walk/revision/candidates/east-08-right-lift.png`
- Create: `tmp/player-side-walk/revision/candidates/east-09-right-cross.png`
- Create: `tmp/player-side-walk/revision/candidates/east-10-right-advance.png`
- Create: `tmp/player-side-walk/revision/candidates/east-11-right-contact.png`

For motion timing, use `east-00` through `east-04` as opposite-half-cycle references: `east-06` mirrors the phase of `east-00` with the stepping legs exchanged, `east-07` mirrors `east-01`, and so on through `east-10` mirroring `east-04`. Keep right limbs foreground and left limbs background rather than swapping depth. Beginning from approved `east-05`, swing the foreground right arm forward and the background left arm backward as the left leg advances.

- [x] **Step 1: Generate frame 7 (`east-06`) from approved frame 6**

Keep the right leg foreground and the left leg background. Move the background left foot forward into ground contact while preserving the same pelvis ownership and occlusion order.

Move the foreground right hand forward and the background left hand backward, maintaining opposite arm/leg motion.

- [x] **Step 2: Generate frame 8 (`east-07`) from frame 7**

Transfer weight onto the background left leg while keeping it anatomically background; begin lifting the heel of the foreground right boot.

Continue the right arm forward and left arm backward without changing their foreground/background ownership.

- [x] **Step 3: Generate frame 9 (`east-08`) from frame 8**

Keep the background left leg supporting and lift the foreground right leg low behind it.

- [x] **Step 4: Generate frame 10 (`east-09`) from frame 9**

Swing the foreground right leg through the crossing pose while preserving foreground ownership at the pelvis and shin.

- [x] **Step 5: Generate frame 11 (`east-10`) from frame 10**

Advance the foreground right boot beyond the left leg while retaining foreground ownership.

- [x] **Step 6: Generate frame 12 (`east-11`) from frame 11**

Place the foreground right boot forward for contact, forming a smooth transition into frame 1 (`east-00`).

- [x] **Step 7: Review the complete user-frame-5-to-12 chain**

Reject any frame where leg ownership changes at the pelvis, the foreground/background occlusion reverses, or the wrong boot becomes the moving boot.

Also reject any frame where the right arm fails to begin swinging forward from frame 6, the left arm fails to swing backward, or an arm changes anatomical depth at the shoulder.

---

### Task 3: Normalize and Assemble Accepted Frames

**Files:**
- Modify: `tmp/player-side-walk/revision/frames/east-05.png`
- Modify: `tmp/player-side-walk/revision/frames/east-06.png`
- Modify: `tmp/player-side-walk/revision/frames/east-07.png`
- Modify: `tmp/player-side-walk/revision/frames/east-08.png`
- Modify: `tmp/player-side-walk/revision/frames/east-09.png`
- Modify: `tmp/player-side-walk/revision/frames/east-10.png`
- Modify: `tmp/player-side-walk/revision/frames/east-11.png`
- Modify: `assets/characters/player/player_farmer_side_walk.png`

- [x] **Step 1: Normalize accepted candidate backgrounds**

Run:

```powershell
godot --headless --path . --log-file .godot\normalize-leg-identity.log -s res://tmp/player-side-walk/revision/normalize_magenta_background.gd
```

Expected: accepted `east-05` through `east-11` outputs have transparent corners and retain their painted edges.

- [x] **Step 2: Install accepted frames**

Copy only the reviewed `east-05` through `east-11` images into `tmp/player-side-walk/revision/frames/`. Preserve `east-00` through `east-04` byte-for-byte.

- [x] **Step 3: Assemble and import**

Run:

```powershell
godot --headless --path . --log-file .godot\assemble-leg-identity.log -s res://scripts/tools/assemble_player_side_walk.gd
godot --headless --path . --import
```

Expected: `player_farmer_side_walk.png` remains exactly `2304x384`; row 1 remains the deterministic mirror of row 0.

---

### Task 4: Validate the Revised Atlas

**Files:**
- Modify: `docs/validation/player-side-walk-12-frame-validation.md`
- Use: `tests/capture_player_side_walk.gd`

- [x] **Step 1: Verify the locked p0 anchor**

Run:

```powershell
godot --headless --path . --log-file .godot\verify-anchor-leg-identity.log -s res://tmp/player-side-walk/revision/verify_anchor_pixels.gd
```

Expected: `PASS: p0 is pixel-identical to its locked anchor`.

- [x] **Step 2: Run the focused suite**

Run:

```powershell
godot --headless --path . --log-file .godot\player-focused-leg-identity.log -s res://tests/run_tests.gd
```

Expected: `PASS: 1979 checks` or a higher count, with no failures.

- [x] **Step 3: Capture and inspect the animation**

Run:

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility -s res://tests/capture_player_side_walk.gd
```

Inspect user frames 5-12 in `.godot/player-side-walk-validation/east-strip.png` and the runtime walk/sprint capture. Human anatomical review remains authoritative.

- [x] **Step 4: Run integration regression**

Run:

```powershell
godot --headless --path . --log-file .godot\main-gameplay-leg-identity.log -s res://tests/run_main_gameplay_integration_tests.gd
git diff --check
```

Expected: `PASS: 1273 main gameplay integration checks` and no whitespace errors.

- [x] **Step 5: Record evidence without committing**

Update the validation document with the accepted leg ownership, transition metrics, capture dimensions, and test counts. Leave all changes uncommitted unless the user explicitly requests a commit.
