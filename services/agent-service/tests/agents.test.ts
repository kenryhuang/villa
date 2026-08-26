import assert from "node:assert/strict";
import test from "node:test";
import { AgentRegistry } from "../src/agents.ts";

test("loads three isolated role profiles and tool collections", () => {
  const registry = AgentRegistry.loadDefault();
  assert.deepEqual(registry.ids(), ["farmer_ahe", "lao_li", "xuezhe_lin"]);
  assert.equal(registry.get("farmer_ahe")?.tools.includes("plant"), true);
  assert.equal(registry.get("lao_li")?.tools.includes("plant"), false);
  assert.equal(registry.get("xuezhe_lin")?.tools.includes("survey"), true);
  assert.equal(registry.get("farmer_ahe")?.soul.traits.includes("踏实"), true);
});

test("builds context from soul goals snapshot events and memory", () => {
  const registry = AgentRegistry.loadDefault();
  const context = registry.buildContext("lao_li", {market: {salt: 3}}, [{kind: "market"}], [{summary: "盐快售罄"}]);
  assert.equal(context.agent.display_name, "老李");
  assert.deepEqual(context.snapshot, {market: {salt: 3}});
  assert.equal(context.recent_events.length, 1);
  assert.equal(context.memories.length, 1);
  assert.equal(context.allowed_tools.includes("buy"), true);
});
