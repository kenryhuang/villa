# Agent Tool Argument Contract Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent scheduled NPC Agent decisions from reaching Godot with invalid tool argument names, types, extra fields, or enum values.

**Architecture:** Add one TypeScript tool-contract module that owns both the OpenAI-compatible JSON Schemas sent to the Provider and the runtime validation applied to the assembled tool call. `provider.ts` uses the schemas for generation guidance; `provider_stream.ts` rejects any Provider output that violates the same contract before emitting `decision.final`. Godot's existing strict validator remains the final authority and is not weakened.

**Tech Stack:** Node.js 24, TypeScript strip-types runtime, OpenAI-compatible Chat Completions tools, `node:test`, Godot 4 GDScript validation tests.

---

### Task 1: Provider Tool JSON Schemas

**Files:**
- Create: `services/agent-service/src/tool_contracts.ts`
- Modify: `services/agent-service/src/provider.ts:11-18`
- Modify: `services/agent-service/tests/provider.test.ts`

- [ ] **Step 1: Write the failing Provider-body assertion**

Extend the first Provider test so its `AgentContext.allowed_tools` contains every current tool, then parse the captured request body and assert that `till`, `plant`, `sell`, `survey`, and `wait` expose exact schemas. The critical assertions are:

```ts
const providerBody = JSON.parse(capturedBody) as {
  tools: Array<{function: {name: string; parameters: Record<string, unknown>}}>;
};
const byName = new Map(providerBody.tools.map((tool) => [tool.function.name, tool.function.parameters]));
assert.deepEqual(byName.get("till"), {
  type: "object",
  properties: {plot: {type: "integer", minimum: 0, maximum: 255}},
  required: ["plot"],
  additionalProperties: false,
});
assert.deepEqual(byName.get("wait"), {
  type: "object", properties: {}, required: [], additionalProperties: false,
});
```

- [ ] **Step 2: Run the Provider test and verify RED**

Run:

```powershell
node --experimental-strip-types --test tests/provider.test.ts
```

Expected: FAIL because the current Provider schema is only `{type: "object", additionalProperties: true}`.

- [ ] **Step 3: Implement the shared schema catalog**

Create `tool_contracts.ts` with exact contracts matching `agent_action_validator.gd`:

```ts
export const SEED_IDS = ["tomato_seed", "carrot_seed", "potato_seed", "grain_seed", "lavender_seed", "grape_seed", "lemon_sapling"] as const;
export const BUILDING_TYPES = ["barn", "greenhouse", "workshop"] as const;
export const REGION_IDS = ["creek", "hills", "forest"] as const;
export const DISCOVERY_IDS = ["crop:moonflower", "terrain:cliff", "crop:stardust_fruit"] as const;

const objectSchema = (properties: Record<string, unknown>, required: string[]) => ({
  type: "object", properties, required, additionalProperties: false,
});

export function toolDescription(name: string): Record<string, unknown> {
  const parameters = TOOL_PARAMETERS[name];
  if (!parameters) throw new Error(`unknown_tool_contract:${name}`);
  return {
    type: "function",
    function: {
      name,
      description: `Role-authorized ${name} command. Return only arguments grounded in the supplied snapshot.`,
      parameters: structuredClone(parameters),
    },
  };
}
```

Define exact schemas for all current tools:

- `till`, `harvest`: integer `plot` in `0..255`.
- `plant`: integer `plot` plus enum `seed_item_id`.
- `buy`, `sell`, `prepare_supplies`, `propose_trade`: bounded string `item_id` plus integer `quantity` in `1..100`.
- `build`: enum `building_type` plus bounded string `building_id`.
- `travel`: enum `region_id` plus integer `duration_minutes` in `10..240`.
- `survey`: enum `region_id`.
- `collect_sample`, `register_discovery`: enum `discovery_id`.
- `speak`, `wait`: exact empty object.

Replace the generic local `toolDescription` in `provider.ts` with the shared import.

- [ ] **Step 4: Run the Provider test and verify GREEN**

Run:

```powershell
node --experimental-strip-types --test tests/provider.test.ts
```

Expected: all Provider tests PASS and captured credentials remain absent from the request body.

### Task 2: Provider Output Contract Validation

**Files:**
- Modify: `services/agent-service/src/tool_contracts.ts`
- Modify: `services/agent-service/src/provider_stream.ts:171-204`
- Modify: `services/agent-service/tests/provider_stream.test.ts`

