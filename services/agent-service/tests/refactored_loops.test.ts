import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { AgentRegistry } from "../src/agents.ts";
import { parseDecisionRequest, type DecisionRequest } from "../src/protocol.ts";
import { runAgentLoop } from "../src/agent_loop.ts";
import { AgentStreamAssembler } from "../src/provider_stream.ts";
import { MemoryRepository } from "../src/memory.ts";
import { ChatIntentWorker } from "../src/chat/intent_worker.ts";
import {
  buildIntentContext,
  parseIntents,
} from "../src/chat/intent_extraction.ts";
import { actionActor, appendIsolatedEvent } from "../src/context_channels.ts";
import { createApp } from "../src/app.ts";
import { ActionBroker } from "../src/transport/action_broker.ts";
import { selectDialogueContext } from "../src/memory/dialogue_context.ts";
import { ProviderBudget } from "../src/budget/provider_budget.ts";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { LocalChatProvider } from "../src/chat/provider.ts";

function request(id = "refactor"): DecisionRequest {
  const parsed = parseDecisionRequest({
    protocol_version: 3,
    tool_execution: "inline",
    request_id: id,
    session_id: "save",
    session_epoch: 1,
    agent_id: "farmer_ahe",
    trigger: "schedule",
    game_minute: 10,
    world_revision: 1,
    active_role: "farmer",
    goals: [],
    allowed_command_tools: ["plant", "wait", "speak"],
    resources: { gold: 30, inventory: { grain_seed: 2 }, resource_revision: 1 },
    experience_events: [],
    goal_refs: [],
  });
  assert.ok(parsed.ok);
  return parsed.value;
}
function response(
  calls: { name: string; args: Record<string, unknown> }[] = [],
  content = "",
) {
  const a = new AgentStreamAssembler();
  a.accept({
    id: "reply",
    choices: [
      {
        index: 0,
        delta: {
          content,
          tool_calls: calls.map((c, index) => ({
            index,
            id: `call-${index}`,
            type: "function",
            function: { name: c.name, arguments: JSON.stringify(c.args) },
          })),
        },
        finish_reason: calls.length ? "tool_calls" : "stop",
      },
    ],
  });
  return a;
}

test("inline loop executes multiple calls in order, feeds errors and reflects without replaying actions", async () => {
  const r = request(),
    ctx = AgentRegistry.loadDefault().buildContext(r.agent_id, r, []);
  const seen: string[] = [],
    keys: string[] = [];
  let round = 0;
  const result = await runAgentLoop(
    r,
    ctx,
    {
      experience: {},
      memories: [],
      core_memories: [{ summary: "保留种子" }],
      confirmed_dialogue: [
        { intents: [{ kind: "trade", status: "proposed" }] },
      ],
      read: async () => {
        seen.push("read");
        return { resources: { gold: 20, inventory: { grain_seed: 1 } } };
      },
      execute: async (action) => {
        seen.push(String(action.arguments.plot));
        keys.push(action.idempotency_key);
        return action.arguments.plot === 0
          ? { ok: false, status: "rejected", failure_code: "plot_occupied" }
          : { ok: true, status: "completed" };
      },
    },
    async (messages, tools) => {
      round++;
      const header = JSON.parse(String(messages[1].content));
      assert.equal(header.core_memories[0].summary, "保留种子");
      assert.equal(
        header.turn.confirmed_dialogue[0].intents[0].status,
        "proposed",
      );
      if (round === 1)
        return response([
          { name: "discover_tools", args: { domains: ["farm"] } },
        ]);
      if (round === 2)
        return response([
          { name: "plant", args: { plot: 0, seed_item_id: "grain_seed" } },
          { name: "inspect_self_resources", args: {} },
          { name: "plant", args: { plot: 1, seed_item_id: "grain_seed" } },
        ]);
      if (round === 3) {
        assert.deepEqual(seen, ["0", "read", "1"]);
        assert.match(JSON.stringify(messages), /plot_occupied/);
        assert.equal(header.resources.gold, 20);
        assert.equal(header.turn.budget.max_actions, 1);
        assert.equal(header.turn.executed_actions.length, 2);
        assert.equal(header.turn.executed_actions[0].status, "rejected");
        const toolMessages = messages.filter((m) => m.role === "tool");
        assert.equal(toolMessages.length, 4);
        return response([
          { name: "plant", args: { plot: 2, seed_item_id: "grain_seed" } },
        ]);
      }
      assert.equal(header.turn.budget.max_actions, 0);
      assert.ok(!tools.some((t) => (t.function as any).name === "plant"));
      return response([], "处理完成");
    },
    () => {},
  );
  assert.equal(round, 4);
  assert.equal(result.actions.length, 0);
  assert.equal(new Set(keys).size, 3);
});

