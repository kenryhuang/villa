# Villa Exploration, Story, Collectibles, and Puzzles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build deterministic fog/region exploration, collectible discovery, four playable puzzle types, story fragments/chapters, map presentation, and persistent exploration state.

**Architecture:** ExplorationSystem owns one fog image and delegates unlock eligibility to RegionManager. CollectibleSystem and PuzzleSystem own one-time discovery/solve state; scene actors only submit events. StorySystem consumes fragment IDs and asks RegionManager to unlock milestones. Map UI renders signals/textures only and has no authority.

**Tech Stack:** Godot 4.7, GDScript, Jolt Physics, spatial shader, Godot Resources, CanvasLayer UI, headless GDScript tests.

## Global Constraints

- Use Godot 4.7, GL Compatibility, Jolt Physics, and the existing RefCounted test harness; add no testing dependency.
- Run all tests with: godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd.
- World extent remains Rect2(-17.2, -13.2, 34.4, 26.4). Shader mapping is world_size vec2(36.0,28.0), world_offset vec2(-18.0,-14.0).
- Fog is one 256 by 256 L8 Image: black unexplored, white explored. Player reveal radius is 3.0. Emit area_revealed only if a black pixel changes.
- Region conditions are level, item, resource, story_progress; all must pass. Unknown type fails closed.
- Consume the EventBus signals `region_unlocked`, `area_revealed`, `collectible_found`, `collectible_category_completed`, `puzzle_solved`, `story_fragment_collected`, `story_chapter_revealed`, and `story_text_display` already declared by Plan 1; do not redeclare them.
- Collection, puzzle solving, and fragment collection are idempotent per stable ID; duplicate events cannot grant rewards, change chapters, or emit completion signals.
- Implement exactly PushPuzzle, PathPuzzle, LightPuzzle, OfferingPuzzle. Rewards are granted only inside Puzzle._solve.
- Collectible Areas use layer 128 and puzzle triggers layer 512. Preserve terrain 1, player 2, building 64; player mask is 81.
- Story milestones are exactly 3→chapter 1→creek, 6→chapter 2→deep_forest, 9→chapter 3→mist_peak, 12→chapter 4→secret_garden, with keys story_chapter_1 through story_chapter_4.
- Persist only IDs, unlocked region IDs, fog PackedByteArray, and revealed chapter; never serialize Nodes, shader objects, Resources, or UI.
- No AI Agent is implemented. Future code may observe filtered local events but must submit any proposed state change to these Godot-authoritative systems.

---

## File Structure

| Path | Responsibility |
|---|---|
| scripts/data/collectible_data.gd, puzzle_data.gd, region_data.gd, story_fragment.gd | Typed authored content. |
| scripts/systems/exploration_system.gd, region_manager.gd | Fog lifecycle, reveal, region eligibility. |
| scripts/systems/collectible_system.gd, collection_book.gd | Discovery and category progress. |
| scripts/systems/puzzle_system.gd, scripts/puzzles | Shared solve gate and four rules. |
| scripts/systems/story_system.gd | Fragment milestones and unlock request. |
| scripts/collectibles/collectible_pickup.gd | One local pickup entry point. |
| assets/shaders/fog_of_war.gdshader, scenes/world/fog_of_war.tscn | World fog. |
| scripts/ui/map_ui.gd, scenes/ui/map_ui.tscn | Read-only map view. |

### Task 1: Typed exploration Resources and GameData indices

**Files:**
- Create: scripts/data/collectible_data.gd, puzzle_data.gd, region_data.gd, story_fragment.gd
- Modify: scripts/core/game_data.gd
- Create: tests/test_exploration_data.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Produces CollectibleData, PuzzleData, RegionData, StoryFragment exactly per detailed-design §§2.11–2.14.
- Produces GameData.get_collectible(id), get_puzzle(id), get_region(id), get_story_fragment(id), get_story_text(key).

- [ ] **Step 1: Write the failing test**