- [ ] **Step 1: Write the failing invalid-argument regression test**

Add an assembler test reproducing the real `slot-0` failure:

```ts
test("rejects Provider tool arguments outside the authoritative contract", () => {
  const assembler = new AgentStreamAssembler();
  assembler.accept({choices: [{delta: {tool_calls: [{
    index: 0, id: "call-invalid",
    function: {name: "till", arguments: JSON.stringify({plot_index: "0"})},
  }]}, finish_reason: "tool_calls"}]});
  assert.throws(
    () => assembler.finish(request, ["till", "wait"]),
    /provider_invalid_intent:invalid_arguments/,
  );
});
```

Keep the existing fragmented-stream assembly test, but make its successful payload `{"plot":0}` and expect `{plot: 0}`.

- [ ] **Step 2: Run the stream test and verify RED**

Run:

```powershell
node --experimental-strip-types --test tests/provider_stream.test.ts
```

Expected: FAIL because `parseActionIntent` currently accepts every plain argument object.

- [ ] **Step 3: Implement runtime validation from the shared contract**

Export:

```ts
export function validToolArguments(name: string, value: unknown): boolean
```

Validate exact own keys, integer ranges, bounded IDs, and enum membership with the same constants used by the JSON Schemas. Do not coerce strings to numbers, rename `plot_index`, remove extra fields, or silently repair Provider output.

In `AgentStreamAssembler.finish()`, after JSON parsing and before constructing the accepted intent, reject invalid arguments:

```ts
if (!validToolArguments(tool.name, args)) {
  throw new Error("provider_invalid_intent:invalid_arguments");
}
```

- [ ] **Step 4: Run the stream test and verify GREEN**

Run:

```powershell
node --experimental-strip-types --test tests/provider_stream.test.ts
```

Expected: the invalid real-world payload is rejected and valid fragmented arguments still assemble successfully.

### Task 3: Full Regression and Connected Acceptance

**Files:**
- Verify: `services/agent-service/src/tool_contracts.ts`
- Verify: `services/agent-service/src/provider.ts`
- Verify: `services/agent-service/src/provider_stream.ts`
- Modify: `tests/agent_service_integration.gd`
- Verify: `scripts/ai_agent/agent_action_validator.gd`

- [ ] **Step 1: Run the complete TypeScript Agent Service suite**

Run:

```powershell
npm test
```

Expected: all Agent Service tests PASS.

- [ ] **Step 2: Strengthen connected acceptance with the Godot validator**

In `tests/agent_service_integration.gd`, load `AgentRegistryScript` and `AgentActionValidatorScript`, then replace the envelope-only final-intent check with:

```gdscript
var registry = AgentRegistryScript.new()
if not registry.load_defaults():
	_fail("unable to load Agent registry")
	return
var checked := AgentActionValidatorScript.new().validate(decision.body, registry, 7)
if not checked.ok:
	_fail("Provider returned invalid intent: " + str(checked.error))
	return
var intent := checked.value as Dictionary
```

- [ ] **Step 3: Run the Godot Agent suites**

Run:

```powershell
godot --headless --path . --script res://tests/run_agent_system_tests.gd
godot --headless --path . --quit-after 2
```

Expected: `786/786` Agent checks pass and the main scene initializes without script errors.

- [ ] **Step 4: Restart the local Agent Service**

Stop only the Node process whose command line is `node --experimental-strip-types src/server.ts` in `services/agent-service`, then restart it from that directory using the existing local configuration.

Expected: `GET http://127.0.0.1:8787/health` returns `status: ok` and `provider: configured`.

- [ ] **Step 5: Run connected streaming acceptance**

Run:

```powershell
godot --headless --path . --script res://tests/agent_service_integration.gd
```

Expected: the real Provider returns one decision that passes `AgentActionValidator`; the command prints `PASS: role agent service integration` and exits `0`.

- [ ] **Step 6: Check formatting and repository state**

Run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors and only the planned files are modified.

- [ ] **Step 7: Commit the fix**

```powershell
git add -- services/agent-service/src/tool_contracts.ts services/agent-service/src/provider.ts services/agent-service/src/provider_stream.ts services/agent-service/tests/provider.test.ts services/agent-service/tests/provider_stream.test.ts tests/agent_service_integration.gd
git commit -m "fix: enforce Agent tool argument contracts"
```