test("read exceptions become tool results and model can recover", async () => {
  const r = request();
  let step = 0;
  await runAgentLoop(
    r,
    AgentRegistry.loadDefault().buildContext(r.agent_id, r, []),
    {
      experience: {},
      memories: [],
      execute: async () => ({}),
      read: async () => {
        throw new Error("world_temporarily_unavailable");
      },
    },
    async (messages) => {
      if (step++ === 0)
        return response([{ name: "inspect_self_resources", args: {} }]);
      assert.match(JSON.stringify(messages), /world_temporarily_unavailable/);
      return response();
    },
    () => {},
  );
  assert.equal(step, 2);
});

test("intent extraction includes latest turn only and preserves trade, activities and information semantics", () => {
  const turn = {
    actor: "a",
    player: "去南湖钓鱼，顺便买两条鱼，问问鱼价。",
    reply: "好，去南湖钓鱼。鱼价我还不知道。",
  };
  const base = {
    target: "玩家",
    place: "南湖",
    activity: "钓鱼",
    item: "鱼",
    quantity: 2,
    gold: null,
    topic: "鱼价",
    detail: "玩家希望买两条鱼并询价",
    player_evidence: "问问鱼价",
    actor_evidence: "鱼价我还不知道",
  };
  const values = [
    { ...base, kind: "activity", status: "confirmed" },
    { ...base, kind: "trade", status: "requested" },
    { ...base, kind: "information_request", status: "requested" },
    { ...base, kind: "information", status: "stated" },
  ];
  const parsed = parseIntents(JSON.stringify({ intents: values }), turn);
  assert.equal(parsed.length, 4);
  assert.equal(parsed[1].gold, null);
  assert.ok(!("player_evidence" in parsed[0]));
  assert.equal(buildIntentContext(turn).length, 2);
  assert.throws(
    () =>
      parseIntents(
        JSON.stringify({
          intents: [{ ...values[0], actor_evidence: "OLD_HISTORY" }],
        }),
        turn,
      ),
    /evidence/,
  );
});

test("chat HTTP completes while extraction is blocked; durable intents accumulate and cannot be forged", async () => {
  const memory = new MemoryRepository(":memory:"),
    registry = AgentRegistry.loadDefault();
  let release!: () => void, entered!: () => void;
  const started = new Promise<void>((r) => (entered = r)),
    blocked = new Promise<void>((r) => (release = r));
  const r = request("chat-async");
  r.trigger = "dialogue";
  r.dialogue_input = "去南湖";
  const intent = {
    kind: "visit" as const,
    status: "confirmed" as const,
    target: "玩家",
    place: "南湖",
    activity: "散步",
    item: "",
    quantity: null,
    gold: null,
    topic: "",
    detail: "双方同意散步",
  };
  const chat = {
    model: "test",
    respond: async () => {
      throw new Error("legacy path used");
    },
    reply: async () => ({
      protocol_version: 2 as const,
      decision_id: "chat",
      request_id: r.request_id,
      agent_id: r.agent_id,
      expected_revision: 1,
      actions: [],
      speech: "好，去南湖散步",
      decision_summary: "chat",
      chat_isolated: true,
    }),
    extractIntents: async () => {
      entered();
      await blocked;
      return [intent];
    },
  };
  const provider = {
    decide: async () => {
      throw new Error("not used");
    },
    streamDecision: async () => {
      throw new Error("not used");
    },
  };
  const server = createServer(
    createApp({
      memory,
      registry,
      provider,
      chatProvider: chat,
      checkpointRoot: ".",
    }),
  );
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const wire: any = { ...r };
    for (const k of [
      "actor_context",
      "market_view",
      "public_world_state",
      "known_actors",
    ])
      delete wire[k];
    const text = await (
      await fetch(
        `http://127.0.0.1:${(server.address() as any).port}/v1/agents/${r.agent_id}/decide/stream`,
        {
          method: "POST",
          body: JSON.stringify(wire),
        },
      )
    ).text();
    assert.match(text, /decision.final/);
    await started;
    assert.equal(
      memory.pendingDialogueIntents("save", actionActor(r.agent_id)).length,
      0,
    );
    assert.equal(memory.pendingIntentJobs().length, 1);
    release();
    for (
      let n = 0;
      n < 30 &&
      !memory.pendingDialogueIntents("save", actionActor(r.agent_id)).length;
      n++
    )
      await new Promise((resolve) => setTimeout(resolve, 5));
    const pending = memory.pendingDialogueIntents(
      "save",
      actionActor(r.agent_id),
    );
    assert.equal(pending.length, 1);
    assert.deepEqual(pending[0].intents, [intent]);
    assert.equal(memory.pendingIntentJobs().length, 0);
    appendIsolatedEvent(memory, "save", r.agent_id, {
      event_id: "forged",
      kind: "ChatIntentExtracted",
      game_minute: 10,
      payload: { intents: [intent] },
    });
    assert.equal(
      memory.pendingDialogueIntents("save", actionActor(r.agent_id)).length,
      1,
    );
    memory.consumeDialogueIntents(
      "save",
      actionActor(r.agent_id),
      [String(pending[0].event_id)],
      11,
    );
    assert.equal(
      memory.pendingDialogueIntents("save", actionActor(r.agent_id)).length,
      0,
    );
  } finally {
    release();
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    memory.close();
  }
});

