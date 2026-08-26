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
  readFileSync(resolve(process.cwd(), "../../shared/agent_protocol/v1", name), "utf8"),
);

test("accepts the shared protocol fixtures", () => {
  assert.equal(parseDecisionRequest(fixture("decision-request.json")).ok, true);
  assert.equal(parseActionIntent(fixture("action-intent.json"), ["plant", "wait"]).ok, true);
  assert.equal(parseActionOutcome(fixture("action-outcome.json")).ok, true);
});

test("rejects invalid envelopes and unauthorized tools", () => {
  const request = fixture("decision-request.json");
  assert.equal(parseDecisionRequest({ ...request, protocol_version: 2 }).ok, false);
  assert.equal(parseDecisionRequest({ ...request, request_id: "" }).ok, false);
  assert.equal(parseDecisionRequest({ ...request, world_revision: -1 }).ok, false);
  const intent = fixture("action-intent.json");
  assert.equal(parseActionIntent({ ...intent, tool_name: "change_gold" }, ["wait"]).ok, false);
  assert.equal(parseActionIntent({ ...intent, arguments: [] }, ["plant"]).ok, false);
  const outcome = fixture("action-outcome.json");
  assert.equal(parseActionOutcome({ ...outcome, status: "maybe" }).ok, false);
});
