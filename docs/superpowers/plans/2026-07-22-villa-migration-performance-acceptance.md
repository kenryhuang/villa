# Villa Migration, Performance, and Acceptance Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove superseded combat-prototype paths, enforce the detailed design's performance strategies, and verify the complete deterministic management game before AI integration.

**Architecture:** Deletion occurs only after replacement scenes and save migrations are proven. Performance checks measure structural budgets instead of relying only on subjective frame rate, and a single acceptance script exercises every player-facing system across save/reload.

**Tech Stack:** Godot 4.7 headless tests, RenderingServer metrics, macOS desktop visual capture, Git.

## Global Constraints

- Preserve terrain, road, camera, vegetation art, tree collisions, and camera occlusion.
- Delete combat files only after no scene, script, test, save fixture, or Input Map references them.
- Grid visualization uses one mesh; default grid data has no node per cell.
- Farming iterates only planted cells and only on `day_changed`.
- Fog updates only after 0.5 world-unit player movement and reuses one `ImageTexture`.
- Static villagers do not run movement work every frame.

---

### Task 1: Replacement-reference audit

**Files:** Create `tests/test_migration_contract.gd`; modify `tests/run_tests.gd`.

**Interfaces:** Produces a resource walk that verifies main scene uses Villagers, management HUD, ToolSystem, and no projectile/combat callbacks.

- [ ] Write failing assertions for absence of `Projectiles`, `fire_requested`, projectile preload, contact-damage UI, and hostile NPC instances from the loaded main scene.
- [ ] Run before deletion; expect RED on the remaining prototype references.
- [ ] Replace residual call sites with the interfaces produced by Plans 3, 5, and 8; do not delete files yet.
- [ ] Run tests and verify the resource walk is GREEN.
- [ ] Commit `refactor: detach combat prototype from villa scene`.

### Task 2: Recoverable combat cleanup

**Files:** Delete `scripts/combat/projectile.gd`, `scripts/combat/projectile.gd.uid`, `scripts/shared/combat_math.gd`, `scripts/shared/combat_math.gd.uid`, `scenes/combat/projectile.tscn`; remove obsolete combat tests and Input Map entries.

**Interfaces:** Consumes the green migration contract from Task 1.

- [ ] Run `rg -n 'projectile|CombatMath|fire_requested|take_hit|contact_damage' . --glob '!docs/**' --glob '!.godot/**'` and save the expected intentional matches.
- [ ] Remove files with `apply_patch` and update the runner; do not use recursive deletion.
- [ ] Run editor import, full tests, and main launch; expected no missing UID/resource errors.
- [ ] Commit `refactor: remove superseded combat prototype`.

### Task 3: Structural performance budgets

**Files:** Create `tests/test_performance_contracts.gd`; modify GridSystem, FarmingSystem, Villager, ExplorationSystem, VegetationBuilder only when a contract fails; modify `tests/run_tests.gd`.

**Interfaces:** Produces queryable counters: grid visual instance count, planted iteration count, villager active movement count, fog update count, and vegetation instance count.

- [ ] Write failing/characterization tests asserting one grid mesh, zero default cell nodes, planted-only iteration, no idle `move_and_slide`, one fog texture reused, 0.5 reveal threshold, and tree count within authored/scatter expectations.
- [ ] Run tests and record which budgets fail.
- [ ] Make the minimum changes required by section 8: cached planted list, state-gated NPC physics, `ImageTexture.update`, visibility range for expanded forests, and MultiMesh only for noninteractive dense forest trees.
- [ ] Run tests and commit `perf: enforce villa simulation budgets`.

### Task 4: Complete gameplay acceptance

**Files:** Create `tests/full_game_acceptance.gd`, modify `tests/capture_scene.gd`, update `docs/detailed-design.md` acceptance commands.

**Interfaces:** Produces a headless deterministic journey and a desktop screenshot.

- [ ] Script a new game that tills, plants, waters, advances a day, harvests, adds inventory, places a building, completes an order, talks to a villager, unlocks a region, collects an item, solves one puzzle, reveals a story fragment, saves, destroys the scene, reloads, and compares canonical state.
- [ ] Run the script before final wiring and verify RED identifies the first missing connection.
- [ ] Fix wiring only; do not add new game features in acceptance.
- [ ] Run the journey, `tests/run_tests.gd`, editor import, and `--quit-after 120`; expected all exit `0`.
- [ ] Capture and inspect the scene at center and map edges, including tree collision/occlusion and expanded-window layout.
- [ ] Commit `test: verify complete villa management loop`.

### Task 5: Release readiness record

**Files:** Create `docs/acceptance/deterministic-villa-v1.md`.

- [ ] Record exact commit, Godot version, macOS version, commands, check counts, save fixture checksum, structural performance counts, screenshots, and known nonblocking limitations.
- [ ] Verify `git status`, `git diff --check`, full suites, and main launch on the recorded commit.
- [ ] Commit `docs: record deterministic villa v1 acceptance`.
