# Player Side Walk Transition Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the visually duplicated and discontinuous poses in the existing 12-frame side walk while preserving its atlas format, farmer identity, exact west mirrors, and 12/18 FPS runtime integration.

**Architecture:** Keep p0 and p6 as opposite contact anchors, author the remaining poses as five explicit opposite-phase pairs, and assemble twelve independent east-facing frame files before deriving west by deterministic mirroring. Automated tests inspect only the boot/lower-shin region for duplicate and jump detection; numbered visual strips remain the authority for left/right leg identity and the approach→crossing→extension semantics.

**Tech Stack:** Godot 4.7 GDScript, `Image`/`SpriteFrames`, built-in image generation precise edits, PNG alpha assets, existing custom test runners.

---

### Task 1: Make the current semantic defects fail in the boot region

**Files:**
- Modify: `tests/test_player_visual.gd:300-365`
- Test: `assets/characters/player/player_farmer_side_walk.png`

- [ ] **Step 1: Add a boot-only silhouette difference helper**

Add a helper that ignores hats, arms, torso texture, and upper trouser changes:

```gdscript
func _boot_silhouette_difference(first: Image, second: Image) -> int:
	var difference := 0
	for y in range(37, 48):
		for x in range(5, 43):
			var first_opaque := first.get_pixel(x, y).a > 0.10
			var second_opaque := second.get_pixel(x, y).a > 0.10
			if first_opaque != second_opaque:
				difference += 1
	return difference
```

- [ ] **Step 2: Add named phase-progression assertions**

After building the twelve 48×48 east silhouettes, assert boot motion for every transition and call out the reported failures by name:

```gdscript
var boot_differences: Array[int] = []
for frame_index in SIDE_WALK_FRAME_COUNT:
	boot_differences.append(
		_boot_silhouette_difference(silhouettes[frame_index], silhouettes[(frame_index + 1) % SIDE_WALK_FRAME_COUNT])
	)
assertions.truthy(boot_differences.min() >= 18, "every side-walk frame advances a boot: %s" % boot_differences)
assertions.truthy(boot_differences.max() <= 80, "side-walk boots never jump across a missing phase: %s" % boot_differences)
for transition in [
	{"from": 1, "to": 2, "name": "left boot leaves the ground"},
	{"from": 3, "to": 4, "name": "left boot crosses the right support leg"},
	{"from": 5, "to": 6, "name": "left boot changes from extension to contact"},
	{"from": 6, "to": 7, "name": "left boot loads after contact"},
	{"from": 7, "to": 8, "name": "right boot leaves the ground"},
	{"from": 9, "to": 10, "name": "right boot crosses the left support leg"},
]:
	var change := _boot_silhouette_difference(silhouettes[transition.from], silhouettes[transition.to])
	assertions.truthy(change >= 18, "%s (%d)" % [transition.name, change])
```

- [ ] **Step 3: Run the focused suite and verify RED**

Run:

```powershell
godot --path . --headless -s res://tests/run_tests.gd
```

Expected: FAIL on at least p1→p2 or p3→p4 boot progression and on the p4→p5/p5→p6 region; no parser or out-of-bounds error.

- [ ] **Step 4: Commit the failing semantic contract**

```powershell
git add tests/test_player_visual.gd
git commit -m "test: detect repeated side-walk boot phases"
```

---

### Task 2: Author five controlled opposite-phase pose pairs

**Files:**
- Reference: `assets/characters/player/player_farmer_side_walk.png`
- Temporary: `tmp/player-side-walk/revision/anchor-00.png`
- Temporary: `tmp/player-side-walk/revision/anchor-06.png`
- Temporary: `tmp/player-side-walk/revision/pair-01-07.png` through `pair-05-11.png`
- Temporary: `tmp/player-side-walk/revision/frames/east-00.png` through `east-11.png`

- [ ] **Step 1: Extract and lock contact anchors p0 and p6**

Extract the current east p0 and p6 cells without rescaling. Inspect them at original resolution and retain them only if p0 has right foot forward/left toe behind and p6 has left foot forward/right toe behind. Copy them to `anchor-00.png`, `anchor-06.png`, and revision frame slots 00/06.

- [ ] **Step 2: Generate phase pair p1/p7 — loading response**

Use the current farmer atlas plus both anchors as edit/style references. Generate exactly two right-facing full-body panels on solid `#ff00ff`: p1 keeps the right foot planted while the left heel lifts; p7 keeps the left foot planted while the right heel lifts. Feet remain separated. Reject neutral standing or identical panels.

- [ ] **Step 3: Generate phase pair p2/p8 — opposite boot fully airborne**

Generate p2 with the right leg nearly vertical as support and the entire left boot airborne behind it; generate p8 with the left leg as support and the entire right boot airborne behind it. These must visibly advance beyond p1/p7 without approaching the body center yet.

- [ ] **Step 4: Generate phase pair p3/p9 — boot approaches the support ankle**

Generate p3 with the left boot moving close behind the right ankle and p9 with the right boot moving close behind the left ankle. The moving boot is low and behind; it has not crossed the support leg.

- [ ] **Step 5: Generate phase pair p4/p10 — crossing under the hips**

