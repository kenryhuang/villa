import type { AppDependencies } from "../memory/service.ts";
import type { DecisionRequest } from "../protocol.ts";
import type { ProviderTraceEvent } from "../provider_stream.ts";
import type { ReadPort } from "../agent_loop.ts";
import { actionActor } from "../context_channels.ts";
import { chatGenerationScope, renderHandoffs } from "../chat_provider.ts";
import { importantChatActors } from "../chat_context.ts";
import { prepareChatContext } from "./context_window.ts";
import type { ChatIntentWorker } from "./intent_worker.ts";

export async function runChatLoop(
  dependencies: AppDependencies,
  decisionRequest: DecisionRequest,
  chatScope: string,
  chatGeneration: string,
  decisionKey: string,
  worker: ChatIntentWorker,
  read: ReadPort,
  emit: (event: ProviderTraceEvent) => void,
  writeEvent: (name: string, payload: unknown) => void,
  signal: AbortSignal,
): Promise<void> {
  if (decisionRequest.protocol_version !== 3)
    throw new Error("chat_requires_protocol_v3");
  const participants = decisionRequest.chat_room?.participants ?? [
    decisionRequest.agent_id,
  ];
  if (
    participants.some(
      (id) => !dependencies.registry.get(id) || id === "village_public",
    )
  )
    throw new Error("invalid_chat_participant");
  dependencies.memory.syncSession(
    decisionRequest.session_id,
    decisionRequest.session_epoch,
  );
  const scope = chatGenerationScope(chatScope, chatGeneration);
  const userEventId = `chat-user:${decisionRequest.chat_room?.turn_id ?? decisionRequest.request_id}`;
  const existing = dependencies.memory.inspectEvent(
    decisionRequest.session_id,
    scope,
    userEventId,
  );
  if (
    existing.found &&
    (existing.payload as any).text !== decisionRequest.dialogue_input
  )
    throw new Error("chat_turn_changed");
  dependencies.memory.appendEvent(decisionRequest.session_id, scope, {
    event_id: `chat-user:${decisionRequest.chat_room?.turn_id ?? decisionRequest.request_id}`,
    kind: "ChatMessage",
    game_minute: decisionRequest.game_minute,
    payload: { speaker: "player", text: decisionRequest.dialogue_input ?? "" },
  });
  const chatContext = dependencies.registry.buildContext(
    decisionRequest.agent_id,
    decisionRequest,
    [],
  );
  const window = await prepareChatContext(
    dependencies.memory,
    dependencies.chatProvider!,
    decisionRequest,
    scope,
    emit,
    () =>
      dependencies.memory.chatContextGeneration(
        decisionRequest.session_id,
        chatScope,
      ) === chatGeneration,
    signal,
  );
  const actors = importantChatActors(
    decisionRequest,
    dependencies.registry
      .ids()
      .filter((id) => id !== "village_public")
      .map((id) => {
        const a = dependencies.registry.get(id)!;
        return { id, name: a.display_name };
      }),
  );
  const provider = dependencies.chatProvider!;
  const intent = provider.reply
    ? await provider.reply(
        decisionRequest,
        chatContext,
        window.history,
        actors,
        emit,
        signal,
        window.summary,
      )
    : await provider.respond(
        decisionRequest,
        chatContext,
        window.history,
        actors,
        read,
        emit,
        signal,
        window.summary,
      );
  if (
    dependencies.memory.chatContextGeneration(
      decisionRequest.session_id,
      chatScope,
    ) !== chatGeneration
  )
    throw new Error("chat_context_reset");
  if (!signal.aborted) {
    dependencies.memory.appendEvent(decisionRequest.session_id, scope, {
      event_id: `chat-reply:${decisionRequest.request_id}`,
      kind: "ChatMessage",
      game_minute: decisionRequest.game_minute,
      payload: {
        speaker: decisionRequest.agent_id,
        text: intent.speech ?? "",
        participants,
      },
    });
    if (intent.chat_handoffs?.length) {
      dependencies.memory.appendEvent(
        decisionRequest.session_id,
        actionActor(decisionRequest.agent_id),
        {
          event_id: `dialogue:${decisionRequest.request_id}`,
          kind: "ChatActionAgreed",
          game_minute: decisionRequest.game_minute,
          payload: {
            handoff_version: 1,
            player_text: "",
            agent_speech: renderHandoffs(intent.chat_handoffs),
            submitted_actions: [],
            outcomes: [],
            handoffs: intent.chat_handoffs,
          },
        },
      );
      writeEvent("loop.trace", {
        event: "chat.handoff_archived",
        source_event_id: `dialogue:${decisionRequest.request_id}`,
        handoffs: intent.chat_handoffs,
      });
    }
    if (provider.extractIntents && provider.reply) {
      worker.enqueue({
        actor: decisionRequest.agent_id,
        player: decisionRequest.dialogue_input ?? "",
        reply: intent.speech ?? "",
        request_id: decisionRequest.request_id,
        session_id: decisionRequest.session_id,
        session_epoch: decisionRequest.session_epoch,
        game_minute: decisionRequest.game_minute,
        room: chatScope,
        generation: chatGeneration,
      });
      writeEvent("loop.trace",{event:"chat.intent_queued",request_id:decisionRequest.request_id});
    }
    dependencies.memory.storeIdempotent(decisionKey, intent);
    writeEvent("decision.final", intent);
    writeEvent("stream.completed", { status: "completed", cached: false });
  }
}
