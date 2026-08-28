# Visible Agent NPC Binding Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Northwest, South, and East NPCs consistently render their own Agent names, show an unobstructed nearby dialogue icon, and register under the correct Agent IDs.

**Architecture:** Scene instances carry their final identity before entering the tree. `Main` remains the integration owner: it supplies each NPC a distinct pair of render priorities, configures Agent dialogue, and registers the configured node with the runtime-created `VillagerSystem`. The NPC scene owns the relative name/prompt layout and depth behavior.

**Tech Stack:** Godot 4.7, GDScript, GL Compatibility renderer, the existing custom headless Agent test runner.

---

### Task 1: Lock the broken identity, registration, and visual-order behavior in tests

**Files:**
- Modify: `tests/test_visible_agent_npc_dialogue.gd`

- [ ] **Step 1: Add the main scene and a VillagerSystem test double**

Add the scene preload beside the existing script and NPC preloads:

```gdscript
const MainScene = preload("res://scenes/main.tscn")
```

Add this focused double beside the other doubles:

```gdscript
class VillagerSystemDouble:
	extends Node

	var registrations: Array[Dictionary] = []

	func register_villager(villager_node: Node3D, villager_id: String) -> void:
		registrations.append({"node": villager_node, "villager_id": villager_id})
```

- [ ] **Step 2: Assert final IDs exist before `_ready()` and bindings declare distinct priorities**

At the beginning of `run`, instantiate but do not add the full main scene to the tree, then assert the exported IDs:

```gdscript
	var packed_main = MainScene.instantiate()
	assertions.equal(packed_main.get_node("Actors/Npcs/NpcNorthwest").villager_id, "farmer_ahe", "northwest NPC enters the tree as farmer Ahe")
	assertions.equal(packed_main.get_node("Actors/Npcs/NpcSouth").villager_id, "lao_li", "south NPC enters the tree as Lao Li")
	assertions.equal(packed_main.get_node("Actors/Npcs/NpcEast").villager_id, "xuezhe_lin", "east NPC enters the tree as Xuezhe Lin")
	packed_main.free()

	var visual_priorities := [
		int((bindings.NpcNorthwest as Dictionary).get("visual_priority", -1)),
		int((bindings.NpcSouth as Dictionary).get("visual_priority", -1)),
		int((bindings.NpcEast as Dictionary).get("visual_priority", -1)),
	]
	assertions.equal(visual_priorities, [1, 3, 5], "Agent NPCs declare distinct nameplate priorities")
```

- [ ] **Step 3: Assert Main registers all Agent NPCs and applies visible ordering**

Assign a `VillagerSystemDouble` before calling `_setup_npcs()`, then add assertions after the existing NPC variables are resolved:

```gdscript
	var villager_system := VillagerSystemDouble.new()
	main.villager_system = villager_system
```

```gdscript
	assertions.equal(
		villager_system.registrations.map(func(entry: Dictionary) -> String: return str(entry.villager_id)),
		["farmer_ahe", "lao_li", "xuezhe_lin"],
		"Main registers all visible Agent NPCs under their final IDs"
	)
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

- [ ] **Step 4: Run the focused suite and verify the new assertions fail for the intended reasons**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: FAIL because scene instances still default to `lao_li`, bindings have no `visual_priority`, Main does not register configured nodes, and prompts do not yet have the intended render ordering.

### Task 2: Apply final identity, registration, and visual priorities

**Files:**
- Modify: `scenes/main.tscn`
- Modify: `scripts/main.gd`
- Modify: `scripts/actors/npc.gd`
- Modify: `scenes/actors/npc.tscn`
- Test: `tests/test_visible_agent_npc_dialogue.gd`

- [ ] **Step 1: Give the three scene instances their final IDs**

Add one exported-property override to each NPC instance in `scenes/main.tscn`:

```gdscript
[node name="NpcNorthwest" parent="Actors/Npcs" instance=ExtResource("4")]
position = Vector3(-3, 0, -2)
villager_id = "farmer_ahe"

[node name="NpcSouth" parent="Actors/Npcs" instance=ExtResource("4")]
position = Vector3(3, 0, -3)
villager_id = "lao_li"

[node name="NpcEast" parent="Actors/Npcs" instance=ExtResource("4")]
position = Vector3(4, 0, 2)
villager_id = "xuezhe_lin"
```

- [ ] **Step 2: Declare visual priorities and register configured NPCs in Main**

Extend `AGENT_NPC_BINDINGS` in `scripts/main.gd`:

```gdscript
const AGENT_NPC_BINDINGS := {
	"NpcNorthwest": {"agent_id": "farmer_ahe", "spawn": Vector2(-3.0, -2.0), "visual_priority": 1},
	"NpcSouth": {"agent_id": "lao_li", "spawn": Vector2(3.0, -3.0), "visual_priority": 3},
	"NpcEast": {"agent_id": "xuezhe_lin", "spawn": Vector2(4.0, 2.0), "visual_priority": 5},
}
```

Pass the priority into `configure_agent`, then register only after configuration succeeds:

```gdscript
		var visual_priority := int(binding.visual_priority)
		if not bool(npc.call("configure_agent", player, agent_id, display_name, visual_priority)):
			push_error("Unable to bind visible NPC %s to Agent %s" % [node_name, agent_id])
			continue
		if villager_system != null and villager_system.has_method("register_villager"):
			villager_system.call("register_villager", npc, agent_id)
```

- [ ] **Step 3: Make NPC visual configuration explicit**

Change `configure_agent` in `scripts/actors/npc.gd` and apply the priority pair:

```gdscript
func configure_agent(
	player: Node3D,
	agent_id: String,
	display_name: String = "",
	visual_priority: int = 1
) -> bool:
	configure(player)
	if agent_id.is_empty():
		return false
	villager_id = agent_id
	if nameplate != null:
		nameplate.text = display_name if not display_name.strip_edges().is_empty() else agent_id
		nameplate.render_priority = visual_priority
		nameplate.visible = health > 0
	if dialogue_prompt_icon != null:
		dialogue_prompt_icon.render_priority = visual_priority + 1
	_agent_dialogue_enabled = true
	refresh_dialogue_prompt()
	return true
```

- [ ] **Step 4: Separate and unocclude the prompt in the NPC scene**

Update the prompt nodes in `scenes/actors/npc.tscn`:

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

- [ ] **Step 5: Run the focused Agent suite**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: PASS with all Agent system checks succeeding and no new parser/runtime errors.

- [ ] **Step 6: Run the full project suite**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_all_tests.gd
```

Expected: the new Agent NPC assertions pass. If the repository has documented unrelated baseline failures, record them separately without masking new failures.

- [ ] **Step 7: Perform a rendered full-scene check**

Run a temporary non-headless probe that captures the initial scene and separately places the player within one metre of `NpcNorthwest` and `NpcEast`. Confirm all three names render in the initial view and that the complete speech-bubble icon appears above, rather than over, the approached NPC's name. Remove the temporary probe before committing.

- [ ] **Step 8: Commit the implementation**

```powershell
git add -- scenes/main.tscn scripts/main.gd scripts/actors/npc.gd scenes/actors/npc.tscn tests/test_visible_agent_npc_dialogue.gd
git commit -m "fix: bind and render every Agent NPC"
```
