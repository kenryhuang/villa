# Villa Villagers and Deterministic Dialogue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hostile prototype NPCs with peaceful scheduled Villagers, persistent affinity, deterministic dialogue, and a signal-driven dialogue UI.

**Architecture:** VillagerSystem owns registration, hourly schedules, affinity, dialogue sessions, effects, and serialization. Villager only performs local movement and emits interaction/speech signals. DialogueService resolves typed Resources with no network, UI, autoload, or Agent dependency. Future Agent code may use the actor adapter methods, but must still submit effects through local systems.

**Tech Stack:** Godot 4.7, GDScript, Jolt Physics, Godot Resources, CanvasLayer UI, headless GDScript tests.

## Global Constraints

- Use Godot 4.7, GL Compatibility, Jolt Physics, and only the existing RefCounted test runner.
- Run all tests with: godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd.
- Godot is authoritative for movement, collision, inventory, economy, relationships, dialogue effects, and save data.
- Do not create or attach AgentGateway, NpcAgentController, FallbackVillagerBrain, HTTPRequest, Agent Service, LLM, or provider code.
- Preserve future Agent protocol version 1. Later code may call only set_agent_destination, face_agent_actor, perform_agent_work, and say_agent_text; it cannot bypass VillagerSystem or DialogueService.
- Retain PlayerController.movement_from_input, WASD, jumping, gravity, and clamping; remove every combat input, signal, script, and projectile reference.
- Add interact on E and mouse right button. Villager body is layer 4, interaction Area3D is layer 256, and Player/Villager masks are 81.
- Evaluate schedules only on EventBus.time_changed when minute equals 0. Overnight start > end means hour >= start or hour < end.
- Clamp affinity to 0 through 100: STRANGER 0–20, FRIEND 21–50, CLOSE 51–80, SOULMATE 81–100.
- Conditions read only affinity_min, has_item, story_chapter_min. Effects permit only affinity, give_item, set_flag. Invalid choices and cycles mutate nothing.
- Consume the `affinity_changed`, `affinity_level_up`, `dialogue_started`, `dialogue_ended`, and `villager_moved` signals already declared by Plan 1's EventBus, preserving the exact detailed-design §3 signatures.

---

## File Structure

| Path | Responsibility |
|---|---|
| scripts/data/villager_data.gd | Identity, positions, schedule, graph, rewards. |
| scripts/data/villager_affinity.gd | Pure clamp/level logic. |
| scripts/data/dialogue_choice.gd, dialogue_node.gd | Typed graph Resources. |
| scripts/systems/dialogue_service.gd | Deterministic graph transition. |
| scripts/systems/villager_system.gd | Runtime authority and persistence. |
| scripts/actors/villager.gd | Peaceful movement and bounded future-Agent adapter. |
| scripts/ui/dialogue_ui.gd, scenes/ui/dialogue_ui.tscn | Rendering and choice input only. |

### Task 1: Typed villager and dialogue Resources

**Files:**
- Create: scripts/data/villager_data.gd
- Create: scripts/data/villager_affinity.gd
- Create: scripts/data/dialogue_choice.gd
- Create: scripts/data/dialogue_node.gd
- Create: tests/test_villager_data.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Produces VillagerData, VillagerAffinity, DialogueChoice, DialogueNode.
- Produces level_for(value: int) -> int, add(amount: int) -> Dictionary, is_terminal() -> bool.

- [ ] **Step 1: Write the failing test**

~~~
var affinity = Affinity.new()
affinity.value = 20
assertions.equal(affinity.add(1).level, Affinity.Level.FRIEND, "21 enters FRIEND")
assertions.equal(affinity.add(200).value, 100, "affinity clamps")
assertions.equal(Affinity.level_for(51), Affinity.Level.CLOSE, "51 enters CLOSE")
assertions.truthy(DialogueNodeScript.new().is_terminal(), "empty node is terminal")
~~~

- [ ] **Step 2: Run RED**

Run: godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd

Expected: FAIL with a missing villager_affinity.gd preload.

- [ ] **Step 3: Implement exact Resources**

~~~
class_name VillagerAffinity
extends Resource
enum Level { STRANGER, FRIEND, CLOSE, SOULMATE }
@export var villager_id := ""
@export_range(0, 100) var value := 0
static func level_for(amount: int) -> Level:
	if amount <= 20: return Level.STRANGER
	if amount <= 50: return Level.FRIEND
	if amount <= 80: return Level.CLOSE
	return Level.SOULMATE
func add(amount: int) -> Dictionary:
	var old_level := level_for(value)
	value = clampi(value + amount, 0, 100)
	return {"value": value, "old_level": old_level, "level": level_for(value)}
~~~

