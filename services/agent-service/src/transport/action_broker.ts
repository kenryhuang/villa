import type { ActionCommand, ActionOutcome, DecisionRequest } from "../protocol.ts";

/** Godot is the executor. A model round waits for a terminal receipt, not dispatch. */
export class ActionBroker {
  #pending = new Map<
    string,
    { session: string; actor: string; action: ActionCommand; resolve: (result: Record<string, unknown>) => void }
  >();

  execute(
    request: DecisionRequest,
    action: ActionCommand,
    emit: (payload: unknown) => void,
    signal?: AbortSignal,
  ): Promise<Record<string, unknown>> {
    signal?.throwIfAborted();
    const key = JSON.stringify([request.session_id, request.agent_id, action.idempotency_key]);
    if (this.#pending.has(key)) throw new Error("action_already_pending");
    return new Promise((resolve, reject) => {
      const cleanup = () => {
        this.#pending.delete(key);
        signal?.removeEventListener("abort", cancel);
      };
      const cancel = () => {
        cleanup();
        reject(new Error("action_wait_cancelled"));
      };
      this.#pending.set(key, {
        session: request.session_id,
        actor: request.agent_id,
        action,
        resolve: (result) => {
          cleanup();
          resolve(result);
        },
      });
      signal?.addEventListener("abort", cancel, { once: true });
      emit({
        session_id: request.session_id,
        session_epoch: request.session_epoch,
        request_id: request.request_id,
        agent_id: request.agent_id,
        intent: {
          protocol_version: 2,
          decision_id: `step:${request.request_id}`,
          request_id: request.request_id,
          agent_id: request.agent_id,
          expected_revision: request.world_revision,
          actions: [action],
          decision_summary: "Execute one agent-loop tool call",
        },
      });
    });
  }

  accept(session: string, actor: string, outcome: ActionOutcome): boolean {
    const pending = this.#pending.get(JSON.stringify([session, actor, outcome.idempotency_key]));
    if (!pending || outcome.action_id !== pending.action.action_id) return false;
    if (["accepted", "in_progress"].includes(outcome.status)) return true;
    pending.resolve({ ok: outcome.status === "completed", ...outcome, tool_name: pending.action.tool_name });
    return true;
  }
}
