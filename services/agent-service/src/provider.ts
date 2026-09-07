import type { AgentContext, AgentDefinition } from "./agents.ts";
import type { ProviderConfig } from "./config.ts";
import type { MemoryEvent } from "./memory.ts";
import type { ActionIntent, DecisionRequest } from "./protocol.ts";
import {ProviderConcurrencyGate} from "./provider_concurrency_gate.ts";
import {
  AgentStreamAssembler,
  decodeProviderSse,
  type ProviderTraceEvent,
} from "./provider_stream.ts";
import {executeReadTool, readToolDescription, toolDescription} from "./tool_contracts.ts";

const DIALOGUE_COMMANDS = new Set([
  "send_message", "propose_trade", "counter_trade", "accept_trade", "reject_trade",
  "cancel_trade", "propose_cooperation", "counter_cooperation", "accept_cooperation",
  "reject_cooperation", "commit_contribution", "cancel_cooperation", "speak", "rent_production", "submit_project", "retry_project", "cancel_project", "publish_commission", "propose_player_commission", "claim_commission", "deliver_commission", "suggest_behavior",
]);

async function withProviderTimeout<T>(
  timeoutMs: number,
  externalSignal: AbortSignal | undefined,
  operation: (signal: AbortSignal) => Promise<T>,
): Promise<T> {
  const controller = new AbortController();
  let abortSource: "timeout" | "external" | undefined;
  const timeout = setTimeout(() => {
    if (controller.signal.aborted) return;
    abortSource = "timeout";
    controller.abort();
  }, timeoutMs);
  const abortFromCaller = () => {
    if (controller.signal.aborted) return;
    abortSource = "external";
    controller.abort(externalSignal?.reason);
  };
  if (externalSignal?.aborted) abortFromCaller();
  else externalSignal?.addEventListener("abort", abortFromCaller, {once: true});
  try {
    return await operation(controller.signal);
  } catch (error) {
    if (abortSource === "timeout") throw new Error("provider_timeout");
    throw error;
  } finally {
    clearTimeout(timeout);
    externalSignal?.removeEventListener("abort", abortFromCaller);
  }
}

export class OpenAICompatibleProvider {
  readonly #config: ProviderConfig;
  readonly #concurrencyGate: ProviderConcurrencyGate;

  constructor(config: ProviderConfig) {
    this.#config = config;
    this.#concurrencyGate = new ProviderConcurrencyGate(config.maxConcurrency);
  }

  async decide(request: DecisionRequest, context: AgentContext): Promise<ActionIntent> {
    return this.streamDecision(request, context, () => {});
  }

