# Single-Click Tree Felling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make five tree variants fall in one two-second atomic action for their full remaining wood, with variant-matched hand-painted frames/stumps, root-level axe contact, and green/red axe-hover eligibility.

**Architecture:** A dependency-free `TreeFellingCatalog` owns the five-variant whitelist, atlas manifest, and felling duration so scatter generation, scene construction, and tree instances share one contract without circular preloads. `TreeInstance` owns batch reward quantity, felling presentation, stump state, and target APIs. `ToolSystem` remains the atomic transaction boundary but uses the target preview's quantity; `GatheringController` uses a target-specific duration; `PlayerActionController` emits axe-hover eligibility; `GatheringFeedback` renders hover color, felling progress, root axe placement, and actual reward quantity. Save normalization explicitly retires two old resource-tree IDs while backfilling newly eligible stable tree IDs.

**Tech Stack:** Godot 4.7.1, GDScript, Sprite3D/AtlasTexture, AI-generated transparent PNG atlases, custom GDScript tests, deterministic Windows captures.

---

### Task 1: Lock the five-variant eligibility contract

**Files:**
- Create: `scripts/world/tree_felling_catalog.gd`
- Modify: `scripts/world/tree_scatter.gd`
- Modify: `scripts/world/tree_instance.gd`
- Modify: `tests/test_tree_scatter.gd`
- Modify: `tests/test_tree_instance.gd`

- [ ] **Step 1: Write failing eligibility tests**

Assert the exact variant table:

```gdscript
const expected := {
	"pine-small": true, "pine-tall": true,
	"canopy-small": true, "canopy-medium": true,
	"round-small": true,
	"fruit": false, "oak-large": false, "pine-large": false,
	"round-medium": false, "yellow": false,
}
for variant in expected:
	assertions.equal(
		TreeFellingCatalogScript.is_variant_choppable(variant), expected[variant],
		"eligibility is variant-driven for %s" % variant
	)
```

Also assert every generated tree placement uses the variant result, including scattered trees outside the old resource forest.

- [ ] **Step 2: Run `godot --path . --headless -s res://tests/run_tests.gd`**

Expected: FAIL because `is_variant_choppable()` is absent and old generation uses list origin.

- [ ] **Step 3: Implement the whitelist**

Create `TreeFellingCatalog` with `CHOPPABLE_VARIANTS`, `FELLING_ATLAS_PATHS`, `GATHER_DURATION`, `is_variant_choppable()`, and `atlas_path()`. Persist `variant` during `TreeInstance.configure()`, delegate instance eligibility to the catalog, and derive every generated placement's `gatherable` value from that variant. `TreeScatter`, `TreeInstance`, and `VegetationBuilder` may preload the catalog; they must not preload one another to discover eligibility.

- [ ] **Step 4: Rerun core tests**

Expected: PASS with all ten variant assertions green.

- [ ] **Step 5: Commit**

```powershell
git add scripts/world/tree_felling_catalog.gd scripts/world/tree_scatter.gd scripts/world/tree_instance.gd tests/test_tree_scatter.gd tests/test_tree_instance.gd
git commit -m "feat: define choppable tree variants"
```

### Task 2: Create five hand-painted felling atlases

**Files:**
- Create: `assets/vegetation/felling/pine-small-felling-sheet.png`
- Create: `assets/vegetation/felling/pine-tall-felling-sheet.png`
- Create: `assets/vegetation/felling/canopy-small-felling-sheet.png`
- Create: `assets/vegetation/felling/canopy-medium-felling-sheet.png`
- Create: `assets/vegetation/felling/round-small-felling-sheet.png`
- Modify: `scripts/world/vegetation_builder.gd`
- Modify: `tests/test_tree_instance.gd`

- [ ] **Step 1: Write failing asset-manifest tests**

```gdscript
for variant in TreeFellingCatalogScript.CHOPPABLE_VARIANTS:
	var path := TreeFellingCatalogScript.atlas_path(variant)
	assertions.truthy(ResourceLoader.exists(path), "%s has a felling atlas" % variant)
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		assertions.truthy(
			texture != null and texture.get_width() % 4 == 0,
			"%s atlas has four equal cells" % variant
		)
```

- [ ] **Step 2: Run core tests and verify RED**

Expected: five missing-atlas failures.

- [ ] **Step 3: Generate one atlas from each exact source tree**

Use image generation with the matching `assets/vegetation/tree-<variant>.png` as reference. Each transparent landscape atlas has four clean equal-width cells: low notch/light chips; deeper notch/moderate right lean; nearly fallen right with fixed root baseline; warm-brown stump with rings and exposed roots. Match source camera, lighting, bark, canopy, edge softness, saturation, and scale. Reject text, borders, opaque boxes, overlapping cells, species drift, gray stumps, or moving root anchors.

