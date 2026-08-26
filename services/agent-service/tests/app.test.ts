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
