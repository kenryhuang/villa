# AI NPC Agent System Design

## Goal

Give each villager an independent, persistent Agent identity while keeping Godot authoritative over simulation and game rules. A remote TypeScript service uses an LLM and Loom-style ReAct loop to select high-level intentions, dialogue, and candidate actions; Godot validates and executes those actions, and falls back to deterministic schedules whenever the service is unavailable.

## Confirmed Product Decisions

- Use one independent TypeScript Agent Service containing logically isolated NPC Agents.
- Identify an Agent by `save_id + npc_id`; do not create one operating-system process per NPC.
- LLM controls dialogue, goals, plans, and high-level actions only.
- Godot controls movement, pathfinding, animation, collision, inventory, economy, quests, relationships, and save data.
- Use mixed dialogue: structured choices for consequential interactions and free text for ordinary conversation.
- Fall back to local schedules and authored dialogue on network, service, model, budget, or parsing failure.
- Use persistent long-term summaries plus bounded recent events instead of complete conversation history.
- Schedule nearby Agents frequently, distant relevant Agents at game-time intervals, and dormant Agents deterministically.
- Phase 2 shares knowledge through ACL-protected family, profession, organization, and team channels.

## Architecture

The Godot client owns `AgentGateway`, `AgentScheduler`, `WorldSnapshotBuilder`, `NpcAgentController`, `AgentActionValidator`, `AgentActionExecutor`, `DialogueController`, and `FallbackVillagerBrain`. The service owns session and decision APIs, logical Agent instances, Loom context construction, tool execution, memory, budgets, provider access, and traces.

Communication uses HTTPS JSON with protocol version `1`; dialogue may add SSE after the request/response contract works. Development uses a local service, while production switches the configured base URL to remote HTTPS. No provider API key is present in the Godot project.

The existing deterministic Villager state machine remains the actuator and fallback brain. AI augments it rather than replacing physics or per-frame behavior.

## Agent Context

Each Agent maps its data to Loom layers:

- `Identity`: role, personality, values, capabilities, and constraints.
- `Goal`: long-term and current objectives, success criteria, and budgets.
- `State`: recent observations, decisions, current action, and commitments.
- `Knowledge`: private facts, heuristics, recent memories, and long-term summaries.
- `Affordances`: permitted tools and resources.

Loom must be consumed through a versioned workspace, private package, or pinned git dependency. Production code must not reference `/Users/huanggui/workspace/loom` or any other machine-local absolute path.

## Perception Contract

Godot produces a minimal snapshot containing `world_revision`, game time, self state, nearby visible actors, visible objects, audible events, active quests, and relevant recent events. Perception is filtered by distance, visibility, location, and known information. Another NPC's private inventory, goal, and memory are never included by default.

Player input and world-authored text are untrusted data. They cannot replace identity, constraints, system instructions, or tool permissions.

## Decision Contract

A decision request includes `protocol_version`, `request_id`, `save_id`, `npc_id`, `world_revision`, `reason`, and `snapshot`. The response includes `decision_id`, the same NPC and world revision, `trace_id`, ordered actions, and `next_think_after_ms`.

Each action contains a unique `action_id`, a closed-set `type`, and schema-validated `params`. Phase A supports `move_to`, `face_actor`, `speak`, `work`, and `wait`. Trade, quest, gift, and memory mutation are added only after the base executor and rejection outcomes are proven.

The service only proposes actions. Godot checks protocol version, idempotency, identity, current world revision, tool permission, target existence, range, resources, and action-specific constraints. Accepted, rejected, failed, and completed outcomes are returned to the service.

## ReAct Limits

- At most 3 ReAct rounds per decision.
- At most 6 tool calls per decision.
- Autonomous decisions time out after 3 seconds.
- Dialogue decisions time out after 10 seconds.
- One in-flight request per NPC.
- Exceeding token or cost budget produces a normal fallback, not a game-blocking error.

## Dialogue

Consequential dialogue is authored as structured options. The model may vary wording and emotion but cannot alter the semantic action bound to an option. Free-text dialogue can update soft impressions and propose future intentions, but cannot directly grant resources, complete quests, or commit a trade. Consequential proposals require a Godot confirmation step.

## Scheduling

- P0: player conversation or critical story event; request immediately.
- P1: nearby and visible; request every 5–15 seconds or on a meaningful event.
- P2: off-screen but quest/team relevant; request each game hour or on a major event.
- P3: dormant, sleeping, or irrelevant; run no LLM request.

Requests for one NPC are serialized, duplicate events are coalesced, and a per-save budget controls concurrency, tokens, and estimated cost.

## Memory

Short-term memory contains at most 24 important observations and 12 dialogue turns plus active commitments. Long-term memory is a structured summary with source IDs, confidence, importance, and game time. Godot checkpoints contain the profile version, long-term summaries, relationship state, current goals, commitments, and sync cursor. The service stores recent windows and traces through a repository interface backed by SQLite in development and PostgreSQL remotely.

## Failure and Security

- Network failure or timeout enters deterministic fallback.
- A retryable 5xx is retried once with backoff; 429 immediately increases the think interval.
- Invalid JSON, unknown actions, and schema failures are rejected and traced.
- Stale world revisions are never executed.
- Late responses for unloaded or removed NPCs are ignored.
- A Godot checkpoint wins a save-memory conflict by creating a new server-side memory version.
- Tools use closed schemas and allowlists; there is no arbitrary code, filesystem, or network tool.
- Traces record inputs, tool calls, decisions, outcomes, latency, tokens, and cost, but not hidden model chain-of-thought.

## Phase 2 Team Model

Shared knowledge channels use `public:village`, `family:<id>`, `profession:<id>`, `organization:<id>`, and `team:<id>` identifiers with membership ACLs. Knowledge includes source, confidence, allowed audience, and expiry. Private Agent memory is not directly readable through a channel.

A Team Coordinator decomposes team objectives, assigns sub-goals to eligible members, gathers outcomes, and reallocates failed work. It cannot execute Godot actions or bypass individual Agent and action permissions.

## Delivery Phases

1. Phase A: protocol schemas, Mock Agent Service, Godot gateway, snapshot, validation, execution, outcome, and fallback.
2. Phase B: one real Loom-backed NPC, provider integration, short-term memory, and mixed dialogue.
3. Phase C: full-village registry, tiered scheduling, long-term summaries, checkpoints, budgets, and trace UI.
4. Phase D: knowledge channels, NPC information transfer, Team Coordinator, and team objectives.

Each phase receives a separate implementation plan. The first plan covers Phase A only so it produces a deterministic, testable vertical slice without requiring a real LLM or network service in CI.

## Acceptance Criteria

- A Godot NPC can send a filtered snapshot to a local Mock Agent Service and execute a valid `speak` or `move_to` action.
- Invalid, unauthorized, duplicate, stale, or malformed decisions do not mutate game state.
- Every attempted action produces an outcome that can be reported to the service.
- Service timeout and unavailability leave NPC schedules and authored dialogue functional.
- Shared protocol fixtures pass in TypeScript and Godot tests.
- No real provider key or live LLM is required by automated tests.
