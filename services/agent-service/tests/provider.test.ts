import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import test from "node:test";
import { loadConfig } from "../src/config.ts";
import { OpenAICompatibleProvider } from "../src/provider.ts";
import { AgentRegistry } from "../src/agents.ts";
import type { DecisionRequest } from "../src/protocol.ts";
import type { MemoryEvent } from "../src/memory.ts";

const request: DecisionRequest = {
  protocol_version: 1, request_id: "req-1", session_id: "save-0", session_epoch: 1,
  agent_id: "farmer_ahe", trigger: "schedule", game_minute: 480, world_revision: 7,
  snapshot: {inventory: {carrot_seed: 6}}, event_delta: [],
};

test("requires a complete real Provider configuration", () => {
  assert.throws(() => loadConfig({}), /AGENT_PROVIDER_BASE_URL/);
  assert.throws(() => loadConfig({AGENT_PROVIDER_BASE_URL: "http://localhost"}), /AGENT_PROVIDER_API_KEY/);
});

test("sends credentials only in the header and accepts one role tool", async () => {
  let capturedHeaders: Record<string, string | string[] | undefined> = {};
  let capturedBody = "";
  const server: Server = createServer((incoming, response) => {
    capturedHeaders = incoming.headers;
    incoming.setEncoding("utf8");
    incoming.on("data", (chunk) => { capturedBody += chunk; });
    incoming.on("end", () => {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify({
        id: "provider-decision-1",
        choices: [{message: {content: "准备播种。", tool_calls: [{id: "call-1", type: "function", function: {
          name: "plant", arguments: JSON.stringify({plot: 0, seed_item_id: "carrot_seed"}),
        }}]}}],
      }));
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  assert.ok(address && typeof address === "object");
  const config = loadConfig({
    AGENT_PROVIDER_BASE_URL: `http://127.0.0.1:${address.port}`,
    AGENT_PROVIDER_API_KEY: "test-key",
    AGENT_PROVIDER_MODEL: "test-model",
  });
  const registry = AgentRegistry.loadDefault();
  const provider = new OpenAICompatibleProvider(config.provider);
  const intent = await provider.decide(request, registry.buildContext("farmer_ahe", request.snapshot, [], []));
  await new Promise<void>((resolve) => server.close(() => resolve()));
  assert.equal(intent.tool_name, "plant");
  assert.equal(intent.expected_revision, 7);
  assert.equal(capturedHeaders.authorization, "Bearer test-key");
  assert.equal(capturedBody.includes("test-key"), false);
});

test("compresses selected events through the configured real Provider", async () => {
  const server: Server = createServer((_incoming, response) => {
    response.setHeader("content-type", "application/json");
    response.end(JSON.stringify({
      id: "memory-1", choices: [{message: {content: JSON.stringify({summary: "阿禾完成了首次胡萝卜丰收。", importance: 8})}}],
    }));
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const provider = new OpenAICompatibleProvider(loadConfig({
    AGENT_PROVIDER_BASE_URL: `http://127.0.0.1:${address.port}`,
    AGENT_PROVIDER_API_KEY: "memory-key", AGENT_PROVIDER_MODEL: "test-model",
  }).provider);
  const agent = AgentRegistry.loadDefault().get("farmer_ahe"); assert.ok(agent);
  const events: MemoryEvent[] = [{event_id: "harvest-1", kind: "harvest", game_minute: 600, importance: 7, payload: {carrot: 4}}];
  const memory = await provider.compactMemory(agent, events);
  await new Promise<void>((resolve) => server.close(() => resolve()));
  assert.equal(memory.summary, "阿禾完成了首次胡萝卜丰收。");
  assert.equal(memory.importance, 8);
});
