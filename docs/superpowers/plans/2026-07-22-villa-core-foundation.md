# Villa Core Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the typed core runtime foundation: EventBus, GameData, GameState, shared data Resources, test registration, and a deterministic minimum SeasonSystem clock.
**Architecture:** Autoloads are the only cross-system boundary: EventBus carries typed notifications, GameData owns immutable definitions, GameState owns mutable global values, and SeasonSystem advances time. Resource classes are passive typed data so Grid/Farming and later systems can consume them without circular dependencies. This plan deliberately excludes SaveManager implementation and all gameplay systems.
**Tech Stack:** Godot 4.7, GDScript, Godot Resources, Jolt Physics, headless GDScript tests.

## Global Constraints
- Use Godot 4.7, GL Compatibility, Jolt Physics, and no third-party test plugin.
- Tests extend RefCounted, expose run(assertions), register in tests/run_tests.gd, and run with godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd.
- Register EventBus, GameData, and GameState in project.godot Autoload using exactly res://scripts/core/event_bus.gd, game_data.gd, game_state.gd.
- EventBus is notification-only; systems do not mutate another system’s state in a signal handler except through that system’s documented public method.
- GameData accepts data only during setup; duplicate or empty stable IDs emit push_error and never replace a prior definition.
- GameState begins with gold 100, one PlayerState containing stamina/max_stamina 100, level 1 and exp 0, and play_time 0.0; it emits gold_changed only after a successful positive change.
- Season is exactly SPRING 0, SUMMER 1, AUTUMN 2, WINTER 3; every season has exactly 7 in-game days.
- Time starts at 06:00. One real second equals one game minute. Emit time_changed for every crossed game minute, day_changed after midnight reset, and season_changed only on season rollover.
- This plan creates no save/load implementation; SaveManager remains a later plan’s responsibility.
- Grid/Farming consumes only the interfaces published below and must not add private dependencies to core scripts.
---

## File Structure
| Path | Responsibility |
|---|---|
| scripts/core/event_bus.gd | All typed global signals declared in detailed design §3. |
| scripts/core/game_data.gd | ID-indexed crop definitions and registration. |
| scripts/core/game_state.gd | Gold/player-level runtime values and safe mutators. |
| scripts/systems/season_system.gd | Minimum clock and season rollover signal source. |
| scripts/data/grid_cell.gd | Grid cell state/value object. |
| scripts/data/crop_data.gd | Authored crop definition Resource. |
| scripts/data/crop_instance.gd | Per-cell crop growth state. |
| scripts/data/player_state.gd | XP threshold helper used by GameState. |
| tests/test_core_foundation.gd | Pure core and signal behavior. |
| tests/test_season_system.gd | Clock rollover behavior. |
### Task 1: Core data Resources and test harness registration
**Files:**
- Create: scripts/data/grid_cell.gd
- Create: scripts/data/crop_data.gd
- Create: scripts/data/crop_instance.gd
- Create: scripts/data/player_state.gd
- Create: tests/test_core_foundation.gd
- Modify: tests/run_tests.gd
**Interfaces:**
- Produces GridCell.world_position() -> Vector2 and world_position_3d() -> Vector3.
- Produces CropInstance.advance_growth() -> bool and get_current_stage() -> int.
- Produces PlayerState stamina/max_stamina, add_exp(amount: int) -> bool, set_stamina(value: int) -> bool, and get_exp_progress() -> float.
- [ ] **Step 1: Write the failing test**
~~~
var cell = GridCellScript.new()
cell.gx = 0; cell.gz = 0; cell.terrain_height = 2.5
assertions.equal(cell.world_position(), Vector2(-17.5, -13.5), "grid origin maps to center")
assertions.equal(cell.world_position_3d(), Vector3(-17.5, 2.5, -13.5), "3d position includes terrain")
var crop = CropInstanceScript.new()
crop.crop_data = make_crop(3, 4)
crop.is_watered_today = true
assertions.truthy(not crop.advance_growth(), "first growth is not mature")
assertions.near(crop.growth_progress, 1.5, 0.001, "watered growth advances one and a half days")
assertions.equal(crop.get_current_stage(), 1, "stage follows progress")
~~~
- [ ] **Step 2: Run RED**
Run: godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
Expected: FAIL because the data scripts and test preload do not exist.
- [ ] **Step 3: Implement typed Resources**
~~~
class_name GridCell
extends RefCounted
enum State { WASTELAND, FARMLAND, PLANTED, BUILDING, ROAD, WATER, DECORATION }
var gx := 0
var gz := 0
var state: State = State.WASTELAND
var watered := false
var crop_instance: CropInstance
var terrain_height := 0.0
var slope := 0.0
func world_position() -> Vector2:
	return Vector2(float(gx) - 17.5, float(gz) - 13.5)
