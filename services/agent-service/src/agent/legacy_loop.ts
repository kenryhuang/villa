import { discoverTools } from "./discovery.ts";
import { LoopBudget } from "../budget/loop_budget.ts";
import { buildContext, buildTools } from "./build_context.ts";
import { GAME_ENV, QUERY_CATALOG } from "./environment.ts";
import { commandDomain, validLoopRead } from "./tools.ts";
export { GAME_ENV, QUERY_CATALOG } from "./environment.ts";
export { commandDomain, validLoopRead } from "./tools.ts";
import type { AgentContext } from "../agents.ts";
import type { DecisionRequest, ActionIntent } from "../protocol.ts";
import { toolArgumentErrors } from "../tool_contracts.ts";
import {
  AgentStreamAssembler,
  type ProviderTraceEvent,
} from "../provider_stream.ts";
import { LOOP_DIALOGUE_COMMANDS as DIALOGUE_COMMANDS } from "../agent_policy.ts";

import { compactWorkingMessages } from "../agent_context_compaction.ts";
import {
  RelationshipDialogue,
  asksRelationshipState,
  pendingRelationshipReply,
} from "../relationship_dialogue.ts";
export { compactWorkingMessages } from "../agent_context_compaction.ts";
import { DEFAULT_LOOP, type LoopConfig } from "../budget/loop_budget.ts";
import type { LoopServices } from "./types.ts";
const obj = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
const BASIC_COMMANDS = ["speak", "wait", "public_wait"];
// Tool-only responses are valid provider output. A trade must not be discarded
// just because the provider omitted prose. Describe the pending request only;
// Godot still validates/executes it and the recipient still has to accept it.
function pendingTradeReply(name: string): string | undefined {
  switch (name) {
    case "propose_trade":
      return "我准备提出这笔交易，请核对交易面板里的物品和金额；双方确认并执行成功后才算成交。";
    case "counter_trade":
      return "我准备提出一份新的交易报价，请核对交易面板里的条款；对方接受并执行成功后才算成交。";
    case "accept_trade":
      return "我准备接受这份交易报价，是否成交以接下来的执行结果为准。";
    case "reject_trade":
      return "我准备拒绝这份交易报价，处理结果以交易面板为准。";
    case "cancel_trade":
      return "我准备撤回这份交易报价，处理结果以交易面板为准。";
    default:
      return undefined;
  }
}
// Conservative UTF-8 byte bound: explicitly labelled as an estimate in telemetry.
export const inputEstimate = (value: unknown): number =>
  new TextEncoder().encode(JSON.stringify(value)).length;
