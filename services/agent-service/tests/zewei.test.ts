import assert from "node:assert/strict";
import test from "node:test";
import {AgentRegistry} from "../src/agents.ts";
import {readFileSync} from "node:fs";

test("zewei is an authored adult Agent using the shared game identity and tools", () => {
  const registry = AgentRegistry.loadDefault();
  const profile = registry.get("zewei");
  assert.ok(profile);
  assert.equal(profile.display_name, "zewei");
  assert.equal(profile.npc_id, "zewei");
  assert.equal(profile.role_id, "merchant");
  assert.equal(profile.soul.social_profile?.age, 22);
  assert.equal(profile.soul.social_profile?.gender, "female");
  assert.ok(profile.soul.traits.includes("对爱人忠诚专一"));
  assert.match(profile.soul.speech_style, /不把陌生人当作爱人/);
  assert.ok(profile.tools.includes("speak") && profile.tools.includes("propose_trade"));
  assert.ok(profile.decision_interval_hours[0] > 0);
  const social = JSON.parse(readFileSync("../../data/living_world/social_profiles.json", "utf8"));
  assert.deepEqual(profile.soul.social_profile, social.actors.zewei);
  // New residents must not change the behavior of existing names/identities.
  assert.ok(registry.get("resident_yun") && registry.get("farmer_ahe"));
});
