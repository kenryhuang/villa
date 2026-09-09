import assert from "node:assert/strict";
import test from "node:test";
import { AgentRegistry } from "../src/agents.ts";
import {executeReadTool, toolDescription, validToolArguments} from "../src/tool_contracts.ts";

test("3D environment tools expose current instance prices without mutating the snapshot", () => {
  const building = {building_id: "windmill:32:31", owner_id: "lao_li", instance_id: "stable-windmill-1", rental_fees: [{recipe_id: "flour", fee_per_batch: 4}]};
  const context = AgentRegistry.loadDefault().buildContext("farmer_ahe", {
    protocol_version: 2, request_id: "rental-context", session_id: "farm3d", session_epoch: 1,
    agent_id: "farmer_ahe", trigger: "schedule", game_minute: 360, world_revision: 1,
    projection_schema_version: 1, actor_context: {world_map: {market: {x: 5, z: 40}}, player_buildings: [building], characters: [{actor_id: "player"}]}, active_role: "farmer",
    goals: ["earn_stable_profit"], allowed_read_tools: ["inspect_map", "inspect_buildings", "inspect_building", "inspect_characters"], allowed_command_tools: ["rent_production"],
    public_world_state: {}, global_public_events: [], known_actors: [], own_event_delta: [],
    market_summary: summary("farmer", 360), market_view: {}, interaction_view: {}, agreement_view: {},
  }, []);
  assert.deepEqual(context.allowed_command_tools, ["rent_production"]);
  assert.deepEqual(executeReadTool(context, "inspect_map", {}), {map: {market: {x: 5, z: 40}}});
  assert.deepEqual(executeReadTool(context, "inspect_characters", {}), {characters: [{actor_id: "player"}]});
  const detail = executeReadTool(context, "inspect_building", {building_id: building.building_id});
  assert.deepEqual(detail, {found: true, value: building});
  assert.deepEqual(executeReadTool(context, "inspect_building", {building_id: building.instance_id}), {found: true, value: building});
  (detail.value as typeof building).rental_fees[0].fee_per_batch = 0;
  assert.deepEqual(executeReadTool(context, "inspect_buildings", {}), {buildings: [building]});
  assert.deepEqual(executeReadTool(context, "inspect_building", {building_id: "missing"}), {found: false});
  assert.throws(() => executeReadTool(context, "inspect_map", {path: "private"}), /invalid_read_arguments/);
});

test("rental commands require bounded quantities and an explicit total price cap", () => {
  const args = {building_id: "windmill:32:31", recipe_id: "flour", batches: 2, max_fee: 8};
  assert.equal(validToolArguments("rent_production", args), true);
  for (const invalid of [{...args, batches: 0}, {...args, batches: 1.5}, {...args, max_fee: -1}, {...args, tenant_id: "player"}, {building_id: args.building_id, recipe_id: args.recipe_id, batches: 2}]) {
    assert.equal(validToolArguments("rent_production", invalid), false);
  }
});

const summary = (roleId: string, gameMinute: number, signals: Record<string, unknown>[] = []) => ({
  schema_version: 1, role_id: roleId, generated_game_minute: gameMinute,
  overview: {item_count: signals.length, shortage_count: 0, surplus_count: 0, rising_count: 0, falling_count: 0},
  signals,
});

test("harvest contract explicitly supports withered cleanup without inventory rewards", () => {
  const tool = toolDescription("harvest").function as {description: string};
  assert.match(tool.description, /withered/);
  assert.match(tool.description, /no items/);
  assert.match(tool.description, /growing.*dormant/);
});

