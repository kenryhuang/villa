import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { MemoryRepository } from "../src/memory.ts";
import { AgentRegistry } from "../src/agents.ts";
import { createApp } from "../src/app.ts";
import { ChatIntentWorker } from "../src/chat/intent_worker.ts";
import { LocalChatProvider } from "../src/chat/provider.ts";
import { intentDiagnostics } from "../src/chat/intent_diagnostics.ts";
import {
  buildIntentContext,
  parseIntents,
} from "../src/chat/intent_extraction.ts";

const job = {
  actor: "farmer_ahe",
  player: "请卖给我两条鱼。",
  reply: "我先确认库存，还没有答应交易。",
  request_id: "trace-job",
  session_id: "trace-save",
  session_epoch: 1,
  game_minute: 10,
  room: "room",
  generation: "",
};
const valid = {
  kind: "trade",
  status: "requested",
  target: "玩家",
  place: "",
  activity: "购买",
  item: "鱼",
  quantity: 2,
  gold: null,
  topic: "",
  detail: "玩家请求买两条鱼，尚未确认",
  player_evidence: "两条鱼",
  actor_evidence: "没有答应交易",
};

test("async diagnostics retain actual model input and raw invalid output after reply lifetime, with exact field error", async () => {
  const memory = new MemoryRepository(":memory:");
  memory.syncSession(job.session_id, 1);
  let release!: () => void, entered!: () => void;
  const gate = new Promise<void>((r) => (release = r)),
    started = new Promise<void>((r) => (entered = r));
  const raw = JSON.stringify({ intents: [{ ...valid, place: null }] });
  let sent: any;
  const upstream = createServer(async (req, res) => {
    let text = "";
    for await (const c of req) text += c;
    sent = JSON.parse(text);
    entered();
    await gate;
    res.setHeader("content-type", "application/json");
    res.end(
      JSON.stringify({
        choices: [{ message: { content: raw }, finish_reason: "stop" }],
      }),
    );
  });
  await new Promise<void>((r) => upstream.listen(0, "127.0.0.1", r));
  const provider = new LocalChatProvider({
    baseUrl: `http://127.0.0.1:${(upstream.address() as any).port}/v1`,
    apiKey: "SECRET_NOT_IN_DIAGNOSTICS",
    model: "test-chat",
    temperature: 0,
    maxConcurrency: 1,
    maxOutputTokens: 500,
    timeoutMs: 3000,
  });
  const worker = new ChatIntentWorker(memory, provider);
  const server = createServer(
    createApp({
      memory,
      registry: AgentRegistry.loadDefault(),
      checkpointRoot: ".",
      provider: {
        decide: async () => {
          throw Error("unused");
        },
      },
    }),
  );
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const query = (actor = job.actor, epoch = 1) =>
    fetch(
      `http://127.0.0.1:${(server.address() as any).port}/v1/chat/intent-trace`,
      {
        method: "POST",
        body: JSON.stringify({
          session_id: job.session_id,
          session_epoch: epoch,
          agent_id: actor,
          request_id: job.request_id,
        }),
      },
    );
  try {
    worker.enqueue(job);
    await started;
    const running: any = await (await query()).json();
    assert.equal(running.status, "running");
    assert.deepEqual(running.calls[0].input, sent);
    assert.deepEqual(running.prepared_messages, buildIntentContext(job));
    assert.equal(running.raw_messages[0].content, job.player);
    assert.deepEqual(running.calls[0].output, {});
    assert.doesNotMatch(JSON.stringify(running), /SECRET_NOT/);
    release();
    for (let i = 0; i < 100 && memory.pendingIntentJobs().length; i++)
      await new Promise((r) => setTimeout(r, 5));
    const failed: any = await (await query()).json();
    assert.equal(failed.status, "failed");
    assert.equal(failed.calls[0].output.message.content, raw);
    assert.match(failed.validation.error, /intents\[0\]\.place.*actual=null/);
    assert.deepEqual(failed.accepted, []);
    assert.equal(memory.pendingIntentJobs().length, 0);
    await worker.drain();
    assert.equal(
      memory.intentJobErrorCount(job.session_id, job.actor, job.request_id),
      1,
    );
    assert.equal(
      ((await (await query("lao_li")).json()) as any).status,
      "not_recorded",
    );
    assert.equal((await query(job.actor, 2)).status, 409);
  } finally {
    release();
    worker.close();
    server.closeAllConnections();
    upstream.closeAllConnections();
    await Promise.all([
      new Promise<void>((r) => server.close(() => r())),
      new Promise<void>((r) => upstream.close(() => r())),
    ]);
    memory.close();
  }
});

test("successful, empty, queued and budget-blocked extractions are distinct and retain source messages", async () => {
  const memory = new MemoryRepository(":memory:");
  memory.syncSession(job.session_id, 1);
  let mode = "valid";
  const provider: any = {
    model: "test",
    extractIntents: async () => {
      if (mode === "budget") throw Error("provider_daily_budget_exhausted");
      return mode === "valid"
        ? parseIntents(JSON.stringify({ intents: [valid] }), job)
        : [];
    },
  };
  const worker = new ChatIntentWorker(memory, provider);
  try {
    for (const state of ["valid", "empty", "budget"]) {
      mode = state;
      const next = { ...job, request_id: state };
      worker.enqueue(next);
      assert.equal(
        intentDiagnostics(memory, job.session_id, job.actor, state).status,
        "queued",
      );
      await worker.drain();
      const report = intentDiagnostics(
        memory,
        job.session_id,
        job.actor,
        state,
      );
      assert.equal(
        report.status,
        state === "valid"
          ? "completed"
          : state === "empty"
            ? "empty"
            : "failed",
      );
      assert.equal(report.archived, state === "valid");
      if (state === "budget") assert.match(report.error!, /daily_budget/);
    }
    assert.equal(memory.pendingIntentJobs().length, 0);
    assert.deepEqual(memory.agentEventFeed(job.session_id, 0).events.map(e => e.event_id), ["chat-intents:valid"], "only successful nonempty extractions publish action events");
  } finally {
    worker.close();
    memory.close();
  }
});