VillagerData exports villager_id, villager_name, role, scene_path, home_position, work_position, schedule, dialogue_tree, affinity_rewards, unlock_condition. DialogueChoice exports choice_id, text, next_node, condition. DialogueNode exports node_id, speaker, text, choices, default_next, condition, effects, and is terminal only when choices/default_next are both empty.

- [ ] **Step 4: Run GREEN**

Run the Task 1 command. Expected: exit 0 and all new checks pass.

- [ ] **Step 5: Commit**

~~~
git add scripts/data tests/test_villager_data.gd tests/run_tests.gd
git commit -m "feat: add villager dialogue resources"
~~~

### Task 2: Deterministic DialogueService

**Files:**
- Create: scripts/systems/dialogue_service.gd
- Create: tests/test_dialogue_service.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Consumes Array[DialogueNode], VillagerAffinity, context containing item_ids, story_chapter, flags.
- Produces begin(villager_id, nodes, affinity, context), choose(choice_id), continue_default(), end().
- Returns {ok, state, node_id, speaker, text, choices, effects}; state is active, ended, error.

- [ ] **Step 1: Write the failing test**

~~~
var opened = service.begin("old_li", nodes, affinity, {"item_ids": [], "story_chapter": 0, "flags": {}})
assertions.equal(opened.node_id, "greeting", "opens root")
assertions.equal(opened.choices.size(), 1, "filters gated choice")
assertions.equal(service.choose("gift").state, "active", "choice advances")
assertions.equal(affinity.value, 5, "effect applies once")
assertions.equal(service.choose("gift").state, "error", "old choice cannot replay")
assertions.equal(service.begin("old_li", cyclic_nodes, affinity, {}).state, "error", "cycle rejected")
~~~

- [ ] **Step 2: Run RED**

Run the standard test command. Expected: FAIL because dialogue_service.gd is absent.

- [ ] **Step 3: Implement graph resolution**

~~~
func choose(choice_id: String) -> Dictionary:
	if _state != "active" or not _visible_choices.has(choice_id):
		return {"ok": false, "state": "error", "error": "invalid_choice"}
	var choice: DialogueChoice = _visible_choices[choice_id]
	_apply_effects(_current.effects)
	return _move_to(choice.next_node)

func _condition_matches(condition: Dictionary) -> bool:
	return int(condition.get("affinity_min", 0)) <= _affinity.value \
		and (str(condition.get("has_item", "")) == "" or str(condition.has_item) in _context.item_ids) \
		and int(condition.get("story_chapter_min", 0)) <= int(_context.story_chapter)
~~~

Index IDs once, require root greeting, reject duplicate IDs and reachable cycles as dialogue_cycle, and apply a departing node once. Return accepted give_item/set_flag effects for VillagerSystem to commit; reject effects outside affinity -100 through 100 or empty give_item/set_flag. This file imports neither singleton nor scripts/agents.

- [ ] **Step 4: Run GREEN**

Run the standard test command. Expected: gated/malformed/cyclic choices cannot alter state.

- [ ] **Step 5: Commit**

~~~
git add scripts/systems/dialogue_service.gd tests/test_dialogue_service.gd tests/run_tests.gd
git commit -m "feat: resolve deterministic villager dialogue"
~~~

### Task 3: VillagerSystem schedule, affinity, and serialization

**Files:**
- Create: scripts/systems/villager_system.gd
- Modify: scripts/core/game_data.gd
- Create: tests/test_villager_system.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Produces `configure(inventory_system: InventorySystem, economy_system: Node) -> void`, register_villager(villager), schedule_entry_for(schedule, hour), affinity_for(id), add_affinity(id, amount), start_dialogue(id, context), choose_dialogue(choice_id), to_dict(), from_dict().

- [ ] **Step 1: Write the failing test**

~~~
assertions.equal(system.schedule_entry_for(schedule, 23).state, "SLEEPING", "overnight at 23")
assertions.equal(system.schedule_entry_for(schedule, 4).state, "SLEEPING", "overnight at 04")
assertions.equal(system.schedule_entry_for(schedule, 8).state, "WORKING", "day at 08")
system.add_affinity("old_li", 51)
assertions.equal(system.to_dict().affinity.old_li, 51, "persists affinity")
~~~

- [ ] **Step 2: Run RED**

Run the standard test command. Expected: FAIL because villager_system.gd is absent.

- [ ] **Step 3: Implement authority**

~~~
func _on_time_changed(hour: int, minute: int) -> void:
	if minute != 0: return
	for villager in _villagers.values():
		villager.apply_schedule(schedule_entry_for(villager.villager_data.schedule, hour))