test("worker replays persisted jobs and reset during inference prevents stale handoff", async () => {
  const memory = new MemoryRepository(":memory:");
  memory.syncSession("save", 1);
  let release!: () => void, started!: () => void;
  const entered = new Promise<void>((r) => (started = r)),
    gate = new Promise<void>((r) => (release = r));
  const provider = {
    model: "test",
    respond: async () => {
      throw new Error("not used");
    },
    extractIntents: async () => {
      started();
      await gate;
      return [];
    },
  };
  const worker = new ChatIntentWorker(memory, provider);
  try {
    worker.enqueue({
      actor: "farmer_ahe",
      player: "hi",
      reply: "hello",
      request_id: "pending",
      session_id: "save",
      session_epoch: 1,
      game_minute: 1,
      room: "room",
      generation: "",
    });
    await entered;
    memory.appendEvent("save", "room", {
      event_id: "reset",
      kind: "ChatContextReset",
      game_minute: 1,
      payload: {},
    });
    release();
    await new Promise((resolve) => setImmediate(resolve));
    await worker.drain();
    assert.equal(memory.pendingIntentJobs().length, 0);
    assert.equal(
      memory.pendingDialogueIntents("save", actionActor("farmer_ahe")).length,
      0,
    );
  } finally {
    release();
    worker.close();
    memory.close();
  }
});

test("queued extraction survives a new epoch but discards the old in-flight result", async () => {
  const memory = new MemoryRepository(":memory:");
  memory.syncSession("save", 1);
  let release!: () => void, started!: () => void;
  const entered = new Promise<void>((resolve) => {
    started = resolve;
  });
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  let calls = 0;
  const worker = new ChatIntentWorker(memory, {
    model: "test",
    extractIntents: async () => {
      if (++calls === 1) {
        started();
        await gate;
      }
      return [];
    },
  });
  try {
    worker.enqueue({
      actor: "farmer_ahe",
      player: "hi",
      reply: "hello",
      request_id: "epoch-job",
      session_id: "save",
      session_epoch: 1,
      game_minute: 1,
      room: "room",
      generation: "",
    });
    await entered;
    memory.syncSession("save", 2);
    release();
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(memory.pendingIntentJobs().length, 1);
    await worker.drain();
    assert.equal(calls, 2);
    assert.equal(memory.pendingIntentJobs().length, 0);
  } finally {
    release();
    worker.close();
    memory.close();
  }
});

