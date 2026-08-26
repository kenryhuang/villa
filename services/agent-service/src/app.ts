import type { IncomingMessage, ServerResponse } from "node:http";
import { isAbsolute, relative, resolve } from "node:path";
import type { AgentRegistry } from "./agents.ts";
import type { MemoryRepository } from "./memory.ts";
import { PROTOCOL_VERSION, parseActionOutcome, parseDecisionRequest, type ActionIntent, type DecisionRequest } from "./protocol.ts";
import type {ProviderTraceEvent} from "./provider_stream.ts";

interface ProviderPort {
  decide(request: DecisionRequest, context: ReturnType<AgentRegistry["buildContext"]>): Promise<ActionIntent>;
  streamDecision?(
    request: DecisionRequest,
    context: ReturnType<AgentRegistry["buildContext"]>,
    emit: (event: ProviderTraceEvent) => void,
    signal?: AbortSignal,
  ): Promise<ActionIntent>;
  compactMemory?(agent: NonNullable<ReturnType<AgentRegistry["get"]>>, events: ReturnType<MemoryRepository["recent"]>): Promise<{summary: string; importance: number}>;
}
interface AppDependencies { memory: MemoryRepository; registry: AgentRegistry; provider: ProviderPort; checkpointRoot: string; }

async function compactMemoryIfDue(dependencies: AppDependencies, sessionId: string, agentId: string): Promise<void> {
  if (!dependencies.provider.compactMemory || !dependencies.memory.shouldCompact(sessionId, agentId)) return;
  const agent = dependencies.registry.get(agentId);
  const events = dependencies.memory.compactionCandidates(sessionId, agentId, 20);
  if (!agent || events.length < 20) return;
  try {
    const compacted = await dependencies.provider.compactMemory(agent, events);
    dependencies.memory.storeLongTermMemory(
      sessionId, agentId, `memory:${sessionId}:${agentId}:${events[0].event_id}:${events.at(-1)?.event_id}`,
      compacted.summary, compacted.importance, events.map((event) => event.event_id),
    );
  } catch {
    // Raw events remain uncompacted and eligible for a later retry.
  }
}

const send = (response: ServerResponse, status: number, body: unknown): void => {
  response.statusCode = status;
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.end(JSON.stringify(body));
};

function decisionContext(dependencies: AppDependencies, request: DecisionRequest) {
  const memories = [
    ...dependencies.memory.longTermRecent(request.session_id, request.agent_id, 8),
    ...dependencies.memory.recent(request.session_id, request.agent_id, 8),
  ];
  return dependencies.registry.buildContext(request.agent_id, request.snapshot, request.event_delta, memories);
}

function storeDecision(
  dependencies: AppDependencies,
  request: DecisionRequest,
  decisionKey: string,
  intent: ActionIntent,
): void {
  dependencies.memory.storeIdempotent(decisionKey, intent);
  dependencies.memory.appendEvent(request.session_id, request.agent_id, {
    event_id: `decision:${intent.decision_id}`,
    kind: "decision",
    game_minute: request.game_minute,
    payload: {
      action_names: intent.actions.map((action) => action.tool_name),
      decision_summary: intent.decision_summary,
    },
  });
}

function beginSse(response: ServerResponse): void {
  response.statusCode = 200;
  response.setHeader("content-type", "text/event-stream; charset=utf-8");
  response.setHeader("cache-control", "no-cache, no-transform");
  response.setHeader("connection", "keep-alive");
  response.setHeader("x-accel-buffering", "no");
  response.flushHeaders();
}

async function readBody(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > 65_536) throw new Error("payload_too_large");
    chunks.push(buffer);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { throw new Error("invalid_json"); }
}

