# Villa Save Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist and restore the complete deterministic game state through an atomic, versioned JSON save file.

**Architecture:** `SaveManager` coordinates small `to_dict/from_dict` adapters owned by each subsystem. Serialization is pure and testable; file replacement is atomic, corrupt files are quarantined, and dependency-ordered restore prevents buildings or crops from loading before their grid.

**Tech Stack:** Godot 4.7, GDScript, `FileAccess`, JSON, `user://` storage.

## Global Constraints

- Save schema version is exactly `1` at initial release.
- Default path is `user://villa_save.json`; write `user://villa_save.tmp` then rename atomically.
- Godot save data is authoritative, including future Agent checkpoints.
- Never silently overwrite an unreadable save; rename it with `.corrupt-<unix-time>`.
- Restore order is world/time, inventory, grid, buildings, exploration, story, villagers, then player position.
- Automatic saves occur after `day_changed` and `region_unlocked`, never every frame.

---

### Task 1: Save codec and schema validation

**Files:**
- Create: `scripts/core/save_codec.gd`
- Create: `tests/fixtures/save_v1.json`
- Create: `tests/test_save_codec.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `SaveCodec.encode(data: Dictionary) -> String`.
- Produces: `SaveCodec.decode(text: String) -> Dictionary` returning `{ok, value}` or `{ok, error}`.
- Produces: `SaveCodec.default_save() -> Dictionary`.

- [ ] **Step 1: Write failing tests** for valid fixture decoding, stable encode/decode round trip, missing top-level sections, wrong version, non-finite numbers, and default values.

```gdscript
var decoded = SaveCodecScript.decode(FileAccess.get_file_as_string("res://tests/fixtures/save_v1.json"))
assertions.truthy(decoded.ok, "save v1 fixture decodes")
assertions.equal(decoded.value.version, 1, "save version is preserved")
assertions.truthy(not SaveCodecScript.decode("{broken").ok, "invalid JSON is rejected")
assertions.truthy(not SaveCodecScript.decode(JSON.stringify({"version": 2})).ok, "unknown version is rejected")
```

- [ ] **Step 2: Run the full Godot suite and verify RED** because `save_codec.gd` is absent.

- [ ] **Step 3: Implement strict v1 validation** requiring `player`, `world`, `inventory`, `grid`, `buildings`, `exploration`, `story`, and `villagers`. Normalize `Vector3` as `{x,y,z}`, `PackedByteArray` as base64, and reject values that are not JSON-compatible.

- [ ] **Step 4: Run the full suite and verify GREEN**.

- [ ] **Step 5: Commit** with `git commit -m "feat: define versioned villa save codec"`.

### Task 2: Subsystem save adapters

**Files:**
- Modify: `scripts/core/game_state.gd`
- Modify: `scripts/systems/inventory_system.gd`
- Modify: `scripts/systems/grid_system.gd`
- Modify: `scripts/systems/building_system.gd`
- Modify: `scripts/systems/economy_system.gd`
- Modify: `scripts/systems/season_system.gd`
- Modify: `scripts/systems/exploration_system.gd`
- Modify: `scripts/systems/story_system.gd`
- Modify: `scripts/systems/villager_system.gd`
- Create: `tests/test_save_adapters.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces on every listed system: `to_dict() -> Dictionary` and `from_dict(data: Dictionary) -> bool`.

- [ ] **Step 1: Write one round-trip test per subsystem** using non-default values; assert restored values and that `from_dict` rejects wrong types without partially mutating state.
- [ ] **Step 2: Run tests and verify RED** on missing adapters.
- [ ] **Step 3: Implement adapters** with sorted stable output. GameState serializes the sole gold and PlayerState authority; Grid serializes only non-default cells and crop `growth_progress`; buildings serialize `building_id/gx/gz`; EconomySystem serializes active orders only; exploration serializes regions, base64 fog, collected IDs and solved IDs; VillagerSystem serializes affinity and flags. SaveManager writes Economy orders to the top-level `active_orders` key and Villager affinity to `villager_affinity`, exactly matching detailed-design §2.17/§6.1.
- [ ] **Step 4: Run the full suite and verify GREEN**.
- [ ] **Step 5: Commit** with `git commit -m "feat: serialize villa gameplay systems"`.

### Task 3: Atomic SaveManager

**Files:**
- Create: `scripts/core/save_manager.gd`
- Create: `tests/test_save_manager.gd`
- Modify: `project.godot`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `SaveManager.save_game(path := SAVE_PATH) -> Error`.
- Produces: `SaveManager.load_game(path := SAVE_PATH) -> bool`.
- Produces: `SaveManager.has_save(path := SAVE_PATH) -> bool`.
- Produces: `SaveManager.configure(systems: Dictionary) -> void` for testable dependency injection.

- [ ] **Step 1: Write failing temporary-directory tests** for atomic write, successful load, missing file, corrupt quarantine, and restore order captured by fake systems.
- [ ] **Step 2: Run tests and verify RED**.
- [ ] **Step 3: Implement collection and restore**. Write to `<path>.tmp`, flush and close, remove only an existing `<path>.bak`, rename current save to `.bak`, rename tmp to final, and restore `.bak` if final rename fails. Restore GameState/time, inventory, grid, buildings, exploration, story, villagers, Economy active orders, then player transform. Emit `EventBus.game_saved` only after success and `game_loaded` only after every adapter succeeds.
- [ ] **Step 4: Run tests and verify GREEN**, confirming temporary files are cleaned.
- [ ] **Step 5: Register `SaveManager` Autoload and commit** with `git commit -m "feat: add atomic save manager"`.

### Task 4: Autosave and player restoration

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scripts/actors/player.gd`
- Create: `tests/test_save_integration.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: SaveManager and all subsystem adapters.
- Produces: `Main.collect_save_dependencies() -> Dictionary` and dependency-ordered startup restoration.

- [ ] **Step 1: Write failing integration tests** proving `day_changed` and `region_unlocked` each queue one coalesced save, player transform restores last, and loading suppresses gameplay signals until state is consistent.
- [ ] **Step 2: Run tests and verify RED**.
- [ ] **Step 3: Implement one-frame autosave coalescing**, configure SaveManager after systems initialize, load only after world geometry exists, and clamp a restored player position to world bounds and terrain height.
- [ ] **Step 4: Run the full suite and main scene**; expected no save-related warnings or duplicate events.
- [ ] **Step 5: Commit** with `git commit -m "feat: integrate villa save and autosave flow"`.

### Task 5: Save acceptance

**Files:**
- Create: `tests/save_acceptance.gd`
- Modify: `docs/detailed-design.md`

**Interfaces:**
- Produces: a headless acceptance script that mutates every persisted subsystem, saves, recreates the scene, loads, and compares canonical encoded dictionaries.

- [ ] **Step 1: Write acceptance script and run before final wiring**; expected FAIL on at least one missing section.
- [ ] **Step 2: Fix only missing adapter wiring exposed by the acceptance test**.
- [ ] **Step 3: Run `save_acceptance.gd`, the full suite, and main launch**; expected all exit `0`.
- [ ] **Step 4: Update the save section with the final schema hash and migration rule**, then commit with `git commit -m "test: verify complete villa save round trip"`.