static func schedule_entry_for(schedule: Array[Dictionary], hour: int) -> Dictionary:
	for entry in schedule:
		var start := int(entry.hour_start); var finish := int(entry.hour_end)
		if (start < finish and hour >= start and hour < finish) or (start > finish and (hour >= start or hour < finish)):
			return entry
	return {}
~~~

Consume the existing Plan 1 EventBus declarations. Store the injected `InventorySystem`; emit affinity_changed, then affinity_level_up on crossing. Resolve each `affinity_rewards[str(new_level)]` ID through `GameData.get_item` and grant the resulting `Item` through the injected `inventory_system.add_item(item)`. Route start/choose/end through DialogueService; resolve `give_item` IDs the same way and commit give_item/set_flag only after ok. Serialize exactly {"affinity": {villager_id: value}, "flags": flags}, accepting only registered IDs on load.

- [ ] **Step 4: Run GREEN**

Run the standard test command. Expected: schedule, reward, signal, clamp, persistence tests pass.

- [ ] **Step 5: Commit**

~~~
git add scripts/systems/villager_system.gd scripts/core/game_data.gd tests/test_villager_system.gd tests/run_tests.gd
git commit -m "feat: schedule villagers and persist affinity"
~~~

### Task 4: Peaceful actor and player interaction

**Files:**
- Create: scripts/actors/villager.gd
- Create: scenes/actors/villager.tscn
- Modify: scripts/actors/player.gd
- Modify: project.godot
- Create: tests/test_villager_logic.gd
- Modify: tests/test_player_logic.gd, tests/run_tests.gd

**Interfaces:**
- Produces apply_schedule(entry), interact(player), set_agent_destination(destination), face_agent_actor(actor_id), perform_agent_work(work_id), say_agent_text(text).
- Emits interaction_requested(villager), speech_requested(villager_id, text).

- [ ] **Step 1: Write the failing test**

~~~
var villager = VillagerScript.new()
villager.set_agent_destination(Vector3(3.0, 0.0, -2.0))
assertions.equal(villager.current_state, "MOVING_TO_WANDER", "bounded agent move")
villager.apply_schedule({"state": "SLEEPING", "position": "home"})
assertions.equal(villager.current_state, "MOVING_TO_HOME", "sleep walks home")
assertions.truthy(not villager.has_method("take_hit"), "no combat API")
assertions.truthy(not PlayerScript.new().has_signal("fire_requested"), "no fire signal")
~~~

- [ ] **Step 2: Run RED**

Run standard tests. Expected: FAIL because Villager does not exist.

- [ ] **Step 3: Implement local movement, bounded adapter, no combat**

~~~
func apply_schedule(entry: Dictionary) -> void:
	match str(entry.get("state", "IDLE")):
		"WORKING": _set_target(villager_data.work_position, "MOVING_TO_WORK")
		"WANDERING": _set_target(_waypoint_for_current_hour(), "MOVING_TO_WANDER")
		"SLEEPING": _set_target(villager_data.home_position, "MOVING_TO_HOME")
		_: current_state = "IDLE"; velocity = Vector3.ZERO
func set_agent_destination(destination: Vector3) -> void:
	_set_target(destination, "MOVING_TO_WANDER")
~~~

Physics calls movement only in MOVING states and arrival resolves WORKING/SLEEPING/WANDERING. interact only emits interaction_requested. face accepts registered actor IDs, work accepts only villager_data.role, say rejects empty or longer than 280. Remove player health, CombatMath, fire signal, fire method, damage method, click firing and raycast; add 2.0-radius group interaction, inputs, masks 81 and layer-256 Area.

- [ ] **Step 4: Run GREEN**

Run standard tests. Expected: movement/no-combat tests pass.

- [ ] **Step 5: Commit**

~~~
git add scripts/actors/villager.gd scenes/actors/villager.tscn scripts/actors/player.gd project.godot tests/test_villager_logic.gd tests/test_player_logic.gd tests/run_tests.gd
git commit -m "feat: replace combat actor behavior with villagers"
~~~

### Task 5: Author villagers and migrate Main while staging combat retirement

**Files:**
- Create: data/villagers/old_li.tres, xiao_hua.tres, blacksmith_zhang.tres
- Create: data/dialogues/old_li_dialogue.tres, xiao_hua_dialogue.tres, blacksmith_zhang_dialogue.tres
- Modify: scenes/main.tscn, scripts/main.gd, tests/smoke_test.gd, tests/run_tests.gd
- Retain until Plan 9: scripts/actors/npc.gd, scenes/actors/npc.tscn, scripts/combat/projectile.gd, scripts/shared/combat_math.gd, scenes/combat/projectile.tscn and their existing tests

**Interfaces:**
- Produces Actors/Villagers containing three instances and Main._on_villager_interaction_requested(villager).

