import { createHash } from "node:crypto";
import type { DecisionRequest } from "../protocol.ts";
export function chatRoomKey(
  r: Pick<DecisionRequest, "agent_id" | "chat_room">,
): string {
  const members = [...(r.chat_room?.participants ?? [r.agent_id])].sort();
  return `chat.room:${createHash("sha256")
    .update(
      JSON.stringify(
        r.chat_room ? ["group", r.chat_room.id] : ["private", members],
      ),
    )
    .digest("hex")}`;
}
export function chatGenerationScope(scope: string, generation: string): string {
  return generation
    ? `${scope}:context:${createHash("sha256").update(generation).digest("hex")}`
    : scope;
}
