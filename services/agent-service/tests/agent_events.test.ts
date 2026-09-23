import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { MemoryRepository } from "../src/memory.ts";
import { AgentRegistry } from "../src/agents.ts";
import { createApp } from "../src/app.ts";
import { parseDecisionRequest } from "../src/protocol.ts";
import { runAgentLoop } from "../src/agent_loop.ts";
import { AgentStreamAssembler } from "../src/provider_stream.ts";

test("dialogue event outbox paginates in order and polling does not consume intentions", () => {
  const memory = new MemoryRepository(":memory:");
  try {
    memory.syncSession("save", 1);
    for (let i = 0; i < 70; i++) memory.appendEvent("save", "action.v2:farmer_ahe", {
      event_id: `chat-intents:${i}`, kind: "ChatIntentExtracted", game_minute: i,
      payload: {intents: [{detail: "private conversation"}]},
    });
    memory.appendEvent("other", "action.v2:farmer_ahe", {event_id: "other", kind: "ChatIntentExtracted", game_minute: 1, payload: {}});
    memory.appendEvent("save", "chat.jobs:farmer_ahe", {event_id: "empty", kind: "ChatIntentFinished", game_minute: 1, payload: {status: "empty"}});
    const first = memory.agentEventFeed("save", 0);
    assert.equal(first.events.length, 64);
    assert.deepEqual(first.events[0], {event_id: "chat-intents:0", agent_id: "farmer_ahe", kind: "dialogue", source: "chat_intent_extracted", game_minute: 0});
    assert.deepEqual(memory.agentEventFeed("save", 0), first, "read-only redelivery is stable");
    assert.equal(memory.pendingDialogueIntents("save", "action.v2:farmer_ahe").length, 9);
    const second = memory.agentEventFeed("save", first.next_cursor);
    assert.equal(second.events.length, 6);
    assert.equal(second.events[0].event_id, "chat-intents:64");
    assert.deepEqual(memory.agentEventFeed("save", second.next_cursor), {next_cursor: second.next_cursor, events: []});
    memory.consumeDialogueIntents("save", "action.v2:farmer_ahe", ["chat-intents:0"], 80);
    assert.equal(memory.agentEventFeed("save", 0).events[0].event_id, "chat-intents:1");
  } finally { memory.close(); }
});

test("event delivery is scoped by session epoch and rejects malformed cursors", async () => {
  const memory = new MemoryRepository(":memory:");
  memory.syncSession("save", 3);
  memory.appendEvent("save", "action.v2:farmer_ahe", {event_id: "intent", kind: "ChatIntentExtracted", game_minute: 1, payload: {}});
  const server = createServer(createApp({memory, registry: AgentRegistry.loadDefault(), checkpointRoot: ".", provider: {decide: async () => {throw Error("unused");}}}));
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${(server.address() as any).port}/v1/agent-events/poll`;
  const poll = (body: unknown) => fetch(url, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(body)});
  try {
    const valid = {session_id: "save", session_epoch: 3, cursor: 0};
    const reply = await poll(valid);
    assert.equal(reply.status, 200);
    assert.equal((await reply.json() as any).events[0].event_id, "intent");
    assert.equal((await poll({...valid, session_epoch: 2})).status, 409);
    assert.equal((await poll({...valid, session_id: "missing"})).status, 409);
    for (const cursor of [-1, 0.5, "0", null]) assert.equal((await poll({...valid, cursor})).status, 400);
    assert.equal((await poll(null)).status, 400);
    memory.syncSession("save", 4);
    assert.equal((await poll(valid)).status, 409);
  } finally {
    await new Promise<void>(resolve => server.close(() => resolve())); memory.close();
  }
});

test("agent context explains the queued trigger; malformed or other-actor events reject", async () => {
  const event = {event_id: "chat-intents:turn", agent_id: "farmer_ahe", kind: "dialogue", game_minute: 5, source: "chat_intent_extracted", priority: 2, trigger: "event"};
  const raw = {protocol_version: 3, request_id: "event-loop", session_id: "save", session_epoch: 1,
    agent_id: "farmer_ahe", trigger: "event", game_minute: 100, world_revision: 5, active_role: "farmer", goals: [],
    allowed_command_tools: ["wait"], resources: {}, experience_events: [], trigger_events: [event]};
  const parsed = parseDecisionRequest(raw); assert.ok(parsed.ok);
  assert.equal(parseDecisionRequest({...raw, trigger_events: [{...event, event_id: `chat-intents:${"r".repeat(160)}`}]}).ok, true, "outbox prefix supports maximum-length request IDs");
  const context = AgentRegistry.loadDefault().buildContext(raw.agent_id, parsed.value, []);
  await runAgentLoop(parsed.value, context, {experience: {}, memories: [], read: async () => ({})}, async messages => {
    assert.deepEqual(JSON.parse(String(messages[1].content)).turn.trigger_events, [event]);
    const result = new AgentStreamAssembler();
    result.accept({choices: [{index: 0, delta: {content: ""}, finish_reason: "stop"}]});
    return result;
  }, () => {});
  for (const patch of [{agent_id: "lao_li"}, {kind: "unknown"}, {priority: -1}, {game_minute: 0.5}, {source: ""}, {extra: true}]) {
    assert.equal(parseDecisionRequest({...raw, trigger_events: [{...event, ...patch}]}).ok, false);
  }
});