~~~
var data = GameDataScript.new()
data.register_collectible(collectible)
assertions.equal(data.get_collectible("diary_001"), collectible, "stable lookup")
assertions.equal(PuzzleDataScript.PuzzleType.OFFERING, 3, "four-type enum stable")
assertions.equal(data.get_story_text("story_chapter_1"), "这里曾经有人生活。", "authored text")
~~~

- [ ] **Step 2: Run RED**

Run the standard test command. Expected: FAIL with absent Resources/index methods.

- [ ] **Step 3: Implement closed data indices**

Collectible category enum is DIARY_FRAGMENT, RARE_SEED, FOSSIL, ARTIFACT, PLANT_SPECIMEN, ANIMAL_TRACK, MESSAGE_BOTTLE, MINERAL. Puzzle enum is PUSH, PATH_CONNECT, LIGHT_REFLECTION, OFFERING. Region exports bounds/conditions/scene/stamina multiplier; fragment exports fragment_id/chapter/text/collectible_id. GameData rejects empty or duplicate IDs without replacing original. Seed chapter texts exactly: 这里曾经有人生活。, 他是位植物学家，正在寻找什么。, 花园深处藏着一项未完成的培育。, 终极种子会让山谷重获生机。.

- [ ] **Step 4: Run GREEN**

Run standard tests. Expected: data and enum tests pass.

- [ ] **Step 5: Commit**

~~~
git add scripts/data scripts/core/game_data.gd tests/test_exploration_data.gd tests/run_tests.gd
git commit -m "feat: add exploration content resources"
~~~

### Task 2: Fog reveal, gated RegionManager, and World scene

**Files:**
- Create: scripts/systems/exploration_system.gd, scripts/systems/region_manager.gd
- Create: assets/shaders/fog_of_war.gdshader, scenes/world/fog_of_war.tscn
- Modify: scripts/world/world.gd, scenes/world/world.tscn
- Modify: scripts/main.gd, scenes/main.tscn
- Create: tests/test_exploration_system.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Produces configure(fog_material), reveal_area(x,z,radius) -> bool, fog_bytes() -> PackedByteArray, load_fog_bytes(bytes) -> bool.
- Produces `RegionManager.configure(game_state: Node, inventory_system: InventorySystem, economy_system: Node, story_system: Node, blockers_root: Node) -> void`, is_unlocked(id), can_unlock(region), unlock_region(id) -> bool.

- [ ] **Step 1: Write the failing test**

~~~
assertions.truthy(exploration.reveal_area(0.0, 0.0, 3.0), "first reveal changes fog")
assertions.truthy(not exploration.reveal_area(0.0, 0.0, 3.0), "same reveal is idempotent")
assertions.equal(exploration.fog_bytes().size(), 65536, "one byte per pixel")
assertions.truthy(not regions.unlock_region("peak"), "unmet requirements block")
assertions.truthy(not regions.can_unlock(unknown_condition_region), "unknown fails closed")
~~~

- [ ] **Step 2: Run RED**

Run standard tests. Expected: FAIL because systems/scene do not exist.

- [ ] **Step 3: Implement fog and region authority**

~~~
func reveal_area(center_x: float, center_z: float, radius: float) -> bool:
	var cx := int(((center_x + 18.0) / 36.0) * 256.0)
	var cz := int(((center_z + 14.0) / 28.0) * 256.0)
	var pixels := int(radius / 36.0 * 256.0)
	var changed := false
	for dz in range(-pixels, pixels + 1):
		for dx in range(-pixels, pixels + 1):
			if dx * dx + dz * dz <= pixels * pixels:
				var x := clampi(cx + dx, 0, 255); var z := clampi(cz + dz, 0, 255)
				if fog_image.get_pixel(x, z).r < 1.0: fog_image.set_pixel(x, z, Color.WHITE); changed = true
	if changed: fog_texture.update(fog_image); EventBus.area_revealed.emit(center_x, center_z, radius)
	return changed
~~~

