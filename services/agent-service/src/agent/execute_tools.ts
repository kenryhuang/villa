import { createHash } from "node:crypto";
import type { DecisionRequest } from "../protocol.ts";
import type { ProviderTraceEvent } from "../provider_stream.ts";
import { toolArgumentErrors } from "../tool_contracts.ts";
import { validLoopRead } from "./tools.ts";
import {
  appendToolResult,
  executeAction,
  type Message,
} from "./tool_results.ts";
import type { LoopServices } from "./types.ts";
import type { LoopBudget } from "../budget/loop_budget.ts";
import type { ToolMenu } from "./tool_menu.ts";

export interface ToolCall {
  id: string;
  name: string;
  arguments: Record<string, unknown>;
}

/** Execute in the model's order. Every call, including a rejected one, gets a result. */
export async function executeTools(
  calls: ToolCall[],
  menu: ToolMenu,
  current: ReturnType<ToolMenu["build"]>,
  request: DecisionRequest,
  services: LoopServices,
  budget: LoopBudget,
  messages: Message[],
  header: {
    resources?: Record<string, unknown>;
    turn?: { executed_actions?: Record<string, unknown>[] };
  },
  emit: (event: ProviderTraceEvent) => void,
  signal?: AbortSignal,
): Promise<boolean> {
  if (calls.some((c) => current.reads.includes(c.name))) budget.readRounds++;
  const results: Message[] = [];
  let uncertain = false;
  for (const call of calls) {
    signal?.throwIfAborted();
    let result: Message;
    if (uncertain) {
      result = {
        ok: false,
        status: "not_executed",
        error: "previous_action_outcome_unknown",
      };
    } else if (current.reads.includes(call.name)) {
      budget.reads++;
      result = await executeRead(call, menu, current, services, signal);
      emit({
        type: "loop",
        payload: {
          event: "read.result",
          loop_id: request.request_id,
          name: call.name,
          arguments: call.arguments,
          result,
        },
      });
    } else {
      budget.takeAction();
      const action = {
        action_id: `step-${budget.actions}-${createHash("sha256").update(request.request_id).digest("hex").slice(0, 24)}`,
        idempotency_key: `loop:${request.session_epoch}:${request.request_id}:${budget.actions}`,
        tool_name: call.name,
        tool_version: 1 as const,
        arguments: call.arguments,
      };
      const errors = toolArgumentErrors(call.name, call.arguments);
      result = errors.length
        ? {
            ok: false,
            status: "rejected",
            error: "invalid_action_arguments",
            details: errors,
          }
        : await executeAction(services.execute!, action, signal);
      header.turn?.executed_actions?.push({
        action_id: action.action_id,
        idempotency_key: action.idempotency_key,
        tool_name: action.tool_name,
        arguments: action.arguments,
        status: result.status ?? (result.ok ? "completed" : "failed"),
        failure_code: result.failure_code ?? result.error,
      });
      uncertain =
        result.status === "unknown" || result.status === "in_progress";
      emit({
        type: "loop",
        payload: {
          event: "action.result",
          loop_id: request.request_id,
          action,
          result,
        },
      });
    }
    if (result.resources && typeof result.resources === "object")
      header.resources = result.resources as Record<string, unknown>;
    appendToolResult(messages, call.id, call.name, result);
    results.push({ tool: call.name, ...result });
  }
  messages.push({
    role: "assistant",
    content: JSON.stringify({
      execution_results: results,
      reflection:
        "Reassess actual results. Errors are observations, not completion. Earlier successful calls remain committed; do not repeat them.",
    }),
  });
  return uncertain;
}

async function executeRead(
  call: ToolCall,
  menu: ToolMenu,
  current: ReturnType<ToolMenu["build"]>,
  services: LoopServices,
  signal?: AbortSignal,
): Promise<Message> {
  if (
    !validLoopRead(
      call.name,
      call.arguments,
      ["query_world", "query_map"].includes(call.name)
        ? current.queryDomains
        : menu.domains,
    )
  )
    return { ok: false, error: "invalid_read_arguments" };
  if (call.name === "discover_tools") return menu.discover(call.arguments);
  try {
    return await services.read(
      call.name === "query_map" ? "query_world" : call.name,
      call.name === "query_map"
        ? { ...call.arguments, domain: "map", section: "regions" }
        : call.arguments,
      signal,
    );
  } catch (error) {
    signal?.throwIfAborted();
    return {
      ok: false,
      error: error instanceof Error ? error.message : "read_failed",
    };
  }
}
