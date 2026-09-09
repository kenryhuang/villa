import assert from "node:assert/strict";
import test from "node:test";
import {validToolArguments} from "../src/tool_contracts.ts";

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
