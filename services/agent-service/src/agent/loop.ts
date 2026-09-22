import type { AgentContext } from "../agents.ts";
import type { ActionIntent, DecisionRequest } from "../protocol.ts";
import type {
  AgentStreamAssembler,
  ProviderTraceEvent,
} from "../provider_stream.ts";
import {
  LoopBudget,
  DEFAULT_LOOP,
  type LoopConfig,
} from "../budget/loop_budget.ts";
import { ContextBudget, inputEstimate } from "../budget/context_budget.ts";
import { buildContext } from "./build_context.ts";
import { ToolMenu } from "./tool_menu.ts";
import { executeTools, type ToolCall } from "./execute_tools.ts";
import type { LoopServices } from "./types.ts";
import { runLegacyAgentLoop } from "./legacy_loop.ts";

export {
  DEFAULT_LOOP,
  validateLoopConfig,
  type LoopConfig,
} from "../budget/loop_budget.ts";
export { inputEstimate } from "../budget/context_budget.ts";
export { compactWorkingMessages } from "../agent_context_compaction.ts";
export { GAME_ENV, QUERY_CATALOG } from "./environment.ts";
export { commandDomain, readDefinition, validLoopRead } from "./tools.ts";
export type { LoopServices, ReadPort } from "./types.ts";

type ModelRound = (
  messages: Record<string, unknown>[],
  tools: Record<string, unknown>[],
  fast: boolean,
) => Promise<AgentStreamAssembler>;

/** build context -> model tool calls -> sequential execution -> append results -> repeat */
export async function runAgentLoop(
  request: DecisionRequest,
  context: AgentContext,
  services: LoopServices,
  round: ModelRound,
  emit: (event: ProviderTraceEvent) => void,
  signal?: AbortSignal,
  config: LoopConfig = DEFAULT_LOOP,
): Promise<ActionIntent> {
  // Older clients understand only a final action batch, not action.request receipts.
  if (!services.execute)
    return runLegacyAgentLoop(
      request,
      context,
      services,
      round,
      emit,
      signal,
      config,
    );

  const publicAgent = context.agent.active_role === "public_coordinator";
  const budget = new LoopBudget(config, publicAgent ? 1 : config.max_actions);
  const capacity = new ContextBudget();
  const menu = new ToolMenu(context.allowed_command_tools, publicAgent);
  let { header, messages } = buildContext(
    request,
    context,
    services,
    config,
    menu.domains,
    budget.actionLimit,
  );
  let corrections = 0;

  while (true) {
    signal?.throwIfAborted();
    budget.nextRound();
    const current = menu.build(budget);
    header.turn.budget = budget.snapshot();
    header.turn.query_catalog = current.catalog;
    messages[1] = { role: "user", content: JSON.stringify(header) };
    messages = capacity.fit(messages, current.tools, config, request, emit);
    emit({
      type: "loop",
      payload: {
        event: "loop.round",
        loop_id: request.request_id,
        round: budget.rounds,
        reads: budget.reads,
        read_rounds: budget.readRounds,
        actions: budget.actions,
        compactions: capacity.compactions,
        input_estimate: inputEstimate({ messages, tools: current.tools }),
      },
    });

    const output = await round(messages, current.tools, corrections > 0);
    const raw = output.rawOutput();
    let calls: ToolCall[];
    try {
      if (raw.finish_reason === "length")
        throw new Error("provider_output_truncated");
      calls = output.toolCalls(4);
      validateCalls(calls, current, menu, budget);
    } catch (error) {
      signal?.throwIfAborted();
      const reason =
        error instanceof Error ? error.message : "invalid_tool_calls";
      emit({
        type: "loop",
        payload: {
          event: "loop.validation_failed",
          loop_id: request.request_id,
          error: reason,
        },
      });
      if (reason.includes("unauthorized") || corrections++ >= 1) throw error;
      messages.push({
        role: "system",
        content: `This response's calls were not executed. Correct the error: ${reason}. Earlier completed calls remain committed. Remaining budget: ${JSON.stringify(budget.snapshot())}`,
      });
      continue;
    }

    if (!calls.length) return output.finish(request, [], 0).intent;
    messages.push({
      role: "assistant",
      content: raw.message.content || null,
      tool_calls: raw.message.tool_calls,
    });
    const uncertain = await executeTools(
      calls,
      menu,
      current,
      request,
      services,
      budget,
      messages,
      header,
      emit,
      signal,
    );
    if (uncertain)
      return {
        protocol_version: 2,
        decision_id: `loop:${request.request_id}`,
        request_id: request.request_id,
        agent_id: request.agent_id,
        expected_revision: request.world_revision,
        actions: [],
        decision_summary: "Execution requires reconciliation",
      };
  }
}

function validateCalls(
  calls: ToolCall[],
  current: ReturnType<ToolMenu["build"]>,
  menu: ToolMenu,
  budget: LoopBudget,
): void {
  const knownReads = [
    "discover_tools",
    "inspect_self_resources",
    "recall_memory",
    "query_world",
    "query_map",
    "inspect_event",
    "inspect_history_segment",
  ];
  for (const call of calls) {
    if (
      !current.reads.includes(call.name) &&
      !current.commands.includes(call.name)
    ) {
      if (
        !menu.authorized.includes(call.name) &&
        !knownReads.includes(call.name)
      )
        throw new Error("provider_unauthorized_tool");
      throw new Error(`tool_not_enabled_or_budget_exhausted:${call.name}`);
    }
  }
  if (new Set(calls.map((c) => c.id)).size !== calls.length)
    throw new Error("duplicate_tool_call_id");
  const reads = calls.filter((c) => current.reads.includes(c.name)).length;
  if (reads > budget.snapshot().remaining_read_calls)
    throw new Error("read_budget_exceeded");
  if (calls.length - reads > budget.remainingActions)
    throw new Error("action_budget_exceeded");
  if (calls.length > 1 && calls.some((c) => c.name === "wait"))
    throw new Error("wait_must_be_exclusive");
}
