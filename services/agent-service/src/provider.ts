import type { AgentContext, AgentDefinition } from "./agents.ts";
import type { ProviderConfig } from "./config.ts";
import type { MemoryEvent } from "./memory.ts";
import { parseActionIntent, type ActionIntent, type DecisionRequest } from "./protocol.ts";

const toolDescription = (name: string) => ({
  type: "function",
  function: {
    name,
    description: `Role-authorized ${name} command. Return only arguments grounded in the supplied snapshot.`,
    parameters: {type: "object", additionalProperties: true},
  },
});

export class OpenAICompatibleProvider {
  readonly #config: ProviderConfig;

  constructor(config: ProviderConfig) {
    this.#config = config;
  }

  async decide(request: DecisionRequest, context: AgentContext): Promise<ActionIntent> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#config.timeoutMs);
    try {
      const endpoint = this.#config.baseUrl.endsWith("/chat/completions")
        ? this.#config.baseUrl : `${this.#config.baseUrl}/chat/completions`;
      const response = await fetch(endpoint, {
        method: "POST",
        signal: controller.signal,
        headers: {"content-type": "application/json", authorization: `Bearer ${this.#config.apiKey}`},
        body: JSON.stringify({
          model: this.#config.model,
          temperature: this.#config.temperature,
          max_tokens: this.#config.maxOutputTokens,
          tool_choice: "auto",
          tools: context.allowed_tools.map(toolDescription),
          messages: [
            {role: "system", content: "You are a game NPC Agent. Use exactly one authorized tool. Never invent world assets."},
            {role: "user", content: JSON.stringify(context)},
          ],
        }),
      });
      if (!response.ok) throw new Error(`provider_http_${response.status}`);
      const payload = await response.json() as Record<string, unknown>;
      const choice = (payload.choices as Array<Record<string, unknown>> | undefined)?.[0];
      const message = choice?.message as Record<string, unknown> | undefined;
      const calls = message?.tool_calls as Array<Record<string, unknown>> | undefined;
      if (!calls || calls.length !== 1) throw new Error("provider_requires_exactly_one_tool_call");
      const call = calls[0];
      const fn = call?.function as Record<string, unknown> | undefined;
      if (!fn || typeof fn.name !== "string" || typeof fn.arguments !== "string") throw new Error("provider_missing_tool_call");
      let args: unknown;
      try { args = JSON.parse(fn.arguments); } catch { throw new Error("provider_invalid_tool_arguments"); }
      const intent: unknown = {
        protocol_version: 1,
        decision_id: typeof payload.id === "string" && payload.id ? payload.id : `${request.request_id}:decision`,
        request_id: request.request_id,
        agent_id: request.agent_id,
        expected_revision: request.world_revision,
        idempotency_key: `${request.request_id}:${String(call?.id || fn.name)}`,
        tool_name: fn.name,
        tool_version: 1,
        arguments: args,
        speech: typeof message?.content === "string" ? message.content : undefined,
        decision_summary: `Selected ${fn.name} from current context`,
      };
      const parsed = parseActionIntent(intent, context.allowed_tools);
      if (!parsed.ok) throw new Error(`provider_invalid_intent:${parsed.error}`);
      return parsed.value;
    } finally {
      clearTimeout(timeout);
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
