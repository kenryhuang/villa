# Geography and Fishing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce one authoritative set of water, shoreline, flower-distance, and fishing-spot rules, then replace the fishing-rod fiber placeholder with a playable, persistent fishing loop.

**Architecture:** Add a read-only `GeographicQueryService` shared by building placement and production, while keeping inventory mutation in the systems that own each transaction. Add a focused `FishingSystem` that owns fishing sessions, deterministic catches, spot depletion, and serialization; `PlayerActionController` routes input, `GameWorld` owns authored spot anchors, and `SaveManager` persists only durable fishing state.

**Tech Stack:** Godot 4.7.1, typed GDScript, existing `RefCounted` test harness, JSON saves, existing inventory/tool/HUD systems.

---

## Scope and file structure

- Create `scripts/systems/geographic_query_service.gd`: read-only natural-water, shoreline, flower-radius, and cast-line queries.
- Create `scripts/data/fishing_spot_data.gd`: validated authored fishing-spot definition.
- Create `scripts/systems/fishing_system.gd`: session state machine, deterministic catch table, depletion, inventory commit, and persistence.
- Create `scripts/world/fishing_spot.gd`: visible/clickable world anchor that forwards interaction.
- Create `scenes/world/fishing_spot.tscn`: text/icon-free initial world marker and collision target.
- Modify `scripts/systems/building_system.gd`: use the shared shoreline query for preview, placement, and restore validation.
- Modify `scripts/systems/production_system.gd`: use the shared shoreline and mature-flower query.
- Modify `scripts/core/game_data.gd`: add fish, fish products, and declarative catch tables.
- Modify `scripts/core/recipe_database.gd`: add tagged common-fish recipes.
- Modify `scripts/world/world.gd`: expose 3–5 stable authored creek fishing spots.
- Modify `scripts/actors/player_action_controller.gd`: route rod clicks and reel input without treating them as movement/cell actions.
- Modify `scripts/systems/tool_system.gd`: delegate rod durability/stamina commit to `FishingSystem`; remove the fiber reward path.
- Modify `scripts/main.gd`: construct, configure, message-wire, and cancel the new systems.
- Modify `scripts/core/save_manager.gd`: validate, save, restore, and roll back fishing state.
- Create `tests/test_geographic_query_service.gd`, `tests/test_fishing_data.gd`, `tests/test_fishing_system.gd`, `tests/test_fishing_main_integration.gd`, and `tests/run_geography_fishing_tests.gd`.

The existing economy-save aggregate currently has unrelated baseline failures. Each task uses the new focused runner plus the passing building, production, and farming suites; final verification records the aggregate save limitation separately.

### Task 1: Authoritative geographic queries

**Files:**
- Create: `tests/test_geographic_query_service.gd`
- Create: `tests/run_geography_fishing_tests.gd`
- Create: `scripts/systems/geographic_query_service.gd`

- [ ] **Step 1: Write the failing geographic service tests**

Test a 2×2 footprint with no water, diagonal water, orthogonal water, stable anchor ordering, Euclidean flower boundary, mature-only filtering, and cap handling. The intended API is:

```gdscript
var geography := GeographicQueryService.new()
assertions.truthy(geography.configure(grid), "geography accepts the authoritative grid")
assertions.truthy(
	geography.footprint_borders_natural_water(Vector2i(10, 10), Vector2i(2, 2)),
	"orthogonal natural water satisfies the shoreline rule"
)
assertions.equal(
	geography.water_anchor(Vector2i(10, 10), Vector2i(2, 2)),
	Vector2i(12, 10),
	"water anchor uses deterministic distance and coordinate ordering"
)
assertions.equal(
	geography.mature_flowers_near(Vector2(11.0, 11.0), 4.0, 4).size(),
	4,
	"flower query uses Euclidean distance and a stable cap"
)
```

- [ ] **Step 2: Run the focused runner and verify RED**

Run: `godot_console --headless --path . --script res://tests/run_geography_fishing_tests.gd`

Expected: script preload fails because `geographic_query_service.gd` does not exist.

- [ ] **Step 3: Implement the minimal read-only service**

Implement these public methods with stable `gz`, then `gx`, ordering and no per-frame processing:

```gdscript
class_name GeographicQueryService
extends RefCounted

var _grid: GridSystem

func configure(grid: GridSystem) -> bool:
	_grid = grid
	return _grid != null

func footprint_borders_natural_water(origin: Vector2i, size: Vector2i) -> bool
func water_anchor(origin: Vector2i, size: Vector2i) -> Vector2i
func mature_flowers_near(center: Vector2, radius: float, cap: int = 0) -> Array[GridCell]
func is_clear_cast_line(from_cell: Vector2i, target_cell: Vector2i) -> bool
```

`GridCell.State.WATER` is natural water in the current map; irrigation remains the separate `watered` flag and therefore cannot satisfy the query.

- [ ] **Step 4: Run the focused runner and verify GREEN**

Run the focused runner. Expected: all Task 1 checks pass.

- [ ] **Step 5: Commit**

