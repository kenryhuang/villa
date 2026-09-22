import { compactWorkingMessages } from "../agent_context_compaction.ts";
import type { LoopConfig } from "./loop_budget.ts";
import type { ProviderTraceEvent } from "../provider_stream.ts";
export const inputEstimate = (value: unknown): number =>
  new TextEncoder().encode(JSON.stringify(value)).length;
export class ContextBudget {
  compactions = 0;
  fit(
    messages: Record<string, unknown>[],
    tools: Record<string, unknown>[],
    config: LoopConfig,
    request: { request_id: string },
    emit: (event: ProviderTraceEvent) => void,
  ) {
    const before = inputEstimate({ messages, tools });
    const protectedInput = inputEstimate({
      messages: messages.slice(0, 2),
      tools,
    });
    const hardPressure = before > config.max_input_tokens;
    if (
      messages.length > 2 &&
      (hardPressure ||
        (before >= config.compact_at_tokens &&
          this.compactions < config.max_compactions))
    ) {
      // The immutable header and tool schema are a real floor. Leave room for
      // useful observations instead of repeatedly targeting below that floor.
      const target = Math.min(
        config.max_input_tokens - 1024,
        Math.max(
          config.compact_target_tokens,
          protectedInput + Math.min(8192, config.max_input_tokens / 8),
        ),
      );
      const candidate = compactWorkingMessages(
        messages,
        target - inputEstimate({ tools, messages: [] }),
      );
      const after = inputEstimate({ messages: candidate, tools });
      // An expanded fixed header may cross the soft threshold before there is
      // compressible history. Do not spend a compaction or enlarge the context.
      if (after < before) {
        messages = candidate;
        this.compactions++;
        emit({
          type: "loop",
          payload: {
            event: "context.compacted",
            loop_id: request.request_id,
            before,
            after,
            target,
            configured_target: config.compact_target_tokens,
            protected_input: protectedInput,
            target_met: after <= target,
            count: this.compactions,
            reason: hardPressure ? "hard_limit_recovery" : "threshold",
            estimate: "utf8_bytes_upper_bound",
          },
        });
      }
    }
    const finalSize = inputEstimate({ messages, tools });
    if (finalSize > config.max_input_tokens) {
      emit({
        type: "loop",
        payload: {
          event: "context.capacity_exceeded",
          loop_id: request.request_id,
          input_estimate: finalSize,
          protected_input: protectedInput,
          tool_bytes: inputEstimate(tools),
          limit: config.max_input_tokens,
          compactions: this.compactions,
          reason:
            protectedInput > config.max_input_tokens
              ? "protected_header_and_tools"
              : "working_context",
        },
      });
      throw new Error("context_capacity_exceeded");
    }
    return messages;
  }
}