Initialize black FORMAT_L8 256 image and ImageTexture. RegionManager stores injected scene-system collaborators and checks `game_state.player_state.level`, `inventory_system.has_item`, `economy_system.has_resources`, and `story_system.fragment_count()`. A missing collaborator fails its corresponding condition closed. On success set region.unlocked, disable the matching blocker below the injected `World/Regions` root, and emit once. Add FogOfWar and Farm/Creek/Forest/Peak Region Areas. Main configures RegionManager only after all collaborators exist and passes player world position to ExplorationSystem after movement.

- [ ] **Step 4: Run GREEN and import**

~~~
godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
~~~

Expected: exit 0 and no shader/scene parse error.

- [ ] **Step 5: Commit**

~~~
git add scripts/systems/exploration_system.gd scripts/systems/region_manager.gd assets/shaders/fog_of_war.gdshader scenes/world/fog_of_war.tscn scripts/world/world.gd scenes/world/world.tscn tests/test_exploration_system.gd tests/run_tests.gd
git commit -m "feat: reveal exploration fog and gated regions"
~~~

### Task 3: CollectibleSystem, CollectionBook, and pickups

**Files:**
- Create: scripts/systems/collectible_system.gd, scripts/systems/collection_book.gd
- Create: scripts/collectibles/collectible_pickup.gd, scenes/collectibles/collectible_pickup.tscn
- Create: tests/test_collectible_system.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Produces collect(data) -> bool, is_collected(id), to_dict(), from_dict().
- Produces CollectionBook.configure(definitions), discover(id) -> bool, category_progress(category).
- Produces CollectiblePickup.collect_for(body) -> bool.

- [ ] **Step 1: Write the failing test**

~~~
assertions.truthy(system.collect(diary), "first collection succeeds")
assertions.truthy(not system.collect(diary), "second is ignored")
assertions.equal(book.category_progress(diary.category), {"total":2,"found":1}, "counts discovery")
assertions.equal(system.to_dict().collected, ["diary_001"], "stable saved IDs")
~~~

- [ ] **Step 2: Run RED**

Run standard tests. Expected: FAIL because collectible files are absent.

- [ ] **Step 3: Implement one-time discovery**

collect rejects null/empty/duplicate IDs, records the stable ID, calls CollectionBook.discover, emits collectible_found, and sends a linked story fragment only when is_story_fragment and GameData has that matching fragment. Configure computes total per category once; discover emits category completion only when found first reaches total. CollectiblePickup is Area3D layer 128, accepts only PlayerController, calls collect and frees only on true. Its bob uses base_y plus sin(elapsed*float_speed)*float_amplitude, preventing vertical drift.

- [ ] **Step 4: Run GREEN**

Run standard tests. Expected: duplicate, category, fragment route, round-trip, and bob tests pass.

- [ ] **Step 5: Commit**

~~~
git add scripts/systems/collectible_system.gd scripts/systems/collection_book.gd scripts/collectibles/collectible_pickup.gd scenes/collectibles/collectible_pickup.tscn tests/test_collectible_system.gd tests/run_tests.gd
git commit -m "feat: collect discoveries into the collection book"
~~~

### Task 4: PuzzleSystem and four puzzle implementations

**Files:**
- Create: scripts/systems/puzzle_system.gd
- Create: scripts/puzzles/puzzle.gd, push_puzzle.gd, path_puzzle.gd, light_puzzle.gd, offering_puzzle.gd
- Create: scenes/puzzles/push_puzzle.tscn, path_puzzle.tscn, light_puzzle.tscn, offering_puzzle.tscn
- Create: tests/test_puzzle_system.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Produces register_puzzle(puzzle), is_solved(id), mark_solved(id) -> bool, to_dict(), from_dict().
- Produces `Puzzle.configure(puzzle_system: PuzzleSystem, inventory_system: InventorySystem, economy_system: Node, region_manager: Node) -> void`, Puzzle._solve() -> bool, PushPuzzle.is_configuration_solved(), PathPuzzle.is_path_connected(), LightPuzzle.is_beam_on_target(), OfferingPuzzle.check_offering().

- [ ] **Step 1: Write the failing test**

