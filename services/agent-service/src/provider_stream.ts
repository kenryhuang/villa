import {parseActionIntent, type ActionIntent, type DecisionRequest} from "./protocol.ts";
import {validToolArguments} from "./tool_contracts.ts";

export type ProviderDelta =
  | {type: "reasoning"; delta: string}
  | {type: "content"; delta: string}
  | {type: "tool_call"; index: number; id?: string; name?: string; arguments?: string};

export type ProviderTraceEvent =
  | {type: "input"; body: Record<string, unknown>}
  | ProviderDelta
  | {type: "output"; output: ProviderRawOutput};

export interface ProviderRawMessage {
  content: string;
  reasoning_content: string;
  tool_calls: Array<{
    id: string;
    type: "function";
    function: {name: string; arguments: string};
  }>;
}

export interface ProviderRawOutput {
  id: string;
  message: ProviderRawMessage;
  finish_reason: string | null;
  usage?: Record<string, unknown>;
}

export interface ProviderStreamResult {
  intent: ActionIntent;
  rawMessage: ProviderRawMessage;
  finishReason: string | null;
  usage?: Record<string, unknown>;
  rawOutput: ProviderRawOutput;
}

type JsonRecord = Record<string, unknown>;

const isRecord = (value: unknown): value is JsonRecord =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function providerContentText(value: unknown): string {
  if (typeof value === "string") return value;
  if (!Array.isArray(value)) throw new Error("provider_stream_invalid_content");
  return value.map((part) => {
    if (typeof part === "string") return part;
    if (isRecord(part) && typeof part.text === "string") return part.text;
    throw new Error("provider_stream_invalid_content");
  }).join("");
}

function parseSseRecord(record: string): Record<string, unknown> | undefined | "done" {
  const data: string[] = [];
  for (const line of record.split(/\r?\n/)) {
    if (!line || line.startsWith(":")) continue;
    if (line === "data") data.push("");
    else if (line.startsWith("data:")) data.push(line.slice(5).replace(/^ /, ""));
  }
  if (data.length === 0) return undefined;
  const source = data.join("\n");
  if (source.trim() === "[DONE]") return "done";
  let parsed: unknown;
  try { parsed = JSON.parse(source); }
  catch { throw new Error("provider_stream_invalid_json"); }
  if (!isRecord(parsed)) throw new Error("provider_stream_invalid_chunk");
  return parsed;
}

function nextRecord(buffer: string): {record: string; rest: string} | undefined {
  const match = /\r?\n\r?\n/.exec(buffer);
  if (!match || match.index === undefined) return undefined;
  return {
    record: buffer.slice(0, match.index),
    rest: buffer.slice(match.index + match[0].length),
  };
}

export async function* decodeProviderSse(
  body: ReadableStream<Uint8Array>,
): AsyncGenerator<Record<string, unknown>> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let done = false;
  while (!done) {
    const next = await reader.read();
    done = next.done;
    buffer += decoder.decode(next.value, {stream: !done});
    let framed = nextRecord(buffer);
    while (framed) {
      buffer = framed.rest;
      const parsed = parseSseRecord(framed.record);
      if (parsed === "done") return;
      if (parsed) yield parsed;
      framed = nextRecord(buffer);
    }
  }
  if (buffer.trim()) {
    const parsed = parseSseRecord(buffer);
    if (parsed && parsed !== "done") yield parsed;
  }
}

interface ToolAccumulator {id: string; name: string; arguments: string;}
export interface ParsedProviderToolCall {index: number; id: string; name: string; arguments: Record<string, unknown>;}

export class AgentStreamAssembler {
  #responseId = "";
  #reasoning = "";
  #content = "";
  #tools = new Map<number, ToolAccumulator>();
  #finishReason: string | null = null;
  #usage?: Record<string, unknown>;

