# Event-Sourced Multi-Agent Economy Validation

Validated on 2026-09-03 with Godot 4.7.1 stable and Node.js 24.19 on branch `feature/painted-production-buildings`.

## Implemented system

The Godot Agent bounded context now owns an append-only event store, deterministic projections, independent Agent inbox cursors, a committed-world fact bridge, dynamic roles, bilateral interactions, cooperation agreements, and bounded private-market pressure. Existing farm, inventory, economy, market, building, activity, and discovery systems remain authoritative; Agent commands reach them only through validation and transactional adapters.

Every decision request contains a frozen protocol-v2 view of:

- public world state and a bounded public-event window;
- every visible actor's current public state and recent public events;
- the requesting Agent's private event delta;
- current market, interaction, agreement, role, goal, and tool views.

Successful decisions acknowledge only the requesting Agent's frozen inbox range. Failure and cancellation release it without advancing the cursor. Public facts therefore reach all Agents independently, while participant/private events remain visibility-filtered.

The local TypeScript service intersects the request capabilities with the active role, serves bounded read-only context tools locally, and sends only zero to three final command actions back to Godot. Role changes immediately replace role-specific goals, tools, and schedule while preserving Soul, history, and general tools.

## Authoritative interactions and economy

Trade proposals reserve only the proposer side. Accept/counter/reject/cancel/expiry are event-backed and idempotent; settlement stages and validates both parties before committing an atomic transfer. Player-targeted interactions require explicit dialogue-card confirmation.

Dialogue counteroffers open a structured editor instead of immediately reusing the old terms. Trade item quantities, gold and expiry are submitted as a complete Player-authored offer; cooperation commitments, reward weights, deadline and note are submitted as a complete revised agreement. A Player-authored counteroffer cannot be accepted by that same Player: only its NPC recipient can settle it.

The four cooperation templates (`joint_crop_supply`, `exploration_sample`, `material_procurement`, and `shared_construction`) use deterministic contribution predicates, deadlines, cancellation/refund rules, relationship effects, and exact integer settlement. Agent actions can satisfy agreement milestones only through recorded authoritative outcomes.

Open and settled private offers create capped market pressure rather than directly setting public prices. The normal market settlement consumes that pressure once, preserving the existing public buy/sell path.

## Save, replay, and migration

Runtime save version 5 stores event schema version 1, the complete immutable event log, next sequence and idempotency outcomes, deterministic projection checkpoint metadata, independent inbox cursors, roles, offers/reservations, agreements/relationships, settled market pressure, and pending market-pressure facts awaiting publication.

Loading validates the complete candidate graph in temporary store/projector/inbox/role/interaction/agreement instances before replacing live state. Event envelopes and JSON numeric values are canonicalized before replay. Corrupt sequences, aggregate versions, visibility, or subsystem snapshots reject the load atomically.

Roles, trade offers, cooperation agreements, relationships, and settled private-market pressure are reconstructed from the immutable event log and compared with their persisted snapshots. Active cooperation commitments are also cross-checked against the exact external asset reservations. A structurally valid but event-inconsistent snapshot is rejected without changing the live session ID, Registry role, or Runtime state.

Legacy Runtime v2/v3 data migrates to exactly one deterministic `AgentWorldBootstrapped` event. This migration preserves normal world saves and the Agent Service SQLite memory database. During `SaveManager` restore, market-pressure application waits until `load_completed`, avoiding mutation of a partially restored market.

Development-only Runtime v4 snapshots are intentionally rejected rather than interpreted under the changed pressure-event contract; no v4 compatibility path is retained. If publishing a `MarketPressureSettled` public fact fails, Runtime v5 persists the complete fact and retries on subsequent game-time ticks. The private pressure is cleared only after the fact commits to the event log.

## Passing evidence

| Check | Result |
|---|---|
| `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd` | Exit 0; 1515 checks passed |
| `godot_console --headless --path . --script res://tests/run_economy_save_integration_tests.gd` | Exit 0; 1541 checks passed |
| `npm --prefix services/agent-service test` | Exit 0; 33 tests passed |
| `godot_console --headless --path . --editor --quit` | Exit 0; changed scripts parsed/imported |
| `godot_console --headless --path . --quit-after 3` | Exit 0; main scene started without script errors |

The focused suites include actual `JSON.stringify`/parse-equivalent round trips, from-zero replay, checkpoint-prefix plus tail validation, corrupt-log rollback, event/snapshot tamper rejection for roles/offers/agreements/pressure, pending lock/offer/agreement/pressure restore, legacy bootstrap migration, Player/NPC offer authority, and editable trade/cooperation counteroffers.

## Recorded repository baselines

`tests/run_economy_system_tests.gd` reports 13 failures out of 71040 checks. They remain in the previously recorded categories: source-owned production/delivery publication guards, legacy maintenance migration, storage-upgrade passive output, crop/beehive scenarios, absent `ToastStack` and `BottomBar/BuildCostBar` fixture nodes, and missing grilled/pickled-fish recipe/arbitrage routes. No Agent assertion failed.

`tests/run_main_gameplay_integration_tests.gd` reports two existing failures out of 1820 checks: automatic seed-map discovery of `grain_seed`, and initial stored-crop contract-delivery availability. These are the same known fixture baselines and are unrelated to this implementation.

## Connected local-service smoke

The running service at the configured local URL returned health status 200 with protocol version 2. A Godot-shaped SSE dialogue decision containing a public market event, another Agent's public status, and the caller's private event delta produced `provider.input`, `reasoning.delta`, `content.delta`, `decision.final`, and `stream.completed`. The final response matched the request, used protocol v2, included speech, and legally chose zero actions.

A schedule-triggered request also streamed Provider reasoning but exceeded the local Provider timeout of 30000 ms before a final decision. This is a local configuration/runtime limit rather than a protocol or Godot main-thread stall; the concise dialogue request completed successfully in under four seconds.

Three local trace/log files under `D:\UnityProject\villa\tmp` were scanned for credential leakage; zero occurrences were found.

## Scope boundary

This implementation adds authoritative non-visual Agent effects, shared/private perception, negotiation, cooperation, roles, persistence, and market feedback. New NPC-specific animations for these actions remain outside this plan. The branch has not been merged or pushed.
