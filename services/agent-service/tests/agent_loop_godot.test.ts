import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createApp } from "../src/app.ts";
import { AgentRegistry } from "../src/agents.ts";
import { MemoryRepository } from "../src/memory.ts";
import { OpenAICompatibleProvider } from "../src/provider.ts";
import { LocalChatProvider } from "../src/chat/provider.ts";

test("Godot collects dialogue events while paused and drains them with one slot without clock ticks", {skip: process.env.RUN_GODOT_LOOP_TEST !== "1", timeout: 40000}, async () => {
  const memory = new MemoryRepository(":memory:");
  memory.syncSession("event-wire", 42);
  for (const actor of ["farmer_ahe", "lao_li"]) memory.appendEvent("event-wire", `action.v2:${actor}`, {
    event_id: `chat-intents:${actor}`, kind: "ChatIntentExtracted", game_minute: 0,
    payload: {source_request_id: actor, intents: [{kind:"information",status:"stated",detail:"玩家说今天有活动",topic:"活动"}]},
  });
  const headers: any[] = [];
  const model = createServer(async (req, res) => {
    let source = ""; for await (const chunk of req) source += chunk;
    const body = JSON.parse(source);
    if (!body.stream) { res.end(JSON.stringify({choices:[{message:{content:'{"summary":"测试事件","importance":1}'}}]})); return; }
    headers.push(JSON.parse(body.messages[1].content));
    res.writeHead(200, {"content-type":"text/event-stream"});
    res.end(`data: ${JSON.stringify({choices:[{index:0,delta:{content:"已收到事件。"},finish_reason:"stop"}]})}\n\ndata: [DONE]\n\n`);
  });
  await new Promise<void>(r => model.listen(0, "127.0.0.1", r));
  const options = {baseUrl:`http://127.0.0.1:${(model.address() as any).port}`,apiKey:"test",model:"test",timeoutMs:4000,maxConcurrency:2,maxOutputTokens:300,temperature:0};
  const service = createServer(createApp({memory,registry:AgentRegistry.loadDefault(),provider:new OpenAICompatibleProvider(options),chatProvider:new LocalChatProvider(options),checkpointRoot:"."}));
  await new Promise<void>(r => service.listen(0, "127.0.0.1", r));
  try {
    const result = await new Promise<{code:number|null;text:string}>((done, reject) => {
      const child = spawn("godot_console.exe", ["--headless","--path",".","--script","tests/run_agent_events_wire.gd","--","--farm-test",`--loop-service=http://127.0.0.1:${(service.address() as any).port}`], {cwd:resolve("../.."),windowsHide:true});
      let text = "";
      child.stdout.on("data", b => text += b); child.stderr.on("data", b => text += b);
      child.on("error", reject); child.on("close", code => done({code,text}));
    });
    assert.equal(result.code, 0, result.text);
    assert.match(result.text, /EVENT_WIRE_OK/);
    assert.equal(headers.length, 2);
    assert.deepEqual(headers.map(h => h.turn.trigger_events[0].event_id), ["chat-intents:farmer_ahe","chat-intents:lao_li"]);
    for (const h of headers) assert.equal(h.turn.confirmed_dialogue.length, 1);
    assert.deepEqual(memory.agentEventFeed("event-wire", 0).events, [], "successful action loops consume delivered dialogue intentions");
  } finally {
    service.closeAllConnections(); model.closeAllConnections();
    await Promise.all([new Promise<void>(r => service.close(() => r())), new Promise<void>(r => model.close(() => r()))]);
    memory.close();
  }
});

