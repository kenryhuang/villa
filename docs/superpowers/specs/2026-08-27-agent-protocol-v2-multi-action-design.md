# Agent Protocol v2 Multi-Action and Current-State Execution Design

## Goal

Replace the coarse global world-revision rejection with authoritative tool-level checks against the current Godot world, and allow each Agent decision to contain zero to three ordered actions. The change must not retry the remote model when world state changes while a decision is in flight.

This is a breaking protocol upgrade. Agent Service and Godot move to protocol version 2 together, reject version 1 traffic, and clear all previous Agent databases and checkpoints during the one-time upgrade.

## Root Cause

The current scheduler dispatches due Agents concurrently. Each request captures the same global `world_revision`. When the first returned action mutates any part of the world, the revision increments. Every later response with the old revision is rejected before its tool semantics are considered, even when it targets an unrelated farm, inventory, market item, discovery, or performs no mutation.

The failure is therefore caused by using one global revision as a hard optimistic-concurrency lock around long-running remote decisions. `AgentRuntime` is only where the validator is invoked; it is not the source of the stale value.

## Protocol Version 2

All Agent HTTP payloads, SSE envelopes, decisions, and outcomes use `protocol_version: 2`. Version 1 requests and responses are invalid. The service health response also advertises version 2.

`DecisionRequest` keeps its current fields and changes only its protocol version. `world_revision` remains a non-negative diagnostic snapshot value.

The version 2 decision envelope is:

```json
{
  "protocol_version": 2,
  "decision_id": "provider-response-id",
  "request_id": "farmer_ahe-42",
  "agent_id": "farmer_ahe",
  "expected_revision": 12,
  "actions": [
    {
      "action_id": "call-1",
      "idempotency_key": "v2:farmer_ahe-42:0:call-1",
      "tool_name": "buy",
      "tool_version": 1,
      "arguments": {"item_id": "carrot_seed", "quantity": 2}
    },
    {
      "action_id": "call-2",
      "idempotency_key": "v2:farmer_ahe-42:1:call-2",
      "tool_name": "plant",
      "tool_version": 1,
      "arguments": {"plot": 0, "seed_item_id": "carrot_seed"}
    }
  ],
  "speech": "我先补充种子，再去播种。",
  "decision_summary": "Buy seed and plant the prepared plot"
}
```

`actions` must be present and must be an array containing zero through three items. An empty array is a successful decision to perform no world action. It may contain speech or be silent. It changes no world state, increments no revision, and produces no action outcome, but the decision remains visible in the raw trace and Agent memory.

Every action must have an ID, a unique idempotency key, an authorized tool name, tool version 1, and arguments matching the exact authoritative tool contract. The Agent Service preserves Provider tool-call index order. It uses the Provider call ID as `action_id` when valid and otherwise generates a deterministic index-based ID. It generates the idempotency key from protocol version, request ID, index, and action ID; the model does not generate identifiers.

The `wait` action is valid only when it is the sole action. `speak` may appear alone or with world actions; player-facing dialogue text remains the envelope-level `speech` field.

Each executed action produces a version 2 outcome. The outcome adds its `action_id` so the service can correlate it with the selected action. Existing outcome fields, including `decision_id`, `idempotency_key`, status, committed revision, changed entities, resource delta, HUD message, and game minute, remain required.

There is no version 1 compatibility parser and no conversion of old top-level `tool_name`, `arguments`, or `idempotency_key` fields.

## Provider and Streaming

The OpenAI-compatible request keeps `tool_choice: "auto"`. Its system prompt permits zero to three ordered authorized tools and tells the model to call only tools grounded in the supplied snapshot. It advises placing a long-running action last.

The stream assembler accumulates tool-call fragments independently by index and preserves reasoning and content deltas. At stream completion it accepts zero, one, two, or three complete calls. It rejects more than three calls, duplicate or invalid indices, incomplete calls, unauthorized tools, invalid arguments, and a multi-action sequence containing `wait`.

A response with no tool calls becomes `actions: []`. Content becomes optional `speech`. The service generates a decision summary for zero-action and multi-action decisions. `decision.final` always carries the canonical version 2 batch envelope.

The raw debug stream continues to expose every `tool_call.delta`; indices distinguish concurrent fragments. The debug window and NDJSON trace require no new visual behavior beyond accepting and displaying the new final payload.

## Godot Validation and Execution

The Godot protocol parser and action validator require the version 2 batch structure and validate every action before execution. The entire decision is rejected before mutation if its envelope or any action is structurally invalid, unauthorized, has invalid arguments, contains duplicate IDs or keys, exceeds three actions, or violates the exclusive `wait` rule.

`expected_revision` is still validated as a non-negative integer but is not compared with the current executor revision. The executor also removes its existing global revision equality check.

After structural validation, actions execute sequentially on the Godot main thread against current authoritative state:

