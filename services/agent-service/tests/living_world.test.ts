import assert from "node:assert/strict";
import test from "node:test";
import {validToolArguments} from "../src/tool_contracts.ts";

test("research explicitly binds sponsor, old-report and required-sample terms", () => {
  const terms = {worker_id: "xuezhe_lin", funder_id: "player", region_id: "creek", reward: 60, deadline_minutes: 500, allow_old_report: false, require_sample: true};
  assert.ok(validToolArguments("propose_investigation", terms));
  assert.equal(validToolArguments("propose_investigation", {...terms, allow_old_report: "false"}), false);
  assert.equal(validToolArguments("propose_investigation", {...terms, reward: -1}), false);
  assert.ok(validToolArguments("collect_sample", {discovery_id: "survey-creek-0"}));
  assert.equal(validToolArguments("offer_intelligence", {target_actor_id: "player", discovery_id: "survey-creek-0", price: 0, ttl: 180}), false);
});

test("repair contribution is bounded real materials and labor, never a declared success", () => {
  assert.ok(validToolArguments("contribute_route_repair", {event_id: "road-0", materials: {wood: 6, stone: 4}, labor_minutes: 60}));
  for (const a of [{event_id: "road-0", materials: {gold: 100}, labor_minutes: 60}, {event_id: "road-0", materials: {}, labor_minutes: 0}, {event_id: "road-0", materials: {wood: 7}, labor_minutes: 60}, {event_id: "road-0", materials: {}, labor_minutes: 61}]) assert.equal(validToolArguments("contribute_route_repair", a), false);
  assert.ok(validToolArguments("public_repair_plan", {expected_version: 1, reason: "Actual blocked route"}));
});

test("activities bound real budgets, venue capacities and versioned voluntary enrollment", () => {
  const terms = {kind: "fishing", starts_in: 120, duration: 540, capacity: 8, minimum: 2, ticket: 5, sponsor: 150, reward: 20, food_quantity: 4, food_price: 20};
  assert.ok(validToolArguments("propose_activity", terms));
  assert.ok(validToolArguments("public_activity_plan", {expected_version: 1, reason: "Voluntary lake gathering", terms}));
  assert.ok(validToolArguments("enroll_activity", {event_id: "e", version: 1}));
  for (const bad of [{...terms, minimum: 9}, {...terms, food_quantity: 9}, {...terms, sponsor: -1}, {...terms, kind: "invented_sport"}, {...terms, scores: [1]}]) assert.equal(validToolArguments("propose_activity", bad), false);
  assert.equal(validToolArguments("submit_activity_score", {event_id: "e", score: 1}), false);
});

test("work requires complete negotiated bounded terms and explicit acceptance version", () => {
  const terms = {worker_id: "lao_li", recipient_id: "village_inn", kind: "delivery", item_id: "grain", quantity: 2, wage: 20, building_id: "", recipe_id: "", max_fee: 0, deadline_minutes: 180, cycles: 1, interval_minutes: 0, parent_contract: "", note: "Voluntary delivery"};
  assert.ok(validToolArguments("propose_work", terms));
  for (const field of Object.keys(terms)) {
    const partial: Record<string, unknown> = {...terms}; delete partial[field];
    assert.equal(validToolArguments("propose_work", partial), false, field);
  }
  for (const bad of [{...terms, wage: -1}, {...terms, cycles: 8}, {...terms, cycles: 2}, {...terms, quantity: 1.5}, {...terms, accepted: true}, {...terms, kind: "processing"}]) assert.equal(validToolArguments("propose_work", bad), false);
  assert.ok(validToolArguments("counter_work", {contract_id: "c", version: 1, terms: {...terms, wage: 30}}));
  assert.equal(validToolArguments("accept_work", {contract_id: "c", version: 0}), false);
  assert.ok(validToolArguments("manage_building", {building_id: "b", version: 1, operation: "open", fee: 0}));
  assert.equal(validToolArguments("start_learning", {skill_id: "free_buildings"}), false);
});

test("joint investment bounds contributions and limits equipment access to its project", () => {
  const plan = {goal: "Mill contributed grain", budget: 20, deadline_minutes: 180, materials: {grain: 2}, steps: [{id: "mill", capability: "rent", depends_on: [], arguments: {building_id: "mill", recipe_id: "flour", batches: 1, max_fee: 4}}]};
  const terms = {partner_id: "lao_li", plan, partner_gold: 10, partner_materials: {grain: 1}, partner_profit_percent: 50};
  assert.ok(validToolArguments("propose_joint_project", terms));
  assert.ok(validToolArguments("propose_joint_project", {...terms, equipment_id: "mill"}));
  for (const bad of [{...terms, partner_gold: 21}, {...terms, partner_materials: {grain: 3}}, {...terms, partner_materials: {stone: 1}}, {...terms, partner_profit_percent: 100}, {...terms, equipment_id: "unrelated"}, {...terms, guaranteed_profit: 500}]) assert.equal(validToolArguments("propose_joint_project", bad), false);
});

