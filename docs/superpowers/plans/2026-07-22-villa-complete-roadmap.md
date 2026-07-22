# Villa Complete Implementation Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute every system described by `docs/detailed-design.md` through a dependency-ordered set of independently testable implementation plans.

**Architecture:** Build the deterministic Godot simulation first, integrate persistence and UI second, remove the combat prototype only after replacement systems pass, then add remote AI as an optional layer over the completed Villager system. Each child plan owns one bounded subsystem and ends with a playable vertical slice.

**Tech Stack:** Godot 4.7, GDScript, Jolt Physics, JSON saves, Node.js 22/TypeScript for the optional Agent Service.

## Global Constraints

- Preserve the existing terrain, road, tree placement, camera controls, tree collision, and camera occlusion behavior.
- Godot is authoritative for all game state and remote AI is optional and failure-tolerant.
- Use EventBus signals for cross-system notification; do not poll UI state every frame.
- Every child plan follows RED/GREEN TDD, runs the complete Godot suite, and commits independently.
- Do not delete combat files until the peaceful Villager replacement, tool interaction, HUD replacement, and save migration all pass.
- Save schema starts at version `1`; future changes require explicit migrations.
- Current supported display baseline is macOS desktop at `1280×720`, with `expand` stretch behavior retained.

---

## Dependency Order

```text
01 Core Foundation
 ├─ 02 Grid + Farming
 ├─ 03 Inventory + Tools + Player
 │   └─ 04 Building + Economy + Season
 └─ 05 Villagers + Deterministic Dialogue

02 + 03 + 04 ──► 06 Exploration + Collectibles + Puzzles + Story
01..06        ──► 07 Save Persistence
01..07        ──► 08 UI + Main Scene Integration
01..08        ──► 09 Migration + Performance + Acceptance

05 + 07       ──► AI Phase A ─► AI Phase B ─► AI Phase C ─► AI Phase D
```

## Plan Index and Completion Gates

| Order | Plan | Produces | Gate |
|---|---|---|---|
| 1 | `2026-07-22-villa-core-foundation.md` | EventBus, GameData, GameState, typed resources, time skeleton | Data registry and signals pass headless tests |
| 2 | `2026-07-22-villa-grid-farming.md` | 36×28 grid, farming loop, crop visuals | Plant/water/grow/harvest loop passes |
| 3 | `2026-07-22-villa-inventory-tools-player.md` | Inventory, tools, stamina, interaction | Tool use consumes stamina and updates inventory |
| 4 | `2026-07-22-villa-building-economy-season.md` | Buildings, orders, gold, season visuals | Place/spend/order/day/season loop passes |
| 5 | `2026-07-22-villa-villagers-dialogue.md` | Peaceful villagers, schedule, affinity, authored dialogue | One full NPC day and dialogue branch pass |
| 6 | `2026-07-22-villa-exploration-story-puzzles.md` | Fog, regions, collectibles, four puzzle types, story | Unlock/collect/solve/reveal loop passes |
| 7 | `2026-07-22-villa-save-persistence.md` | Atomic versioned save/load and subsystem adapters | Round-trip fixture and corrupt-save recovery pass |
| 8 | `2026-07-22-villa-ui-main-integration.md` | HUD and five screens, main scene orchestration, audio shell | Complete farming/build/dialogue UI journey passes |
| 9 | `2026-07-22-villa-migration-performance-acceptance.md` | Combat removal, performance budgets, final acceptance | Clean launch, save reload, target frame/node budgets |
| 10 | `2026-07-22-ai-npc-agent-phase-a.md` | Mock Agent protocol and deterministic local loop | Service and fallback integration pass |
| 11 | `2026-07-22-ai-npc-agent-phase-b.md` | One Loom-backed NPC and mixed dialogue | One real Agent works without granting authority |
| 12 | `2026-07-22-ai-npc-agent-phase-c.md` | Full-village scheduling, memory, budgets, traces | 20/50/100 logical NPC load gates pass |
| 13 | `2026-07-22-ai-npc-agent-phase-d.md` | ACL knowledge channels and Team Coordinator | Team task completes without private-memory leakage |

## Execution Rules

- Execute plans 1–9 in order. Plans 2, 3, and 5 may be developed in parallel only after Plan 1 merges, but merge and verify them sequentially.
- AI Phase A may begin after Plan 1, but do not attach it to gameplay until Plan 5 provides peaceful Villagers and Plan 7 provides save checkpoints.
- At each plan boundary run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path /Users/huanggui/UnrealEngine/villa --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 120
```

- If a child plan changes a published interface, update later plan documents in the same commit before continuing.
- Preserve a playable main scene after every merge; incomplete screens remain hidden and incomplete systems remain disabled.

## Final Product Gate

- [ ] Start a new game, farm one crop, place one building, complete one order, talk to one villager, unlock one region, collect one item, solve one puzzle, reveal one story fragment, save, quit, reload, and verify identical state.
- [ ] Disconnect Agent Service and repeat deterministic farming, building, villager schedule, authored dialogue, save, and load flows.
- [ ] Reconnect Agent Service and verify one NPC resumes Agent decisions without duplicating a decision, outcome, quest, trade, or memory.
- [ ] Run all Godot and TypeScript suites with zero failures, import warnings, leaked nodes, parse errors, or live-provider dependencies.
