# Role-Based NPC Agent Framework Validation

Validated on 2026-08-27 with Godot 4.7.1 stable and Node.js 24.19 on branch `feature/painted-production-buildings`.

## Passing evidence

| Check | Result |
|---|---|
| `npm --prefix services/agent-service test` | Exit 0; 25/25 tests passed |
| `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd` | Exit 0; 813/813 checks passed |
| `godot --headless --path . --quit-after 2` | Exit 0; main scene initialized without script errors |
| `godot_console --headless --path . --script res://tests/agent_service_integration.gd` | Exit 0; real Provider returned a valid protocol v2 decision with one action, then v2 outcome and checkpoint passed |

The passing suites cover role-isolated Soul/goals/tools, exact Provider JSON Schemas, protocol v2 rejection of v1 traffic, zero-to-three ordered tool calls, empty decisions, per-action idempotency, fail-stop and in-progress-stop batch execution, current-state domain validation without global revision rejection or model retry, fragmented UTF-8 Provider SSE, streaming dialogue routing, bounded debug traces, world save round trips, session-isolated SQLite memory, Provider-backed long-term memory compaction, checkpoint safety, and asynchronous memory sidecar coordination.

## Protocol v2 destructive migration

Before the updated local service accepted any request, validation observed `PRAGMA user_version=2` and zero rows in `sessions`, `events`, `long_term_memories`, and `idempotency`. Six pre-v2 checkpoint SQLite files under the configured checkpoint root were removed. A non-SQLite preservation test proves checkpoint cleanup does not delete unrelated files, and a second v2 repository open proves the migration does not clear new data again.

## Existing repository baselines

Two broader suites fail identically on `main` and this feature branch when run with the same console binary:

| Suite | `main` | Feature branch | Assessment |
|---|---:|---:|---|
| `tests/run_task2_trade_tests.gd` | 13 of 1386 failed | 13 of 1386 failed | Existing Market settlement/history baseline |
| `tests/run_economy_save_integration_tests.gd` | 45 of 1507 failed | 45 of 1507 failed | Existing building/save fixture cascade |

These failures are recorded rather than changed because they are outside the Agent framework and the counts/messages are unchanged from `main`. Save-mutating Godot suites must be run serially because they share `user://villa_saves`.

## Real Provider smoke

The connected test requires all of:

- `services/agent-service/config/agent-service.local.json` with a real Provider base URL, API key, and model;
- `config/agent-client.local.json` with `enabled` set to `true` and the running service URL;
- a running Agent Service.

An ignored local credential configuration was used for the connected validation. No secret value was printed or persisted in trace output. The script verified protocol v2 health, session sync, `stream.started`, sanitized Provider input, optional reasoning/content/tool deltas, one Provider output, one final farmer batch accepted by `AgentActionValidator`, stream completion, per-action outcome persistence when non-empty, and checkpoint export. The observed real decision contained one valid action. Both local files are ignored by Git, and no environment-variable fallback exists.

## Intentional non-goals

NPC actions mutate authoritative inventories, market state, farms, buildings, activities, and discoveries, and publish their committed results to the HUD. NPC-specific planting, harvesting, building, and travel visuals are intentionally deferred; the current framework represents these actions through world data and message-panel output.