test("core memory is scoped by save and actor, with source validation", () => {
  const memory = new MemoryRepository(":memory:");
  try {
    memory.appendEvent("s", "a", {
      event_id: "source",
      kind: "GoalAdopted",
      game_minute: 1,
      payload: {},
    });
    memory.storeCoreMemory("s", "a", "promise", "答应交付粮食", ["source"], 1);
    assert.equal(memory.coreMemories("s", "a").length, 1);
    assert.equal(memory.coreMemories("s", "b").length, 0);
    assert.equal(memory.coreMemories("other", "a").length, 0);
    assert.throws(
      () =>
        memory.storeCoreMemory("s", "b", "promise", "假记忆", ["source"], 1),
      /invalid_core_memory/,
    );
  } finally {
    memory.close();
  }
});

test("action broker waits for completion, rejects cross-actor receipts and handles cancellation", async () => {
  const broker = new ActionBroker(),
    r = request(),
    controller = new AbortController();
  let settled = false;
  const action = {
    action_id: "a",
    idempotency_key: "key",
    tool_name: "wait",
    tool_version: 1 as const,
    arguments: { reason: "test" },
  };
  const pending = broker
    .execute(r, action, () => {}, controller.signal)
    .then((v) => {
      settled = true;
      return v;
    });
  const outcome = {
    protocol_version: 2 as const,
    decision_id: "step",
    action_id: "a",
    idempotency_key: "key",
    status: "in_progress" as const,
    committed_revision: 1,
    changed_entities: [],
    resource_delta: {},
    hud_message: "",
    game_minute: 10,
  };
  assert.equal(broker.accept("save", "other", outcome), false);
  assert.equal(broker.accept("save", r.agent_id, outcome), true);
  await Promise.resolve();
  assert.equal(settled, false);
  broker.accept("save", r.agent_id, { ...outcome, status: "completed" });
  assert.equal((await pending).ok, true);
  const next = broker.execute(
    r,
    { ...action, idempotency_key: "next" },
    () => {},
    controller.signal,
  );
  controller.abort();
  await assert.rejects(next, /cancelled/);
});

test("intent backlog keeps latest cancellation visible and does not consume arrivals from a later turn", () => {
  const memory = new MemoryRepository(":memory:");
  try {
    for (let i = 0; i < 12; i++)
      memory.appendEvent("s", "a", {
        event_id: `intent-${i}`,
        kind: "ChatIntentExtracted",
        game_minute: i,
        payload: {
          intents: [
            {
              kind: "visit",
              status: i === 11 ? "cancelled" : "confirmed",
              place: "南湖",
            },
          ],
        },
      });
    const first = memory.pendingDialogueIntents("s", "a");
    assert.equal(first.length, 9);
    assert.equal(first[0].event_id, "intent-0");
    assert.equal(first.at(-1)!.context_only, true);
    memory.appendEvent("s", "a", {
      event_id: "new",
      kind: "ChatIntentExtracted",
      game_minute: 20,
      payload: { intents: [] },
    });
    memory.consumeDialogueIntents(
      "s",
      "a",
      first.filter((e) => !e.context_only).map((e) => String(e.event_id)),
      20,
    );
    assert.deepEqual(
      memory.pendingDialogueIntents("s", "a").map((e) => e.event_id),
      ["intent-8", "intent-9", "intent-10", "intent-11", "new"],
    );
    const huge = {
      event_id: "large",
      game_minute: 1,
      source: "latest_dialogue_turn",
      intents: [{ detail: "来源事实".repeat(5000) }],
    };
    const bounded = selectDialogueContext([huge], 1000);
    assert.equal(bounded[0].details_available, true);
    assert.equal(bounded[0].event_id, "large");
    assert.ok(!bounded[0].intents);
  } finally {
    memory.close();
  }
});