1. Each tool reuses its existing domain conditions for current plots, inventory, market state, activities, buildings, and discoveries.
2. A successful mutation commits immediately and increments `world_revision` once.
3. A successful non-mutating action does not increment the revision.
4. A rejected or failed action produces its concrete domain failure, stops the batch, and leaves earlier successful actions committed.
5. An action returning `in_progress`, including travel or build, is reported and stops the batch. Later actions are not executed.
6. Actions after a stop condition produce no outcome because they were never attempted.

There is no cross-tool rollback transaction. Existing per-tool rollback behavior remains responsible for preventing partial corruption inside an individual tool.

`AgentRuntime` publishes and reports each attempted action outcome in execution order. Successful HUD messages remain separate so players can see each actual world change. A failure publishes one warning for the failed step. Dialogue speech is emitted once for the decision independently of whether the batch is empty, completes, fails, or enters progress.

No stale retry queue, event replay, or additional Provider call is introduced. A domain rejection waits for the next normal schedule, event, or dialogue trigger.

## Idempotency and Persistence

Every action has its own idempotency key. Reprocessing the same decision cannot apply an already executed action twice: the executor returns the stored per-action outcome. A stored `completed` outcome permits batch traversal to continue to the next action. A stored `in_progress`, `rejected`, or `failed` outcome stops traversal exactly as it did on the original execution.

The Godot executor continues to persist its outcome map with the game world. Version 2 keys include a `v2:` prefix, so old saved keys cannot collide with new actions. The game-world save format is not deleted by this protocol migration.

The Agent Service decision memory records the ordered selected action names and decision summary. It receives one outcome request per attempted action, allowing verified memory to reflect partial completion accurately.

## Destructive Version 2 Data Migration

SQLite `PRAGMA user_version` identifies the Agent database protocol generation. On startup:

- a new database initializes directly as version 2;
- an existing database whose version is not 2 is treated as pre-v2 and reset once;
- sessions, raw events, long-term memories, FTS data, and idempotency data are all cleared;
- the version 2 schema is recreated and `user_version` is set to 2;
- subsequent version 2 starts do not clear data again.

When and only when that database upgrade occurs, the service removes old checkpoint database files under the configured checkpoint root. Deletion is restricted to `.sqlite`, `.sqlite-wal`, and `.sqlite-shm` files resolved inside that configured directory. It does not delete the directory itself, unrelated files, files outside the configured root, or Godot world saves.

The migration runs before the service begins listening, so version 2 requests cannot observe partially migrated state. Startup fails visibly if the database reset or checkpoint cleanup cannot complete.

## Error Handling

- Protocol version mismatch: reject the request or stream as `invalid_protocol_version`.
- Invalid batch size, action, order constraint, authorization, or arguments: reject the whole decision before Godot mutation.
- Provider returns four or more calls: emit `stream.error`; do not cache a decision.
- Current world rejects an otherwise valid action: report its concrete domain failure, stop remaining actions, and do not retry the model.
- Empty action list: complete normally without an outcome.
- Database or checkpoint migration failure: do not start the Agent Service.

## Tests and Acceptance

TypeScript tests must prove:

- version 1 requests, decisions, outcomes, and cached shapes reject;
- zero, one, two, and three Provider tool calls normalize to ordered version 2 actions;
- four calls reject;
- fragmented and interleaved multi-call SSE arguments assemble correctly;
- every action is authorized and argument-valid;
- action IDs and idempotency keys are deterministic and unique;
- `wait` is empty-batch-adjacent but, when called, remains exclusive;
- decision memory records the ordered action list;
- version 2 outcomes correlate by action ID;
- upgrading an old populated database clears every Agent data table and old checkpoint SQLite file;
- restarting an already version 2 database preserves new data.

Godot tests must prove:

- version 1 and old single-tool envelopes reject;
- zero through three actions parse, while four reject;
- a valid decision with an old expected revision still executes;
- actions based on the same revision can modify independent assets sequentially;
- competing actions against the same plot return a specific domain failure rather than `stale_world_revision`;
- failure and `in_progress` stop later actions but preserve earlier commits;
- empty actions complete without mutation or outcome;
- `wait` is exclusive;
- each attempted action reports one ordered outcome and no extra Gateway decision request occurs;
- executor revision and saved outcomes remain valid after multi-action execution.

Final acceptance restarts the configured local Agent Service to trigger the destructive migration, verifies the old database tables and checkpoint SQLite files are gone, runs both TypeScript and Godot suites, and performs a simulated Godot streaming request through the real local service. The acceptance result may contain zero through three actions but must be a valid version 2 decision.

## Out of Scope

- visual NPC movement or animation for actions;
- cross-action atomic rollback;
- entity-specific revision tracking;
- automatic model retry after domain failure;
- compatibility with protocol version 1 or preservation of pre-v2 Agent databases and checkpoints;
- deletion of Godot world saves or non-SQLite files in the checkpoint directory.
