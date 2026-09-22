import { actionActor, appendIsolatedEvent } from "../context_channels.ts";
import { createHash } from "node:crypto";
import type { AgentRegistry } from "../agents.ts";
import type { MemoryRepository } from "../memory.ts";
import type { DecisionRequest, ActionIntent } from "../protocol.ts";
import type { ProviderTraceEvent } from "../provider_stream.ts";
import type { ChatPort } from "../chat_provider.ts";
export interface ProviderPort {
  decide(
    request: DecisionRequest,
    context: ReturnType<AgentRegistry["buildContext"]>,
  ): Promise<ActionIntent>;
  streamDecision?(
    request: DecisionRequest,
    context: ReturnType<AgentRegistry["buildContext"]>,
    emit: (event: ProviderTraceEvent) => void,
    signal?: AbortSignal,
  ): Promise<ActionIntent>;
  compactMemory?(
    agent: NonNullable<ReturnType<AgentRegistry["get"]>>,
    events: ReturnType<MemoryRepository["recent"]>,
    sessionId?: string,
  ): Promise<{ summary: string; importance: number }>;
}
export interface AppDependencies {
  memory: MemoryRepository;
  registry: AgentRegistry;
  provider: ProviderPort;
  chatProvider?: ChatPort;
  checkpointRoot: string;
}

export function appendExperience(
  d: AppDependencies,
  session: string,
  actor: string,
  event: Parameters<MemoryRepository["appendEvent"]>[2],
): void {
  if (d.chatProvider) appendIsolatedEvent(d.memory, session, actor, event);
  else d.memory.appendEvent(session, actor, event);
}

const memoryJobs = new WeakMap<MemoryRepository, Set<string>>();
export async function compactMemoryIfDue(
  dependencies: AppDependencies,
  sessionId: string,
  agentId: string,
): Promise<void> {
  const memory = dependencies.memory;
  if (memory.closed || !dependencies.provider.compactMemory) return;
  const jobs = memoryJobs.get(memory) ?? new Set<string>();
  memoryJobs.set(memory, jobs);
  const storageId = dependencies.chatProvider ? actionActor(agentId) : agentId;
  const key = `${sessionId}:${storageId}`;
  if (jobs.has(key)) return;
  jobs.add(key);
  try {
    const agent = dependencies.registry.get(agentId);
    if (!agent) return;
    const history = memory.historyCandidates(sessionId, storageId);
    if (history.events.length) {
      const summary = await dependencies.provider.compactMemory(
        agent,
        [
          ...(history.previous
            ? [
                {
                  event_id: "history-prefix",
                  kind: "prior_history_summary",
                  game_minute: history.events[0].game_minute,
                  payload: { summary: history.previous },
                },
              ]
            : []),
          ...history.events,
        ],
        sessionId,
      );
      if (memory.closed) return;
      if (
        history.events.every(
          (e) =>
            JSON.stringify(
              memory.inspectEvent(sessionId, storageId, e.event_id).payload,
            ) === JSON.stringify(e.payload),
        )
      )
        memory.storeHistory(
          sessionId,
          storageId,
          history.events.map((e) => e.event_id),
          summary.summary,
        );
    }
    if (!memory.shouldCompact(sessionId, storageId)) return;
    const events = memory.compactionCandidates(sessionId, storageId, 8);
    if (!events.length) return;
    const result = await dependencies.provider.compactMemory(
      agent,
      events,
      sessionId,
    );
    if (memory.closed) return;
    // A restored checkpoint may have removed these future events while the model ran.
    if (
      events.some(
        (e) =>
          JSON.stringify(
            memory.inspectEvent(sessionId, storageId, e.event_id).payload,
          ) !== JSON.stringify(e.payload),
      )
    )
      return;
    memory.storeLongTermMemory(
      sessionId,
      storageId,
      `memory:${sessionId}:${storageId}:${events[0].event_id}:${events.at(-1)!.event_id}`,
      result.summary,
      result.importance,
      events.map((e) => e.event_id),
    );
    if (result.importance >= 8)
      memory.storeCoreMemory(
        sessionId,
        storageId,
        `experience:${events[0].event_id}`,
        result.summary,
        events.map((e) => e.event_id),
        events.at(-1)!.game_minute,
      );
  } catch {
    // Durable raw candidates remain queryable and retry on the next event/sync.
  } finally {
    jobs.delete(key);
  }
}