func world_position_3d() -> Vector3:
	var point := world_position()
	return Vector3(point.x, terrain_height, point.y)
~~~
CropData exports crop_id, crop_name, category, growth_days default 3, seasons, seed_price, sell_price, exp_reward, seed_drop_chance default 0.2, stage_textures, water_required. CropInstance stores `growth_progress: float`, adds `1.5` when watered and `1.0` otherwise, resets is_watered_today after advance, marks mature when progress reaches crop_data.growth_days, and returns stage 0 for an empty stage_textures list. Its serialization uses `growth_progress`; UI may display `floori(growth_progress)` as elapsed whole days. PlayerState owns stamina/max_stamina plus level/exp, clamps stamina in `set_stamina`, emits the existing stamina signal only on change, and uses exact level thresholds [0,100,250,500,850,1300,1900,2600,3500,4600,6000].
- [ ] **Step 4: Run GREEN**
Run the Task 1 command. Expected: exit 0 and cell/crop/XP assertions pass.
- [ ] **Step 5: Commit**
~~~
git add scripts/data tests/test_core_foundation.gd tests/run_tests.gd
git commit -m "feat: add core data resources"
~~~
### Task 2: EventBus, GameData, GameState, and Autoloads
**Files:**
- Create: scripts/core/event_bus.gd
- Create: scripts/core/game_data.gd
- Create: scripts/core/game_state.gd
- Modify: project.godot
- Create: tests/test_core_autoloads.gd
- Modify: tests/run_tests.gd
**Interfaces:**
- Produces EventBus signals cell_state_changed, cell_watered, crop_planted, crop_grew, crop_matured, crop_harvested, gold_changed, season_changed, day_changed, time_changed, stamina_changed, level_changed, exp_gained.
- Produces GameData.register_crop(data: CropData) -> bool and get_crop(id: String) -> CropData.
- Produces GameState.add_gold(amount: int) -> bool, spend_gold(amount: int) -> bool, add_exp(amount: int) -> bool.
- [ ] **Step 1: Write the failing test**
~~~
var data = GameDataScript.new()
assertions.truthy(data.register_crop(make_crop_data("turnip")), "first ID registers")
assertions.truthy(not data.register_crop(make_crop_data("turnip")), "duplicate rejected")
assertions.equal(data.get_crop("turnip").crop_name, "Turnip", "lookup returns authored crop")
var state = GameStateScript.new()
assertions.truthy(state.spend_gold(30), "can spend available gold")
assertions.equal(state.gold, 70, "spend changes gold")
assertions.truthy(not state.spend_gold(71), "cannot overspend")
~~~
- [ ] **Step 2: Run RED**
Run the standard test command. Expected: FAIL because core scripts are absent.
- [ ] **Step 3: Implement core authority and configuration**
~~~
func register_crop(data: CropData) -> bool:
	if data == null or data.crop_id.is_empty() or _crops.has(data.crop_id):
		push_error("Invalid or duplicate crop ID")
		return false
	_crops[data.crop_id] = data
	return true
func spend_gold(amount: int) -> bool:
	if amount <= 0 or amount > gold: return false
	gold -= amount
	EventBus.gold_changed.emit(gold)
	return true