~~~
assertions.truthy(push.is_configuration_solved(), "distinct stones solve")
assertions.truthy(path.is_path_connected(), "linked path solves")
assertions.truthy(light.is_beam_on_target(), "beam reaches target")
assertions.truthy(offering.check_offering(), "required items consume once")
assertions.truthy(not offering.check_offering(), "solved offering cannot consume twice")
~~~

- [ ] **Step 2: Run RED**

Run standard tests. Expected: FAIL because puzzle classes are absent.

- [ ] **Step 3: Implement single reward gate and rules**

~~~
func _solve() -> bool:
	if is_solved or not puzzle_system.mark_solved(puzzle_id): return false
	is_solved = true
	for item_id in reward_items:
		var item: Item = GameData.get_item(item_id)
		if item != null: inventory_system.add_item(item)
	if reward_gold > 0: economy_system.add_gold(reward_gold)
	if not unlock_region.is_empty(): region_manager.unlock_region(unlock_region)
	puzzle_solved.emit(puzzle_id); EventBus.puzzle_solved.emit(puzzle_id)
	return true
~~~

Every Puzzle instance stores only collaborators supplied by Main or its scene factory; PuzzleSystem, InventorySystem, EconomySystem, and RegionManager are not Autoloads. Push requires one distinct stone within 0.5 for every target. Path uses north/east/south/west booleans and breadth-first searches reciprocal edges from start_cell to end_cell. Light traces source/mirror normals for at most 16 reflections and accepts final distance <= 0.35 to target. Offering validates every required count through the injected InventorySystem before any remove, then removes all values and calls _solve. Every scene has a layer-512 visual/trigger Area and invokes only its named rule.

- [ ] **Step 4: Run GREEN**

Run standard tests. Expected: four-rule, reward-once, duplicate-solve, and unlock tests pass.

- [ ] **Step 5: Commit**

~~~
git add scripts/systems/puzzle_system.gd scripts/puzzles scenes/puzzles tests/test_puzzle_system.gd tests/run_tests.gd
git commit -m "feat: add exploration puzzle types"
~~~

### Task 5: StorySystem and read-only Map UI

**Files:**
- Create: scripts/systems/story_system.gd, scripts/ui/map_ui.gd, scenes/ui/map_ui.tscn
- Modify: scenes/main.tscn, scripts/main.gd
- Create: tests/test_story_system.gd, tests/test_map_ui.gd
- Modify: tests/run_tests.gd

**Interfaces:**
- Produces `StorySystem.configure(region_manager: Node) -> void`, collect_fragment(id) -> bool, fragment_count() -> int, to_dict(), from_dict().
- Produces set_fog_texture(texture), set_region_unlocked(id), set_marker_visible(id, visible).

- [ ] **Step 1: Write the failing test**

~~~
for id in ["fragment_001","fragment_002","fragment_003"]: story.collect_fragment(id)
assertions.equal(story.story_revealed_up_to, 1, "three reveal one")
assertions.equal(regions.unlock_requests, ["creek"], "chapter requests creek")
assertions.truthy(not story.collect_fragment("fragment_003"), "duplicate no repeat")
map.set_marker_visible("diary_001", false)
assertions.truthy(not map.marker_nodes.diary_001.visible, "marker hides")
~~~

- [ ] **Step 2: Run RED**

Run standard tests. Expected: FAIL because StorySystem/MapUI are absent.

- [ ] **Step 3: Implement milestones and map**

~~~
const STORY_MILESTONES := [
	{"fragments_needed":3,"chapter":1,"text_key":"story_chapter_1","region_id":"creek"},
	{"fragments_needed":6,"chapter":2,"text_key":"story_chapter_2","region_id":"deep_forest"},
	{"fragments_needed":9,"chapter":3,"text_key":"story_chapter_3","region_id":"mist_peak"},
	{"fragments_needed":12,"chapter":4,"text_key":"story_chapter_4","region_id":"secret_garden"},
]
~~~

Store the injected RegionManager and IDs sorted for serialization. For each newly reached milestone, set revealed chapter, call `region_manager.unlock_region`, emit story_chapter_revealed and story_text_display(GameData.get_story_text(text_key)). Main configures StorySystem and RegionManager after both scene nodes exist; neither is an Autoload. Build the §7.4 MapUI tree: full screen MapUI, center 800x500 MapPanel, MapViewport/SubViewport, FogOverlay, Markers, four-row legend. Connect map open/close, area reveal, region unlock, collectible found. Map code only changes texture/visibility; it never unlocks, collects, solves, or progresses story.

