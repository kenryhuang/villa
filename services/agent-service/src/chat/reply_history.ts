import type { MemoryEvent } from "../memory.ts";
import { chatReplyText } from "../chat_reply.ts";

// Match whole long messages, never common greetings, paraphrases or substrings.
const MIN_ECHO_CHARS = 40;

export function historicalReplyPrefixes(history: MemoryEvent[], actor: string): string[] {
  const prefixes = new Set<string>();
  for (const event of history) {
    if (event.kind !== "ChatMessage" || event.payload.speaker !== actor) continue;
    const raw = chatReplyText(String(event.payload.text ?? ""));
    const clean = withoutHistoricalReply(raw, [...prefixes]);
    for (const text of [raw, clean]) if (text.length >= MIN_ECHO_CHARS) prefixes.add(text);
  }
  return [...prefixes].sort((a, b) => b.length - a.length);
}

/** Wait while a stream could be replaying history so old text never flashes in the UI. */
export function withoutHistoricalReply(text: string, prefixes: string[], complete = true): string {
  let remaining = text.trimStart();
  const candidates = prefixes.filter(p => p.length >= MIN_ECHO_CHARS).sort((a, b) => b.length - a.length);
  while (remaining) {
    if (!complete && candidates.some(p => p.startsWith(remaining))) return "";
    const prefix = candidates.find(p => remaining === p ||
      (remaining.startsWith(p) && /^\s*\n/.test(remaining.slice(p.length))));
    if (!prefix) {
      // The delimiter may arrive in a later chunk.
      if (!complete && candidates.some(p => remaining.startsWith(p) && /^\s*$/.test(remaining.slice(p.length)))) return "";
      break;
    }
    remaining = remaining.slice(prefix.length).trimStart();
  }
  return complete ? remaining.trimEnd() : remaining;
}

/** Keep the immutable archive intact; normalize only the model-facing copy. */
export function normalizeChatHistory(history: MemoryEvent[]): MemoryEvent[] {
  const prior: MemoryEvent[] = [];
  const normalized: MemoryEvent[] = [];
  for (const event of history) {
    if (event.kind !== "ChatMessage" || event.payload.speaker === "player") {
      normalized.push(event);
      prior.push(event);
      continue;
    }
    const text = withoutHistoricalReply(chatReplyText(String(event.payload.text ?? "")),
      historicalReplyPrefixes(prior, String(event.payload.speaker)));
    normalized.push({ ...event, payload: { ...event.payload, text } });
    prior.push(event);
  }
  return normalized;
}