- [ ] **Step 4: Add the atlas manifest and configure dependency**

Use `TreeFellingCatalog.FELLING_ATLAS_PATHS` as the manifest. `VegetationBuilder` loads the atlas beside the original texture and passes it to `TreeInstance.configure()`. A missing/invalid atlas makes that selected variant ineligible and logs a clear error; never recreate the cylinder stump.

- [ ] **Step 5: Import and test**

Run:

```powershell
godot --path . --headless --editor --quit
godot --path . --headless -s res://tests/run_tests.gd
```

Expected: all five atlases import and tests PASS.

- [ ] **Step 6: Commit**

```powershell
git add assets/vegetation/felling scripts/world/tree_felling_catalog.gd scripts/world/vegetation_builder.gd tests/test_tree_instance.gd
git commit -m "feat: add hand-painted tree felling atlases"
```

### Task 3: Render three felling frames and painted stumps

**Files:**
- Modify: `scripts/world/tree_instance.gd`
- Modify: `tests/test_gathering_visuals.gd`

- [ ] **Step 1: Write failing frame-boundary tests**

```gdscript
tree.begin_felling(1)
tree.set_felling_progress(0.10)
assertions.equal(tree.get_felling_frame(), 0, "early progress shows notch frame")
tree.set_felling_progress(0.50)
assertions.equal(tree.get_felling_frame(), 1, "middle progress shows leaning frame")
tree.set_felling_progress(0.85)
assertions.equal(tree.get_felling_frame(), 2, "late progress shows fallen frame")
tree.cancel_felling()
assertions.equal(tree.get_felling_frame(), -1, "cancel restores standing art")
```

After depletion assert atlas cell 3 is visible as the stump and no `CylinderMesh` remains; after respawn assert the original sprite returns.

- [ ] **Step 2: Run gathering visual tests and verify RED**

Expected: missing felling API and old cylinder stump failures.

- [ ] **Step 3: Implement atlas slicing and presentation state**

Create a felling/stump `Sprite3D`; slice four equal regions with `AtlasTexture`; use progress thresholds `0.325` and `0.675`; use `flip_h` for fall direction; preserve the root baseline; and reset texture, position, scale, modulation, and particles in `cancel_felling()`. Visual stage 3 shows atlas cell 3.

- [ ] **Step 4: Rerun visual tests and verify GREEN**

- [ ] **Step 5: Commit**

```powershell
git add scripts/world/tree_instance.gd tests/test_gathering_visuals.gd
git commit -m "feat: animate tree felling frames"
```

### Task 4: Make tree rewards batch-aware and atomic

**Files:**
- Modify: `scripts/world/tree_instance.gd`
- Modify: `scripts/systems/tool_system.gd`
- Modify: `tests/test_tool_action_transaction.gd`
- Modify: `tests/test_resource_gathering.gd`

- [ ] **Step 1: Write failing fresh/partial/full-inventory tests**

Assert fresh preview/commit quantity 5 and `remaining_after == 0`; a legacy tree with 3 units yields 3; inventory space for only 4 rejects before movement; every failure leaves target, inventory, stamina, durability, time, and events unchanged.

- [ ] **Step 2: Run resource and main-gameplay tests and verify RED**

Expected: transaction currently hardcodes quantity 1.

- [ ] **Step 3: Override the tree reward contract**

```gdscript
func preview_reward(tool_id: String) -> Dictionary:
	return {item_id: remaining_units} if can_gather(tool_id) else {}

func commit_gather(tool_id: String, total_day: int = 0) -> Dictionary:
	var reward := preview_reward(tool_id)
	if reward.is_empty() or total_day < 0:
		return {}
	remaining_units = 0
	_respawn_day = total_day + respawn_days
	_update_visual_stage()
	_set_gather_active(false)
	return reward
```

- [ ] **Step 4: Generalize `ToolSystem` to preview quantity**

Accept one positive reward entry, preflight `_can_add_rewards({item: quantity})`, add exactly `quantity`, compare committed reward to the preview dictionary, emit that quantity, and keep stamina/durability costs at one action. Ore preview remains quantity 1.

- [ ] **Step 5: Rerun tests and verify GREEN**

- [ ] **Step 6: Commit**

```powershell
git add scripts/world/tree_instance.gd scripts/systems/tool_system.gd tests/test_tool_action_transaction.gd tests/test_resource_gathering.gd
git commit -m "feat: gather full tree yield atomically"
```

### Task 5: Run trees for two seconds and anchor the axe at the root

**Files:**
- Modify: `scripts/world/tree_instance.gd`
- Modify: `scripts/systems/gathering_controller.gd`
- Modify: `scripts/ui/gathering_feedback.gd`
- Modify: `scripts/visual/tool_swing_visual.gd`
- Modify: `tests/test_gathering_controller.gd`
- Modify: `tests/test_gathering_visuals.gd`