  accept(chunk: Record<string, unknown>): readonly ProviderDelta[] {
    if (typeof chunk.id === "string" && chunk.id) this.#responseId ||= chunk.id;
    if (isRecord(chunk.usage)) this.#usage = {...chunk.usage};
    const choices = chunk.choices;
    if (choices === undefined) return [];
    if (!Array.isArray(choices) || choices.length > 1) throw new Error("provider_stream_invalid_choices");
    if (choices.length === 0) return [];
    const choice = choices[0];
    if (!isRecord(choice)) throw new Error("provider_stream_invalid_choice");
    if (choice.finish_reason !== undefined && choice.finish_reason !== null) {
      if (typeof choice.finish_reason !== "string") throw new Error("provider_stream_invalid_finish_reason");
      this.#finishReason = choice.finish_reason;
    }
    const delta = choice.delta;
    if (!isRecord(delta)) throw new Error("provider_stream_invalid_delta");
    const emitted: ProviderDelta[] = [];
    if (delta.reasoning_content !== undefined && delta.reasoning_content !== null) {
      if (typeof delta.reasoning_content !== "string") throw new Error("provider_stream_invalid_reasoning");
      if (delta.reasoning_content) {
        this.#reasoning += delta.reasoning_content;
        emitted.push({type: "reasoning", delta: delta.reasoning_content});
      }
    }
    if (delta.content !== undefined && delta.content !== null) {
      const content = providerContentText(delta.content);
      if (content) {
        this.#content += content;
        emitted.push({type: "content", delta: content});
      }
    }
    if (delta.tool_calls !== undefined && delta.tool_calls !== null) {
      if (!Array.isArray(delta.tool_calls)) throw new Error("provider_stream_invalid_tool_calls");
      for (const value of delta.tool_calls) emitted.push(this.#acceptToolCall(value));
    }
    return emitted;
  }

  #acceptToolCall(value: unknown): ProviderDelta {
    if (!isRecord(value) || !Number.isSafeInteger(value.index) || Number(value.index) < 0) {
      throw new Error("provider_stream_invalid_tool_call");
    }
    const index = Number(value.index);
    const tool = this.#tools.get(index) || {id: "", name: "", arguments: ""};
    const event: ProviderDelta = {type: "tool_call", index};
    if (value.id !== undefined && value.id !== null) {
      if (typeof value.id !== "string") throw new Error("provider_stream_invalid_tool_id");
      tool.id += value.id;
      event.id = value.id;
    }
    if (value.function !== undefined && value.function !== null) {
      if (!isRecord(value.function)) throw new Error("provider_stream_invalid_tool_function");
      if (value.function.name !== undefined && value.function.name !== null) {
        if (typeof value.function.name !== "string") throw new Error("provider_stream_invalid_tool_name");
        tool.name += value.function.name;
        event.name = value.function.name;
      }
      if (value.function.arguments !== undefined && value.function.arguments !== null) {
        if (typeof value.function.arguments !== "string") throw new Error("provider_stream_invalid_tool_arguments");
        tool.arguments += value.function.arguments;
        event.arguments = value.function.arguments;
      }
    }
    this.#tools.set(index, tool);
    return event;
  }

  toolCalls(maximum = Number.MAX_SAFE_INTEGER): ParsedProviderToolCall[] {
    const tools = [...this.#tools.entries()].sort(([left], [right]) => left - right);
    if (tools.length > maximum) throw new Error(maximum === 3 ? "provider_too_many_tool_calls" : "provider_too_many_read_calls");
    return tools.map(([index, tool]) => {
      if (!tool.name || !tool.arguments) throw new Error("provider_incomplete_tool_call");
      let args: unknown;
      try { args = JSON.parse(tool.arguments); }
      catch { throw new Error("provider_invalid_tool_arguments"); }
      if (!isRecord(args)) throw new Error("provider_invalid_tool_arguments");
      return {index, id: tool.id, name: tool.name, arguments: args};
    });
  }

  rawMessage(): ProviderRawMessage {
    return {
      content: this.#content,
      reasoning_content: this.#reasoning,
      tool_calls: this.toolCalls().map((tool) => ({
        id: tool.id,
        type: "function" as const,
        function: {name: tool.name, arguments: JSON.stringify(tool.arguments)},
      })),
    };
  }

  rawOutput(): ProviderRawOutput {
    return {
      id: this.#responseId,
      message: this.rawMessage(),
      finish_reason: this.#finishReason,
      ...(this.#usage ? {usage: this.#usage} : {}),
    };
  }

  finish(request: DecisionRequest, allowedTools: readonly string[], maximumActions = 3): ProviderStreamResult {
    if (this.#tools.size > maximumActions) throw new Error("provider_too_many_tool_calls");
    const parsedTools = this.toolCalls(maximumActions);
    const actions = parsedTools.map((tool) => {
      if (!allowedTools.includes(tool.name)) throw new Error("provider_invalid_intent:unauthorized_tool");
      if (!validToolArguments(tool.name, tool.arguments)) {
        throw new Error("provider_invalid_intent:invalid_arguments");
      }
      const providerId = tool.id.trim();
      const actionId = providerId && providerId.length <= 80 ? providerId : `action-${tool.index}`;
      return {
        action_id: actionId,
        idempotency_key: `v2:${request.request_id}:${tool.index}:${actionId}`,
        tool_name: tool.name,
        tool_version: 1 as const,
        arguments: tool.arguments,
      };
    });
    if (actions.length > 1 && actions.some((action) => action.tool_name === "wait")) {
      throw new Error("provider_invalid_intent:wait_must_be_exclusive");
    }
    const rawMessage = this.rawMessage();
    const rawOutput = this.rawOutput();
    const speech = this.#content.trim() || (request.trigger === "dialogue"
      ? actions.filter((action) => action.tool_name === "speak" && action.arguments.target_actor_id === "player")
        .map((action) => String(action.arguments.text).trim()).join("\n")
      : "");
    const intentValue: unknown = {
      protocol_version: 2,
      decision_id: this.#responseId || `${request.request_id}:decision`,
      request_id: request.request_id,
      agent_id: request.agent_id,
      expected_revision: request.world_revision,
      actions,
      ...(speech ? {speech: speech.slice(0, 500)} : {}),
      decision_summary: actions.length === 0
        ? "Selected no action from current context"
        : `Selected ${actions.map((action) => action.tool_name).join(", ")} from current context`,
    };
    const parsed = parseActionIntent(intentValue, allowedTools);
    if (!parsed.ok) throw new Error(`provider_invalid_intent:${parsed.error}`);
    return {
      intent: parsed.value,
      rawMessage,
      finishReason: this.#finishReason,
      ...(this.#usage ? {usage: this.#usage} : {}),
      rawOutput,
    };
  }
}
