import assert from "node:assert/strict";
import {createServer} from "node:http";
import test from "node:test";
import {AgentRegistry} from "../src/agents.ts";
import {OpenAICompatibleProvider} from "../src/provider.ts";
import {executeReadTool} from "../src/tool_contracts.ts";
import type {DecisionRequest} from "../src/protocol.ts";

const request: DecisionRequest = {
  protocol_version: 2, request_id: "recovery", session_id: "isolated", session_epoch: 1,
  agent_id: "xuezhe_lin", trigger: "schedule", game_minute: 480, world_revision: 7,
  projection_schema_version: 1, active_role: "explorer", goals: [],
  actor_context: {self: {gold: 20, inventory: {}}, world_map: {regions: [{id: "farm", description: "Actual 3D farm"}]}},
  allowed_read_tools: ["inspect_region", "inspect_market_depth", "compare_market_items"],
  allowed_command_tools: ["speak"], public_world_state: {}, global_public_events: [],
  known_actors: [], own_event_delta: [],
  market_summary: {schema_version: 1, role_id: "farmer", generated_game_minute: 480, overview: {item_count: 0, shortage_count: 0, surplus_count: 0, rising_count: 0, falling_count: 0}, signals: []},
  market_view: {salt: {depth: {stock: 8, quotes: [{quantity: 2, buy_total: 11, sell_total: 9, buy_available: true}]}}},
  interaction_view: {}, agreement_view: {},
};
const read = ["inspect_region", {region_id: "farm"}] as const;
const speak = ["speak", {target_actor_id: "player", text: "我先查看市场。"}] as const;
type Call = readonly [string, Record<string, unknown>];

async function scenario(rounds: Array<readonly Call[] | "timeout">, verify: (provider: OpenAICompatibleProvider, bodies: any[]) => Promise<void>) {
  const bodies: any[] = [];
  const server = createServer((incoming, response) => {
    let body = "";
    incoming.setEncoding("utf8");
    incoming.on("data", (chunk) => body += chunk);
    incoming.on("end", () => {
      bodies.push(JSON.parse(body));
      const calls = rounds[bodies.length - 1] ?? "timeout";
      if (calls === "timeout") return;
      const tool_calls = calls.map(([name, args], index) => ({index, id: `r${bodies.length}-${index}`, type: "function", function: {name, arguments: JSON.stringify(args)}}));
      response.setHeader("content-type", "text/event-stream");
      response.end(`data: ${JSON.stringify({id: `round-${bodies.length}`, choices: [{delta: {tool_calls}, finish_reason: "tool_calls"}]})}\n\ndata: [DONE]\n\n`);
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  try {
    await verify(new OpenAICompatibleProvider({baseUrl: `http://127.0.0.1:${address.port}`, apiKey: "test", model: "test", timeoutMs: 200, maxConcurrency: 2, maxOutputTokens: 1200, temperature: 0}), bodies);
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}
const context = () => AgentRegistry.loadDefault().buildContext(request.agent_id, request, []);

test("3D region and market depth read the supplied authoritative data", () => {
  assert.deepEqual(executeReadTool(context(), "inspect_region", {region_id: "farm"}), {found: true, value: request.actor_context.world_map.regions[0]});
  assert.deepEqual(executeReadTool(context(), "inspect_region", {region_id: "missing"}), {found: false});
  const merchant = AgentRegistry.loadDefault().buildContext("lao_li", {...request, agent_id: "lao_li", active_role: "merchant"}, []);
  assert.deepEqual(executeReadTool(merchant, "inspect_market_depth", {item_id: "salt"}), {found: true, value: request.market_view.salt.depth});
  const legacy = context();
  legacy.public_world_state.regions = [{region_id: "old", description: "Legacy region"}];
  assert.equal(executeReadTool(legacy, "inspect_region", {region_id: "old"}).found, true);
});

test("mixed batches inspect safely and only return a reissued command", async () => {
  await scenario([[read, speak], [speak]], async (provider, bodies) => {
    const result = await provider.decide(request, context());
    assert.equal(result.actions.length, 1);
    assert.equal(result.actions[0].action_id, "r2-0");
    const feedback = bodies[1].messages.filter((m: any) => m.role === "tool").map((m: any) => JSON.parse(m.content));
    assert.equal(feedback[0].found, true);
    assert.equal(feedback[1].error, "command_not_executed");
    assert.equal(bodies[1].enable_thinking, false);
  });
});

test("exhausted reads receive explicit feedback and a bounded command-only correction", async () => {
  await scenario([[read], [read], [read], [speak]], async (provider, bodies) => {
    assert.equal((await provider.decide(request, context())).actions[0].tool_name, "speak");
    assert.equal(bodies.length, 4);
    assert.deepEqual(JSON.parse(bodies[2].messages[1].content).allowed_read_tools, []);
    assert.match(bodies[2].messages[0].content, /0 remaining/);
    assert.deepEqual(bodies[2].tools.map((t: any) => t.function.name), ["speak"]);
    assert.equal(JSON.parse(bodies[3].messages.at(-1).content).error, "read_round_limit");
  });
});

test("malformed array arguments can be corrected without widening permissions", async () => {
  await scenario([[["compare_market_items", {item_ids: '["salt"]'}]], [["compare_market_items", {item_ids: ["salt"]}]], [speak]], async (provider, bodies) => {
    assert.equal((await provider.decide(request, context())).actions.length, 1);
    assert.equal(JSON.parse(bodies[1].messages.at(-1).content).error, "invalid_read_arguments");
  });
  await scenario([[read, ["grant_gold", {amount: 100}]]], async (provider) => {
    await assert.rejects(provider.decide(request, context()), /unauthorized_tool/);
  });
});

test("repeated invalid tool use terminates instead of looping", async () => {
  await scenario([[read], [read], [read], [read]], async (provider, bodies) => {
    await assert.rejects(provider.decide(request, context()), /provider_tool_correction_exhausted/);
    assert.equal(bodies.length, 4);
  });
});

test("autonomous timeout retries once without thinking and preserves final timeout errors", async () => {
  await scenario(["timeout", [speak]], async (provider, bodies) => {
    assert.equal((await provider.decide(request, context())).actions.length, 1);
    assert.equal(bodies.length, 2);
    assert.equal(bodies[1].enable_thinking, false);
  });
  await scenario(["timeout", "timeout"], async (provider, bodies) => {
    await assert.rejects(provider.decide(request, context()), /provider_timeout/);
    assert.equal(bodies.length, 2);
  });
});

test("external cancellation never triggers a timeout retry", async () => {
  await scenario(["timeout"], async (provider, bodies) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(new Error("game_closed")), 50);
    try { await assert.rejects(provider.streamDecision(request, context(), () => {}, controller.signal), /game_closed/); }
    finally { clearTimeout(timer); }
    assert.ok(bodies.length <= 1);
  });
});
