import { selectDialogueContext } from "../memory/dialogue_context.ts";
import {
  decisionContext,
  compactMemoryIfDue,
  storeDecision,
  archiveGoalPlans,
  type AppDependencies,
} from "../memory/service.ts";
import { actionActor, actionFacts } from "../context_channels.ts";
import type { DecisionRequest } from "../protocol.ts";
import type { ProviderTraceEvent } from "../provider_stream.ts";
import type { WorldReadBroker } from "../world_read_broker.ts";
import type { ActionBroker } from "../transport/action_broker.ts";

export async function runActionLoop(
  dependencies: AppDependencies,
  decisionRequest: DecisionRequest,
  decisionKey: string,
  receivedEventIds: unknown[],
  reads: WorldReadBroker,
  actions: ActionBroker,
  emit: (event: ProviderTraceEvent) => void,
  writeEvent: (name: string, payload: unknown) => void,
  signal: AbortSignal,
): Promise<void> {
  if (!dependencies.provider.streamDecision)
    throw new Error("provider_streaming_unavailable");
  const inspectedIntents = new Set<string>();
  const context = decisionContext(dependencies, decisionRequest);
  void compactMemoryIfDue(
    dependencies,
    decisionRequest.session_id,
    decisionRequest.agent_id,
  );
  if (decisionRequest.protocol_version === 3) {
    writeEvent("context.ack", {
      session_id: decisionRequest.session_id,
      session_epoch: decisionRequest.session_epoch,
      request_id: decisionRequest.request_id,
      event_ids: receivedEventIds,
    });
    const storageId = dependencies.chatProvider
      ? actionActor(decisionRequest.agent_id)
      : decisionRequest.agent_id;
    const experience = dependencies.memory.experience(
      decisionRequest.session_id,
      storageId,
    );
    const recentIds = new Set(
      (experience.recent_events as Record<string, unknown>[]).map(
        (e) => e.event_id,
      ),
    );
    context.loop_services = {
      experience,
      core_memories: dependencies.memory.coreMemories(
        decisionRequest.session_id,
        storageId,
      ),
      confirmed_dialogue: selectDialogueContext(
        dependencies.memory.pendingDialogueIntents(
          decisionRequest.session_id,
          storageId,
        ),
      ),
      ...(decisionRequest.tool_execution === "inline"
        ? {
            execute: async (action, signal) => {
              // Archive model-authored goal text before the executor creates a goal reference.
              const dispatchId = `dispatch:${action.idempotency_key}`;
              const previous = dependencies.memory.inspectEvent(
                decisionRequest.session_id,
                storageId,
                dispatchId,
              );
              if (
                previous.found &&
                JSON.stringify((previous.payload as any).action) !==
                  JSON.stringify(action)
              )
                throw new Error("tool_replay_mismatch");
              dependencies.memory.appendEvent(
                decisionRequest.session_id,
                storageId,
                {
                  event_id: dispatchId,
                  kind: "ActionToolDispatched",
                  game_minute: decisionRequest.game_minute,
                  payload: { action },
                },
              );
              archiveGoalPlans(dependencies, decisionRequest, [action]);
              const outcome = await actions.execute(
                decisionRequest,
                action,
                (p) => writeEvent("action.request", p),
                signal,
              );
              const fresh = await reads.read(
                decisionRequest,
                "inspect_self_resources",
                {},
                (p) => writeEvent("read.request", p),
                signal,
              );
              return actionFacts({
                ...outcome,
                ...(fresh.resources ? { resources: fresh.resources } : {}),
              });
            },
          }
        : {}),
      memories: context.memories.filter(
        (m) =>
          !(m.source_event_ids as string[] | undefined)?.some((id) =>
            recentIds.has(id),
          ),
      ),
      read: async (name, args, signal) => {
        if (name === "recall_memory")
          return {
            memories: dependencies.memory.relevant(
              decisionRequest.session_id,
              storageId,
              String(args.query),
            ),
          };
        if (name === "inspect_event") {
          const event = dependencies.memory.inspectEvent(
            decisionRequest.session_id,
            storageId,
            String(args.event_id),
          );
          if (event.found) inspectedIntents.add(String(args.event_id));
          return event;
        }
        if (name === "inspect_history_segment")
          return dependencies.memory.historySegment(
            decisionRequest.session_id,
            storageId,
            Number(args.cursor ?? 0),
          );
        const result = await reads.read(
          decisionRequest,
          name,
          args,
          (p) => writeEvent("read.request", p),
          signal,
        );
        if (result.resources)
          dependencies.memory.syncResources(
            decisionRequest.session_id,
            decisionRequest.agent_id,
            decisionRequest.session_epoch,
            Number(
              (result.resources as Record<string, unknown>).resource_revision,
            ),
            result.resources as Record<string, unknown>,
          );
        return dependencies.chatProvider ? actionFacts(result) : result;
      },
    };
  }
  const intent = await dependencies.provider.streamDecision(
    decisionRequest,
    context,
    emit,
    signal,
  );
  if (!signal.aborted) {
    storeDecision(dependencies, decisionRequest, decisionKey, intent);
    if (intent.decision_summary !== "Execution requires reconciliation")
      dependencies.memory.consumeDialogueIntents(
        decisionRequest.session_id,
        dependencies.chatProvider
          ? actionActor(decisionRequest.agent_id)
          : decisionRequest.agent_id,
        (context.loop_services?.confirmed_dialogue ?? [])
          .filter(
            (e) =>
              !e.context_only &&
              (!e.details_available ||
                inspectedIntents.has(String(e.event_id))),
          )
          .map((e) => String(e.event_id)),
        decisionRequest.game_minute,
      );
    writeEvent("decision.final", intent);
    writeEvent("stream.completed", { status: "completed", cached: false });
  }
}
