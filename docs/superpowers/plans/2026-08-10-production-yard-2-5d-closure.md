# Production Yard 2.5D Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render every production-yard perimeter as one closed 2.5D rectangular frame under the locked orthographic camera.

**Architecture:** Keep the authoritative X/Z perimeter coordinates, collision bodies, atlas families, and construction rows unchanged. Render each segment as a non-billboard, double-sided painted world card: X-edge cards use zero Y rotation and Z-edge cards use 90-degree Y rotation, allowing the orthographic camera to project a closed 2.5D rectangle naturally.

**Tech Stack:** Godot 4.7, GDScript, axis-aligned Sprite3D world cards, PNG atlas regions, headless GDScript tests

---

### Task 1: Lock the 2.5D projection contract and implement it

**Files:**
- Modify: `tests/test_building_production_yard.gd`
- Modify: `scripts/buildings/building_production_yard.gd`

- [x] **Step 1: Write failing projection assertions**

In the existing style/stage loop, inspect every primary fence sprite and require the straight atlas column, non-billboard mode, and axis-specific world rotation:

```gdscript
var axis := int(sprite.get_meta("axis", -1))
assertions.truthy(axis in [0, 1], "%s fence segment records its world axis" % style)
	assertions.equal(
		sprite.region_rect,
		Rect2(0.0, float(stage) * 512.0, 512.0, 512.0),
		"%s stage %d uses the straight world-plane frame" % [style, stage]
	)
	assertions.equal(
		sprite.billboard,
		BaseMaterial3D.BILLBOARD_DISABLED,
		"%s fence remains an axis-aligned 2.5D world card" % style
	)
	assertions.truthy(
		is_equal_approx(sprite.rotation.y, 0.0 if axis == 0 else PI * 0.5),
		"%s fence rotates onto its X/Z perimeter axis" % style
	)
```

Keep `_assert_closed_rectangle_layout` so the test covers both the ground-plane rectangle and its screen-facing representation.

- [x] **Step 2: Run the building suite and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: failures show missing `axis` metadata, screen-facing billboard mode, the wrong atlas column, and missing Z-axis world rotation.

- [x] **Step 3: Implement axis-aware world-card segments**

Change `_add_segment` to treat its integer argument as the ground-plane axis:

```gdscript
func _add_segment(position_value: Vector3, axis: int, parent: Node, sorting: float) -> void:
	if _yard_texture == null:
		return
	var sprite := Sprite3D.new()
	sprite.texture = _yard_texture
	sprite.region_enabled = true
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.double_sided = true
	sprite.pixel_size = SEGMENT_WORLD_SIZE / SEGMENT_PIXEL_SIZE
	sprite.scale = Vector3(1.0, SEGMENT_VERTICAL_SCALE, 1.0)
	sprite.position = position_value + Vector3(0.0, SEGMENT_BASE_Y, 0.0)
	sprite.rotation.y = 0.0 if axis == 0 else PI * 0.5
	sprite.sorting_offset = sorting
	sprite.set_meta("axis", axis)
	parent.add_child(sprite)
	_segments.append(sprite)
```

Update `_apply_visual_state` so every segment selects atlas column 0 while construction stage still selects the row:

```gdscript
sprite.region_rect = Rect2(
	0.0,
	float(_construction_stage) * ATLAS_FRAME_SIZE.y,
	ATLAS_FRAME_SIZE.x,
	ATLAS_FRAME_SIZE.y
)
```

Do not enable billboard mode or mirror the painting: rotating the vertical card in world space lets the orthographic camera produce the correct diagonal while world-up posts remain vertical.

- [x] **Step 4: Run the building suite and require GREEN**

Run the building suite again. Expected: all building-system assertions pass, including construction crossfades, preview/maintenance tinting, closed X/Z perimeter points, straight atlas selection, non-billboard mode, and axis rotation.

- [x] **Step 5: Commit the runtime correction**

```powershell
git add scripts/buildings/building_production_yard.gd tests/test_building_production_yard.gd docs/superpowers/plans/2026-08-10-production-yard-2-5d-closure.md
git commit -m "fix: project yard fences as a closed 2.5d frame"
```

### Task 2: Verify production integration

**Files:**
- Verify: `scripts/buildings/building_production_yard.gd`
- Verify: `tests/test_building_production_yard.gd`

- [x] **Step 1: Run affected integration suites**

Run:

```powershell
godot --headless --path . --script res://tests/run_production_system_tests.gd
godot --headless --path . --script res://tests/run_production_chain_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: every runner exits `0` with a `PASS` summary.

- [x] **Step 2: Check repository integrity**

Run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors; only known unrelated untracked Godot `.uid` files may remain outside this change.

- [x] **Step 3: Mark the plan complete and commit only if the checklist changed after Task 1**

If Task 2 checkbox updates are not already included in the Task 1 commit, commit the completed plan separately:

```powershell
git add docs/superpowers/plans/2026-08-10-production-yard-2-5d-closure.md
git commit -m "docs: complete yard 2.5d closure plan"
```
