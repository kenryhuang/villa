# Visible Agent Farmer Work Design

**Date:** 2026-08-28
**Status:** Approved for implementation planning
**Scope:** Give the visible farmer Agent Ahe a real, world-backed 20-plot farm; execute tilling, planting, and harvesting through visible movement and lightweight action feedback; change every crop's initial and repeat growth duration to about 30 real seconds.

## Goals

- Ahe selects and operates real world grid cells instead of a detached invisible farm registry.
- Ahe walks to a selected plot before tilling, planting, or harvesting changes any world asset.
- NPC farming uses the same authoritative grid, crop, season, inventory, and harvest rules as player farming.
- Ahe owns a visible four-by-five farm near her spawn. The player may walk through and inspect it but may not farm, harvest, or build on its plots.
- Every crop initially matures in 108 game minutes, approximately 30 real seconds at the current clock rate.
- Watering preserves its 50% growth bonus, reducing maturity to 72 game minutes, approximately 20 real seconds.
- Repeat-producing crops use the same duration for each repeat cycle.
- Preserve Agent dialogue responsiveness while Ahe is working.

## Non-goals

- No frame-by-frame walking or farming animation atlases.
- No general navigation overhaul for every NPC.
- No offline real-time crop progress while the game is closed.
- No local AI replacement for the LLM's crop and plot decisions.
- No acceleration of the global day, season, economy, order, or production clocks.

## Existing Behavior and Problem

`AgentRuntime` currently constructs a twelve-plot `NpcFarmRegistry`. The Agent tools mutate that registry immediately using plot indices, minute deadlines, and fixed yields. Those mutations affect Ahe's private inventory and Agent snapshots but never touch `GridSystem`, `FarmingSystem`, or visible crop nodes. Ahe therefore appears stationary while the message panel describes invisible farming.

Player crops use `CropData.growth_days` and advance only from `FarmingSystem.on_day_changed`. A game day spans 300 real seconds. Default crops need three to five days, so uninterrupted maturation takes roughly 15–25 real minutes. This is slower than the desired gameplay cadence.

## Architecture

### VisibleNpcFarmSystem

Add a world-aware `VisibleNpcFarmSystem` under `Main`. It is the Agent farm port and owns only:

- the farmer Agent ID;
- the selected four-by-five farm anchor;
- the stable mapping from `plot_index` 0–19 to `Vector2i` grid coordinates;
- plot ownership queries;
- the ordered work queue and its persisted action records;
- projected queue state used to validate a multi-action decision.

It does not own a duplicate crop object or plot state. Farm snapshots are derived from the mapped `GridCell` values and their real `CropInstance` objects.

`AgentRuntime.configure` receives the farm port from `Main` after `GridSystem`, `FarmingSystem`, `SeasonSystem`, and `NpcEconomySystem` are configured. Ahe is no longer initialized in the detached twelve-plot `NpcFarmRegistry`. The executor and request snapshot builder talk only to the injected farm-port interface.

The old registry class remains solely as the parser for version-2 Agent-state migration. `AgentRuntime` does not retain or query an old registry after configuration, and Ahe never uses it during normal runtime.

### NpcFarmActionController

Add an `NpcFarmActionController` that connects the queued farm work to Ahe's visible NPC node. Its responsibilities are:

- select the next queued action;
- request movement to an interaction point beside the mapped cell;
- detect arrival or stalled movement;
- turn Ahe toward the plot;
- play the appropriate lightweight action feedback;
- ask `VisibleNpcFarmSystem` to revalidate and commit after the feedback duration;
- report completion or failure back to `AgentRuntime`.

Business rules and asset transactions remain outside the visual controller.

### Plot Ownership

The selected 20 cells carry an owner reservation for `farmer_ahe`. Owner-aware validation is shared by farming and building entry points:

- player till, plant, harvest, and building placement reject these cells;
- Ahe may operate them through the farm port;
- walking and camera interaction remain permitted;
- crops and farmland remain visible and use normal rendering.

Ownership is checked both during preview and immediately before commit. Internal restoration code may restore saved cell state without being mistaken for a player action.

## Farm Selection and Stable Plot Mapping

On a new game, the system searches around Ahe's configured spawn for a complete four-by-five rectangle. Candidate anchors are scored deterministically by:

1. distance from Ahe's spawn;
2. all 20 cells being in bounds and farmable by terrain slope;
3. no road, water, building, decoration, blocked region, or existing crop overlap;
4. reachable interaction positions around the rectangle;
5. stable grid-coordinate ordering as the final tie-breaker.

The lowest-scoring valid anchor is selected. Plot indices are row-major and never change for that farm: `plot = row * 5 + column`, with four rows and five columns.

The chosen anchor is persisted. Loading validates the anchor against map bounds and the exact 20-coordinate mapping, but existing saved farmland and crops do not invalidate their own reservation. If no complete region is available for a new game, the system creates no partial farm, publishes a warning, and rejects Ahe's farm tools with `farm_unavailable`. Dialogue and the other Agents continue to function.