~~~
Declare every detailed-design §3 signal now, using Variant only for types not created by this plan and the exact typed farming/time signatures. GameState owns a PlayerState instance and forwards successful XP changes as exp_gained(amount), emitting level_changed after PlayerState levels. Add three Autoload entries under [autoload] with EventBus, GameData, GameState Node paths; do not register SaveManager yet.
- [ ] **Step 4: Run GREEN and import**
~~~
godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
~~~
Expected: both commands exit 0; project settings expose exactly the three new core Autoloads.
- [ ] **Step 5: Commit**
~~~
git add scripts/core project.godot tests/test_core_autoloads.gd tests/run_tests.gd
git commit -m "feat: add core game autoloads"
~~~
### Task 3: Minimum SeasonSystem clock
**Files:**
- Create: scripts/systems/season_system.gd
- Create: tests/test_season_system.gd
- Modify: tests/run_tests.gd
**Interfaces:**
- Consumes EventBus.time_changed(hour: int, minute: int), day_changed(total_day: int), season_changed(new_season: int).
- Produces SeasonSystem.advance_game_minutes(minutes: int) -> void, current_season, current_day, total_days, hour, minute.
- [ ] **Step 1: Write the failing rollover test**
~~~
var clock = SeasonSystemScript.new()
clock.hour = 23; clock.minute = 59
clock.advance_game_minutes(1)
assertions.equal(clock.hour, 6, "midnight resets to 06")
assertions.equal(clock.current_day, 2, "day advances")
clock.current_day = 7; clock.current_season = clock.Season.SPRING
clock.hour = 23; clock.minute = 59
clock.advance_game_minutes(1)
assertions.equal(clock.current_day, 1, "season day wraps")
assertions.equal(clock.current_season, clock.Season.SUMMER, "season advances")
~~~
- [ ] **Step 2: Run RED**
Run the standard test command. Expected: FAIL because season_system.gd is absent.
- [ ] **Step 3: Implement deterministic minute advancement**
~~~
func advance_game_minutes(minutes_to_add: int) -> void:
	for unused in range(maxi(0, minutes_to_add)):
		minute += 1
		if minute >= 60:
			minute = 0
			hour += 1
		if hour >= 24:
			hour = 6
			current_day += 1
			total_days += 1
			if current_day > DAYS_PER_SEASON:
				current_day = 1
				current_season = (current_season + 1) % 4
				EventBus.season_changed.emit(current_season)
			EventBus.day_changed.emit(total_days)
		EventBus.time_changed.emit(hour, minute)
~~~
Set DAYS_PER_SEASON to 7, MINUTES_PER_REAL_SECOND to 1.0, start at Spring/day 1/total day 1/06:00, and let _process accumulate fractional real seconds then call advance_game_minutes only for whole minutes. Do not implement terrain, weather, tree, or save visuals in this minimal skeleton.
- [ ] **Step 4: Run GREEN**
Run standard tests. Expected: minute signal count, midnight, seven-day rollover, and no-negative-minute tests pass.
- [ ] **Step 5: Commit**
~~~
git add scripts/systems/season_system.gd tests/test_season_system.gd tests/run_tests.gd
git commit -m "feat: add deterministic season clock"
~~~
### Task 4: Core completion gate
**Files:**
- Verify only.
**Interfaces:**
- Produces the public core contracts consumed by the Grid/Farming plan.
- [ ] **Step 1: Verify all tests and a clean import**
~~~
godot --headless --path /Users/huanggui/UnrealEngine/villa --script tests/run_tests.gd
godot --headless --path /Users/huanggui/UnrealEngine/villa --editor --quit
git diff --check
~~~
Expected: all commands exit 0. The next plan may call only GameData.get_crop, GameState add_gold/spend_gold/add_exp, SeasonSystem current_season, EventBus farm/time signals, and the four data classes.
- [ ] **Step 2: Commit verification record**
~~~
git status --short
git log -3 --oneline
~~~
Expected: the three task commits are visible; no commit is created by this verification task.
