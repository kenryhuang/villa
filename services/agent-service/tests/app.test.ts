import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { AgentRegistry } from "../src/agents.ts";
import { createApp } from "../src/app.ts";
import { MemoryRepository } from "../src/memory.ts";
import type { ActionIntent, DecisionRequest } from "../src/protocol.ts";
import type {ProviderTraceEvent} from "../src/provider_stream.ts";

function parseProjectSse(source: string): Array<{name: string; data: Record<string, any>}> {
  return source.split(/\r?\n\r?\n/).flatMap((record) => {
    if (!record.trim() || record.startsWith(":")) return [];
    let name = "message";
    const data: string[] = [];
    for (const line of record.split(/\r?\n/)) {
      if (line.startsWith("event:")) name = line.slice(6).trim();
      if (line.startsWith("data:")) data.push(line.slice(5).trimStart());
    }
    return data.length ? [{name, data: JSON.parse(data.join("\n"))}] : [];
  });
}

test("serves health decision outcome and checkpoint routes", async () => {
  const directory = mkdtempSync(join(tmpdir(), "villa-agent-app-"));
  const memory = new MemoryRepository(join(directory, "memory.sqlite"));
  const provider = {decide: async (request: DecisionRequest): Promise<ActionIntent> => ({
    protocol_version: 1, decision_id: "d1", request_id: request.request_id, agent_id: request.agent_id,
    expected_revision: request.world_revision, idempotency_key: "d1:wait", tool_name: "wait", tool_version: 1,
    arguments: {}, decision_summary: "No urgent action",
  })};
  const server = createServer(createApp({memory, registry: AgentRegistry.loadDefault(), provider, checkpointRoot: directory}));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const base = `http://127.0.0.1:${address.port}`;
  const json = async (path: string, body?: unknown) => {
    const response = await fetch(base + path, body === undefined ? {} : {method: "POST", headers: {"content-type": "application/json", "x-session-id": "save-0"}, body: JSON.stringify(body)});
    return {status: response.status, body: await response.json() as Record<string, unknown>};
  };
  assert.equal((await json("/health")).status, 200);
  assert.equal((await json("/v1/sessions/sync", {session_id: "save-0", session_epoch: 1})).status, 200);
  const request = JSON.parse(readFileSync(join(process.cwd(), "../../shared/agent_protocol/v1/decision-request.json"), "utf8"));
  const decision = await json("/v1/agents/farmer_ahe/decide", request);
  assert.equal(decision.status, 200);
  assert.equal(decision.body.tool_name, "wait");
  const outcome = JSON.parse(readFileSync(join(process.cwd(), "../../shared/agent_protocol/v1/action-outcome.json"), "utf8"));
  assert.equal((await json("/v1/agents/farmer_ahe/outcomes", outcome)).status, 202);
  assert.equal((await json("/v1/agents/farmer_ahe/outcomes", outcome)).status, 200);
  const exported = await json("/v1/checkpoints/export", {session_id: "save-0", checkpoint_id: "slot-0"});
  assert.equal(exported.status, 200);
  assert.equal(typeof exported.body.sha256, "string");
  await new Promise<void>((resolve) => server.close(() => resolve()));
  memory.close(); rmSync(directory, {recursive: true, force: true});
});

