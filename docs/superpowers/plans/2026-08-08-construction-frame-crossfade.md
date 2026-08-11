# Construction Frame Crossfade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend every construction-frame crossfade to two seconds without changing ten-second stage thresholds or the thirty-second construction duration.

**Architecture:** Keep the existing `ConstructionTransitions` duplicate-sprite approach. Make both outgoing and incoming tweens two seconds long, and cover duration plus midpoint opacity with the existing building construction test.

**Tech Stack:** Godot 4.7, GDScript, repository headless test runners.

---

### Task 1: Two-second construction crossfade

**Files:**
- Modify: `tests/test_building_construction_state.gd`
- Modify: `scripts/buildings/building_instance.gd`

- [x] **Step 1: Write the failing duration and midpoint tests**

Change both duration assertions to `2.0`. Before advancing from foundation, finish the initial setup tweens with `custom_step(2.0)`. After the foundation-to-frame transition, step the new tweens by one second and assert both sprites have alpha `0.5`; step once more and assert the outgoing sprite reaches `0.0`, the incoming sprite reaches `1.0`, and the outgoing sprite is queued for deletion.

```gdscript
for tween in tree.get_processed_tweens():
	tween.custom_step(2.0)

assertions.near(instance.STAGE_FADE_OUT_DURATION, 2.0, 0.001, "outgoing stage fade duration")
assertions.near(instance.STAGE_FADE_IN_DURATION, 2.0, 0.001, "incoming stage fade duration")
for tween in tree.get_processed_tweens():
	tween.custom_step(1.0)
assertions.near(outgoing.modulate.a, 0.5, 0.01, "outgoing frame is half transparent after one second")
assertions.near(construction_sprite.modulate.a, 0.5, 0.01, "incoming frame is half visible after one second")
for tween in tree.get_processed_tweens():
	tween.custom_step(1.0)
assertions.near(outgoing.modulate.a, 0.0, 0.01, "outgoing frame finishes fading after two seconds")
assertions.near(construction_sprite.modulate.a, 1.0, 0.01, "incoming frame finishes fading after two seconds")
assertions.truthy(outgoing.is_queued_for_deletion(), "finished outgoing frame is queued for cleanup")
```

- [x] **Step 2: Run the building suite and verify RED**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: duration and one-second opacity assertions fail because the current fades are `0.12` and `0.18` seconds.

- [x] **Step 3: Implement the minimal timing change**

In `scripts/buildings/building_instance.gd`, change only:

```gdscript
const STAGE_FADE_OUT_DURATION := 2.0
const STAGE_FADE_IN_DURATION := 2.0
```

- [x] **Step 4: Run verification and verify GREEN**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
git diff --check
```

Expected: both runners pass, no parser errors, and no whitespace errors. Existing assertions continue proving `10` seconds per stage and `30` seconds total.

- [x] **Step 5: Mark complete and commit**

Mark every checkbox `[x]`, then run:

```powershell
git add scripts/buildings/building_instance.gd tests/test_building_construction_state.gd docs/superpowers/plans/2026-08-08-construction-frame-crossfade.md
git commit -m "fix: extend construction frame crossfade"
```
