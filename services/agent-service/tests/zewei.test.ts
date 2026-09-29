import assert from "node:assert/strict";
import test from "node:test";
import {AgentRegistry} from "../src/agents.ts";
import {readFileSync} from "node:fs";

test("flower_girl (display name zewei) is an authored adult Agent using the shared game identity and tools", () => {
  const registry = AgentRegistry.loadDefault();
  const profile = registry.get("flower_girl");
  assert.ok(profile);
  assert.equal(profile.display_name, "zewei");
  assert.equal(profile.npc_id, "flower_girl");
  assert.equal(profile.role_id, "merchant");
  assert.equal(profile.soul.social_profile?.age, 22);
  assert.equal(profile.soul.social_profile?.gender, "female");
  assert.ok(profile.soul.traits.includes("对爱人忠诚专一"));
  assert.match(profile.soul.speech_style, /主动/);
  assert.doesNotMatch(JSON.stringify(profile.soul), /娇羞|害羞/);
  assert.ok(profile.tools.includes("speak") && profile.tools.includes("propose_trade"));
  assert.ok(profile.decision_interval_hours[0] > 0);
  const social = JSON.parse(readFileSync("../../data/living_world/social_profiles.json", "utf8"));
  assert.deepEqual(profile.soul.social_profile, social.actors.flower_girl);
  // New residents must not change the behavior of existing names/identities.
  assert.ok(registry.get("resident_yun") && registry.get("farmer_ahe"));
});
