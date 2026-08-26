import type { IncomingMessage, ServerResponse } from "node:http";
import type { AgentRegistry } from "./agents.ts";
import type { MemoryRepository } from "./memory.ts";
import { parseActionOutcome, parseDecisionRequest, type ActionIntent, type DecisionRequest } from "./protocol.ts";

interface ProviderPort { decide(request: DecisionRequest, context: ReturnType<AgentRegistry["buildContext"]>): Promise<ActionIntent>; }
interface AppDependencies { memory: MemoryRepository; registry: AgentRegistry; provider: ProviderPort; checkpointRoot: string; }

const send = (response: ServerResponse, status: number, body: unknown): void => {
  response.statusCode = status;
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.end(JSON.stringify(body));
};

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
        send(response, 200, {status: "ok", protocol_version: 1, provider: "configured"}); return;
      }
      if (request.method !== "POST") { send(response, 404, {error: {code: "NOT_FOUND"}}); return; }
      const body = await readBody(request);
      if (url.pathname === "/v1/sessions/sync") {
        const record = body as Record<string, unknown>;
        if (!record || typeof record.session_id !== "string" || !Number.isSafeInteger(record.session_epoch)) throw new Error("invalid_session");
        dependencies.memory.syncSession(record.session_id, Number(record.session_epoch));
        send(response, 200, {status: "synced"}); return;
      }
      const decisionMatch = url.pathname.match(/^\/v1\/agents\/([^/]+)\/decide$/);
      if (decisionMatch) {
        const parsed = parseDecisionRequest(body);
        if (!parsed.ok) throw new Error(parsed.error);
        if (parsed.value.agent_id !== decisionMatch[1]) { send(response, 409, {error: {code: "AGENT_MISMATCH"}}); return; }
        const cached = dependencies.memory.getIdempotent(`decision:${parsed.value.request_id}`);
        if (cached) { send(response, 200, cached); return; }
        const memories = dependencies.memory.recent(parsed.value.session_id, parsed.value.agent_id, 12);
        const context = dependencies.registry.buildContext(parsed.value.agent_id, parsed.value.snapshot, parsed.value.event_delta, memories);
        const intent = await dependencies.provider.decide(parsed.value, context);
        dependencies.memory.storeIdempotent(`decision:${parsed.value.request_id}`, intent);
        dependencies.memory.appendEvent(parsed.value.session_id, parsed.value.agent_id, {
          event_id: `decision:${intent.decision_id}`, kind: "decision", game_minute: parsed.value.game_minute,
          payload: {tool_name: intent.tool_name, decision_summary: intent.decision_summary},
        });
        send(response, 200, intent); return;
      }
      const outcomeMatch = url.pathname.match(/^\/v1\/agents\/([^/]+)\/outcomes$/);
      if (outcomeMatch) {
        const parsed = parseActionOutcome(body);
        if (!parsed.ok) throw new Error(parsed.error);
        const key = `outcome:${parsed.value.idempotency_key}`;
        if (dependencies.memory.getIdempotent(key)) { send(response, 200, {status: "duplicate"}); return; }
        dependencies.memory.storeIdempotent(key, parsed.value);
        const sessionId = String(request.headers["x-session-id"] || "");
        if (!sessionId) throw new Error("missing_session_id");
        dependencies.memory.appendEvent(sessionId, outcomeMatch[1], {
          event_id: key, kind: parsed.value.status === "completed" ? "action_completed" : "action_result",
          game_minute: parsed.value.game_minute,
          payload: {status: parsed.value.status, resource_delta: parsed.value.resource_delta, changed_entities: parsed.value.changed_entities},
        });
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
        dependencies.memory.importCheckpoint(record.path, record.sha256, record.session_id);
        send(response, 200, {status: "imported"}); return;
      }
      send(response, 404, {error: {code: "NOT_FOUND"}});
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown_error";
      send(response, message === "payload_too_large" ? 413 : 400, {error: {code: message}});
    }
  };
}