test("checkpoint preserves pending extraction and core memory and rolls back later results", () => {
  const directory = mkdtempSync(join(tmpdir(), "loop-refactor-checkpoint-"));
  const memory = new MemoryRepository(join(directory, "db.sqlite"));
  try {
    memory.syncSession("s", 1);
    memory.appendEvent("s", "a", {
      event_id: "source",
      kind: "GoalAdopted",
      game_minute: 1,
      payload: {},
    });
    memory.storeCoreMemory("s", "a", "promise", "兑现承诺", ["source"], 1);
    memory.appendEvent("s", "chat.jobs:a", {
      event_id: "job",
      kind: "ChatIntentPending",
      game_minute: 1,
      payload: { session_id: "s", actor: "a" },
    });
    const checkpoint = memory.exportCheckpoint("s", directory, "refactor");
    memory.appendEvent("s", "chat.jobs:a", {
      event_id: "done",
      kind: "ChatIntentFinished",
      game_minute: 2,
      payload: { job_id: "job" },
    });
    assert.equal(memory.pendingIntentJobs().length, 0);
    memory.importCheckpoint(checkpoint.path, checkpoint.sha256, "s");
    assert.equal(memory.pendingIntentJobs().length, 1);
    assert.equal(memory.coreMemories("s", "a")[0].summary, "兑现承诺");
  } finally {
    memory.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test("provider reservation survives restart, blocks excess calls and resets only on a later game day", () => {
  const directory = mkdtempSync(join(tmpdir(), "loop-refactor-budget-"));
  try {
    const path = join(directory, "budget.json"),
      scope = { session_id: "save", game_minute: 1080 };
    const budget = new ProviderBudget(path);
    budget.reserve(scope, { max_tokens: 7_980_000 });
    const restarted = new ProviderBudget(path);
    assert.equal(restarted.reserved("save"), budget.reserved("save"));
    assert.throws(
      () => restarted.reserve(scope, { max_tokens: 50000 }),
      /daily_budget/,
    );
    assert.throws(
      () =>
        restarted.reserve({ ...scope, game_minute: 0 }, { max_tokens: 50000 }),
      /daily_budget/,
    );
    restarted.reserve({ ...scope, game_minute: 2160 }, { max_tokens: 50000 });
    assert.ok(restarted.reserved("save") < 100000);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("chat model reply and async extractor use separate prompts with no world-read dependency", async () => {
  const inputs: any[] = [];
  const turn = {
    actor: "farmer_ahe",
    player: "可以买两条鱼吗？",
    reply: "让我先确认鱼的库存。",
    session_id: "s",
    game_minute: 10,
  };
  const extracted = {
    kind: "trade",
    status: "requested",
    target: "玩家",
    place: "",
    activity: "购买",
    item: "鱼",
    quantity: 2,
    gold: null,
    topic: "",
    detail: "玩家请求购买两条鱼，NPC尚未确认",
    player_evidence: "买两条鱼",
    actor_evidence: "先确认鱼的库存",
  };
  const server = createServer(async (req, res) => {
    let source = "";
    for await (const chunk of req) source += chunk;
    const body = JSON.parse(source);
    inputs.push(body);
    if (body.stream) {
      res.setHeader("content-type", "text/event-stream");
      res.end(
        `data: ${JSON.stringify({ choices: [{ delta: { content: turn.reply }, finish_reason: "stop" }] })}\n\ndata: [DONE]\n\n`,
      );
    } else {
      res.setHeader("content-type", "application/json");
      res.end(
        JSON.stringify({
          choices: [
            {
              message: { content: JSON.stringify({ intents: [extracted] }) },
              finish_reason: "stop",
            },
          ],
        }),
      );
    }
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    // Same endpoint shape accepted by the action client, including an explicit completions suffix.
    const provider = new LocalChatProvider({
      baseUrl: `http://127.0.0.1:${(server.address() as any).port}/v1/chat/completions`,
      apiKey: "test",
      model: "chat",
      maxConcurrency: 1,
      timeoutMs: 2000,
      maxOutputTokens: 800,
      temperature: 0,
    });
    const r = request();
    r.trigger = "dialogue";
    r.dialogue_input = turn.player;
    const reply = await provider.reply(
      r,
      AgentRegistry.loadDefault().buildContext(r.agent_id, r, []),
      [],
      [],
      () => {},
    );
    assert.equal(reply.speech, turn.reply);
    assert.equal(inputs.length, 1);
    assert.deepEqual(reply.actions, []);
    const intents = await provider.extractIntents(turn, () => {});
    assert.equal(intents[0].status, "requested");
    assert.equal(intents[0].quantity, 2);
    assert.equal(inputs.length, 2);
    assert.ok(inputs.every((b) => !b.tools));
    assert.equal(inputs[1].stream, false);
    assert.deepEqual(JSON.parse(inputs[1].messages[1].content), {
      speaker: turn.actor,
      current_player_message: turn.player,
      current_npc_reply: turn.reply,
    });
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