// Explicit opt-in: npm test remains usable without an installed Godot binary.
test(
  "Godot paused scene exchanges lazy reads with real Agent Service",
  { skip: process.env.RUN_GODOT_LOOP_TEST !== "1", timeout: 45000 },
  async () => {
    const directory = mkdtempSync(join(tmpdir(), "godot-loop-")),
      memory = new MemoryRepository(join(directory, "db.sqlite"));
    let round = 0;
    const sizes: number[] = [];
    const model = createServer(async (req, res) => {
      const chunks = [];
      for await (const c of req) chunks.push(c);
      const body = JSON.parse(Buffer.concat(chunks).toString());
      if (!body.stream) {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(
          JSON.stringify({
            choices: [{ message: { content: JSON.stringify({ summary: "玩家曾询问自己的农田。", importance: 4 }) } }],
          }),
        );
        return;
      }
      sizes.push(Buffer.byteLength(JSON.stringify(body)));
      const call = [
        { name: "discover_tools", arguments: JSON.stringify({ domains: ["farm"] }) },
        { name: "query_world", arguments: JSON.stringify({ domain: "farm", section: "plots", limit: 1 }) },
      ][round++];
      res.writeHead(200, { "content-type": "text/event-stream" });
      res.end(
        `data: ${JSON.stringify({ id: "godot-mock", choices: [{ index: 0, delta: call ? { tool_calls: [{ index: 0, id: "call", type: "function", function: call }] } : { content: "我查到了自己的农田。" }, finish_reason: call ? "tool_calls" : "stop" }] })}\n\ndata: [DONE]\n\n`,
      );
    });
    await new Promise<void>((r) => model.listen(0, "127.0.0.1", r));
    const provider = new OpenAICompatibleProvider({
      baseUrl: `http://127.0.0.1:${(model.address() as any).port}`,
      apiKey: "test",
      model: "test",
      timeoutMs: 4000,
      maxConcurrency: 1,
      maxOutputTokens: 300,
      temperature: 0,
    });
    const service = createServer(
      createApp({ memory, registry: AgentRegistry.loadDefault(), provider, checkpointRoot: directory }),
    );
    await new Promise<void>((r) => service.listen(0, "127.0.0.1", r));
    try {
      const output = await new Promise<{ code: number | null; text: string }>((resolvePromise, reject) => {
        const child = spawn(
          "godot_console.exe",
          [
            "--headless",
            "--path",
            ".",
            "--script",
            "tests/run_agent_loop_wire.gd",
            "--",
            "--farm-test",
            `--loop-service=http://127.0.0.1:${(service.address() as any).port}`,
          ],
          { cwd: resolve("../.."), windowsHide: true },
        );
        let text = "";
        child.stdout.on("data", (b) => (text += b));
        child.stderr.on("data", (b) => (text += b));
        child.on("error", reject);
        child.on("close", (code) => resolvePromise({ code, text }));
      });
      assert.equal(output.code, 0, output.text);
      assert.equal(round, 3);
      assert.ok(sizes[0] < 16000, `initial bytes ${sizes[0]}`);
      console.log(`Godot wire verified: ${round} model rounds; initial provider body ${sizes[0]} UTF-8 bytes.`);
    } finally {
      service.closeAllConnections();
      model.closeAllConnections();
      await new Promise<void>((r) => service.close(() => r()));
      await new Promise<void>((r) => model.close(() => r()));
      memory.close();
      rmSync(directory, { recursive: true, force: true });
    }
  },
);

// Exercise the new action.request -> Godot executor -> outcome -> next model round path.
test(
  "Godot inline execution returns a receipt to the model before final decision",
  { skip: process.env.RUN_GODOT_LOOP_TEST !== "1", timeout: 45000 },
  async () => {
    const directory = mkdtempSync(join(tmpdir(), "godot-inline-")),
      memory = new MemoryRepository(join(directory, "db.sqlite"));
    let round = 0;
    const inputs: any[] = [];
    const model = createServer(async (req, res) => {
      let source = "";
      for await (const c of req) source += c;
      const body = JSON.parse(source);
      if (!body.stream) {
        res.end(
          JSON.stringify({
            choices: [{ message: { content: JSON.stringify({ summary: "执行等待。", importance: 1 }) } }],
          }),
        );
        return;
      }
      inputs.push(body);
      round++;
      const call =
        round === 1 ? { name: "wait", arguments: JSON.stringify({ reason: "test inline receipt" }) } : undefined;
      res.writeHead(200, { "content-type": "text/event-stream" });
      res.end(
        `data: ${JSON.stringify({ id: "inline-test", choices: [{ index: 0, delta: call ? { tool_calls: [{ index: 0, id: "call", type: "function", function: call }] } : { content: "我查到了自己的农田。" }, finish_reason: call ? "tool_calls" : "stop" }] })}\n\ndata: [DONE]\n\n`,
      );
    });
    await new Promise<void>((r) => model.listen(0, "127.0.0.1", r));
    const provider = new OpenAICompatibleProvider({
      baseUrl: `http://127.0.0.1:${(model.address() as any).port}`,
      apiKey: "test",
      model: "test",
      timeoutMs: 4000,
      maxConcurrency: 1,
      maxOutputTokens: 300,
      temperature: 0,
    });
    const service = createServer(
      createApp({ memory, registry: AgentRegistry.loadDefault(), provider, checkpointRoot: directory }),
    );
    await new Promise<void>((r) => service.listen(0, "127.0.0.1", r));
    try {
      const output = await new Promise<{ code: number | null; text: string }>((resolvePromise, reject) => {
        const child = spawn(
          "godot_console.exe",
          [
            "--headless",
            "--path",
            ".",
            "--script",
            "tests/run_agent_loop_wire.gd",
            "--",
            "--farm-test",
            "--inline-test",
            `--loop-service=http://127.0.0.1:${(service.address() as any).port}`,
          ],
          { cwd: resolve("../.."), windowsHide: true },
        );
        let text = "";
        child.stdout.on("data", (b) => (text += b));
        child.stderr.on("data", (b) => (text += b));
        child.on("error", reject);
        child.on("close", (code) => resolvePromise({ code, text }));
      });
      assert.equal(output.code, 0, output.text);
      assert.equal(round, 2);
      const receipt = inputs[1].messages.find((m: any) => m.role === "tool");
      assert.equal(JSON.parse(receipt.content).status, "completed");
      assert.equal(JSON.parse(inputs[1].messages[1].content).turn.budget.max_actions, 2);
    } finally {
      service.closeAllConnections();
      model.closeAllConnections();
      await new Promise<void>((r) => service.close(() => r()));
      await new Promise<void>((r) => model.close(() => r()));
      memory.close();
      rmSync(directory, { recursive: true, force: true });
    }
  },
);
