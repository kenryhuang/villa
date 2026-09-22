import type { ActionCommand } from "../protocol.ts";

export type Message = Record<string, unknown>;

/** Preserve the provider's assistant call and its protocol-linked tool result. */
export function appendToolResult(
  messages: Message[],
  id: string,
  name: string,
  result: Message,
): void {
  messages.push({
    role: "tool",
    tool_call_id: id,
    name,
    content: JSON.stringify(result),
  });
}

export async function executeAction(
  execute: (action: ActionCommand, signal?: AbortSignal) => Promise<Message>,
  action: ActionCommand,
  signal?: AbortSignal,
): Promise<Message> {
  try {
    return await execute(action, signal);
  } catch (error) {
    signal?.throwIfAborted();
    // Transport uncertainty is not permission to repeat a side effect.
    return {
      ok: false,
      status: "unknown",
      error: error instanceof Error ? error.message : "tool_execution_failed",
      action_id: action.action_id,
      idempotency_key: action.idempotency_key,
      instruction:
        "Execution may have started. Inspect current activity/outcomes before retrying; do not assume rollback.",
    };
  }
}
