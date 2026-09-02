import assert from "node:assert/strict";
import test from "node:test";
import { AgentRegistry } from "../src/agents.ts";
import {executeReadTool} from "../src/tool_contracts.ts";

test("loads three isolated role profiles and tool collections", () => {
  const registry = AgentRegistry.loadDefault();
  assert.deepEqual(registry.ids(), ["farmer_ahe", "lao_li", "xuezhe_lin"]);
  assert.equal(registry.get("farmer_ahe")?.tools.includes("plant"), true);
  assert.equal(registry.get("lao_li")?.tools.includes("plant"), false);
  assert.equal(registry.get("xuezhe_lin")?.tools.includes("survey"), true);
  assert.equal(registry.get("farmer_ahe")?.soul.traits.includes("踏实"), true);
});

test("local reads cannot reach data absent from the immutable context", () => {
  const registry = AgentRegistry.loadDefault();
  const request = {
    protocol_version: 2 as const, request_id: "req", session_id: "save", session_epoch: 1,
    agent_id: "farmer_ahe", trigger: "schedule" as const, game_minute: 60, world_revision: 1,
    projection_schema_version: 1 as const,
    actor_context: {self: {gold: 12, inventory: {carrot_seed: 2}}}, active_role: "farmer",
    goals: ["keep_crops_healthy"], allowed_read_tools: ["inspect_self_resources", "inspect_known_actor"],
    allowed_command_tools: [], public_world_state: {}, global_public_events: [],
    known_actors: [{actor_id: "lao_li", region_id: "market"}], own_event_delta: [],
    market_view: {}, interaction_view: {}, agreement_view: {}, snapshot: {}, event_delta: [],
  };
  const context = registry.buildContext("farmer_ahe", request, []);
  assert.deepEqual(executeReadTool(context, "inspect_self_resources", {item_ids: ["carrot_seed", "secret"]}), {
    gold: 12, items: {carrot_seed: 2, secret: 0},
  });
  assert.deepEqual(executeReadTool(context, "inspect_known_actor", {actor_id: "xuezhe_lin"}), {found: false});
  assert.throws(() => executeReadTool(context, "inspect_market_depth", {item_id: "grain"}), /unauthorized_read/);
});

test("builds context from soul goals snapshot events and memory", () => {
  const registry = AgentRegistry.loadDefault();
  const context = registry.buildContext("lao_li", {
    protocol_version: 2, request_id: "req", session_id: "save", session_epoch: 1,
    agent_id: "lao_li", trigger: "schedule", game_minute: 60, world_revision: 1,
    projection_schema_version: 1,
    actor_context: {self: {gold: 50, inventory: {salt: 2}}, relationships: {farmer_ahe: {trust: 3}}},
    active_role: "farmer",
    goals: ["keep_crops_healthy", "invented_goal"],
    allowed_read_tools: ["inspect_self_resources", "inspect_farm_plots", "inspect_market_depth"],
    allowed_command_tools: ["plant", "buy", "survey", "invented_tool"],
    public_world_state: {season: 0}, global_public_events: [{event_type: "SeasonChanged"}],
    known_actors: [{actor_id: "farmer_ahe"}], own_event_delta: [{event_type: "MessageReceived"}],
    market_view: {salt: {price: 3}}, interaction_view: {active_offers: []},
    agreement_view: {active_agreements: []}, snapshot: {}, event_delta: [],
  }, [{summary: "盐快售罄"}]);
  assert.equal(context.agent.display_name, "老李");
  assert.equal(context.agent.active_role, "farmer");
  assert.deepEqual(context.agent.goals, ["keep_crops_healthy"]);
  assert.equal(context.global_public_events.length, 1);
  assert.equal(context.own_event_delta.length, 1);
  assert.equal(context.memories.length, 1);
  assert.deepEqual(context.allowed_command_tools, ["plant", "buy"]);
  assert.deepEqual(context.allowed_read_tools, ["inspect_self_resources", "inspect_farm_plots"]);
  assert.equal("snapshot" in context, false);
});

test("rejects a dynamic role not present in the local role directory", () => {
  const registry = AgentRegistry.loadDefault();
  const request = {
    protocol_version: 2 as const, request_id: "req", session_id: "save", session_epoch: 1,
    agent_id: "farmer_ahe", trigger: "schedule" as const, game_minute: 60, world_revision: 1,
    projection_schema_version: 1, actor_context: {}, active_role: "wizard", goals: [],
    allowed_read_tools: [], allowed_command_tools: [], public_world_state: {},
    global_public_events: [], known_actors: [], own_event_delta: [], market_view: {},
    interaction_view: {}, agreement_view: {}, snapshot: {}, event_delta: [],
  };
  assert.throws(() => registry.buildContext("farmer_ahe", request, []), /Unknown role/);
});
