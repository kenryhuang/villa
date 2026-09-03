import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { loadConfigFile, type ProviderConfig } from "../src/config.ts";
import { OpenAICompatibleProvider } from "../src/provider.ts";
import { AgentRegistry } from "../src/agents.ts";
import {executeReadTool} from "../src/tool_contracts.ts";
import type { DecisionRequest } from "../src/protocol.ts";
import type { MemoryEvent } from "../src/memory.ts";

const request: DecisionRequest = {
  protocol_version: 2, request_id: "req-1", session_id: "save-0", session_epoch: 1,
  agent_id: "farmer_ahe", trigger: "schedule", game_minute: 480, world_revision: 7,
  projection_schema_version: 1,
  actor_context: {self: {gold: 20, inventory: {carrot_seed: 6}}, farm: [{plot: 0, state: "tilled"}]},
  active_role: "farmer", goals: ["keep_crops_healthy"],
  allowed_read_tools: ["inspect_self_resources", "inspect_farm_plots", "inspect_market_item"],
  allowed_command_tools: ["till", "plant", "harvest", "build", "buy", "sell", "speak", "wait"],
  public_world_state: {season: 0}, global_public_events: [], known_actors: [], own_event_delta: [],
  market_summary: {schema_version: 1, role_id: "farmer", generated_game_minute: 480, overview: {item_count: 1, shortage_count: 0, surplus_count: 0, rising_count: 0, falling_count: 0}, signals: []},
  market_view: {secret_crop: {marker: "FULL_MARKET_SENTINEL", mid_price: 99}},
  interaction_view: {active_offers: []}, agreement_view: {active_agreements: []},
};

const ALL_TOOLS = [
  "till", "plant", "harvest", "build", "buy", "sell", "speak", "wait",
  "propose_trade", "prepare_supplies", "travel", "survey", "collect_sample", "register_discovery",
];