  async streamDecision(
    request: DecisionRequest,
    context: AgentContext,
    emit: (event: ProviderTraceEvent) => void,
    externalSignal?: AbortSignal,
  ): Promise<ActionIntent> {
    const endpoint = this.#config.baseUrl.endsWith("/chat/completions")
      ? this.#config.baseUrl : `${this.#config.baseUrl}/chat/completions`;
    const isDialogue = request.trigger === "dialogue";
    const allowedCommands = isDialogue
      ? context.allowed_command_tools.filter((name) => DIALOGUE_COMMANDS.has(name))
      : [...context.allowed_command_tools];
    const systemContent = isDialogue
      ? "You are a game NPC Agent speaking directly with the player. Reply in character in one to three concise sentences. You may use local read tools, then optionally issue at most one authorized interaction command. Never perform farming, travel, harvesting, or market speculation during dialogue. A rental command is a request to queue production: while dialogue pauses the world, Godot defers and revalidates it after resume. Never describe a proposal, queued request, or processing order as completed goods. If you promise a trade or rental, issue the corresponding authorized command in this response; otherwise clearly say no operation was submitted. Never invent world assets."
      : "You are a game NPC Agent. You may use local read tools to inspect only the supplied context, then use zero to three authorized command tools in execution order. For farm3d, inspect actor_context.living_world and prefer submit_project for multi-step goals that you choose yourself. Choose milestones and budgets from resources and opportunities; decline uneconomic plans. Existing accepted projects execute without more model calls. Use no command when no action is needed. Put travel or build last. Never invent world assets.";
    const {market_view: _marketView, ...promptContext} = context;
    const userContent = isDialogue
      ? {context: promptContext, dialogue_input: request.dialogue_input ?? ""}
      : promptContext;
    const messages: Record<string, unknown>[] = [
      {role: "system", content: systemContent},
      {role: "user", content: JSON.stringify(userContent)},
    ];
    let readRounds = 0;
    while (true) {
      const availableReads = readRounds < 2 ? [...context.allowed_read_tools] : [];
      const providerBody: Record<string, unknown> = {
        model: this.#config.model,
        ...(isDialogue ? {enable_thinking: false} : {}),
        temperature: this.#config.temperature,
        max_tokens: this.#config.maxOutputTokens,
        stream: true,
        stream_options: {include_usage: true},
        messages: structuredClone(messages),
        tool_choice: "auto",
        tools: [
          ...availableReads.map(readToolDescription),
          ...allowedCommands.map(toolDescription),
        ],
      };
      if ((providerBody.tools as unknown[]).length === 0) {
        delete providerBody.tool_choice;
        delete providerBody.tools;
      }
      emit({type: "input", body: structuredClone(providerBody)});
      const {assembler, rawOutput} = await this.#concurrencyGate.run(
        externalSignal,
        () => withProviderTimeout(
          this.#config.timeoutMs,
          externalSignal,
          async (signal) => {
            const response = await fetch(endpoint, {
              method: "POST",
              signal,
              headers: {"content-type": "application/json", authorization: `Bearer ${this.#config.apiKey}`},
              body: JSON.stringify(providerBody),
            });
            if (!response.ok) throw new Error(`provider_http_${response.status}`);
            if (!response.body) throw new Error("provider_missing_stream_body");
            const roundAssembler = new AgentStreamAssembler();
            for await (const chunk of decodeProviderSse(response.body)) {
              for (const event of roundAssembler.accept(chunk)) emit(event);
            }
            return {assembler: roundAssembler, rawOutput: roundAssembler.rawOutput()};
          },
        ),
      );
      emit({type: "output", output: rawOutput});
      const calls = assembler.toolCalls();
      const reads = calls.filter((call) => availableReads.includes(call.name));
      if (reads.length > 0) {
        if (reads.length !== calls.length) throw new Error("provider_mixed_read_and_command_tools");
        readRounds += 1;
        messages.push({role: "assistant", content: rawOutput.message.content || null, tool_calls: rawOutput.message.tool_calls});
        for (const call of reads) {
          messages.push({
            role: "tool",
            tool_call_id: call.id,
            name: call.name,
            content: JSON.stringify(executeReadTool(context, call.name, call.arguments)),
          });
        }
        continue;
      }
      return assembler.finish(request, allowedCommands, isDialogue ? 1 : 3).intent;
    }
  }

  async compactMemory(agent: AgentDefinition, events: MemoryEvent[]): Promise<{summary: string; importance: number}> {
    if (events.length === 0) throw new Error("memory_compaction_requires_events");
    const payload = await this.#concurrencyGate.run(
      undefined,
      () => withProviderTimeout(
        this.#config.timeoutMs,
        undefined,
        async (signal) => {
          const endpoint = this.#config.baseUrl.endsWith("/chat/completions")
            ? this.#config.baseUrl : `${this.#config.baseUrl}/chat/completions`;
          const response = await fetch(endpoint, {
            method: "POST", signal,
            headers: {"content-type": "application/json", authorization: `Bearer ${this.#config.apiKey}`},
            body: JSON.stringify({
              model: this.#config.model, temperature: Math.min(0.3, this.#config.temperature),
              max_tokens: Math.min(600, this.#config.maxOutputTokens), response_format: {type: "json_object"},
              messages: [
                {role: "system", content: "Compress verified NPC events into one factual long-term memory. Return JSON with summary and importance (1-10). Do not invent facts."},
                {role: "user", content: JSON.stringify({agent: {id: agent.agent_id, soul: agent.soul, goals: agent.goals}, events})},
              ],
            }),
          });
          if (!response.ok) throw new Error(`provider_http_${response.status}`);
          return await response.json() as Record<string, unknown>;
        },
      ),
    );
    const choice = (payload.choices as Array<Record<string, unknown>> | undefined)?.[0];
    const message = choice?.message as Record<string, unknown> | undefined;
    if (typeof message?.content !== "string") throw new Error("provider_missing_memory_content");
    let value: unknown;
    try { value = JSON.parse(message.content); } catch { throw new Error("provider_invalid_memory_json"); }
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("provider_invalid_memory");
    const record = value as Record<string, unknown>;
    if (typeof record.summary !== "string" || !record.summary.trim() || record.summary.length > 1200) throw new Error("provider_invalid_memory_summary");
    if (!Number.isSafeInteger(record.importance) || Number(record.importance) < 1 || Number(record.importance) > 10) throw new Error("provider_invalid_memory_importance");
    return {summary: record.summary.trim(), importance: Number(record.importance)};
  }
}
