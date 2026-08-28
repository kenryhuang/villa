import type { AgentContext, AgentDefinition } from "./agents.ts";
import type { ProviderConfig } from "./config.ts";
import type { MemoryEvent } from "./memory.ts";
import type { ActionIntent, DecisionRequest } from "./protocol.ts";
import {
  AgentStreamAssembler,
  decodeProviderSse,
  type ProviderTraceEvent,
} from "./provider_stream.ts";
import {toolDescription} from "./tool_contracts.ts";

export class OpenAICompatibleProvider {
  readonly #config: ProviderConfig;

  constructor(config: ProviderConfig) {
    this.#config = config;
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
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#config.timeoutMs);
    const abortFromCaller = () => controller.abort(externalSignal?.reason);
    if (externalSignal?.aborted) abortFromCaller();
    else externalSignal?.addEventListener("abort", abortFromCaller, {once: true});
    try {
      const endpoint = this.#config.baseUrl.endsWith("/chat/completions")
        ? this.#config.baseUrl : `${this.#config.baseUrl}/chat/completions`;
      const isDialogue = request.trigger === "dialogue";
      const providerContext = isDialogue
        ? {...context, allowed_tools: []}
        : context;
      const systemContent = isDialogue
        ? "You are a game NPC Agent speaking directly with the player. Reply immediately in character using the Agent soul and speech style. Answer the player's dialogue input in one to three concise sentences. Do not call tools or plan world actions. Never invent world assets."
        : "You are a game NPC Agent. Use zero to three authorized tools in the exact order they should execute. Use no tool when no action is needed. Put travel or build last. Never invent world assets.";
      const userContent = isDialogue
        ? {context: providerContext, dialogue_input: request.dialogue_input ?? ""}
        : providerContext;
      const providerBody: Record<string, unknown> = {
        model: this.#config.model,
        temperature: this.#config.temperature,
        max_tokens: this.#config.maxOutputTokens,
        stream: true,
        stream_options: {include_usage: true},
        messages: [
          {role: "system", content: systemContent},
          {role: "user", content: JSON.stringify(userContent)},
        ],
      };
      if (!isDialogue) {
        providerBody.tool_choice = "auto";
        providerBody.tools = providerContext.allowed_tools.map(toolDescription);
      }
      emit({type: "input", body: structuredClone(providerBody)});
      const response = await fetch(endpoint, {
        method: "POST",
        signal: controller.signal,
        headers: {"content-type": "application/json", authorization: `Bearer ${this.#config.apiKey}`},
        body: JSON.stringify(providerBody),
      });
      if (!response.ok) throw new Error(`provider_http_${response.status}`);
      if (!response.body) throw new Error("provider_missing_stream_body");
      const assembler = new AgentStreamAssembler();
      for await (const chunk of decodeProviderSse(response.body)) {
        for (const event of assembler.accept(chunk)) emit(event);
      }
      const result = assembler.finish(request, providerContext.allowed_tools);
      emit({type: "output", output: result.rawOutput});
      return result.intent;
    } finally {
      clearTimeout(timeout);
      externalSignal?.removeEventListener("abort", abortFromCaller);
    }
  }

  async compactMemory(agent: AgentDefinition, events: MemoryEvent[]): Promise<{summary: string; importance: number}> {
    if (events.length === 0) throw new Error("memory_compaction_requires_events");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#config.timeoutMs);
    try {
      const endpoint = this.#config.baseUrl.endsWith("/chat/completions")
        ? this.#config.baseUrl : `${this.#config.baseUrl}/chat/completions`;
      const response = await fetch(endpoint, {
        method: "POST", signal: controller.signal,
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
      const payload = await response.json() as Record<string, unknown>;
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
    } finally {
      clearTimeout(timeout);
    }
  }
}
