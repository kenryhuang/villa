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
    ...assembler.accept({id: "chat-1", choices: [{delta: {content: "整理土地。", tool_calls: [{index: 0, id: "call-1", type: "function", function: {name: "ti", arguments: "{\"pl"}}]}, finish_reason: null}]}),
    ...assembler.accept({id: "chat-1", choices: [{delta: {tool_calls: [{index: 0, function: {name: "ll", arguments: "ot\":"}}]}, finish_reason: null}]}),
    ...assembler.accept({id: "chat-1", choices: [{delta: {tool_calls: [{index: 0, function: {arguments: "0}"}}]}, finish_reason: "tool_calls"}], usage: {total_tokens: 42}}),
  ];
  assert.deepEqual(emitted.map((event) => event.type), [
    "reasoning", "reasoning", "content", "content", "tool_call", "tool_call", "tool_call",
  ]);
  const result = assembler.finish(request, ["till", "wait"]);
  assert.deepEqual(result.rawMessage, {
    content: "我来整理土地。",
    reasoning_content: "地块未开垦。",
    tool_calls: [{id: "call-1", type: "function", function: {name: "till", arguments: "{\"plot\":0}"}}],
  });
  assert.equal(result.finishReason, "tool_calls");
  assert.deepEqual(result.usage, {total_tokens: 42});
  assert.equal(result.intent.tool_name, "till");
  assert.deepEqual(result.intent.arguments, {plot: 0});
});

function assemblerFor(toolName: string, args: Record<string, unknown>): AgentStreamAssembler {
  const assembler = new AgentStreamAssembler();
  assembler.accept({choices: [{delta: {tool_calls: [{
    index: 0,
    id: `call-${toolName}`,
    function: {name: toolName, arguments: JSON.stringify(args)},
  }]}, finish_reason: "tool_calls"}]});
  return assembler;
}

test("rejects Provider tool arguments outside the authoritative contract", () => {
  const invalidCases: Array<[string, Record<string, unknown>]> = [
    ["till", {plot_index: "0"}],
    ["plant", {plot: 0, seed_item_id: "invented_seed"}],
    ["sell", {item_id: "salt", quantity: "4", price: "5"}],
    ["build", {building_type: "castle", building_id: "home-1"}],
    ["travel", {region_id: "moon", duration_minutes: 60}],
    ["survey", {direction: "surroundings", purpose: "探索"}],
    ["collect_sample", {discovery_id: "invented_discovery"}],
    ["wait", {minutes: 30}],
  ];
  for (const [toolName, args] of invalidCases) {
    assert.throws(
      () => assemblerFor(toolName, args).finish(request, [toolName]),
      /provider_invalid_intent:invalid_arguments/,
      `${toolName} rejects ${JSON.stringify(args)}`,
    );
  }
});

test("accepts exact Provider tool arguments for every contract shape", () => {
  const validCases: Array<[string, Record<string, unknown>]> = [
    ["till", {plot: 0}],
    ["harvest", {plot: 255}],
    ["plant", {plot: 2, seed_item_id: "carrot_seed"}],
    ["buy", {item_id: "salt", quantity: 4}],
    ["sell", {item_id: "grain", quantity: 1}],
    ["prepare_supplies", {item_id: "rope", quantity: 2}],
    ["propose_trade", {item_id: "bread", quantity: 3}],
    ["build", {building_type: "barn", building_id: "barn-1"}],
    ["travel", {region_id: "creek", duration_minutes: 60}],
    ["survey", {region_id: "forest"}],
    ["collect_sample", {discovery_id: "crop:moonflower"}],
    ["register_discovery", {discovery_id: "terrain:cliff"}],
    ["speak", {}],
    ["wait", {}],
  ];
  for (const [toolName, args] of validCases) {
    assert.deepEqual(
      assemblerFor(toolName, args).finish(request, [toolName]).intent.arguments,
      args,
      `${toolName} accepts ${JSON.stringify(args)}`,
    );
  }
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