```text
git add scripts/systems/geographic_query_service.gd tests/test_geographic_query_service.gd tests/run_geography_fishing_tests.gd
git commit -m "feat: centralize geographic resource queries"
```

### Task 2: Share shoreline and flower authority

**Files:**
- Modify: `tests/test_building_economy_effects.gd`
- Modify: `scripts/systems/building_system.gd`
- Modify: `scripts/systems/production_system.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Add failing integration assertions**

Add assertions that both systems expose the same injected object and that waterwheel diagnostics reject diagonal water with `water_required`, accept orthogonal water, and return the stable `water_anchor`. Add flower assertions for immature, mature, radius-boundary, outside-boundary, and harvested cells.

```gdscript
building_system.set_geographic_query_service(geography)
production.set_geographic_query_service(geography)
assertions.truthy(building_system.get_geographic_query_service() == geography, "placement uses shared geography")
assertions.truthy(production.get_geographic_query_service() == geography, "production uses shared geography")
```

- [ ] **Step 2: Verify RED**

Run the focused runner and `run_building_system_tests.gd`. Expected: missing setter/getter assertions fail.

- [ ] **Step 3: Inject the service and replace duplicate queries**

Add `set_geographic_query_service()` and `get_geographic_query_service()` to both systems. Keep lazy construction as a test-compatible fallback, but main must construct one service and inject the same instance. Replace `_footprint_borders_water()`, saved shoreline checks after grid restoration, `is_water_connected()`, and `count_nearby_mature_flowers()` with service calls.

- [ ] **Step 4: Verify GREEN and regressions**

Run:

```text
godot_console --headless --path . --script res://tests/run_geography_fishing_tests.gd
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
godot_console --headless --path . --script res://tests/run_production_system_tests.gd
godot_console --headless --path . --script res://tests/run_farming_system_tests.gd
```

- [ ] **Step 5: Commit**

```text
git add scripts/systems/building_system.gd scripts/systems/production_system.gd scripts/main.gd tests/test_building_economy_effects.gd
git commit -m "refactor: share shoreline and flower authority"
```

### Task 3: Fishing catalog and recipes

**Files:**
- Create: `tests/test_fishing_data.gd`
- Modify: `tests/run_geography_fishing_tests.gd`
- Modify: `scripts/core/game_data.gd`
- Modify: `scripts/core/recipe_database.gd`

- [ ] **Step 1: Write failing catalog tests**

Require item IDs `creek_crucian`, `river_perch`, `carp`, `rainbow_trout`, `night_catfish`, `drift_bottle`, `grilled_fish`, and `pickled_fish`. Assert fish category/tags, unique market definitions, catch-table season/hour fields, and recipe station/input/output.

- [ ] **Step 2: Verify RED**

Run the focused runner. Expected: missing fish definitions and recipes fail.

- [ ] **Step 3: Add the exact catalog**

Add declarative `FISHING_TABLES` entries with `item_id`, `weight`, `seasons`, `hour_ranges`, and `unique` fields. Add `item_matches_tag(item_id, tag)` for recipe resolution. Add `grilled_fish` and `pickled_fish` recipes using an input selector record:

```gdscript
{"tag": "common_fish", "quantity": 2}
```

Keep drift bottles out of the market catalog.

- [ ] **Step 4: Verify GREEN**

Run the focused runner and `run_production_system_tests.gd`.

- [ ] **Step 5: Commit**

```text
git add scripts/core/game_data.gd scripts/core/recipe_database.gd tests/test_fishing_data.gd tests/run_geography_fishing_tests.gd
git commit -m "feat: add fishing items and food recipes"
```

### Task 4: Fishing spot definitions and deterministic sessions

**Files:**
- Create: `scripts/data/fishing_spot_data.gd`
- Create: `scripts/systems/fishing_system.gd`
- Create: `tests/test_fishing_system.gd`
- Modify: `tests/run_geography_fishing_tests.gd`

- [ ] **Step 1: Write failing state-machine tests**

Cover invalid spot/distance/water/line/capacity, `IDLE → CASTING → WAITING_BITE → BITE_WINDOW → RESOLVING → COOLDOWN`, timeout/cancel, one settlement per `session_id`, deterministic season/hour filtering, three-success depletion, next-day reset, and empty candidate rejection.

```gdscript
var started := fishing.start_cast("west-creek-01", Vector3(-14.0, 0.0, 0.0), 1, 8, 0)
assertions.truthy(started.ok, "valid shoreline cast starts")
assertions.equal(fishing.get_session_state(), FishingSystem.SessionState.CASTING, "cast enters casting")
fishing.advance_realtime(0.5)
assertions.equal(fishing.get_session_state(), FishingSystem.SessionState.WAITING_BITE, "cast waits for bite")
```

- [ ] **Step 2: Verify RED**

Run the focused runner. Expected: missing fishing data/system scripts.

- [ ] **Step 3: Implement validated data and pure state transitions**

`FishingSpotData` validates stable IDs and water/stand cells. `FishingSystem` exposes:

```gdscript
func configure(grid, geography, inventory, game_data, world_seed: int) -> bool
func register_spot(spot: FishingSpotData) -> bool
func start_cast(spot_id: String, player_position: Vector3, total_day: int, hour: int, minute: int) -> Dictionary
func advance_realtime(delta: float) -> void
func reel(session_id: int) -> Dictionary
func cancel(reason: String) -> bool
func to_dict() -> Dictionary
func validate_dict(value: Dictionary) -> bool
func from_dict(value: Dictionary) -> bool
```

Inject callbacks for rod durability/stamina commit so this system does not mutate `ToolSystem` internals directly. Select catches with a local `RandomNumberGenerator` seeded from world seed, stable spot hash, total day, and `cast_sequence`.

- [ ] **Step 4: Verify GREEN**

Run the focused runner. Expected: all state, determinism, and depletion checks pass.

- [ ] **Step 5: Commit**

```text
git add scripts/data/fishing_spot_data.gd scripts/systems/fishing_system.gd tests/test_fishing_system.gd tests/run_geography_fishing_tests.gd
git commit -m "feat: implement deterministic fishing sessions"
```

### Task 5: World interaction and input ownership

**Files:**
- Create: `scripts/world/fishing_spot.gd`
- Create: `scenes/world/fishing_spot.tscn`
- Create: `tests/test_fishing_main_integration.gd`
- Modify: `scripts/world/world.gd`
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `scripts/systems/tool_system.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/run_geography_fishing_tests.gd`

- [ ] **Step 1: Write failing integration tests**

Assert the world exposes 3–5 stable spots, a rod click calls `start_cast`, the reel click cannot become a movement/cell action, player input is blocked only during an active session, and all terminal paths restore input. Assert `_use_fishing_rod()` no longer adds fiber.

- [ ] **Step 2: Verify RED**

Run the focused runner. Expected: missing world spot and controller APIs.

- [ ] **Step 3: Wire the vertical slice**

Instantiate spot nodes from `GameWorld.fishing_spot_definitions()`. Give each node an `interact()` method and `fishing_spot` group. In `PlayerActionController.perform_target_interaction()`, route a fishing spot only when slot 4/rod is selected; while a session is active, the next left click calls `reel()` before raycasting. Main connects fishing state signals to `player.set_movement_input_blocked()` and HUD messages. `ToolSystem` exposes `commit_fishing_cast_cost()` and contains no reward logic.

- [ ] **Step 4: Verify GREEN and launch**

Run the focused runner, player controller suite, editor compile, and a five-second main-scene headless launch.

- [ ] **Step 5: Commit**

```text
git add scripts/world/fishing_spot.gd scenes/world/fishing_spot.tscn scripts/world/world.gd scripts/actors/player_action_controller.gd scripts/systems/tool_system.gd scripts/main.gd tests/test_fishing_main_integration.gd tests/run_geography_fishing_tests.gd
git commit -m "feat: connect shoreline fishing gameplay"
```

### Task 6: Fishing persistence and rollback

**Files:**
- Create: `tests/test_fishing_save_integration.gd`
- Modify: `tests/run_geography_fishing_tests.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Write failing save tests**

