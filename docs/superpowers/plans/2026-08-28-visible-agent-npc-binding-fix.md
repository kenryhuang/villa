# Visible Agent NPC Presentation Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Northwest, South, and East NPCs consistently render their own Agent names and show an unobstructed nearby dialogue icon.

**Architecture:** `Main` supplies each Agent NPC a distinct pair of render priorities while preserving the existing binding and dialogue flow. The NPC scene owns the relative name/prompt layout and depth behavior.

**Tech Stack:** Godot 4.7, GDScript, GL Compatibility renderer, the existing custom Agent and project test runners.

---

### Task 1: Lock the visual-order regression in tests

**Files:**
- Modify: `tests/test_visible_agent_npc_dialogue.gd`

- [x] **Step 1: Assert bindings declare distinct priorities**

After reading `AGENT_NPC_BINDINGS`, add:

```gdscript
	var visual_priorities := [
		int((bindings.NpcNorthwest as Dictionary).get("visual_priority", -1)),
		int((bindings.NpcSouth as Dictionary).get("visual_priority", -1)),
		int((bindings.NpcEast as Dictionary).get("visual_priority", -1)),
	]
	assertions.equal(visual_priorities, [1, 3, 5], "Agent NPCs declare distinct nameplate priorities")
```

- [x] **Step 2: Assert Agent configuration applies visible ordering**

After resolving `farmer`, `merchant`, and `explorer`, add:

```gdscript
	var expected_priorities := {"farmer_ahe": 1, "lao_li": 3, "xuezhe_lin": 5}
	for npc in [farmer, merchant, explorer]:
		var nameplate := npc.get_node("Nameplate") as Label3D
		var prompt := npc.get_node("DialoguePrompt") as Node3D
		var prompt_icon := npc.get_node("DialoguePrompt/Icon") as Sprite3D
		var expected_priority := int(expected_priorities[npc.villager_id])
		assertions.equal(nameplate.render_priority, expected_priority, "%s receives a unique nameplate priority" % npc.villager_id)
		assertions.equal(prompt_icon.render_priority, expected_priority + 1, "%s prompt renders above its nameplate" % npc.villager_id)
		assertions.truthy(prompt_icon.no_depth_test, "%s prompt ignores world depth" % npc.villager_id)
		assertions.truthy(prompt.position.y > nameplate.position.y, "%s prompt sits above its nameplate" % npc.villager_id)
```

- [x] **Step 3: Run the focused suite and verify the assertions fail correctly**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: FAIL with priority values `-1`/`0` instead of `1, 3, 5`, and with prompt depth testing still enabled.

### Task 2: Apply distinct name and prompt priorities

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scripts/actors/npc.gd`
- Modify: `scenes/actors/npc.tscn`
- Test: `tests/test_visible_agent_npc_dialogue.gd`

- [x] **Step 1: Declare visual priorities in Main**

Extend `AGENT_NPC_BINDINGS` in `scripts/main.gd`:

```gdscript
const AGENT_NPC_BINDINGS := {
	"NpcNorthwest": {"agent_id": "farmer_ahe", "spawn": Vector2(-3.0, -2.0), "visual_priority": 1},
	"NpcSouth": {"agent_id": "lao_li", "spawn": Vector2(3.0, -3.0), "visual_priority": 3},
	"NpcEast": {"agent_id": "xuezhe_lin", "spawn": Vector2(4.0, 2.0), "visual_priority": 5},
}
```

Keep the existing Agent configuration call, then apply visual ordering separately:

```gdscript
		if not bool(npc.call("configure_agent", player, agent_id, display_name)):
			push_error("Unable to bind visible NPC %s to Agent %s" % [node_name, agent_id])
			continue
		npc.call("configure_agent_visual_priority", int(binding.visual_priority))
```

- [x] **Step 2: Apply the priority pair without changing the binding signature**

Add a focused method in `scripts/actors/npc.gd` so the existing three-argument `configure_agent` interface remains stable:

```gdscript
func configure_agent_visual_priority(visual_priority: int) -> void:
	if nameplate != null:
		nameplate.render_priority = visual_priority
	if dialogue_prompt_icon != null:
		dialogue_prompt_icon.render_priority = visual_priority + 1
```

- [x] **Step 3: Separate and unocclude the prompt**

Update `scenes/actors/npc.tscn`:

```gdscript
[node name="DialoguePrompt" type="Node3D" parent="."]
visible = false
position = Vector3(0, 2.05, 0)

[node name="Icon" type="Sprite3D" parent="DialoguePrompt"]
texture = ExtResource("2_prompt")
pixel_size = 0.0075
billboard = 1
no_depth_test = true
shaded = false
double_sided = true
```

- [x] **Step 4: Run the focused Agent suite**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: PASS with all Agent system checks succeeding.

- [x] **Step 5: Run the full project suite against the recorded baseline**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_tests.gd
```

Expected: no failures beyond the four recorded baseline failures (three economy state checks and the existing villager-count check).

- [x] **Step 6: Perform a rendered full-scene check**

Use a temporary non-headless probe to capture the initial scene and then place the player within one metre of `NpcNorthwest` and `NpcEast`. Confirm all three names render simultaneously and that a complete speech-bubble icon appears above each approached NPC's name. Remove the probe before committing.

- [x] **Step 7: Commit the implementation**

```powershell
git add -- scripts/main.gd scripts/actors/npc.gd scenes/actors/npc.tscn tests/test_visible_agent_npc_dialogue.gd docs/superpowers/specs/2026-08-28-visible-agent-npc-binding-fix-design.md docs/superpowers/plans/2026-08-28-visible-agent-npc-binding-fix.md
git commit -m "fix: render every Agent NPC interaction marker"
```
