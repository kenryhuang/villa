import assert from "node:assert/strict";
import {createServer} from "node:http";
import test from "node:test";
import {mkdtempSync, readFileSync, writeFileSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {AgentRegistry} from "../src/agents.ts";
import {OpenAICompatibleProvider} from "../src/provider.ts";
import {executeReadTool, toolDescription, validToolArguments, toolArgumentErrors} from "../src/tool_contracts.ts";
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
type Call = readonly [string, Record<string, unknown> | string];

async function scenario(rounds: Array<readonly Call[] | "timeout">, verify: (provider: OpenAICompatibleProvider, bodies: any[]) => Promise<void>, finishReasons: string[] = []) {
  const bodies: any[] = [];
  const server = createServer((incoming, response) => {
    let body = "";
    incoming.setEncoding("utf8");
    incoming.on("data", (chunk) => body += chunk);
    incoming.on("end", () => {
      bodies.push(JSON.parse(body));
      const calls = rounds[bodies.length - 1] ?? "timeout";
      if (calls === "timeout") return;
      const tool_calls = calls.map(([name, args], index) => ({index, id: `r${bodies.length}-${index}`, type: "function", function: {name, arguments: typeof args === "string" ? args : JSON.stringify(args)}}));
      response.setHeader("content-type", "text/event-stream");
      response.end(`data: ${JSON.stringify({id: `round-${bodies.length}`, choices: [{delta: {...(bodies.at(-1).enable_thinking === true ? {reasoning_content: "检查当前事件。"} : {}), tool_calls}, finish_reason: finishReasons[bodies.length - 1] ?? "tool_calls"}]})}\n\ndata: [DONE]\n\n`);
    });
  });
  // Windows can allocate port 6667 (or another Fetch-forbidden service port)
  // for listen(0). Bind in a high range so transport tests reach the mock.
  for (let attempt = 0; ; attempt++) {
    try {
      await new Promise<void>((resolve, reject) => {
        const failed = (error: Error) => { server.off("listening", ready); reject(error); };
        const ready = () => { server.off("error", failed); resolve(); };
        server.once("error", failed).once("listening", ready).listen(20000 + Math.floor(Math.random() * 30000), "127.0.0.1");
      });
      break;
    } catch (error) {
      if (attempt >= 9 || (error as NodeJS.ErrnoException).code !== "EADDRINUSE") throw error;
    }
  }
  const address = server.address(); assert.ok(address && typeof address === "object");
  try {
    await verify(new OpenAICompatibleProvider({baseUrl: `http://127.0.0.1:${address.port}`, apiKey: "test", model: "test", timeoutMs: 200, maxConcurrency: 2, maxOutputTokens: 1200, temperature: 0}), bodies);
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}
const context = () => AgentRegistry.loadDefault().buildContext(request.agent_id, request, []);

test("daily reservations persist across restarts, share actors, and cannot reset by rewinding", async () => {
  const directory = mkdtempSync(join(tmpdir(), "villa-provider-budget-"));
  const path = join(directory, "usage.json");
  const config = {baseUrl: "http://127.0.0.1:29999", apiKey: "test", model: "test", timeoutMs: 50, maxConcurrency: 2, maxOutputTokens: 1200, temperature: 0};
  try {
    writeFileSync(path, JSON.stringify({isolated: {day: 2, reserved: 7_999_999}}));
    for (const minute of [2160, 0, 2159]) {
      const provider = new OpenAICompatibleProvider(config, path);
      await assert.rejects(provider.decide({...request, game_minute: minute}, context()), /provider_daily_budget_exhausted/);
      assert.equal(JSON.parse(readFileSync(path, "utf8")).isolated.reserved, 7_999_999);
    }
    const anotherActor = {...request, agent_id: "lao_li", game_minute: 2160};
    await assert.rejects(new OpenAICompatibleProvider(config, path).decide(anotherActor, AgentRegistry.loadDefault().buildContext("lao_li", anotherActor, [])), /provider_daily_budget_exhausted/);
    // Next day gets a new reservation even if transport subsequently fails.
    await assert.rejects(new OpenAICompatibleProvider(config, path).decide({...request, game_minute: 3240}, context()));
    const usage = JSON.parse(readFileSync(path, "utf8")).isolated;
    assert.equal(usage.day, 3);
    assert.ok(usage.reserved > 0 && usage.reserved < 8_000_000);
    writeFileSync(path, JSON.stringify({isolated: {day: 3, reserved: -1}}));
    assert.throws(() => new OpenAICompatibleProvider(config, path), /provider_budget_store_invalid/);
  } finally { rmSync(directory, {recursive: true, force: true}); }
});

test("behavior text schema matches the service and Godot 500-character limit", () => {
  const schema = toolDescription("suggest_behavior") as any;
  assert.equal(schema.function.parameters.properties.text.maxLength, 500);
  assert.equal(validToolArguments("suggest_behavior", {text: "意".repeat(500), ttl: 720}), true);
  for (const length of [519, 528, 661]) {
    const args = {text: "意".repeat(length), ttl: 720};
    assert.equal(validToolArguments("suggest_behavior", args), false);
    assert.deepEqual(toolArgumentErrors("suggest_behavior", args), [`suggest_behavior.text: length ${length} exceeds maximum 500`]);
  }
});

const plan = {goal: "Produce and sell flour", budget: 50, deadline_minutes: 480, materials: {},
  steps: [{id: "buy", capability: "buy", depends_on: [], arguments: {item_id: "grain", quantity: 2, limit: 40}}]};
const correctionCases: Array<{label: string; bad: Call; good: Call; detail: RegExp}> = [
  {label: "behavior text", bad: ["suggest_behavior", {text: "x".repeat(661), ttl: 720}], good: ["suggest_behavior", {text: "Recheck supplies before spending", ttl: 720}], detail: /suggest_behavior.text: length 661 exceeds maximum 500/},
  ...[505, 520].map(length => ({label: `project goal ${length}`, bad: ["submit_project", {...plan, goal: "x".repeat(length)}] as Call, good: ["submit_project", plan] as Call, detail: /submit_project.goal: length .* exceeds maximum 500/})),
  {label: "public price cap", bad: ["public_food_plan", {expected_version: 1, reason: "Unmet food gap", quantity: 3, unit_reward: 220, deadline_minutes: 240}], good: ["public_wait", {expected_version: 1, reason: "Competing price exceeds authorized cap"}], detail: /public_food_plan.unit_reward: maximum is 200/},
];
for (const sample of correctionCases) {
  test(`corrects trace failure: ${sample.label}, without executing the rejected batch`, async () => {
    await scenario([[speak, sample.bad], [sample.good]], async (provider, bodies) => {
      const ctx = {...context(), allowed_command_tools: ["speak", sample.bad[0], sample.good[0]]};
      const events: any[] = [];
      const result = await provider.streamDecision(request, ctx, event => events.push(event));
      assert.equal(bodies.length, 2);
      assert.deepEqual(result.actions.map(a => [a.action_id, a.tool_name, a.arguments]), [["r2-0", sample.good[0], sample.good[1]]]);
      const feedback = bodies[1].messages.filter((m: any) => m.role === "tool").map((m: any) => JSON.parse(m.content));
      assert.equal(feedback.length, 2);
      assert.match(feedback[0].details.join(" "), sample.detail);
      assert.match(feedback[0].message, /No commands were executed/);
      assert.equal(bodies[1].enable_thinking, false);
      assert.deepEqual(JSON.parse(bodies[1].messages[1].content).allowed_read_tools, []);
      assert.ok(events.some(e => e.type === "output" && e.output.validation_errors?.some((s: string) => sample.detail.test(s))));
    });
  });
}

test("wait plus intention is corrected by the model, not silently filtered", async () => {
  const intention: Call = ["suggest_behavior", {text: "Wait for an affordable supply", ttl: 720}];
  await scenario([[["wait", {reason: "No affordable supply"}], intention], [intention]], async (provider, bodies) => {
    const result = await provider.decide(request, {...context(), allowed_command_tools: ["wait", "suggest_behavior"]});
    assert.equal(result.actions[0].action_id, "r2-0");
    assert.match(JSON.parse(bodies[1].messages.at(-1).content).details.join(" "), /wait must be the only command/);
  });
});

test("incomplete JSON is traced and regenerated without malformed history", async () => {
  const broken: Call = ["suggest_behavior", '{"text":"Remember supply","ttl":'];
  const good: Call = ["suggest_behavior", {text: "Remember supply", ttl: 720}];
  await scenario([[speak, broken], [good]], async (provider, bodies) => {
    const events: any[] = [];
    const result = await provider.streamDecision(request, {...context(), allowed_command_tools: ["speak", "suggest_behavior"]}, e => events.push(e));
    assert.equal(result.actions[0].action_id, "r2-0");
    assert.equal(events.find(e => e.type === "output").output.message.tool_calls[1].function.arguments, broken[1]);
    assert.equal(bodies[1].messages.some((m: any) => m.role === "assistant"), false);
    assert.match(JSON.parse(bodies[1].messages.at(-1).content).details.join(" "), /incomplete or invalid JSON/);
  });
});

test("length finish rejects even a complete first command and regenerates the entire batch", async () => {
  await scenario([[speak], [speak]], async (provider, bodies) => {
    const result = await provider.decide(request, context());
    assert.equal(result.actions[0].action_id, "r2-0");
    assert.match(JSON.parse(bodies[1].messages.at(-1).content).details.join(" "), /output was truncated/);
  }, ["length"]);
});

test("invalid commands get only one correction, shared with read corrections", async () => {
  const bad: Call = ["speak", {target_actor_id: "player", text: "x".repeat(1001)}];
  await scenario([[bad], [bad]], async (provider, bodies) => {
    await assert.rejects(provider.decide(request, context()), /provider_invalid_intent:invalid_arguments/);
    assert.equal(bodies.length, 2);
  });
  await scenario([[read, speak], [bad]], async (provider, bodies) => {
    await assert.rejects(provider.decide(request, context()), /provider_invalid_intent:invalid_arguments/);
    assert.equal(bodies.length, 2);
  });
});

test("unauthorized tools fail closed even alongside incomplete JSON", async () => {
  await scenario([[["speak", '{"text":'], ["grant_gold", {amount: 100}]]], async (provider, bodies) => {
    await assert.rejects(provider.decide(request, context()), /unauthorized_tool/);
    assert.equal(bodies.length, 1);
  });
});

test("cancellation while reporting validation prevents the correction request", async () => {
  await scenario([[["speak", {target_actor_id: "player", text: "x".repeat(1001)}]]], async (provider, bodies) => {
    const controller = new AbortController();
    await assert.rejects(provider.streamDecision(request, context(), event => {
      if (event.type === "output" && event.output.validation_errors) controller.abort(new Error("game_closed"));
    }, controller.signal), /game_closed/);
    assert.equal(bodies.length, 1);
  });
});

test("dialogue correction retains its one-command limit and authorization", async () => {
  await scenario([[speak, speak], [speak]], async (provider, bodies) => {
    const result = await provider.decide({...request, trigger: "dialogue"}, context());
    assert.equal(result.actions.length, 1);
    assert.equal(result.actions[0].action_id, "r2-0");
    assert.match(JSON.parse(bodies[1].messages.at(-1).content).details.join(" "), /maximum commands is 1/);
    assert.deepEqual(bodies[1].tools.map((t: any) => t.function.name), ["speak"]);
  });
  await scenario([[["speak", {text: "missing recipient"}]], [["buy", {item_id: "bread", quantity: 1}]]], async (provider, bodies) => {
    await assert.rejects(provider.decide({...request, trigger: "dialogue"}, {...context(), allowed_command_tools: ["speak", "buy"]}), /unauthorized_tool/);
    assert.equal(bodies.length, 2);
  });
});

test("3D region and market depth read the supplied authoritative data", () => {
  assert.deepEqual(executeReadTool(context(), "inspect_region", {region_id: "farm"}), {found: true, value: request.actor_context.world_map.regions[0]});
  assert.deepEqual(executeReadTool(context(), "inspect_region", {region_id: "missing"}), {found: false});
  const merchant = AgentRegistry.loadDefault().buildContext("lao_li", {...request, agent_id: "lao_li", active_role: "merchant"}, []);
  assert.deepEqual(executeReadTool(merchant, "inspect_market_depth", {item_id: "salt"}), {found: true, value: request.market_view.salt.depth});
  const legacy = context();
  legacy.public_world_state.regions = [{region_id: "old", description: "Legacy region"}];
  assert.equal(executeReadTool(legacy, "inspect_region", {region_id: "old"}).found, true);
});

test("autonomous triggers retain thinking across reads even with concise population planning", async () => {
  for (const trigger of ["event", "schedule", "catch_up"] as const) {
    const ctx = context();
    ctx.actor_context.planning_limits = {concise: true, daily_private_requests: 16, used: 1};
    await scenario([[read], [speak]], async (provider, bodies) => {
      const reasoning: string[] = [];
      const result = await provider.streamDecision({...request, trigger}, ctx, event => {
        if (event.type === "reasoning") reasoning.push(event.delta);
      });
      assert.equal(result.actions.length, 1);
      assert.deepEqual(bodies.map(body => body.enable_thinking), [true, true], trigger);
      assert.deepEqual(reasoning, ["检查当前事件。", "检查当前事件。"], trigger);
    });
  }
});

test("private negotiation stays voluntary, bounded and explicit about cargo ownership", async () => {
  const ctx = context();
  ctx.actor_context.living_world = {work: {contracts: [{status: "proposed", employer: "lao_li", accepted_by: ["lao_li"], terms: {worker_id: request.agent_id, kind: "delivery"}}]}};
  await scenario([[speak, speak], [speak]], async (provider, bodies) => {
    const intent = await provider.decide(request, ctx);
    assert.equal(intent.actions.length, 1);
    assert.equal(bodies[0].enable_thinking, true);
    assert.equal(bodies[1].enable_thinking, false);
    assert.match(bodies[0].messages[0].content, /EMPLOYER supplies cargo/);
    assert.match(bodies[0].messages[0].content, /not required to accept/);
    assert.deepEqual(bodies[0].tools.filter((tool: any) => tool.function.name === "speak").length, 1);
  });
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