## Agent Snapshot and Tool Semantics

The farmer snapshot contains exactly 20 plot records derived from the world. Each record includes:

- `plot_index`;
- grid coordinate;
- world position;
- ownership and reachability;
- state: `untilled`, `tilled`, `growing`, `mature`, `dormant`, or `withered`;
- planted crop and source seed item when present;
- normalized growth progress and remaining game minutes;
- current-season validity;
- whether a queued action already reserves the plot.

The version-2 decision protocol remains unchanged: `actions` may contain zero to three entries. `till`, `plant`, and `harvest` keep their existing arguments and plot-index meaning, but accepted work initially reports `in_progress` instead of committing immediately.

The farm system validates the whole batch against projected state so a decision such as `till plot 2` followed by `plant plot 2` is accepted and queued in order. It rejects conflicting plot reservations and impossible dependencies before movement begins.

While Ahe's automatic work queue is non-empty, her scheduled automatic decision trigger is suppressed. Dialogue triggers remain allowed and continue through the normal streaming path. When the queue becomes empty, the next normal schedule interval may trigger a new decision.

## Work Execution Flow

For each queued farm action:

1. Resolve the stable plot index to its real cell and interaction point.
2. Set Ahe's movement target.
3. Preserve the current four-direction static visual while she moves.
4. Detect arrival within the farm interaction radius.
5. Stop, face the cell, and begin about one second of visual feedback.
6. Re-run authoritative ownership, terrain, season, crop, and inventory validation.
7. Commit the real transaction only after the feedback finishes.
8. Increment world revision for a mutation, persist the idempotent outcome, report it to Agent Service, and publish the final message.
9. Continue with the next queued action.

Ahe's movement and action feedback do not lock the global clock. Crops and the rest of the world continue advancing. The arrival-time validation is therefore authoritative.

### Batch Failure Rules

- A failure cancels later actions whose projected preconditions depend on the failed action.
- Independent later actions may remain queued only when their plots and resources are disjoint.
- A stalled or timed-out move produces `path_blocked` and returns Ahe to idle.
- A changed plot, season, or inventory produces `condition_changed`.
- Missing farm mapping produces `farm_unavailable`.
- No failure retries itself. The next Agent decision receives the updated snapshot and decides what to do.
- Every idempotency key can commit at most once across repeated network delivery and save/load.

## Authoritative Farming Transactions

### Till

The target must belong to Ahe, be farmable terrain, and be untilled with no crop or incompatible world occupant. Commit through an owner-aware grid farming transition. Only the final commit changes the cell to farmland and creates its standard visual.

### Plant

The target must belong to Ahe, be empty farmland, allow the crop in the current environment and season, and have no conflicting reservation. Ahe's NPC inventory must own the requested seed. Seed removal and `FarmingSystem` crop creation form one atomic transaction. Any failure restores both inventory and cell state.

### Harvest

The target must belong to Ahe and contain a mature crop. Reuse the formal Farming harvest preview and prepared-publication transaction. Ahe's inventory must accept the complete yield before the crop mutation is finalized.

For annual crops, harvest restores empty farmland. For `annual_regrow`, `bush`, `tree`, and `vine` crops, harvest increments the harvest count, preserves the established plant, resets it to growing progress zero, and begins a new 108-game-minute repeat cycle. This deliberately supersedes the earlier clear-all behavior for repeat-producing crops.

## Visual Feedback

No new character animation atlas is required. The action controller composes feedback around the existing static Ahe sprite:

- **Till:** reuse `assets/ui/action_icons/hoe.png`; swing the icon twice along a short arc, apply a small body dip, and emit brown soil particles.
- **Plant:** show the chosen crop's stage-zero seed texture, dip Ahe toward the plot, and emit a few falling seed particles.
- **Harvest:** show a small hand-painted SVG basket, briefly pulse the mature crop, and emit green leaf particles.

The feedback uses small procedural particles and tweens. It lasts approximately one second and is cancelled cleanly on scene exit, load, NPC defeat, or action failure. Successful soil or crop changes occur at the end, not at the beginning, of the feedback.

The message panel publishes a concise travel/start message and the final result. Queue transitions, movement targets, arrival checks, validation details, and raw outcomes are recorded in the Agent debug stream rather than the player-facing message feed.

## Continuous Crop Growth

### Timing

Keep `SeasonSystem.REAL_SECONDS_PER_DAY = 300` and `MINUTES_PER_REAL_SECOND = 3.6` unchanged. Add crop duration in game minutes:

- initial duration: 108 game minutes for every crop;
- repeat duration: 108 game minutes for every repeat-producing crop;
- watered multiplier: 1.5;
- unwatered real duration: about 30 seconds;
- watered real duration: about 20 seconds.