export function createApp(dependencies: AppDependencies) {
  return async (request: IncomingMessage, response: ServerResponse): Promise<void> => {
    try {
      const url = new URL(request.url || "/", "http://localhost");
      if (request.method === "GET" && url.pathname === "/health") {
        send(response, 200, {status: "ok", protocol_version: PROTOCOL_VERSION, provider: "configured"}); return;
      }
      if (request.method !== "POST") { send(response, 404, {error: {code: "NOT_FOUND"}}); return; }
      const body = await readBody(request);
      if (url.pathname === "/v1/sessions/sync") {
        const record = body as Record<string, unknown>;
        if (!record || typeof record.session_id !== "string" || !Number.isSafeInteger(record.session_epoch)) throw new Error("invalid_session");
        if (record.reset === true) dependencies.memory.resetSession(record.session_id, Number(record.session_epoch));
        else dependencies.memory.syncSession(record.session_id, Number(record.session_epoch));
        send(response, 200, {status: "synced"}); return;
      }
      const streamMatch = url.pathname.match(/^\/v1\/agents\/([^/]+)\/decide\/stream$/);
      if (streamMatch) {
        const parsed = parseDecisionRequest(body);
        if (!parsed.ok) throw new Error(parsed.error);
        const decisionRequest = parsed.value;
        if (decisionRequest.agent_id !== streamMatch[1]) {
          send(response, 409, {error: {code: "AGENT_MISMATCH"}}); return;
        }
        const decisionKey = `decision:${decisionRequest.session_id}:${decisionRequest.request_id}`;
        const cached = dependencies.memory.getIdempotent(decisionKey) as ActionIntent | undefined;
        beginSse(response);
        let sequence = 0;
        const writeEvent = (name: string, payload: unknown): void => {
          if (response.destroyed || response.writableEnded) return;
          sequence += 1;
          const envelope = {
            protocol_version: PROTOCOL_VERSION,
            stream_id: `${decisionRequest.request_id}:stream`,
            request_id: decisionRequest.request_id,
            agent_id: decisionRequest.agent_id,
            sequence,
            timestamp_msec: Date.now(),
            payload,
          };
          response.write(`id: ${sequence}\nevent: ${name}\ndata: ${JSON.stringify(envelope)}\n\n`);
        };
        if (cached) {
          writeEvent("decision.final", cached);
          writeEvent("stream.completed", {status: "completed", cached: true});
          response.end();
          return;
        }
        writeEvent("stream.started", {trigger: decisionRequest.trigger});
        const controller = new AbortController();
        let finished = false;
        const cancel = () => { if (!finished) controller.abort(); };
        request.once("aborted", cancel);
        response.once("close", cancel);
        const heartbeat = setInterval(() => {
          if (!response.destroyed && !response.writableEnded) response.write(": heartbeat\n\n");
        }, 5_000);
        try {
          if (!dependencies.provider.streamDecision) throw new Error("provider_streaming_unavailable");
          const emit = (event: ProviderTraceEvent): void => {
            switch (event.type) {
              case "input": writeEvent("provider.input", event.body); break;
              case "reasoning": writeEvent("reasoning.delta", {delta: event.delta}); break;
              case "content": writeEvent("content.delta", {delta: event.delta}); break;
              case "tool_call": writeEvent("tool_call.delta", {
                index: event.index,
                ...(event.id !== undefined ? {id: event.id} : {}),
                ...(event.name !== undefined ? {name: event.name} : {}),
                ...(event.arguments !== undefined ? {arguments: event.arguments} : {}),
              }); break;
              case "output": writeEvent("provider.output", event.output); break;
            }
          };
          const intent = await dependencies.provider.streamDecision(
            decisionRequest,
            decisionContext(dependencies, decisionRequest),
            emit,
            controller.signal,
          );
          if (!controller.signal.aborted) {
            storeDecision(dependencies, decisionRequest, decisionKey, intent);
            writeEvent("decision.final", intent);
            writeEvent("stream.completed", {status: "completed", cached: false});
          }
        } catch (error) {
          if (!controller.signal.aborted) {
            const message = error instanceof Error ? error.message : "unknown_error";
            writeEvent("stream.error", {
              code: message,
              message,
              retryable: message.includes("timeout") || message.startsWith("provider_http_5"),
            });
          }
        } finally {
          finished = true;
          clearInterval(heartbeat);
          request.removeListener("aborted", cancel);
          response.removeListener("close", cancel);
          if (!response.destroyed && !response.writableEnded) response.end();
        }
        return;
      }
      const decisionMatch = url.pathname.match(/^\/v1\/agents\/([^/]+)\/decide$/);
      if (decisionMatch) {
        const parsed = parseDecisionRequest(body);
        if (!parsed.ok) throw new Error(parsed.error);
        if (parsed.value.agent_id !== decisionMatch[1]) { send(response, 409, {error: {code: "AGENT_MISMATCH"}}); return; }
        const decisionKey = `decision:${parsed.value.session_id}:${parsed.value.request_id}`;
        const cached = dependencies.memory.getIdempotent(decisionKey);
        if (cached) { send(response, 200, cached); return; }
        const context = decisionContext(dependencies, parsed.value);
        const intent = await dependencies.provider.decide(parsed.value, context);
        storeDecision(dependencies, parsed.value, decisionKey, intent);
        send(response, 200, intent); return;
      }
      const outcomeMatch = url.pathname.match(/^\/v1\/agents\/([^/]+)\/outcomes$/);
      if (outcomeMatch) {
        const parsed = parseActionOutcome(body);
        if (!parsed.ok) throw new Error(parsed.error);
        const sessionId = String(request.headers["x-session-id"] || "");
        if (!sessionId) throw new Error("missing_session_id");
        const key = `outcome:${sessionId}:${parsed.value.idempotency_key}`;
        if (dependencies.memory.getIdempotent(key)) { send(response, 200, {status: "duplicate"}); return; }
        dependencies.memory.storeIdempotent(key, parsed.value);
        dependencies.memory.appendEvent(sessionId, outcomeMatch[1], {
          event_id: key, kind: parsed.value.status === "completed" ? "action_completed" : "action_result",
          game_minute: parsed.value.game_minute,
          payload: {status: parsed.value.status, resource_delta: parsed.value.resource_delta, changed_entities: parsed.value.changed_entities},
        });
        await compactMemoryIfDue(dependencies, sessionId, outcomeMatch[1]);
        send(response, 202, {status: "accepted"}); return;
      }
      if (url.pathname === "/v1/checkpoints/export") {
        const record = body as Record<string, unknown>;
        if (typeof record?.session_id !== "string" || typeof record?.checkpoint_id !== "string") throw new Error("invalid_checkpoint_request");
        send(response, 200, dependencies.memory.exportCheckpoint(record.session_id, dependencies.checkpointRoot, record.checkpoint_id)); return;
      }
      if (url.pathname === "/v1/checkpoints/import") {
        const record = body as Record<string, unknown>;
        if (typeof record?.session_id !== "string" || typeof record?.path !== "string" || typeof record?.sha256 !== "string") throw new Error("invalid_checkpoint_request");
        const root = resolve(dependencies.checkpointRoot);
        const checkpointPath = resolve(record.path);
        const checkpointRelative = relative(root, checkpointPath);
        if (checkpointRelative.startsWith("..") || isAbsolute(checkpointRelative)) throw new Error("invalid_checkpoint_path");
        dependencies.memory.importCheckpoint(checkpointPath, record.sha256, record.session_id);
        send(response, 200, {status: "imported"}); return;
      }
      send(response, 404, {error: {code: "NOT_FOUND"}});
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown_error";
      send(response, message === "payload_too_large" ? 413 : 400, {error: {code: message}});
    }
  };
}
