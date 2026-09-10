import assert from "node:assert/strict";
import {createServer} from "node:http";
import test from "node:test";
import {ProviderConcurrencyGate} from "../src/provider_concurrency_gate.ts";
import {OpenAICompatibleProvider, buildDialogueContext} from "../src/provider.ts";
import {executeReadTool} from "../src/tool_contracts.ts";
import {AgentRegistry} from "../src/agents.ts";
import {readFileSync} from "node:fs";

function deferred<T = void>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => resolve = done);
  return {promise, resolve};
}

for (const limit of [1, 2, 5]) {
  test(`dialogue preempts a running background round at concurrency ${limit} and resumes it safely`, {timeout: 3000}, async () => {
    const gate = new ProviderConcurrencyGate(limit);
    const stop = new AbortController();
    const started = Array.from({length: limit}, () => deferred());
    const finish = deferred();
    const order: string[] = [];
    let active = 0;
    let peak = 0;
    let preemptions = 0;
    const jobs = started.map((ready, id) => {
      let attempts = 0;
      return gate.run(stop.signal, async (signal) => {
        attempts += 1; active += 1; peak = Math.max(peak, active);
        ready.resolve();
        try {
          if (attempts === 1) await new Promise<void>((resolve, reject) => {
            const abort = () => { preemptions += 1; reject(signal.reason); };
            signal.addEventListener("abort", abort, {once: true});
            if (signal.aborted) abort();
            finish.promise.then(() => { signal.removeEventListener("abort", abort); resolve(); });
          });
          else await finish.promise;
          return `background-${id}`;
        } finally { active -= 1; }
      });
    });
    try {
      await Promise.all(started.map((ready) => ready.promise));
      const queued = gate.run(stop.signal, async () => { order.push("queued-background"); return "queued"; });
      const dialogue = gate.run(stop.signal, async () => { active += 1; peak = Math.max(peak, active); order.push("dialogue"); active -= 1; return "reply"; }, "dialogue");
      assert.equal(await dialogue, "reply");
      assert.equal(order[0], "dialogue");
      assert.equal(preemptions, 1);
      assert.ok(peak <= limit);
      finish.resolve();
      assert.deepEqual(await Promise.all(jobs), started.map((_, id) => `background-${id}`));
      assert.equal(await queued, "queued");
    } finally {
      stop.abort(); finish.resolve(); await Promise.allSettled(jobs);
    }
  });
}

test("cancelled background work is not resurrected after dialogue preemption", {timeout: 3000}, async () => {
  const gate = new ProviderConcurrencyGate(1);
  const stop = new AbortController();
  const started = deferred();
  let attempts = 0;
  const background = gate.run(stop.signal, async (signal) => {
    attempts += 1; started.resolve();
    await new Promise((_, reject) => signal.addEventListener("abort", () => {
      stop.abort(new Error("game_closed")); reject(signal.reason);
    }, {once: true}));
  });
  const rejected = assert.rejects(background, /game_closed/);
  await started.promise;
  assert.equal(await gate.run(undefined, async () => "reply", "dialogue"), "reply");
  await rejected;
  assert.equal(attempts, 1);
});

function fixture() {
  return JSON.parse(readFileSync("../../shared/agent_protocol/v2/decision-request.json", "utf8"));
}

test("compact dialogue retains intent and terms, while inspect tools retain full data", () => {
  const request = fixture();
  request.allowed_read_tools = ["inspect_building", "inspect_known_actor"];
  request.actor_context.world_map = {regions: [{id: "farm"}]};
  request.actor_context.player_buildings = [{building_id: "mill", owner_id: "player", production: {maintenance_state: "overdue", service_records: {history: "large-history".repeat(10000)}}}];
  request.actor_context.living_world = {project: {id: "p1", status: "active", reason: "queue_full", plan: {goal: "Make flour for the inn"}, steps: {mill: {status: "blocked", error: "queue_full"}}}, recent_projects: []};
  request.known_actors = [{actor_id: "player", display_name: "玩家", recent_public_events: [{text: "large-event".repeat(10000)}]}];
  const context = AgentRegistry.loadDefault().buildContext(request.agent_id, request, []);
  const before = JSON.stringify(context);
  const compact = buildDialogueContext(context);
  assert.ok(JSON.stringify(compact).length < before.length / 10);
  assert.equal((compact.actor_context.living_world as any).project.plan.goal, "Make flour for the inn");
  assert.deepEqual((compact.actor_context.living_world as any).project, request.actor_context.living_world.project);
  assert.equal((compact.actor_context.living_world as any).project.steps.mill.error, "queue_full");
  assert.deepEqual(compact.interaction_view, context.interaction_view);
  assert.deepEqual(compact.agreement_view, context.agreement_view);
  assert.equal((compact.actor_context.player_buildings as any[])[0].production.maintenance_state, "overdue");
  assert.equal((executeReadTool(context, "inspect_building", {building_id: "mill"}).value as any).production.service_records.history, request.actor_context.player_buildings[0].production.service_records.history);
  assert.equal(JSON.stringify(context), before);
});

test("a real Provider dialogue bypasses busy background HTTP without committing its partial command", {timeout: 5000}, async () => {
  const firstStarted = deferred();
  const bodies: any[] = [];
  const stop = new AbortController();
  const server = createServer((incoming, response) => {
    let body = "";
    incoming.setEncoding("utf8");
    incoming.on("data", (chunk) => body += chunk);
    incoming.on("end", () => {
      const value = JSON.parse(body); bodies.push(value);
      response.setHeader("content-type", "text/event-stream");
      if (bodies.length === 1) {
        response.write(`data: ${JSON.stringify({id: "unfinished", choices: [{delta: {tool_calls: [{index: 0, id: "never-commit", type: "function", function: {name: "speak", arguments: JSON.stringify({target_actor_id: "player", text: "Unfinished"})}}]}, finish_reason: null}]})}\n\n`);
        firstStarted.resolve();
        return;
      }
      const dialogue = value.enable_thinking === false;
      response.end(`data: ${JSON.stringify({id: dialogue ? "dialogue" : "resumed", choices: [{delta: {content: dialogue ? "我正在等面粉加工，今天也想聊聊你的计划。" : "Background finished"}, finish_reason: "stop"}]})}\n\ndata: [DONE]\n\n`);
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object");
  const provider = new OpenAICompatibleProvider({baseUrl: `http://127.0.0.1:${address.port}`, apiKey: "test", model: "test", timeoutMs: 2000, maxConcurrency: 1, maxOutputTokens: 1200, temperature: 0});
  const request = fixture(); request.allowed_command_tools = ["speak"];
  const context = AgentRegistry.loadDefault().buildContext(request.agent_id, request, []);
  const background = provider.streamDecision(request, context, () => {}, stop.signal);
  try {
    await firstStarted.promise;
    const result = await provider.decide({...request, request_id: "dialogue-priority", trigger: "dialogue", dialogue_input: "你在做什么呢？"}, context);
    assert.match(result.speech || "", /面粉/);
    assert.equal(bodies[1].enable_thinking, false);
    assert.deepEqual((await background).actions, []);
    assert.equal(bodies.length, 3);
  } finally {
    stop.abort(); await Promise.allSettled([background]);
    server.closeAllConnections(); await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
