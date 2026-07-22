# AI NPC Agent Phase D Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add secure multi-Agent cooperation through ACL-protected knowledge channels and a Team Coordinator that delegates goals without reading private memory or executing game actions.

**Architecture:** Shared knowledge is a separate repository with explicit audience and provenance. Team Coordinator produces sub-goals and assignments; individual Agents decide their own actions, and Godot validates all results through the existing protocol.

**Tech Stack:** Phase C Agent Service, PostgreSQL/SQLite repository, Loom child loops, Godot team-task projections.

## Global Constraints

- Channel IDs are `public:village`, `family:<id>`, `profession:<id>`, `organization:<id>`, or `team:<id>`.
- Every knowledge item has source, confidence, audience, created time, and expiry.
- Private Agent memory is never queryable through channel APIs.
- Knowledge publication requires membership and a role-authorized tool.
- Team Coordinator cannot call Godot action tools or impersonate a member.
- Every service task runs `npm --prefix services/agent-service test && npm --prefix services/agent-service run typecheck`.
- Every Godot task runs `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`.

---

### Task 1: Channel model and ACL repository

**Files:** Create `services/agent-service/src/knowledge/channel-types.ts`, `channel-repository.ts`, `sqlite-channel-repository.ts`, `postgres-channel-repository.ts`, and `tests/channel-repository.test.ts`.

- [ ] Test valid IDs, membership read/write roles, expiry, provenance, conflicting facts, cross-save isolation, and private-memory non-access.
- [ ] Implement transactional publish/query/revoke with stable pagination and no implicit public fallback.
- [ ] Run tests/typecheck and commit `feat: add ACL knowledge channels`.

### Task 2: Knowledge publication and perception tools

**Files:** Create `services/agent-service/src/tools/publish-channel-knowledge.ts`, `query-channel-knowledge.ts`, `tests/channel-tools.test.ts`; modify `src/loom/npc-context.ts`.

- [ ] Test role allowlists, audience narrowing, confidence bounds, untrusted player claims, duplicate source events, expired facts, and denied channels.
- [ ] Implement explicit tool schemas. Publication records an Agent-authored claim; it never rewrites private memory or Godot state.
- [ ] Run tests and commit `feat: let authorized agents share knowledge`.

### Task 3: Team goals and Coordinator

**Files:** Create `services/agent-service/src/teams/team-types.ts`, `team-coordinator.ts`, `team-repository.ts`, and `tests/team-coordinator.test.ts`.

**Interfaces:** `createTeamGoal`, `planAssignments`, `reportProgress`, `reassignFailed`; assignments include required capabilities and individual sub-goals.

- [ ] Test capability matching, no eligible member, balanced assignments, failure reassignment, cancellation, budget cap, and coordinator tool denial.
- [ ] Implement Coordinator as a Loom loop whose affordances contain registry/channel/team tools only—never `move_to`, `work`, trade, quest, or inventory tools.
- [ ] Run tests and commit `feat: coordinate multi-agent village teams`.

### Task 4: Godot team-task projection

**Files:** Create `scripts/agents/team_task_bridge.gd`, `tests/test_team_task_bridge.gd`; modify `shared/agent_protocol/v1/fixtures/checkpoint.json`, `scripts/agents/npc_agent_controller.gd`, `tests/run_tests.gd`.

- [ ] Test assignment acceptance, stale assignment rejection, individual outcome aggregation, save/reload, offline continuation, and no direct Coordinator action execution.
- [ ] Project an assignment into each Agent's current goals and report only validated Godot outcomes. Preserve deterministic fallback tasks when service is absent.
- [ ] Run Godot/contract tests and commit `feat: project agent team goals into Godot`.

### Task 5: Information propagation acceptance

**Files:** Create `services/agent-service/tests/team-acceptance.test.ts` and `tests/team_agent_acceptance.gd`.

- [ ] Scenario: one NPC witnesses a resource shortage, publishes to its profession channel, Coordinator creates a repair team, eligible members receive sub-goals, Godot accepts their legal work outcomes, and an unrelated NPC cannot read the channel.
- [ ] Add adversarial cases for prompt injection, forged membership, private-memory query, expired facts, replayed assignment, and Coordinator action attempt.
- [ ] Run all service/Godot suites plus 20-member team load; commit `test: verify secure multi-agent cooperation`.
