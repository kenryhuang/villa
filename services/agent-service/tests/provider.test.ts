import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { loadConfigFile, type ProviderConfig } from "../src/config.ts";
import { OpenAICompatibleProvider } from "../src/provider.ts";
import { AgentRegistry } from "../src/agents.ts";
import type { DecisionRequest } from "../src/protocol.ts";
import type { MemoryEvent } from "../src/memory.ts";

const request: DecisionRequest = {
  protocol_version: 2, request_id: "req-1", session_id: "save-0", session_epoch: 1,
  agent_id: "farmer_ahe", trigger: "schedule", game_minute: 480, world_revision: 7,
  snapshot: {inventory: {carrot_seed: 6}}, event_delta: [],
};

const ALL_TOOLS = [
  "till", "plant", "harvest", "build", "buy", "sell", "speak", "wait",
  "propose_trade", "prepare_supplies", "travel", "survey", "collect_sample", "register_discovery",
];

function configuredProvider(baseUrl: string, apiKey: string): {provider: ProviderConfig; cleanup: () => void} {
  const root = mkdtempSync(join(tmpdir(), "villa-provider-config-"));
  const path = join(root, "agent-service.json");
  writeFileSync(path, JSON.stringify({
    service: {},
    provider: {base_url: baseUrl, api_key: apiKey, model: "test-model"},
    memory: {database_path: "data/memory.sqlite", checkpoint_root: "data/checkpoints"},
  }), "utf8");
  return {provider: loadConfigFile(path, root).provider, cleanup: () => rmSync(root, {recursive: true, force: true})};
}

test("sends credentials only in the header and accepts one role tool", async () => {
  let capturedHeaders: Record<string, string | string[] | undefined> = {};
  let capturedBody = "";
  const server: Server = createServer((incoming, response) => {
    capturedHeaders = incoming.headers;
    incoming.setEncoding("utf8");
    incoming.on("data", (chunk) => { capturedBody += chunk; });
    incoming.on("end", () => {
      response.setHeader("content-type", "text/event-stream");
      response.end([
        `data: ${JSON.stringify({id: "provider-decision-1", choices: [{delta: {content: "准备播种。", tool_calls: [{index: 0, id: "call-1", type: "function", function: {name: "plant", arguments: JSON.stringify({plot: 0, seed_item_id: "carrot_seed"})}}]}, finish_reason: "tool_calls"}]})}\n\n`,
        "data: [DONE]\n\n",
      ].join(""));
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  assert.ok(address && typeof address === "object");
  const config = configuredProvider(`http://127.0.0.1:${address.port}`, "test-key");
  const registry = AgentRegistry.loadDefault();
  const provider = new OpenAICompatibleProvider(config.provider);
  const context = registry.buildContext("farmer_ahe", request.snapshot, [], []);
  const intent = await provider.decide(request, {...context, allowed_tools: ALL_TOOLS});
  await new Promise<void>((resolve) => server.close(() => resolve()));
  config.cleanup();
  assert.equal(intent.actions[0].tool_name, "plant");
  assert.equal(intent.expected_revision, 7);
  assert.equal(capturedHeaders.authorization, "Bearer test-key");
  assert.equal(capturedBody.includes("test-key"), false);
  const providerBody = JSON.parse(capturedBody) as {
    tool_choice: string;
    stream: boolean;
    tools: Array<{function: {name: string; parameters: Record<string, unknown>}}>;
  };
  assert.equal(providerBody.tool_choice, "auto");
  assert.equal(providerBody.stream, true);
  assert.deepEqual(providerBody.tools.map((tool) => tool.function.name), ALL_TOOLS);
  const byName = new Map(providerBody.tools.map((tool) => [tool.function.name, tool.function.parameters]));
  assert.deepEqual(byName.get("till"), {
    type: "object",
    properties: {plot: {type: "integer", minimum: 0, maximum: 255}},
    required: ["plot"],
    additionalProperties: false,
  });
  assert.deepEqual(byName.get("plant"), {
    type: "object",
    properties: {
      plot: {type: "integer", minimum: 0, maximum: 255},
      seed_item_id: {type: "string", enum: [
        "tomato_seed", "carrot_seed", "potato_seed", "grain_seed",
        "lavender_seed", "grape_seed", "lemon_sapling",
      ]},
    },
    required: ["plot", "seed_item_id"],
    additionalProperties: false,
  });
  assert.deepEqual(byName.get("sell"), {
    type: "object",
    properties: {
      item_id: {type: "string", minLength: 1, maxLength: 80},
      quantity: {type: "integer", minimum: 1, maximum: 100},
    },
    required: ["item_id", "quantity"],
    additionalProperties: false,
  });
  assert.deepEqual(byName.get("survey"), {
    type: "object",
    properties: {region_id: {type: "string", enum: ["creek", "hills", "forest"]}},
    required: ["region_id"],
    additionalProperties: false,
  });
  assert.deepEqual(byName.get("wait"), {
    type: "object", properties: {}, required: [], additionalProperties: false,
  });
});

test("includes the exact player dialogue in the Provider prompt", async () => {
  let capturedBody = "";
  const server: Server = createServer((incoming, response) => {
    incoming.setEncoding("utf8");
    incoming.on("data", (chunk) => { capturedBody += chunk; });
    incoming.on("end", () => {
      response.setHeader("content-type", "text/event-stream");
      response.end([
        `data: ${JSON.stringify({id: "dialogue-1", choices: [{delta: {content: "价格很稳定。"}, finish_reason: "stop"}]})}\n\n`,
        "data: [DONE]\n\n",
      ].join(""));
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const config = configuredProvider(`http://127.0.0.1:${address.port}`, "dialogue-key");
  const provider = new OpenAICompatibleProvider(config.provider);
  const dialogueRequest: DecisionRequest = {
    ...request,
    request_id: "dialogue-request-1",
    trigger: "dialogue",
    dialogue_input: "今天胡萝卜价格怎么样？",
  };
  const context = AgentRegistry.loadDefault().buildContext("farmer_ahe", request.snapshot, [], []);
  await provider.decide(dialogueRequest, context);
  await new Promise<void>((resolve) => server.close(() => resolve()));
  config.cleanup();
  const providerBody = JSON.parse(capturedBody) as {messages: Array<{role: string; content: string}>};
  const userMessage = providerBody.messages.find((message) => message.role === "user");
  const systemMessage = providerBody.messages.find((message) => message.role === "system");
  assert.ok(userMessage);
  assert.equal(JSON.parse(userMessage.content).dialogue_input, "今天胡萝卜价格怎么样？");
  assert.match(systemMessage?.content || "", /in character/i);
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
  const config = configuredProvider(`http://127.0.0.1:${address.port}`, "memory-key");
  const provider = new OpenAICompatibleProvider(config.provider);
  const agent = AgentRegistry.loadDefault().get("farmer_ahe"); assert.ok(agent);
  const events: MemoryEvent[] = [{event_id: "harvest-1", kind: "harvest", game_minute: 600, importance: 7, payload: {carrot: 4}}];
  const memory = await provider.compactMemory(agent, events);
  await new Promise<void>((resolve) => server.close(() => resolve()));
  config.cleanup();
  assert.equal(memory.summary, "阿禾完成了首次胡萝卜丰收。");
  assert.equal(memory.importance, 8);
});