- [ ] **Step 4: Run GREEN and manual acceptance**

~~~
godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 120
~~~

Expected: exit 0. Desktop: press M; fog clears near player, found marker hides, Creek becomes visible only after third fragment.

- [ ] **Step 5: Commit**

~~~
git add scripts/systems/story_system.gd scripts/ui/map_ui.gd scenes/ui/map_ui.tscn scenes/main.tscn scripts/main.gd tests/test_story_system.gd tests/test_map_ui.gd tests/run_tests.gd
git commit -m "feat: reveal story chapters through exploration"
~~~

### Task 6: First exploration slice and serialization adapters

**Files:**
- Create: data/regions/farm.tres, creek.tres
- Create: data/collectibles/diary_001.tres, diary_002.tres, diary_003.tres
- Create: data/items/rare_seed_moonflower.tres
- Create: data/story_fragments/fragment_001.tres, fragment_002.tres, fragment_003.tres
- Modify: scenes/world/world.tscn, scripts/systems/exploration_system.gd, scripts/systems/collectible_system.gd, scripts/systems/puzzle_system.gd, scripts/systems/story_system.gd, tests/smoke_test.gd, tests/run_tests.gd
- Create: tests/test_exploration_persistence.gd

**Interfaces:**
- Produces `to_dict/from_dict` adapters for the exploration and story sections in detailed-design §6.1; Plan 7 composes them into SaveManager.
- Produces Farm/Creek authored vertical slice.

- [ ] **Step 1: Write failing save/scene test**

~~~
assertions.equal(save.exploration.collected, ["diary_001"], "collectible IDs saved")
assertions.equal(save.exploration.solved_puzzles, ["push_puzzle_001"], "puzzles saved")
assertions.equal(save.story.chapter, 1, "chapter saved")
assertions.truthy(main.has_node("World/FogOfWar"), "world fog")
assertions.truthy(main.has_node("UI/MapUI"), "map UI")
~~~

- [ ] **Step 2: Run RED**

Run standard tests. Expected: FAIL because authored slice and serialization adapters are absent.

- [ ] **Step 3: Author and wire exact content**

Farm starts unlocked; Creek condition is story_progress value 1. Place diary_001 (-5,0,-4), diary_002 (0,0,-5.5), diary_003 (5,0,-3.5), linked to fragments 001–003. Register `rare_seed_moonflower` in GameData, then place push_puzzle_001 (6,0,4) rewarding that item ID. In Main, configure RegionManager with GameState and the existing InventorySystem, EconomySystem, StorySystem, and `World/Regions`; configure StorySystem with RegionManager; configure every puzzle with the existing PuzzleSystem, InventorySystem, EconomySystem, and RegionManager. Implement stable `to_dict/from_dict` methods: exploration fog/regions first, then collectibles, puzzles, and story. The test invokes adapters in that exact order and refreshes MapUI afterward. Do not create SaveManager or autosave wiring here.

- [ ] **Step 4: Final verification**

~~~
godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 120
git diff --check
~~~

Expected: all exit 0. Manually collect diaries and confirm Creek/text once; unit tests round-trip fog/markers/chapter/Creek/pickup IDs through adapters.

- [ ] **Step 5: Commit**

~~~
git add data/regions data/collectibles data/story_fragments scenes/world/world.tscn scripts/systems/exploration_system.gd scripts/systems/collectible_system.gd scripts/systems/puzzle_system.gd scripts/systems/story_system.gd tests/test_exploration_persistence.gd tests/smoke_test.gd tests/run_tests.gd
git commit -m "feat: serialize the first exploration story slice"
~~~

## Completion Gate

The feature is complete only when fog, region gates, discovery, all four puzzle rules, milestones, map state, and save/load are deterministic. No Agent implementation is authorized by this plan.