- [ ] **Step 1: Write the failing migration test**

~~~
assertions.truthy(main.has_node("Actors/Villagers"), "villager container")
assertions.equal(main.get_node("Actors/Villagers").get_child_count(), 3, "three villagers")
assertions.truthy(not main.has_node("Projectiles"), "no projectile container")
assertions.truthy(ResourceLoader.exists("res://scripts/actors/npc.gd"), "legacy remains recoverable until final migration")
~~~

- [ ] **Step 2: Run RED**

Run standard tests. Expected: FAIL because Npcs/Projectiles remain.

- [ ] **Step 3: Author exact data and scene wiring**

Old Li is shopkeeper home (-3.2,0,-2), work (-2,0,-1); Xiao Hua florist home (3,0,-3.2), work (2,0,-2); Blacksmith Zhang blacksmith home (4,0,2.4), work (3.5,0,1.4). Each schedule is 6–8 IDLE, 8–12 WORKING, 12–13 IDLE, 13–17 WORKING, 17–19 WANDERING, 19–21 MOVING_TO_HOME, 21–6 SLEEPING. Each graph has greeting and farewell; Old Li gift adds 5. Replace active Npcs with Villagers, detach Projectiles from Main, add Systems/VillagerSystem, place/register instances, and connect interaction to start_dialogue. Configure VillagerSystem with the existing InventorySystem and EconomySystem, then reconfigure EconomySystem with InventorySystem, GameState, and VillagerSystem so completed orders can call the published `add_affinity(id, amount)` interface. Keep legacy combat files and isolated tests untouched so Plan 9 can audit and remove them after HUD and save migration pass.

- [ ] **Step 4: Verify GREEN**

~~~
godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 120
~~~

Expected: all exit 0; smoke finds three peaceful villagers and no combat resources.

- [ ] **Step 5: Commit**

~~~
git add data scenes/main.tscn scripts/main.gd tests/smoke_test.gd tests/run_tests.gd
git commit -m "feat: migrate active NPCs to villagers"
~~~

### Task 6: Dialogue UI and Villager serialization adapter

**Files:**
- Create: scripts/ui/dialogue_ui.gd, scenes/ui/dialogue_ui.tscn, tests/test_dialogue_ui.gd, tests/test_villager_persistence.gd
- Modify: scenes/main.tscn, scripts/main.gd, tests/run_tests.gd

**Interfaces:**
- Produces show_dialogue(view), show_story(text), hide_dialogue.
- Consumes EventBus dialogue_started/dialogue_ended/story_text_display and VillagerSystem.choose_dialogue.

- [ ] **Step 1: Write the failing UI/serialization test**

~~~
ui.show_dialogue({"speaker":"老李","text":"早上好。","choices":[{"choice_id":"farewell","text":"再见"}]})
assertions.truthy(ui.visible, "dialogue visible")
assertions.equal(ui.speaker_name.text, "老李", "speaker shown")
assertions.equal(ui.choices.get_child_count(), 1, "allowed choice shown")
assertions.equal(restored.affinity_for("old_li").value, 51, "affinity restores")
~~~

- [ ] **Step 2: Run RED**

Run standard tests. Expected: FAIL because UI and VillagerSystem serialization wiring are absent.

- [ ] **Step 3: Implement exact presentation and persistence**

Create DialogueUI > DialoguePanel > SpeakerRow > SpeakerPortrait/SpeakerName; TextContainer RichTextLabel; ChoicesContainer VBoxContainer; ContinueHint. Bottom anchor height is 200 and starts hidden. Render supplied choices only and bind to choose_dialogue; hide only after ended. Implement `VillagerSystem.to_dict() -> Dictionary` and `from_dict(data: Dictionary) -> bool`, restoring affinity and flags only after villagers register. UI never polls or mutates game state. Plan 7 will compose this adapter into SaveManager and add autosave; EconomySystem remains the sole owner of active orders.

- [ ] **Step 4: Final verification**

~~~
godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 120
git diff --check
~~~

Expected: exit 0. Desktop: approach Old Li, press E, choose gift once, see affinity update, reach farewell; the adapter unit test round-trips affinity 51.

- [ ] **Step 5: Commit**

~~~
git add scripts/ui/dialogue_ui.gd scenes/ui/dialogue_ui.tscn scenes/main.tscn scripts/main.gd scripts/systems/villager_system.gd tests/test_dialogue_ui.gd tests/test_villager_persistence.gd tests/run_tests.gd
git commit -m "feat: present and serialize villager dialogue"
~~~

## Completion Gate

Future AI Phase A may attach only after this plan is green, using Task 4 adapters and its own protocol validator; it may not bypass VillagerSystem or DialogueService.
