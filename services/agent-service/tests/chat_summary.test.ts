import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { MemoryRepository, type MemoryEvent } from "../src/memory.ts";
import { AgentRegistry } from "../src/agents.ts";
import { prepareChatContext } from "../src/chat/context_window.ts";
import { chatRoomKey, type ChatPort } from "../src/chat_provider.ts";
import {
  CHAT_HISTORY_TURNS,
  chatMessages,
  selectChatHistory,
} from "../src/chat_context.ts";
import { createApp } from "../src/app.ts";
import {
  parseDecisionRequest,
  type DecisionRequest,
  type ActionIntent,
} from "../src/protocol.ts";

const request = (id: string): DecisionRequest => {
  const parsed = parseDecisionRequest({
    protocol_version: 3,
    request_id: id,
    session_id: "window",
    session_epoch: 1,
    agent_id: "farmer_ahe",
    trigger: "dialogue",
    dialogue_input: `问题-${id}`,
    game_minute: 10,
    world_revision: 1,
    active_role: "farmer",
    goals: [],
    allowed_command_tools: ["wait", "speak"],
    resources: {},
    experience_events: [],
    goal_refs: [],
  });
  assert.ok(parsed.ok);
  return parsed.value;
};
const reply = (r: DecisionRequest): ActionIntent => ({
  protocol_version: 2,
  decision_id: r.request_id,
  request_id: r.request_id,
  agent_id: r.agent_id,
  expected_revision: r.world_revision,
  actions: [],
  speech: `答复-${r.request_id}`,
  decision_summary: "chat",
  chat_isolated: true,
});
const message = (id: string, speaker: string, text: string): MemoryEvent => ({
  event_id: id,
  kind: "ChatMessage",
  game_minute: 10,
  payload: { speaker, text },
});

test("HTTP chat retains current turn and four complete previous turns without summary calls", async () => {
  const memory = new MemoryRepository(":memory:"),
    registry = AgentRegistry.loadDefault();
  const windows: any[] = [];
  let summaries = 0;
  const chat: ChatPort = {
    model: "test",
    summarize: async () => {
      summaries++;
      return "must not run";
    },
    respond: async (r, c, history, actors, _read, _emit, _signal, summary) => {
      windows.push({
        history,
        summary,
        messages: chatMessages(r, c, history, actors, summary),
      });
      return reply(r);
    },
  };
  const server = createServer(
    createApp({
      memory,
      registry,
      chatProvider: chat,
      checkpointRoot: ".",
      provider: {
        decide: async (r) => reply(r),
        streamDecision: async (r) => reply(r),
      },
    }),
  );
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    for (let i = 0; i < 18; i++) {
      const r = request(String(i));
      r.game_minute = 100 - i;
      const wire: any = { ...r };
      for (const key of [
        "actor_context",
        "market_view",
        "known_actors",
        "public_world_state",
      ])
        delete wire[key];
      const res = await fetch(
        `http://127.0.0.1:${(server.address() as any).port}/v1/agents/${r.agent_id}/decide/stream`,
        { method: "POST", body: JSON.stringify(wire) },
      );
      assert.match(await res.text(), /event: decision.final/);
      const window = windows.at(-1)!;
      assert.equal(window.history.length, Math.min(i, 4) * 2 + 1);
      assert.equal(
        window.history[0].event_id,
        `chat-user:${Math.max(0, i - 4)}`,
      );
      assert.equal(window.history.at(-1).payload.text, r.dialogue_input);
      assert.equal(window.summary, "");
      assert.equal(
        JSON.parse(window.messages[0].content).conversation_summary,
        undefined,
      );
    }
    assert.equal(summaries, 0);
    assert.equal(
      memory.chatRecent("window", chatRoomKey(request("x")), 100).length,
      36,
    );
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    memory.close();
  }
});

test("group replies count as one player turn and keep all speakers in chronological order", async () => {
  const memory = new MemoryRepository(":memory:"),
    r = request("last"),
    scope = "group";
  r.chat_room = {
    id: scope,
    participants: ["farmer_ahe", "lao_li", "zewei"],
    turn_id: "6",
  };
  try {
    for (let i = 0; i <= 6; i++) {
      memory.appendEvent(
        r.session_id,
        scope,
        message(`chat-user:${i}`, "player", `问${i}`),
      );
      for (const actor of i === 6
        ? ["lao_li"]
        : ["farmer_ahe", "lao_li", "zewei"])
        memory.appendEvent(
          r.session_id,
          scope,
          message(`${actor}:${i}`, actor, `答${i}`),
        );
    }
    const history = selectChatHistory(
      r,
      memory.chatRecentTurns(r.session_id, scope, CHAT_HISTORY_TURNS),
    );
    assert.equal(history[0].event_id, "chat-user:2");
    assert.equal(history.length, 18);
    assert.deepEqual(
      history.slice(-2).map((e) => e.event_id),
      ["chat-user:6", "lao_li:6"],
    );
    assert.equal(
      history.filter((e) => e.payload.speaker === "player").length,
      5,
    );
  } finally {
    memory.close();
  }
});

test("old summaries cannot re-enter chat, and reset or cancellation prevents window preparation", async () => {
  const memory = new MemoryRepository(":memory:"),
    r = request("current"),
    scope = chatRoomKey(r);
  const provider: ChatPort = {
    model: "test",
    respond: async (r) => reply(r),
    summarize: async () => {
      throw Error("must not summarize");
    },
  };
  try {
    memory.appendEvent(r.session_id, scope, message("old", "player", "旧话"));
    memory.storeHistory(r.session_id, scope, ["old"], "OLD_SUMMARY_SENTINEL");
    memory.appendEvent(
      r.session_id,
      scope,
      message("chat-user:current", "player", r.dialogue_input!),
    );
    const window = await prepareChatContext(
      memory,
      provider,
      r,
      scope,
      () => {},
      () => true,
    );
    assert.equal(window.summary, "");
    const messages = chatMessages(
      r,
      AgentRegistry.loadDefault().buildContext(r.agent_id, r, []),
      window.history,
      [],
      "OLD_SUMMARY_SENTINEL",
    );
    assert.doesNotMatch(JSON.stringify(messages), /OLD_SUMMARY_SENTINEL/);
    await assert.rejects(
      prepareChatContext(
        memory,
        provider,
        r,
        scope,
        () => {},
        () => false,
      ),
      /chat_context_reset/,
    );
    const controller = new AbortController();
    controller.abort();
    await assert.rejects(
      prepareChatContext(
        memory,
        provider,
        r,
        scope,
        () => {},
        () => true,
        controller.signal,
      ),
    );
  } finally {
    memory.close();
  }
});

test("character budget drops whole older turns and always preserves the current player message", () => {
  const r = request("current");
  const history = [
    message("old-u", "player", "旧问题"),
    message("old-a", r.agent_id, "长回复".repeat(2500)),
    message("recent-u", "player", "去哪里？"),
    message("recent-a", r.agent_id, "去南湖。"),
    message("chat-user:current", "player", r.dialogue_input!),
  ];
  assert.deepEqual(
    selectChatHistory(r, history).map((e) => e.event_id),
    ["recent-u", "recent-a", "chat-user:current"],
  );
});