test("crop inspection preserves authoritative planting restrictions and named calendar", () => {
  const cropOptions = [{crop_id: "grain", seed_item_id: "grain_seed", season_names: ["spring"], season_valid: false, plantable_plots: [], unavailable_reason: "wrong_season"}];
  const world = {season: 3, season_name: "winter", season_label: "冬季", season_day: 5, year: 2, time_of_day: {hour: 20, minute: 7, text: "20:07"}};
  const context = AgentRegistry.loadDefault().buildContext("farmer_ahe", {
    protocol_version: 2, request_id: "crop-context", session_id: "save", session_epoch: 1,
    agent_id: "farmer_ahe", trigger: "schedule", game_minute: 57247, world_revision: 1,
    projection_schema_version: 1, actor_context: {crop_options: cropOptions}, active_role: "farmer",
    goals: ["keep_crops_healthy"], allowed_read_tools: ["inspect_crop_options"], allowed_command_tools: ["plant", "harvest"],
    public_world_state: world, global_public_events: [], known_actors: [], own_event_delta: [],
    market_summary: summary("farmer", 57247), market_view: {}, interaction_view: {}, agreement_view: {},
  }, []);
  assert.deepEqual(context.public_world_state, world);
  const result = executeReadTool(context, "inspect_crop_options", {});
  assert.deepEqual(result, {crop_options: cropOptions});
  (result.crop_options as typeof cropOptions)[0].season_valid = true;
  assert.equal((context.actor_context.crop_options as typeof cropOptions)[0].season_valid, false);
});

test("loads three private roles and an isolated public coordinator", () => {
  const registry = AgentRegistry.loadDefault();
  assert.deepEqual(registry.ids(), ["farmer_ahe", "lao_li", "village_public", "xuezhe_lin"]);
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
    market_summary: summary("farmer", 60),
    market_view: {}, interaction_view: {}, agreement_view: {},
  };
  const context = registry.buildContext("farmer_ahe", request, []);
  assert.deepEqual(executeReadTool(context, "inspect_self_resources", {item_ids: ["carrot_seed", "secret"]}), {
    gold: 12, items: {carrot_seed: 2, secret: 0},
  });
  assert.deepEqual(executeReadTool(context, "inspect_known_actor", {actor_id: "xuezhe_lin"}), {found: false});
  assert.throws(() => executeReadTool(context, "inspect_market_depth", {item_id: "grain"}), /unauthorized_read/);
});

test("builds context from soul goals projected events and memory", () => {
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
    market_summary: summary("farmer", 60),
    market_view: {salt: {price: 3}}, interaction_view: {active_offers: []},
    agreement_view: {active_agreements: []},
  }, [{summary: "盐快售罄"}]);
  assert.equal(context.agent.display_name, "老李");
  assert.equal(context.agent.active_role, "farmer");
  assert.deepEqual(context.agent.goals, ["keep_crops_healthy"]);
  assert.equal(context.global_public_events.length, 1);
  assert.equal(context.own_event_delta.length, 1);
  assert.equal(context.memories.length, 1);
  assert.equal(context.market_summary.role_id, "farmer");
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
    global_public_events: [], known_actors: [], own_event_delta: [],
    market_summary: summary("wizard", 60),
    market_view: {}, interaction_view: {}, agreement_view: {},
  };
  assert.throws(() => registry.buildContext("farmer_ahe", request, []), /Unknown role/);
});


test("public coordinator never inherits private tools or changes into a private role", () => {
  const registry = AgentRegistry.loadDefault();
  const request = {protocol_version: 2 as const, request_id: "public-context", session_id: "public-test", session_epoch: 1, agent_id: "village_public", trigger: "event" as const, game_minute: 60, world_revision: 1, projection_schema_version: 1 as const, active_role: "public_coordinator", goals: ["protect_basic_food_access"], allowed_read_tools: ["inspect_self_resources", "inspect_known_discoveries"], allowed_command_tools: ["public_food_plan", "public_wait", "buy", "propose_trade", "submit_project", "propose_role_change"], actor_context: {public_coordination: {budget: {available: 5000}}}, public_world_state: {}, global_public_events: [], known_actors: [], own_event_delta: [], market_summary: summary("public_coordinator", 60), market_view: {}, interaction_view: {}, agreement_view: {}};
  const context = registry.buildContext("village_public", request, []);
  assert.deepEqual(context.allowed_command_tools, ["public_food_plan", "public_wait"]);
  assert.deepEqual(context.allowed_read_tools, []);
  assert.throws(() => registry.buildContext("village_public", {...request, active_role: "merchant"}, []), /Public authority/);
  assert.throws(() => registry.buildContext("lao_li", {...request, agent_id: "lao_li"}, []), /Public authority/);
  const privateContext = registry.buildContext("lao_li", {...request, agent_id: "lao_li", active_role: "merchant"}, []);
  assert.equal(privateContext.allowed_command_tools.includes("public_food_plan"), false);
});
