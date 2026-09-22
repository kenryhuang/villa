import type { MemoryRepository } from "../memory.ts";
import type { ChatPort } from "./provider.ts";
import type { DecisionRequest } from "../protocol.ts";
import type { ProviderTraceEvent } from "../provider_stream.ts";
import { CHAT_HISTORY_TURNS, selectChatHistory } from "./build_context.ts";

export async function prepareChatContext(
  memory: MemoryRepository,
  _provider: ChatPort,
  r: DecisionRequest,
  scope: string,
  emit: (e: ProviderTraceEvent) => void,
  isCurrent: () => boolean,
  signal?: AbortSignal,
) {
  signal?.throwIfAborted();
  if (memory.closed || !isCurrent()) throw new Error("chat_context_reset");
  const history = selectChatHistory(
    r,
    memory.chatRecentTurns(r.session_id, scope, CHAT_HISTORY_TURNS),
  );
  emit({
    type: "loop",
    payload: {
      event: "chat.context_window",
      retained_event_ids: history.map((e) => e.event_id),
      retained_messages: history.length,
      retained_turns: history.filter((e) => e.payload.speaker === "player")
        .length,
      max_turns: CHAT_HISTORY_TURNS,
      summary_characters: 0,
      extraction_scope: "current_player_and_current_npc_reply",
    },
  });
  return { history, summary: "" };
}
