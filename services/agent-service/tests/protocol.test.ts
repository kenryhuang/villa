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
  assert.equal(parseDecisionRequest(fixture("decision-request.json")).ok, true);
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
