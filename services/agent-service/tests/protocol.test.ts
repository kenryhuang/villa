import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";
import {
  parseActionIntent,
  parseActionOutcome,
  parseDecisionRequest,
} from "../src/protocol.ts";

const fixture = (name: string): Record<string, unknown> => JSON.parse(
  readFileSync(resolve(process.cwd(), "../../shared/agent_protocol/v2", name), "utf8"),
);

test("accepts the shared protocol fixtures", () => {
  const request = fixture("decision-request.json");
  assert.equal(parseDecisionRequest(request).ok, true);
  assert.equal(Object.hasOwn(request, "snapshot"), false);
  assert.equal(Object.hasOwn(request, "event_delta"), false);
  assert.equal(parseActionIntent(fixture("action-intent.json"), ["plant", "wait"]).ok, true);
  assert.equal(parseActionOutcome(fixture("action-outcome.json")).ok, true);
});

test("accepts zero through three actions and rejects invalid batches", () => {
  const request = fixture("decision-request.json");
  assert.equal(parseDecisionRequest({ ...request, protocol_version: 1 }).ok, false);
  assert.equal(parseDecisionRequest({ ...request, request_id: "" }).ok, false);
  assert.equal(parseDecisionRequest({ ...request, world_revision: -1 }).ok, false);
  const intent = fixture("action-intent.json");
  assert.equal(parseActionIntent({...intent, actions: []}, ["plant", "wait"]).ok, true);
  const action = (intent.actions as Record<string, unknown>[])[0];
  const three = [0, 1, 2].map((index) => ({
    ...action, action_id: `call-${index}`, idempotency_key: `key-${index}`,
  }));
  assert.equal(parseActionIntent({...intent, actions: three}, ["plant", "wait"]).ok, true);
  assert.equal(parseActionIntent({...intent, actions: [...three, {...three[0], action_id: "call-3", idempotency_key: "key-3"}]}, ["plant"]).ok, false);
  assert.equal(parseActionIntent({...intent, actions: [{...action, tool_name: "change_gold"}]}, ["plant"]).ok, false);
  assert.equal(parseActionIntent({...intent, actions: [{...action, arguments: []}]}, ["plant"]).ok, false);
  assert.equal(parseActionIntent({...intent, actions: [{...action}, {...action, idempotency_key: "other"}]}, ["plant"]).ok, false);
  assert.equal(parseActionIntent({...intent, actions: [{...action}, {...action, action_id: "other"}]}, ["plant"]).ok, false);
  const wait = {...action, action_id: "wait", idempotency_key: "wait-key", tool_name: "wait", arguments: {}};
  assert.equal(parseActionIntent({...intent, actions: [wait, action]}, ["plant", "wait"]).ok, false);
  const outcome = fixture("action-outcome.json");
  assert.equal(parseActionOutcome({ ...outcome, status: "maybe" }).ok, false);
  assert.equal(parseActionOutcome({ ...outcome, action_id: "" }).ok, false);
});

test("requires the complete immutable projection and rejects malformed capability lists", () => {
  const request = fixture("decision-request.json");
  for (const field of [
    "projection_schema_version", "actor_context", "active_role", "goals",
    "allowed_read_tools", "allowed_command_tools", "public_world_state",
    "global_public_events", "known_actors", "own_event_delta", "market_summary", "market_view",
    "interaction_view", "agreement_view",
  ]) {
    const missing = {...request};
    delete missing[field];
    assert.equal(parseDecisionRequest(missing).ok, false, `requires ${field}`);
  }
  assert.equal(parseDecisionRequest({...request, projection_schema_version: 2}).ok, false);
  assert.equal(parseDecisionRequest({...request, goals: ["ok", 3]}).ok, false);
  assert.equal(parseDecisionRequest({...request, allowed_read_tools: ["inspect_self_resources", "inspect_self_resources"]}).ok, false);
  assert.equal(parseDecisionRequest({...request, allowed_command_tools: ["plant", ""]}).ok, false);
  assert.equal(parseDecisionRequest({...request, known_actors: [{actor_id: "a"}, "private-leak"]}).ok, false);
  assert.deepEqual(parseDecisionRequest({...request, snapshot: {}}), {ok: false, error: "legacy_request_fields"});
  assert.deepEqual(parseDecisionRequest({...request, event_delta: []}), {ok: false, error: "legacy_request_fields"});
  assert.equal(parseDecisionRequest({...request, market_summary: []}).ok, false);
  assert.equal(parseDecisionRequest({...request, market_summary: {}}).ok, false);
  assert.equal(parseDecisionRequest({...request, market_summary: {...request.market_summary as object, role_id: "merchant"}}).ok, false);
  assert.equal(parseDecisionRequest({...request, market_summary: {...request.market_summary as object, signals: Array(21).fill({})}}).ok, false);
});

test("enforces the compact market signal limit for each role", () => {
  const request = fixture("decision-request.json");
  const signal = (index: number) => ({
    item_id: `item-${index}`,
    mid_price: 100,
    base_price: 100,
    stock_ratio_bps: 10_000,
    price_change_bps: 0,
    reason_codes: ["market_scope"],
  });
  const withSignals = (role: string, count: number) => ({
    ...request,
    active_role: role,
    market_summary: {
      ...request.market_summary as object,
      role_id: role,
      signals: Array.from({length: count}, (_, index) => signal(index)),
    },
  });

  assert.equal(parseDecisionRequest(withSignals("farmer", 12)).ok, true);
  assert.equal(parseDecisionRequest(withSignals("farmer", 13)).ok, false);
  assert.equal(parseDecisionRequest(withSignals("merchant", 20)).ok, true);
  assert.equal(parseDecisionRequest(withSignals("merchant", 21)).ok, false);
  assert.equal(parseDecisionRequest(withSignals("explorer", 10)).ok, true);
  assert.equal(parseDecisionRequest(withSignals("explorer", 11)).ok, false);
});