test("scopes idempotency by session and rejects checkpoints outside its root", async () => {
  const directory = mkdtempSync(join(tmpdir(), "villa-agent-session-"));
  const outside = mkdtempSync(join(tmpdir(), "villa-agent-outside-"));
  const memory = new MemoryRepository(join(directory, "memory.sqlite"));
  let calls = 0;
  const provider = {decide: async (request: DecisionRequest): Promise<ActionIntent> => ({
    protocol_version: 1, decision_id: `d${++calls}`, request_id: request.request_id, agent_id: request.agent_id,
    expected_revision: request.world_revision, idempotency_key: `d${calls}:wait`, tool_name: "wait", tool_version: 1,
    arguments: {}, decision_summary: "No urgent action",
  })};
  const server = createServer(createApp({memory, registry: AgentRegistry.loadDefault(), provider, checkpointRoot: directory}));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const base = `http://127.0.0.1:${address.port}`;
  const post = async (path: string, body: unknown, sessionId: string) => {
    const response = await fetch(base + path, {method: "POST", headers: {"content-type": "application/json", "x-session-id": sessionId}, body: JSON.stringify(body)});
    return {status: response.status, body: await response.json() as Record<string, unknown>};
  };
  const fixture = JSON.parse(readFileSync(join(process.cwd(), "../../shared/agent_protocol/v1/decision-request.json"), "utf8")) as DecisionRequest;
  await post("/v1/agents/farmer_ahe/decide", {...fixture, session_id: "save-a"}, "save-a");
  await post("/v1/agents/farmer_ahe/decide", {...fixture, session_id: "save-b"}, "save-b");
  assert.equal(calls, 2);
  const escaped = await post("/v1/checkpoints/import", {session_id: "save-a", path: join(outside, "foreign.sqlite"), sha256: "0".repeat(64)}, "save-a");
  assert.equal(escaped.status, 400);
  assert.equal((escaped.body.error as Record<string, unknown>).code, "invalid_checkpoint_path");
  await new Promise<void>((resolve) => server.close(() => resolve()));
  memory.close(); rmSync(directory, {recursive: true, force: true}); rmSync(outside, {recursive: true, force: true});
});

test("streams stable Agent events and replays only a cached final decision", async () => {
  const directory = mkdtempSync(join(tmpdir(), "villa-agent-stream-route-"));
  const memory = new MemoryRepository(join(directory, "memory.sqlite"));
  let providerCalls = 0;
  const provider = {
    decide: async (request: DecisionRequest): Promise<ActionIntent> => makeWaitIntent(request),
    streamDecision: async (
      request: DecisionRequest,
      _context: unknown,
      emit: (event: ProviderTraceEvent) => void,
    ): Promise<ActionIntent> => {
      providerCalls += 1;
      emit({type: "input", body: {model: "test-model", messages: []}});
      emit({type: "reasoning", delta: "地块未开垦。"});
      emit({type: "content", delta: "我先整理土地。"});
      emit({type: "tool_call", index: 0, id: "call-1", name: "wait", arguments: "{}"});
      emit({type: "output", output: {
        id: "stream-decision-1",
        message: {content: "我先整理土地。", reasoning_content: "地块未开垦。", tool_calls: [{id: "call-1", type: "function", function: {name: "wait", arguments: "{}"}}]},
        finish_reason: "tool_calls",
      }});
      return makeWaitIntent(request);
    },
  };
  const server = createServer(createApp({memory, registry: AgentRegistry.loadDefault(), provider, checkpointRoot: directory}));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const base = `http://127.0.0.1:${address.port}`;
  const fixture = JSON.parse(readFileSync(join(process.cwd(), "../../shared/agent_protocol/v1/decision-request.json"), "utf8")) as DecisionRequest;
  const postStream = async () => {
    const response = await fetch(base + "/v1/agents/farmer_ahe/decide/stream", {
      method: "POST", headers: {"content-type": "application/json", accept: "text/event-stream"}, body: JSON.stringify(fixture),
    });
    return {response, events: parseProjectSse(await response.text())};
  };
  const first = await postStream();
  assert.equal(first.response.status, 200);
  assert.match(first.response.headers.get("content-type") || "", /^text\/event-stream/);
  assert.deepEqual(first.events.map((event) => event.name), [
    "stream.started", "provider.input", "reasoning.delta", "content.delta",
    "tool_call.delta", "provider.output", "decision.final", "stream.completed",
  ]);
  assert.deepEqual(first.events.map((event) => event.data.sequence), [1, 2, 3, 4, 5, 6, 7, 8]);
  assert.equal(first.events[6].data.payload.tool_name, "wait");
  const replay = await postStream();
  assert.deepEqual(replay.events.map((event) => event.name), ["decision.final", "stream.completed"]);
  assert.equal(providerCalls, 1);
  await new Promise<void>((resolve) => server.close(() => resolve()));
  memory.close(); rmSync(directory, {recursive: true, force: true});
});