Require exact round-trip of success counts, cast sequences, reset day, and unique bottles. Reject unknown spots, negative counts, count above three, duplicate unique IDs, malformed versions, and partial payloads without mutating live state. Assert saving cancels the transient session and releases the reservation.

- [ ] **Step 2: Verify RED**

Run the focused runner. Expected: SaveManager lacks fishing configuration/payload.

- [ ] **Step 3: Add fishing as a transactional participant**

Add `configure_fishing_runtime(fishing_system)` requiring `to_dict`, `validate_dict`, `from_dict`, and `cancel`. Gather `fishing_state`, validate it before world mutation, snapshot the current fishing state, restore it after other durable systems, and roll it back if any later participant fails. `Main.cancel_transient_actions()` cancels fishing before save/load.

- [ ] **Step 4: Verify GREEN**

Run the focused runner plus editor compile. Also run the existing save suite and record its pre-existing failures separately; no new fishing assertion may fail.

- [ ] **Step 5: Commit**

```text
git add scripts/core/save_manager.gd scripts/main.gd tests/test_fishing_save_integration.gd tests/run_geography_fishing_tests.gd
git commit -m "feat: persist fishing spot state"
```

### Task 7: Final verification and documentation

**Files:**
- Modify: `docs/validation/building-geography-fishing-validation.md`

- [ ] **Step 1: Run focused and regression verification**

Run the geography/fishing runner, building, production, farming, player-controller, editor compile, and main-scene launch serially. Run `git diff --check` and inspect `git status --short`.

- [ ] **Step 2: Record exact evidence**

Document command exit codes, check counts, the known economy-save baseline failures, manual controls, fish spot coordinates, and save path behavior. Do not claim the unrelated aggregate suite passes.

- [ ] **Step 3: Commit**

```text
git add docs/validation/building-geography-fishing-validation.md
git commit -m "docs: validate geography and fishing systems"
```