export async function runLegacyAgentLoop(
  request: DecisionRequest,
  context: AgentContext,
  services: LoopServices,
  round: (
    messages: Record<string, unknown>[],
    tools: Record<string, unknown>[],
    fast: boolean,
  ) => Promise<AgentStreamAssembler>,
  emit: (event: ProviderTraceEvent) => void,
  signal?: AbortSignal,
  config: LoopConfig = DEFAULT_LOOP,
): Promise<ActionIntent> {
  const publicAgent = context.agent.active_role === "public_coordinator";
  const dialogue = request.trigger === "dialogue";
  const authorizedCommands = context.allowed_command_tools.filter(
    (n) => !dialogue || DIALOGUE_COMMANDS.has(n),
  );
  const domains = publicAgent
    ? ["public", "environment", "social", "memory"]
    : Object.keys(GAME_ENV.domains).filter((x) => x !== "public");
  const opened = new Set<string>();
  const basicCommands = [
    ...BASIC_COMMANDS,
    ...(dialogue && !publicAgent ? ["adopt_short_term_goal"] : []),
  ];
  const enabledCommands = new Set<string>(basicCommands);
  let reads = 0,
    readRounds = 0,
    compactions = 0,
    corrections = 0;
  const relationship = new RelationshipDialogue();
  const relationshipQuestion =
    dialogue && asksRelationshipState(request.dialogue_input ?? "");
  const actionLimit = publicAgent
    ? 1
    : request.trigger === "dialogue"
      ? config.max_dialogue_actions
      : config.max_actions;
  if (!dialogue && request.dialogue_followups?.length)
    emit({
      type: "loop",
      payload: {
        event: "dialogue.handoff_review",
        loop_id: request.request_id,
        source_event_ids: request.dialogue_followups.map((e) => e.event_id),
        goal_ids: (request.goal_refs ?? []).map((g) => g.goal_id),
      },
    });
  const budget = new LoopBudget(config, actionLimit);
  let { header, messages } = buildContext(
    request,
    context,
    services,
    config,
    domains,
    actionLimit,
  );
  while (true) {
    signal?.throwIfAborted();
    budget.nextRound();
    const canRead =
      reads < config.max_read_calls && readRounds < config.max_read_rounds;
    const queryDomains = [...opened].filter((d) => QUERY_CATALOG[d]);
    const readNames = canRead
      ? [
          "discover_tools",
          "inspect_self_resources",
          "recall_memory",
          ...(queryDomains.length ? ["query_world"] : []),
          ...(queryDomains.includes("map") ? ["query_map"] : []),
          ...(opened.has("memory")
            ? ["inspect_event", "inspect_history_segment"]
            : []),
        ]
      : [];
    const available = authorizedCommands.filter(
      (n) => !BASIC_COMMANDS.includes(n) && opened.has(commandDomain(n)),
    );
    const commands =
      budget.remainingActions > 0
        ? authorizedCommands.filter((n) => enabledCommands.has(n))
        : [];
    const tools = buildTools(
      readNames,
      queryDomains,
      domains,
      available,
      commands,
    );
    header.turn.budget = {
      remaining_read_rounds: Math.max(0, config.max_read_rounds - readRounds),
      remaining_read_calls: canRead ? config.max_read_calls - reads : 0,
      max_read_calls_per_round: canRead
        ? Math.min(4, config.max_read_calls - reads)
        : 0,
      max_actions: budget.remainingActions,
    };
    header.turn.query_catalog = Object.fromEntries(
      [...opened]
        .filter((d) => QUERY_CATALOG[d])
        .map((d) => [d, QUERY_CATALOG[d]]),
    );
    messages[1] = { role: "user", content: JSON.stringify(header) };
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
          compactions < config.max_compactions))
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
        compactions++;
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
            count: compactions,
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
          compactions,
          reason:
            protectedInput > config.max_input_tokens
              ? "protected_header_and_tools"
              : "working_context",
        },
      });
      throw new Error("context_capacity_exceeded");
    }
    emit({
      type: "loop",
      payload: {
        event: "loop.round",
        loop_id: request.request_id,
        read_rounds: readRounds,
        reads,
        compactions,
        input_estimate: inputEstimate({ messages, tools }),
      },
    });
    const assembler = await round(
      messages,
      tools,
      request.trigger === "dialogue" || corrections > 0,
    );
    const raw = assembler.rawOutput();
    try {
      if (raw.finish_reason === "length")
        throw new Error("provider_output_truncated");
      const calls = assembler.toolCalls(Math.max(4, actionLimit));
      const unavailable = calls.filter(
        (c) => !readNames.includes(c.name) && !commands.includes(c.name),
      );
      if (unavailable.length) {
        if (
          unavailable.some(
            (c) =>
              !context.allowed_command_tools.includes(c.name) &&
              ![
                "discover_tools",
                "inspect_self_resources",
                "recall_memory",
                "query_world",
                "query_map",
                "inspect_event",
                "inspect_history_segment",
              ].includes(c.name),
          )
        )
          throw new Error("provider_unauthorized_tool");
        if (
          unavailable.some(
            (c) =>
              context.allowed_command_tools.includes(c.name) &&
              !authorizedCommands.includes(c.name),
          )
        )
          throw new Error(
            "dialogue_action_not_allowed: answer the player's message; autonomous farming, trading and exploration belong to a background loop",
          );
        if (
          unavailable.some((c) =>
            context.allowed_command_tools.includes(c.name),
          )
        )
          throw new Error(
            "action_tool_not_enabled: use discover_tools to discover its domain and select the exact action name before calling it",
          );
        throw new Error(
          canRead
            ? "read_tool_not_discovered: open its domain using discover_tools first"
            : "read_budget_exhausted: finish with an enabled action or a reply; no more reads are available",
        );
      }
      if (calls.some((c) => readNames.includes(c.name))) {
        if (calls.some((c) => !readNames.includes(c.name)))
          throw new Error("mixed_read_action_batch");
        if (reads + calls.length > config.max_read_calls)
          throw new Error("read_budget_exceeded");
        // Validate all calls before any read or catalog mutation.
        if (
          calls.some(
            (c) =>
              !validLoopRead(
                c.name,
                c.arguments,
                ["query_world", "query_map"].includes(c.name)
                  ? queryDomains
                  : domains,
              ),
          )
        )
          throw new Error("invalid_read_arguments");
        messages.push({
          role: "assistant",
          content: raw.message.content || null,
          tool_calls: raw.message.tool_calls,
        });
        readRounds++;
        for (const call of calls) {
          reads++;
          let result: Record<string, unknown>;
          if (call.name === "discover_tools") {
            result = discoverTools(
              call.arguments,
              opened,
              enabledCommands,
              authorizedCommands,
              basicCommands,
              BASIC_COMMANDS,
            );
          } else
            try {
              result = await services.read(
                call.name === "query_map" ? "query_world" : call.name,
                call.name === "query_map"
                  ? { ...call.arguments, domain: "map", section: "regions" }
                  : call.arguments,
                signal,
              );
            } catch (error) {
              signal?.throwIfAborted();
              result = {
                ok: false,
                error: error instanceof Error ? error.message : "read_failed",
                instruction:
                  "Inspect the error and choose a corrected query or finish.",
              };
            }
          relationship.observe(call.name, call.arguments, result);
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
          if (result.resources) {
            header.resources = obj(result.resources);
            messages[1] = { role: "user", content: JSON.stringify(header) };
          }
          messages.push({
            role: "tool",
            tool_call_id: call.id,
            name: call.name,
            content: JSON.stringify(result),
          });
        }
        continue;
      }
      const errors = calls.flatMap((c) =>
        toolArgumentErrors(c.name, c.arguments),
      );
      if (errors.length)
        throw new Error(`invalid_action_arguments:${errors.join("; ")}`);
      if (relationshipQuestion && !relationship.attempted)
        throw new Error(
          "relationship_state_required: discover_tools actors, then query_world(domain=actors, section=relationship, id=player) before answering. Memories and empty proposals are not live relationship state.",
        );
      const intent = assembler.finish(request, commands, actionLimit).intent;
      if (
        dialogue &&
        intent.actions.some(
          (a) => a.tool_name === "resolve_relationship_dialogue",
        )
      ) {
        if (!relationship.player)
          throw new Error(
            "relationship_state_required: query_world(domain=actors, section=relationship, id=player) must succeed before changing this relationship.",
          );
        if (relationship.player.status === "dating") {
          const redundant = intent.actions.filter(
            (a) =>
              a.tool_name === "resolve_relationship_dialogue" &&
              a.arguments.decision === "confirm",
          );
          if (redundant.length) {
            intent.actions = intent.actions.filter(
              (a) => !redundant.includes(a),
            );
            intent.speech =
              "我刚确认了，我们已经是恋人了。我会认真对待我们的关系。";
            intent.decision_summary =
              "Acknowledged existing relationship from current world state; no repeated confirmation";
            emit({
              type: "loop",
              payload: {
                event: "dialogue.relationship_already_confirmed",
                loop_id: request.request_id,
                relationship_version: relationship.player.version,
              },
            });
          }
        }
      }
      if (dialogue && !intent.speech?.trim()) {
        const action =
          intent.actions.length === 1 ? intent.actions[0] : undefined;
        const tradeReply = action
          ? pendingTradeReply(action.tool_name)
          : undefined;
        const fallback =
          tradeReply ??
          (action
            ? pendingRelationshipReply(action.tool_name, action.arguments)
            : undefined);
        if (!fallback)
          throw new Error(
            "dialogue_reply_required: provide a brief in-character spoken reply to the player's current message, even when submitting an interaction request",
          );
        intent.speech = fallback;
        emit({
          type: "loop",
          payload: {
            event: "dialogue.reply_fallback",
            loop_id: request.request_id,
            tool_name: intent.actions[0].tool_name,
            source: tradeReply
              ? "pending_trade_template"
              : "relationship_intent_template",
            speech: fallback,
          },
        });
      }
      return intent;
    } catch (error) {
      if (signal?.aborted) throw error;
      const message = error instanceof Error ? error.message : "loop_error";
      emit({
        type: "loop",
        payload: {
          event: "loop.validation_failed",
          loop_id: request.request_id,
          error: message,
          called_tools: raw.message.tool_calls.map((c) => c.function.name),
          enabled_tools: [...readNames, ...commands],
          remaining_read_calls: Math.max(0, config.max_read_calls - reads),
        },
      });
      if (message.includes("unauthorized") || corrections++ >= 1) throw error;
      messages.push({
        role: "system",
        content: `This rejected batch was not submitted. Earlier successful tool calls remain committed. Correct once or finish without action: ${message.slice(0, 900)}. Remaining reads: ${canRead ? config.max_read_calls - reads : 0}; at most ${header.turn.budget.max_read_calls_per_round} in one round. Current action menu: ${commands.join(", ")}.`,
      });
    }
  }
}