test("emits stream.error without committing a failed decision", async () => {
  const directory = mkdtempSync(join(tmpdir(), "villa-agent-stream-error-"));
  const memory = new MemoryRepository(join(directory, "memory.sqlite"));
  const provider = {
    decide: async (request: DecisionRequest): Promise<ActionIntent> => makeWaitIntent(request),
    streamDecision: async (
      _request: DecisionRequest,
      _context: unknown,
      emit: (event: ProviderTraceEvent) => void,
    ): Promise<ActionIntent> => {
      emit({type: "input", body: {model: "test-model"}});
      throw new Error("provider_stream_broken");
    },
  };
  const server = createServer(createApp({memory, registry: AgentRegistry.loadDefault(), provider, checkpointRoot: directory}));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const fixture = JSON.parse(readFileSync(join(process.cwd(), "../../shared/agent_protocol/v1/decision-request.json"), "utf8")) as DecisionRequest;
  const response = await fetch(`http://127.0.0.1:${address.port}/v1/agents/farmer_ahe/decide/stream`, {
    method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(fixture),
  });
  const events = parseProjectSse(await response.text());
  assert.deepEqual(events.map((event) => event.name), ["stream.started", "provider.input", "stream.error"]);
  assert.equal(memory.getIdempotent(`decision:${fixture.session_id}:${fixture.request_id}`), undefined);
  await new Promise<void>((resolve) => server.close(() => resolve()));
  memory.close(); rmSync(directory, {recursive: true, force: true});
});

test("aborts the Provider when the streaming client disconnects", async () => {
  const directory = mkdtempSync(join(tmpdir(), "villa-agent-stream-abort-"));
  const memory = new MemoryRepository(join(directory, "memory.sqlite"));
  let releaseAbort!: () => void;
  const aborted = new Promise<void>((resolve) => { releaseAbort = resolve; });
  const provider = {
    decide: async (request: DecisionRequest): Promise<ActionIntent> => makeWaitIntent(request),
    streamDecision: async (
      _request: DecisionRequest,
      _context: unknown,
      emit: (event: ProviderTraceEvent) => void,
      signal?: AbortSignal,
    ): Promise<ActionIntent> => {
      emit({type: "input", body: {model: "test-model"}});
      await new Promise<void>((_resolve, reject) => signal?.addEventListener("abort", () => {
        releaseAbort();
        reject(new Error("cancelled"));
      }, {once: true}));
      throw new Error("unreachable");
    },
  };
  const server = createServer(createApp({memory, registry: AgentRegistry.loadDefault(), provider, checkpointRoot: directory}));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const fixture = JSON.parse(readFileSync(join(process.cwd(), "../../shared/agent_protocol/v1/decision-request.json"), "utf8")) as DecisionRequest;
  const controller = new AbortController();
  const response = await fetch(`http://127.0.0.1:${address.port}/v1/agents/farmer_ahe/decide/stream`, {
    method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(fixture), signal: controller.signal,
  });
  assert.ok(response.body);
  await response.body.getReader().read();
  controller.abort();
  await Promise.race([aborted, new Promise((_, reject) => setTimeout(() => reject(new Error("abort_not_propagated")), 1_000))]);
  assert.equal(memory.getIdempotent(`decision:${fixture.session_id}:${fixture.request_id}`), undefined);
  await new Promise<void>((resolve) => server.close(() => resolve()));
  memory.close(); rmSync(directory, {recursive: true, force: true});
});

function makeWaitIntent(request: DecisionRequest): ActionIntent {
  return {
    protocol_version: 1,
    decision_id: "stream-decision-1",
    request_id: request.request_id,
    agent_id: request.agent_id,
    expected_revision: request.world_revision,
    idempotency_key: `${request.request_id}:wait`,
    tool_name: "wait",
    tool_version: 1,
    arguments: {},
    decision_summary: "Wait for the next cycle",
  };
}