`FarmingSystem` tracks the last synchronized absolute game minute and advances planted crops from authoritative elapsed game minutes received through the normal time signal. `day_changed` continues environment transitions and daily water clearing but no longer adds a full growth day. This prevents double advancement.

The existing `growth_progress` save value remains a bounded proportional progress value using the crop's current maturity scale. A new minute-based advance method converts elapsed minutes into proportional progress. This preserves existing crop serialization while changing the pacing source from daily ticks to continuous time.

On load, the farming clock cursor synchronizes to the restored world time before normal processing. It does not count real time spent outside the game. If the Season clock is paused or locked, no time signal advances growth.

### Stages and Debugging

- Two-stage crops display only their seed and mature visuals.
- Four-stage crops update near one-third, two-thirds, and full progress.
- Visuals and `crop_grew` signals update only when the derived stage changes.
- `crop_matured` emits once when the lifecycle first becomes mature.
- Debug key `N` continues to advance one visual growth stage without changing date, market, or elapsed-time cursors.
- The seed selector displays `成熟约 30 秒 · 浇水约 20 秒` instead of a day count.

## Persistence and Migration

The Agent world save version advances. It stores:

- the farm anchor and stable 20-cell mapping;
- queued action records, ordering, dependencies, decision/action IDs, and idempotency keys;
- enough movement/action phase state to safely resume at the target;
- executor outcomes and world revision as before.

The grid save remains the only owner of farmland and crop state. The NPC economy save remains the only owner of Ahe's inventory.

Saving during movement or visual feedback persists the action as uncommitted. Loading restarts travel to the target and repeats arrival validation. It never resumes halfway through a mutation. Committed outcomes remain idempotent and are not repeated.

Version-2 Agent saves are accepted by migration: detached plot contents are discarded because they have no world coordinates, the old farm record is replaced by a newly selected empty visible farm, and Ahe's NPC inventory plus other Agent state remains intact. Invalid new farm mappings reject only the Agent-world portion and publish a clear warning rather than corrupting the grid.

Restore order is: world time and grid, farming clock synchronization, NPC economy, Agent farm mapping and queue, then visible action resumption.

## Error Handling and Observability

- Player-facing notifications distinguish started, completed, and failed work without exposing raw protocol payloads.
- Agent debug records include queued, moving, arrived, animating, revalidated, committed, rejected, and cancelled phases.
- A failed visual asset uses a simple transform tween and does not block the authoritative action.
- A missing Ahe scene binding disables visible work and returns `actor_unavailable`; it does not mutate a plot off-screen.
- A missing complete farm region returns `farm_unavailable` and leaves existing world assets unchanged.
- Any transaction failure rolls back inventory and crop/grid changes before an outcome is reported.

## Testing Strategy

### Unit Tests

- deterministic four-by-five candidate selection and row-major mapping;
- complete-region rejection and no partial reservation;
- owner checks for player farming, harvesting, and building placement;
- world-derived Agent farm snapshot fields;
- projected validation for zero-to-three actions and same-plot till-then-plant;
- dependency cancellation and preservation of independent queued work;
- movement arrival, stall, timeout, and cancellation;
- visual feedback state and commit-at-end timing;
- exactly-once outcome handling and save/load resumption;
- 108-minute unwatered and 72-minute watered maturity;
- no growth without elapsed game time;
- stage transition and one-shot maturity signals;
- annual clear and repeat-crop reset behavior.

### Integration Tests

- `Main` creates and binds the 20-plot visible farm to Ahe and `AgentRuntime`;
- Agent snapshots track actual grid/crop mutations;
- a three-action batch drives Ahe sequentially through real cells;
- seed removal and planting roll back together;
- harvest and NPC inventory receipt commit atomically;
- player farming and building tools reject reserved cells;
- save/load during travel or feedback does not duplicate mutations;
- scheduled Agent decisions pause during work while dialogue streaming remains responsive;
- debug `N` remains independent from calendar and continuous cursor state;
- seed selector shows second-based timing.

### Visual Verification

Capture the real main scene with Ahe moving among the 20 plots and performing each of till, plant, and harvest. Confirm direction selection, grounding, tool/icon placement, particle readability, prompt/nameplate clearance, world mutation timing, and absence of placeholder meshes or animation-frame jitter.

## Acceptance Criteria

- Ahe visibly travels to and operates one of 20 reserved world plots selected by the LLM.
- No farm or inventory mutation happens before she reaches the plot and completes feedback.
- The visible soil, crop lifecycle, Agent snapshot, NPC inventory, outcomes, and messages agree after every action.
- Player tools cannot occupy the reserved farm.
- Every crop matures in about 30 real seconds unwatered and 20 seconds watered while the game clock runs.
- Repeat-producing crops re-enter a 30-second growth cycle; annual crops leave empty farmland.
- Queued actions and idempotency survive save/load without duplication.
- Ahe remains available for dialogue while working.