Generate p4 with the left boot passing behind the right support leg directly under the hips, and p10 with the right boot passing behind the left support leg. This phase must differ visibly from the approach phase but must not form a forward stride.

- [ ] **Step 6: Generate phase pair p5/p11 — short forward extension**

Generate p5 with the left boot only slightly ahead of the right support leg and p11 with the right boot only slightly ahead of the left support leg. Avoid the previous full split-stride jump; these poses lead into p6/p0 contact.

- [ ] **Step 7: Chroma-key and inspect each extracted panel immediately**

For every approved pair, run the installed chroma-key helper with border auto-detection, soft matte, thresholds 12/220, and despill. Split into the declared frame slots. Compare each new frame with its preceding frame, following frame, and opposite-phase partner before moving to the next pair. Do not commit `tmp/` inputs.

---

### Task 3: Assemble from independent frame inputs and make tests green

**Files:**
- Modify: `scripts/tools/assemble_player_side_walk.gd`
- Modify: `assets/characters/player/player_farmer_side_walk.png`
- Test: `tests/test_player_visual.gd`

- [ ] **Step 1: Change the assembler input boundary**

Replace the 4×3 contact-sheet reader with exactly twelve validated files under `res://tmp/player-side-walk/revision/frames`. Keep the existing common-scale calculation, y=184 baseline, transparent-corner rejection, row-0 assembly, and exact row-1 mirroring:

```gdscript
const INPUT_DIR := "res://tmp/player-side-walk/revision/frames"

for index in FRAME_COUNT:
	var source := Image.load_from_file(ProjectSettings.globalize_path(
		INPUT_DIR.path_join("east-%02d.png" % index)
	))
	if source == null or source.is_empty() or not _has_transparent_corners(source):
		_fail("Missing or invalid east frame %02d." % index)
		return
	var used := source.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		_fail("East frame %02d is empty." % index)
		return
	maximum_bounds = maximum_bounds.max(used.size)
	sources.append(source)
```

- [ ] **Step 2: Assemble and import the revised atlas**

Run:

```powershell
godot --path . --headless -s res://scripts/tools/assemble_player_side_walk.gd
godot --path . --headless --import
```

Expected: the atlas remains exactly `2304×384`; east contains twelve revised frames and west contains their exact mirrors.

- [ ] **Step 3: Run the focused suite and correct art frame-by-frame**

Run:

```powershell
godot --path . --headless -s res://tests/run_tests.gd
```

Expected: PASS. If a boot transition fails, regenerate only the named pose pair; do not relax the 18/80 thresholds to accept a duplicate or jump.

- [ ] **Step 4: Commit the revised art and assembler**

```powershell
git add assets/characters/player/player_farmer_side_walk.png scripts/tools/assemble_player_side_walk.gd tests/test_player_visual.gd
git commit -m "fix: add missing side-walk crossing poses"
```

---

### Task 4: Re-capture, visually review, and finalize validation

**Files:**
- Modify: `tests/capture_player_side_walk.gd`
- Modify: `docs/validation/player-side-walk-12-frame-validation.md`
- Modify: `docs/superpowers/plans/2026-08-14-player-side-walk-transition-revision.md`

- [ ] **Step 1: Regenerate deterministic strips**

Run:

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility -s res://tests/capture_player_side_walk.gd
```

Expected: numbered east/west strips, half-cycle pairs, and runtime 12/18 FPS samples are regenerated under `.godot/player-side-walk-validation/`.

- [ ] **Step 2: Perform the semantic review that automation cannot prove**

Inspect at original resolution and explicitly accept or reject each chain:

- p0→p1→p2: right contact/loading remains stable while the left boot lifts;
- p2→p3→p4→p5: left boot moves airborne-behind → near right ankle → across center → slightly forward;
- p5→p6→p7→p8: left extension → contact → loading while right boot becomes airborne;
- p8→p9→p10→p11→p0: exact opposite-leg progression and clean loop closure.

- [ ] **Step 3: Run focused and main integration regression**

```powershell
godot --path . --headless -s res://tests/run_tests.gd
godot --path . --headless -s res://tests/run_main_gameplay_integration_tests.gd
git diff --check
```

Expected: 1,963+ focused checks and 1,273 main gameplay integration checks pass; no script error or whitespace error.

- [ ] **Step 4: Update validation evidence and commit**

Record boot-difference values, reviewed transition chains, capture dimensions, 12/18 FPS results, and the unchanged known isolated hive regression. Mark this revision plan complete and commit:

```powershell
git add tests/capture_player_side_walk.gd tests/capture_player_side_walk.gd.uid docs/validation/player-side-walk-12-frame-validation.md docs/superpowers/plans/2026-08-14-player-side-walk-transition-revision.md
git commit -m "docs: validate revised side-walk transitions"
```

---

## Completion checklist

- [ ] p1/p2 and p3/p4 have visibly different boot positions.
- [ ] p4→p5 contains the crossing-to-short-extension transition instead of a split-stride jump.
- [ ] p5/p6/p7/p8 are four distinct stages.
- [ ] The opposite half-cycle has the same transition granularity.
- [ ] Boot-only automated checks and numbered-strip semantic review both pass.
- [ ] The game still uses the `2304×384` atlas at 12 FPS walk and 18 FPS sprint.