test("autonomous goals accept bounded DAGs and reject cycles, unsupported steps and bad result references", () => {
  const plan = {goal: "Try a small flour business", budget: 100, deadline_minutes: 600, materials: {grain: 2}, steps: [
    {id: "mill", capability: "rent", depends_on: [], arguments: {building_id: "mill-1", recipe_id: "flour", batches: 1, max_fee: 4}},
    {id: "ready", capability: "wait_production", depends_on: ["mill"], arguments: {order_step: "mill"}},
    {id: "sale", capability: "sell", depends_on: ["ready"], arguments: {item_id: "flour", quantity: 1, limit: 50}},
  ]};
  assert.ok(validToolArguments("submit_project", plan));
  const cycle = structuredClone(plan);
  cycle.steps[0].depends_on = ["sale"];
  assert.equal(validToolArguments("submit_project", cycle), false);
  const unsupported = structuredClone(plan);
  unsupported.steps[0].capability = "grant_gold";
  assert.equal(validToolArguments("submit_project", unsupported), false);
  const badReference = structuredClone(plan);
  badReference.steps[1].arguments.order_step = "missing";
  assert.equal(validToolArguments("submit_project", badReference), false);
  assert.equal(validToolArguments("submit_project", {...plan, budget: 1.5}), false);
  assert.equal(validToolArguments("submit_project", {...plan, materials: {grain: -2}}), false);
});

test("commissions require bounded prepaid terms and explicit delivery version/proof", () => {
  const terms = {demand_id: "bread", item_id: "bread", quantity: 4, unit_reward: 100, kind: "purchase", max_claims: 2, deadline_minutes: 600};
  assert.ok(validToolArguments("publish_commission", terms));
  assert.equal(validToolArguments("publish_commission", {...terms, actor_id: "player"}), false);
  assert.equal(validToolArguments("publish_commission", {...terms, unit_reward: -1}), false);
  assert.equal(validToolArguments("publish_commission", {...terms, quantity: 1000}), false);
  assert.ok(validToolArguments("deliver_commission", {claim_id: "claim", quantity: 2, version: 1, order_id: ""}));
  assert.equal(validToolArguments("deliver_commission", {claim_id: "claim", quantity: 2, order_id: ""}), false);
});


test("delivery proposals require complete terms and do not grant authority over player assets", () => {
  const terms = {task_id: "", version: 0, recipient_id: "village_inn", item_id: "grain", quantity: 2, reward: 5, deadline_minutes: 180, schedule: "after_step", note: "Return to the mill afterwards"};
  assert.ok(validToolArguments("propose_delivery", terms));
  for (const field of Object.keys(terms)) {
    const missing = {...terms}; delete missing[field];
    assert.equal(validToolArguments("propose_delivery", missing), false, field);
  }
  for (const invalid of [{...terms, reward: -1}, {...terms, quantity: 1.5}, {...terms, schedule: "teleport"}, {...terms, payer: "player"}, {...terms, accepted: true}]) {
    assert.equal(validToolArguments("propose_delivery", invalid), false);
  }
  assert.ok(validToolArguments("cancel_delivery", {task_id: "delivery-1", version: 2}));
  assert.equal(validToolArguments("cancel_delivery", {task_id: "delivery-1", version: 0}), false);
});

test("project changes carry a version, source and a fully validated executable plan", () => {
  const plan = {goal: "Try one batch", budget: 10, deadline_minutes: 180, materials: {}, steps: [{id: "buy", capability: "buy", depends_on: [], arguments: {item_id: "grain", quantity: 1, limit: 10}}]};
  const change = {project_id: "p1", version: 1, plan, source: "dialogue"};
  assert.ok(validToolArguments("revise_project", change));
  assert.equal(validToolArguments("revise_project", {...change, version: 1.5}), false);
  assert.equal(validToolArguments("revise_project", {...change, source: "force_player"}), false);
  assert.equal(validToolArguments("revise_project", {...change, plan: {...plan, budget: -10}}), false);
});


test("public budget commands exclude all private-account and market-write fields", () => {
  const plan = {expected_version: 1, reason: "Food gap exceeds incoming supply", quantity: 2, unit_reward: 100, deadline_minutes: 180};
  assert.ok(validToolArguments("public_food_plan", plan));
  for (const invalid of [{...plan, quantity: 13}, {...plan, unit_reward: 201}, {...plan, expected_version: 0}, {...plan, account_id: "player"}, {...plan, target_price: 1}]) assert.equal(validToolArguments("public_food_plan", invalid), false);
  assert.ok(validToolArguments("public_wait", {expected_version: 1, reason: "Existing incoming supply is adequate"}));
});