- [ ] **Step 1: Write failing duration/cancel/anchor tests**

Assert a tree exposes 2.0 seconds, does not commit at 1.2, commits at 2.0, and cancel calls `cancel_felling()` without mutation. Assert ore still commits at 1.2. Add:

```gdscript
var anchor := GatheringFeedback.tree_axe_anchor(
	Vector3(4.0, 1.0, 2.0), Vector3(2.0, 1.0, 2.0)
)
assertions.near(anchor.y, 1.20, 0.001, "axe pivot is 0.2m above ground")
assertions.near(anchor.x, 3.55, 0.001, "axe pivot is 0.45m actor-side")
```

- [ ] **Step 2: Run main-gameplay and visual tests and verify RED**

- [ ] **Step 3: Implement target duration and felling callbacks**

`TreeInstance.get_gather_duration()` returns `2.0`. `GatheringController` stores target duration, otherwise uses `action_duration == 1.2`. Feedback begins felling at `ACTING`, forwards normalized progress, restores on cancel/fail, and leaves committed stump state intact.

- [ ] **Step 4: Implement the root anchor**

```gdscript
static func tree_axe_anchor(tree_position: Vector3, actor_position: Vector3) -> Vector3:
	var toward_actor := actor_position - tree_position
	toward_actor.y = 0.0
	if toward_actor.is_zero_approx():
		toward_actor = Vector3.RIGHT
	return tree_position + toward_actor.normalized() * 0.45 + Vector3.UP * 0.20
```

Use this only for axe-on-tree. Keep the handle-end pivot and adjust the axe sprite contact offset so the blade meets the low trunk. Pickaxe placement remains actor-side.

- [ ] **Step 5: Rerun tests and verify GREEN**

- [ ] **Step 6: Commit**

```powershell
git add scripts/world/tree_instance.gd scripts/systems/gathering_controller.gd scripts/ui/gathering_feedback.gd scripts/visual/tool_swing_visual.gd tests/test_gathering_controller.gd tests/test_gathering_visuals.gd
git commit -m "feat: run two-second root-level tree felling"
```

### Task 6: Add green/red axe-hover eligibility

**Files:**
- Modify: `scripts/world/tree_instance.gd`
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `scripts/ui/gathering_feedback.gd`
- Modify: `scenes/ui/gathering_feedback.tscn`
- Modify: `tests/test_player_action_controller.gd`
- Modify: `tests/test_main_pointer_farming.gd`
- Modify: `tests/test_gathering_visuals.gd`

- [ ] **Step 1: Write failing hover lifecycle tests**

Assert axe-selected hover reports target/allowed, eligible uses green, ineligible uses red, pointer exit/tool switch/build mode hides the ring, and clicking red starts no movement/cost and reports `tree_not_choppable` / `此树不可砍伐`.

- [ ] **Step 2: Run pointer/visual tests and verify RED**

Expected: decorative tree interaction areas are disabled and no hover signal/ring exists.

- [ ] **Step 3: Expose standing-tree hover collision**

Keep `GatherArea` on the interaction layer for every standing tree, including non-choppable variants; disable it for depleted stumps. Add `is_chop_eligible()` without invoking a transaction.

- [ ] **Step 4: Emit and clear hover state**

Add `tree_hover_changed(target, allowed)` to `PlayerActionController`. Only raycast for hover when farming slot 2 is selected and pointer is not over UI. Clear on pointer, slot, mode, UI, and action transitions. Reject red clicks before `request_gather()`.

- [ ] **Step 5: Render a separate hover ring**

Add `TreeHoverRing` to feedback. Use green `Color(0.25, 0.9, 0.38, 0.62)` and red `Color(0.95, 0.2, 0.18, 0.62)` at root +0.04m; hide it when gathering begins.

- [ ] **Step 6: Rerun pointer/visual/main tests and verify GREEN**

- [ ] **Step 7: Commit**

```powershell
git add scripts/world/tree_instance.gd scripts/actors/player_action_controller.gd scripts/ui/gathering_feedback.gd scenes/ui/gathering_feedback.tscn tests/test_player_action_controller.gd tests/test_main_pointer_farming.gd tests/test_gathering_visuals.gd
git commit -m "feat: show tree chopping eligibility"
```

### Task 7: Migrate retired and newly eligible tree records

**Files:**
- Modify: `scripts/world/world.gd`
- Modify: `tests/test_resource_gathering.gd`
- Modify: `tests/test_economy_save_integration.gd`

- [ ] **Step 1: Write failing migration tests**

Use an old v2 array containing `tree-resource-04` (`round-medium`) and `tree-resource-07` (`fruit`), an eligible partial tree, and ores. Assert retired records drop, partial state remains, newly eligible stable scatter IDs backfill to five, ores remain unchanged, and unrelated unknown/duplicate records still reject atomically.