export function decisionContext(
  dependencies: AppDependencies,
  request: DecisionRequest,
) {
  if (request.protocol_version === 3) {
    dependencies.memory.syncSession(request.session_id, request.session_epoch);
    const resources = request.resources!;
    dependencies.memory.syncResources(
      request.session_id,
      request.agent_id,
      request.session_epoch,
      Number(resources.resource_revision ?? request.world_revision),
      resources,
    );
    for (const event of request.experience_events ?? [])
      appendExperience(dependencies, request.session_id, request.agent_id, {
        event_id: String(event.event_id),
        kind: String(event.kind ?? event.event_type ?? "world"),
        game_minute: Number(event.game_minute),
        payload: (event.payload ?? event) as Record<string, unknown>,
      });
    const memories = dependencies.memory.relevant(
      request.session_id,
      dependencies.chatProvider
        ? actionActor(request.agent_id)
        : request.agent_id,
      [
        request.dialogue_input ?? "",
        JSON.stringify(
          dependencies.memory.pendingDialogueIntents(
            request.session_id,
            dependencies.chatProvider
              ? actionActor(request.agent_id)
              : request.agent_id,
          ),
        ),
        ...request.goals,
        JSON.stringify(request.goal_refs ?? []),
        JSON.stringify(request.dialogue_followups ?? []),
        JSON.stringify((request.experience_events ?? []).slice(-3)),
      ].join(" "),
    );
    return dependencies.registry.buildContext(
      request.agent_id,
      request,
      memories,
    );
  }
  const memories = [
    ...dependencies.memory.longTermRecent(
      request.session_id,
      request.agent_id,
      8,
    ),
    ...dependencies.memory
      .recent(request.session_id, request.agent_id, 8)
      .map((event) => ({ ...event })),
  ];
  return dependencies.registry.buildContext(
    request.agent_id,
    request,
    memories,
  );
}

export function storeDecision(
  dependencies: AppDependencies,
  request: DecisionRequest,
  decisionKey: string,
  intent: ActionIntent,
): void {
  dependencies.memory.storeIdempotent(decisionKey, intent);
  dependencies.memory.appendEvent(
    request.session_id,
    dependencies.chatProvider
      ? actionActor(request.agent_id)
      : request.agent_id,
    {
      event_id: `decision:${intent.decision_id}`,
      kind: "decision",
      game_minute: request.game_minute,
      payload: {
        actions: intent.actions,
        action_names: intent.actions.map((action) => action.tool_name),
        decision_summary: intent.decision_summary,
      },
    },
  );
  if (
    !dependencies.chatProvider &&
    request.trigger === "dialogue" &&
    request.dialogue_input?.trim()
  ) {
    dependencies.memory.appendEvent(
      request.session_id,
      dependencies.chatProvider
        ? actionActor(request.agent_id)
        : request.agent_id,
      {
        event_id: `dialogue:${request.protocol_version === 3 ? request.request_id : intent.decision_id}`,
        kind: "dialogue",
        game_minute: request.game_minute,
        payload: {
          player_text: request.dialogue_input,
          agent_speech:
            intent.speech?.trim() ||
            intent.actions
              .filter(
                (a) =>
                  a.tool_name === "speak" &&
                  a.arguments.target_actor_id === "player",
              )
              .map((a) => String(a.arguments.text ?? ""))
              .join("\n"),
        },
      },
    );
  }
  archiveGoalPlans(dependencies, request, intent.actions);
  void compactMemoryIfDue(dependencies, request.session_id, request.agent_id);
}

export function archiveGoalPlans(
  dependencies: AppDependencies,
  request: DecisionRequest,
  actions: ActionIntent["actions"],
): void {
  if (dependencies.chatProvider)
    for (const action of actions) {
      if (
        !["adopt_short_term_goal", "revise_short_term_goal"].includes(
          action.tool_name,
        )
      )
        continue;
      const goalId =
        action.tool_name === "adopt_short_term_goal"
          ? "goal-" +
            createHash("sha256")
              .update(action.idempotency_key)
              .digest("hex")
              .slice(0, 24)
          : String(action.arguments.goal_id);
      const version =
        action.tool_name === "adopt_short_term_goal"
          ? 1
          : Number(action.arguments.version) + 1;
      dependencies.memory.appendEvent(
        request.session_id,
        actionActor(request.agent_id),
        {
          event_id: `action-goal:${goalId}:${version}`,
          kind: "ActionGoalPlan",
          game_minute: request.game_minute,
          payload: {
            goal_id: goalId,
            version,
            description: action.arguments.description,
          },
        },
      );
    }
}
