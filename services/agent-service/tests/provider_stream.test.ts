import assert from "node:assert/strict";
import test from "node:test";
import {AgentStreamAssembler, decodeProviderSse} from "../src/provider_stream.ts";
import type {DecisionRequest} from "../src/protocol.ts";

const request: DecisionRequest = {
  protocol_version: 1,
  request_id: "stream-request-1",
  session_id: "stream-session",
  session_epoch: 1,
  agent_id: "farmer_ahe",
  trigger: "dialogue",
  game_minute: 480,
  world_revision: 7,
  snapshot: {},
  event_delta: [],
  dialogue_input: "整理第一块地",
};

function byteStream(bytes: Uint8Array, boundaries: readonly number[]): ReadableStream<Uint8Array> {
  return new ReadableStream({
    start(controller) {
      let start = 0;
      for (const end of boundaries) {
        controller.enqueue(bytes.slice(start, end));
        start = end;
      }
      if (start < bytes.length) controller.enqueue(bytes.slice(start));
      controller.close();
    },
  });
}

test("decodes fragmented Provider SSE without corrupting UTF-8", async () => {
  const source = [
    ": heartbeat\n\n",
    "data: {\"id\":\"chat-1\",\"choices\":[{\"delta\":{\"reasoning_content\":\"地块未开垦。\"},\"finish_reason\":null}]}\n\n",
    "data: {\"id\":\"chat-1\",\"choices\":[{\"delta\":{\"content\":\"我来整理土地。\"},\"finish_reason\":null}]}\n\n",
    "data: [DONE]\n\n",
  ].join("");
  const bytes = new TextEncoder().encode(source);
  const decoded: Record<string, unknown>[] = [];
  for await (const chunk of decodeProviderSse(byteStream(bytes, Array.from({length: bytes.length - 1}, (_, index) => index + 1)))) {
    decoded.push(chunk);
  }
  assert.equal(decoded.length, 2);
  assert.equal(((decoded[0].choices as any[])[0].delta as any).reasoning_content, "地块未开垦。");
  assert.equal(((decoded[1].choices as any[])[0].delta as any).content, "我来整理土地。");
});

test("assembles interleaved reasoning content and fragmented tool arguments", () => {
  const assembler = new AgentStreamAssembler();
  const emitted = [
    ...assembler.accept({id: "chat-1", choices: [{delta: {reasoning_content: "地块未"}, finish_reason: null}]}),
    ...assembler.accept({id: "chat-1", choices: [{delta: {reasoning_content: "开垦。", content: "我来"}, finish_reason: null}]}),
    ...assembler.accept({id: "chat-1", choices: [{delta: {content: "整理土地。", tool_calls: [{index: 0, id: "call-1", type: "function", function: {name: "ti", arguments: "{\"plot_"}}]}, finish_reason: null}]}),
    ...assembler.accept({id: "chat-1", choices: [{delta: {tool_calls: [{index: 0, function: {name: "ll", arguments: "index\":"}}]}, finish_reason: null}]}),
    ...assembler.accept({id: "chat-1", choices: [{delta: {tool_calls: [{index: 0, function: {arguments: "0}"}}]}, finish_reason: "tool_calls"}], usage: {total_tokens: 42}}),
  ];
  assert.deepEqual(emitted.map((event) => event.type), [
    "reasoning", "reasoning", "content", "content", "tool_call", "tool_call", "tool_call",
  ]);
  const result = assembler.finish(request, ["till", "wait"]);
  assert.deepEqual(result.rawMessage, {
    content: "我来整理土地。",
    reasoning_content: "地块未开垦。",
    tool_calls: [{id: "call-1", type: "function", function: {name: "till", arguments: "{\"plot_index\":0}"}}],
  });
  assert.equal(result.finishReason, "tool_calls");
  assert.deepEqual(result.usage, {total_tokens: 42});
  assert.equal(result.intent.tool_name, "till");
  assert.deepEqual(result.intent.arguments, {plot_index: 0});
});

test("rejects incomplete or multiple final tool calls", () => {
  const incomplete = new AgentStreamAssembler();
  incomplete.accept({choices: [{delta: {content: "没有工具"}, finish_reason: "stop"}]});
  assert.throws(() => incomplete.finish(request, ["wait"]), /exactly_one_tool_call/);

  const multiple = new AgentStreamAssembler();
  multiple.accept({choices: [{delta: {tool_calls: [
    {index: 0, id: "one", function: {name: "wait", arguments: "{}"}},
    {index: 1, id: "two", function: {name: "wait", arguments: "{}"}},
  ]}, finish_reason: "tool_calls"}]});
  assert.throws(() => multiple.finish(request, ["wait"]), /exactly_one_tool_call/);
});
