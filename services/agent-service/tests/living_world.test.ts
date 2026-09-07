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