function configuredProvider(
  baseUrl: string,
  apiKey: string,
  overrides: Record<string, unknown> = {},
): {provider: ProviderConfig; cleanup: () => void} {
  const root = mkdtempSync(join(tmpdir(), "villa-provider-config-"));
  const path = join(root, "agent-service.json");
  writeFileSync(path, JSON.stringify({
    service: {},
    provider: {base_url: baseUrl, api_key: apiKey, model: "test-model", ...overrides},
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
  const context = registry.buildContext("farmer_ahe", {...request, allowed_command_tools: ALL_TOOLS}, []);
  const intent = await provider.decide(request, context);
  await new Promise<void>((resolve) => server.close(() => resolve()));
  config.cleanup();
  assert.equal(intent.actions[0].tool_name, "plant");
  assert.equal(intent.expected_revision, 7);
  assert.equal(capturedHeaders.authorization, "Bearer test-key");
  assert.equal(capturedBody.includes("test-key"), false);
  const providerBody = JSON.parse(capturedBody) as {
    tool_choice: string;
    stream: boolean;
    messages: Array<{role: string; content: string}>;
    tools: Array<{function: {name: string; parameters: Record<string, unknown>}}>;
  };
  assert.equal(providerBody.tool_choice, "auto");
  assert.equal(providerBody.stream, true);
  const sentContext = JSON.parse(providerBody.messages.find((message) => message.role === "user")?.content || "{}") as Record<string, unknown>;
  assert.deepEqual(sentContext.market_summary, request.market_summary);
  assert.equal(Object.hasOwn(sentContext, "market_view"), false);
  assert.doesNotMatch(capturedBody, /FULL_MARKET_SENTINEL/);
  assert.deepEqual(providerBody.tools.map((tool) => tool.function.name), [
    "inspect_self_resources", "inspect_farm_plots", "inspect_market_item",
    "till", "plant", "harvest", "build", "buy", "sell", "speak", "wait", "propose_trade",
  ]);
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
	  agreement_id: {type: "string", minLength: 1, maxLength: 80},
    },
    required: ["item_id", "quantity"],
    additionalProperties: false,
  });
  assert.equal(byName.has("survey"), false, "Godot cannot widen the local farmer role");
  assert.deepEqual(byName.get("wait"), {
    type: "object",
    properties: {reason: {type: "string", minLength: 1, maxLength: 300}},
    required: ["reason"], additionalProperties: false,
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
  const context = AgentRegistry.loadDefault().buildContext("farmer_ahe", dialogueRequest, []);
  assert.deepEqual(
    executeReadTool(context, "inspect_market_item", {item_id: "secret_crop"}),
    {found: true, value: {marker: "FULL_MARKET_SENTINEL", mid_price: 99}},
  );
  await provider.decide(dialogueRequest, context);
  await new Promise<void>((resolve) => server.close(() => resolve()));
  config.cleanup();
  const providerBody = JSON.parse(capturedBody) as {
    messages: Array<{role: string; content: string}>;
    tools?: Array<{function: {name: string}}>;
    tool_choice?: unknown;
  };
  const userMessage = providerBody.messages.find((message) => message.role === "user");
  const systemMessage = providerBody.messages.find((message) => message.role === "system");
  assert.ok(userMessage);
  const dialoguePayload = JSON.parse(userMessage.content) as {
    dialogue_input: string;
    context: {allowed_read_tools: string[]; allowed_command_tools: string[]};
  };
  assert.equal(dialoguePayload.dialogue_input, "今天胡萝卜价格怎么样？");
  assert.deepEqual(dialoguePayload.context.allowed_read_tools, ["inspect_self_resources", "inspect_farm_plots", "inspect_market_item"]);
  assert.deepEqual(dialoguePayload.context.allowed_command_tools, ["till", "plant", "harvest", "build", "buy", "sell", "speak", "wait"]);
  assert.equal("tools" in providerBody, true);
  assert.equal("tool_choice" in providerBody, true);
  assert.deepEqual(providerBody.tools?.map((tool) => tool.function.name), [
    "inspect_self_resources", "inspect_farm_plots", "inspect_market_item", "speak",
  ]);
  assert.match(systemMessage?.content || "", /in character/i);
  assert.match(systemMessage?.content || "", /at most one authorized interaction command/i);
});

test("executes local read tools and sends only final commands to Godot", async () => {
  const bodies: Record<string, unknown>[] = [];
  let turn = 0;
  const server: Server = createServer((incoming, response) => {
    let body = "";
    incoming.setEncoding("utf8");
    incoming.on("data", (chunk) => { body += chunk; });
    incoming.on("end", () => {
      bodies.push(JSON.parse(body));
      response.setHeader("content-type", "text/event-stream");
      turn += 1;
      const chunk = turn === 1
        ? {id: "read-turn", choices: [{delta: {tool_calls: [{index: 0, id: "read-1", type: "function", function: {name: "inspect_self_resources", arguments: JSON.stringify({item_ids: ["carrot_seed", "private_item"]})}}]}, finish_reason: "tool_calls"}]}
        : {id: "command-turn", choices: [{delta: {content: "开始播种。", tool_calls: [{index: 0, id: "plant-1", type: "function", function: {name: "plant", arguments: JSON.stringify({plot: 0, seed_item_id: "carrot_seed"})}}]}, finish_reason: "tool_calls"}]};
      response.end(`data: ${JSON.stringify(chunk)}\n\ndata: [DONE]\n\n`);
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const config = configuredProvider(`http://127.0.0.1:${address.port}`, "read-key");
  const context = AgentRegistry.loadDefault().buildContext("farmer_ahe", request, []);
  const intent = await new OpenAICompatibleProvider(config.provider).decide(request, context);
  await new Promise<void>((resolve) => server.close(() => resolve()));
  config.cleanup();
  assert.equal(bodies.length, 2);
  const secondMessages = bodies[1].messages as Array<Record<string, unknown>>;
  const toolMessage = secondMessages.find((message) => message.role === "tool");
  assert.ok(toolMessage);
  assert.deepEqual(JSON.parse(String(toolMessage.content)), {gold: 20, items: {carrot_seed: 6, private_item: 0}});
  assert.deepEqual(intent.actions.map((action) => action.tool_name), ["plant"]);
});

test("gives every Provider read-tool round a fresh timeout budget", async () => {
  let turn = 0;
  const server: Server = createServer((incoming, response) => {
    incoming.resume();
    incoming.on("end", () => {
      turn += 1;
      const chunk = turn === 1
        ? {id: "slow-read", choices: [{delta: {tool_calls: [{index: 0, id: "read-1", type: "function", function: {name: "inspect_self_resources", arguments: JSON.stringify({item_ids: ["carrot_seed"]})}}]}, finish_reason: "tool_calls"}]}
        : {id: "slow-command", choices: [{delta: {tool_calls: [{index: 0, id: "plant-1", type: "function", function: {name: "plant", arguments: JSON.stringify({plot: 0, seed_item_id: "carrot_seed"})}}]}, finish_reason: "tool_calls"}]};
      setTimeout(() => {
        response.setHeader("content-type", "text/event-stream");
        response.end(`data: ${JSON.stringify(chunk)}\n\ndata: [DONE]\n\n`);
      }, 125);
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const config = configuredProvider(
    `http://127.0.0.1:${address.port}`,
    "round-timeout-key",
    {timeout_ms: 200},
  );
  try {
    const context = AgentRegistry.loadDefault().buildContext("farmer_ahe", request, []);
    const intent = await new OpenAICompatibleProvider(config.provider).decide(request, context);
    assert.equal(turn, 2);
    assert.deepEqual(intent.actions.map((action) => action.tool_name), ["plant"]);
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    config.cleanup();
  }
});

test("reports an internally timed out Provider round as provider_timeout", async () => {
  const server: Server = createServer((incoming, response) => {
    incoming.resume();
    incoming.on("end", () => setTimeout(() => response.end(), 250));
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const config = configuredProvider(
    `http://127.0.0.1:${address.port}`,
    "stable-timeout-key",
    {timeout_ms: 100},
  );
  try {
    const context = AgentRegistry.loadDefault().buildContext("farmer_ahe", request, []);
    await assert.rejects(
      new OpenAICompatibleProvider(config.provider).decide(request, context),
      /provider_timeout/,
    );
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    config.cleanup();
  }
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