- [ ] **Step 2: Run resource/economy tests and verify RED**

- [ ] **Step 3: Add explicit retirement handling**

```gdscript
const RETIRED_GATHERABLE_TREE_IDS := {
	"tree-resource-04": true,
	"tree-resource-07": true,
}
```

Skip only those records before unknown-ID rejection. Do not broadly ignore unknown resources.

- [ ] **Step 4: Rerun migration/economy tests and verify GREEN**

- [ ] **Step 5: Commit**

```powershell
git add scripts/world/world.gd tests/test_resource_gathering.gd tests/test_economy_save_integration.gd
git commit -m "feat: migrate choppable tree variants"
```

### Task 8: Verify gameplay chain, visuals, and full regression

**Files:**
- Modify: `tests/test_main_gathering_integration.gd`
- Modify: `tests/capture_manual_gathering.gd`
- Modify: `docs/superpowers/specs/2026-08-04-manual-gathering-design.md`
- Modify: `docs/validation/manual-gathering-validation.md`
- Modify: `docs/superpowers/plans/2026-08-04-single-click-tree-felling.md`

- [ ] **Step 1: Replace repeated-tree integration assertions**

Use real pointer/physical movement. Assert a fresh tree remains active at 1.2 seconds, completes at 2.0, adds 5 wood, deducts 8 stamina/1 durability, advances 10 minutes, becomes a painted stump, releases navigation blockers, reduces building wood shortage by 5, and does not alter market stock. Assert copper remains 1.2 seconds/one unit.

- [ ] **Step 2: Add cancellation coverage**

Cancel at each of the three frame intervals and assert original art, five units, no wood/stamina/durability/time delta, and no stale lock.

- [ ] **Step 3: Extend deterministic captures**

Capture green hover, red hover, root axe contact, frames 1/2/3, falling left/right, painted stump, and `+5 木材` at 1280×720, 1920×1080, and 3000×2000.

- [ ] **Step 4: Run and inspect Windows captures**

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility -s res://tests/capture_manual_gathering.gd
```

Expected: all expected PNGs exist; no opaque boxes, species drift, root jump, wrong fall direction, floating axe, gray stump, or text overlap.

- [ ] **Step 5: Run every automated runner**

```powershell
godot --path . --headless -s res://tests/run_tests.gd
godot --path . --headless -s res://tests/run_grid_system_tests.gd
godot --path . --headless -s res://tests/run_farming_system_tests.gd
godot --path . --headless -s res://tests/run_building_system_tests.gd
godot --path . --headless -s res://tests/run_economy_system_tests.gd
godot --path . --headless -s res://tests/run_economy_ui_tests.gd
godot --path . --headless -s res://tests/run_main_gameplay_integration_tests.gd
godot --path . --headless -s res://tests/run_resource_gathering_tests.gd
godot --path . --headless -s res://tests/run_gathering_visual_tests.gd
godot --path . --headless -s res://tests/run_main_gathering_integration_tests.gd
```

Expected: every runner exits 0; no new parse, orphan, lock, transaction, texture, or shader warning.

- [ ] **Step 6: Update formal docs and static-check**

Update the original design's tree quantity/timing/UI sections to reference the approved delta spec. Record exact counts and art review in validation, mark all plan boxes complete, then run `git diff --check` and scan for `TBD|TODO|FIXME|NotImplemented`.

- [ ] **Step 7: Request final code/art review**

Review batch rollback, retired save IDs, pointer priority, cancellation, two-second lock ownership, atlas transparency/root alignment, and all three capture sizes. Resolve every Critical/Important finding and rerun affected suites.

- [ ] **Step 8: Commit final validation**

```powershell
git add tests/test_main_gathering_integration.gd tests/capture_manual_gathering.gd docs/superpowers/specs/2026-08-04-manual-gathering-design.md docs/validation/manual-gathering-validation.md docs/superpowers/plans/2026-08-04-single-click-tree-felling.md
git commit -m "docs: validate single-click tree felling"
```

## Completion Criteria

- [ ] Exactly five approved variants are choppable everywhere; all other trees show red hover and reject clicks without movement/cost.
- [ ] One fresh tree action lasts 2 seconds, atomically awards 5 wood, deducts 8 stamina/1 durability, advances 10 minutes, and ends as a painted stump.
- [ ] Five matched atlases each contain three felling frames plus a stump with stable transparent root anchors.
- [ ] Axe impact sits at the low trunk; ore/pickaxe behavior stays unchanged.
- [ ] Cancellation at every felling phase restores the tree without gameplay/event mutation.
- [ ] Old partial/retired tree saves load safely and newly eligible stable trees backfill full.
- [ ] All tests, captures, static checks, and final review pass.
