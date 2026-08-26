# Role-Based NPC Agent Framework Validation

Validated on 2026-08-26 with Godot 4.7.1 stable and Node.js 24.19 on branch `feature/painted-production-buildings`.

## Passing evidence

| Check | Result |
|---|---|
| `npm --prefix services/agent-service test` | Exit 0; 16/16 tests passed |
| `godot --headless --path . --script res://tests/run_agent_system_tests.gd` | Exit 0; 100/100 checks passed |
| `godot --headless --path . --quit-after 2` | Exit 0; main scene initialized without script errors |
| `godot --headless --path . --script res://tests/agent_service_integration.gd` | Exit 0; explicitly skipped because no enabled local client configuration was present |

The passing suites cover role-isolated Soul/goals/tools, strict protocol validation, real OpenAI-compatible HTTP behavior through local fake endpoints, authoritative headless world mutations, idempotency, stale revisions, scheduling, event coalescing, dialogue routing, world save round trips, session-isolated SQLite memory, Provider-backed long-term memory compaction, checkpoint checksum/path safety, and asynchronous memory sidecar coordination.

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

No local credential configuration was present during this validation, so no public Provider request was made and no secret value was printed. With configuration present, the script performs health, session sync, one farmer decision, outcome persistence, and checkpoint export. Both local files are ignored by Git, and no environment-variable fallback exists.

## Intentional non-goals

NPC actions mutate authoritative inventories, market state, farms, buildings, activities, and discoveries, and publish their committed results to the HUD. NPC-specific planting, harvesting, building, and travel visuals are intentionally deferred; the current framework represents these actions through world data and message-panel output.
