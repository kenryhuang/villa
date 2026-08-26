type JsonSchema = Record<string, unknown>;

export const SEED_IDS = [
  "tomato_seed", "carrot_seed", "potato_seed", "grain_seed",
  "lavender_seed", "grape_seed", "lemon_sapling",
] as const;

export const BUILDING_TYPES = ["barn", "greenhouse", "workshop"] as const;
export const REGION_IDS = ["creek", "hills", "forest"] as const;
export const DISCOVERY_IDS = [
  "crop:moonflower", "terrain:cliff", "crop:stardust_fruit",
] as const;

const PLOT_SCHEMA = {type: "integer", minimum: 0, maximum: 255};
const ITEM_ID_SCHEMA = {type: "string", minLength: 1, maxLength: 80};
const QUANTITY_SCHEMA = {type: "integer", minimum: 1, maximum: 100};

function objectSchema(properties: Record<string, unknown>, required: string[]): JsonSchema {
  return {type: "object", properties, required, additionalProperties: false};
}

const TOOL_PARAMETERS: Readonly<Record<string, JsonSchema>> = {
  till: objectSchema({plot: PLOT_SCHEMA}, ["plot"]),
  harvest: objectSchema({plot: PLOT_SCHEMA}, ["plot"]),
  plant: objectSchema({
    plot: PLOT_SCHEMA,
    seed_item_id: {type: "string", enum: [...SEED_IDS]},
  }, ["plot", "seed_item_id"]),
  buy: objectSchema({item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA}, ["item_id", "quantity"]),
  sell: objectSchema({item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA}, ["item_id", "quantity"]),
  prepare_supplies: objectSchema({item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA}, ["item_id", "quantity"]),
  propose_trade: objectSchema({item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA}, ["item_id", "quantity"]),
  build: objectSchema({
    building_type: {type: "string", enum: [...BUILDING_TYPES]},
    building_id: ITEM_ID_SCHEMA,
  }, ["building_type", "building_id"]),
  travel: objectSchema({
    region_id: {type: "string", enum: [...REGION_IDS]},
    duration_minutes: {type: "integer", minimum: 10, maximum: 240},
  }, ["region_id", "duration_minutes"]),
  survey: objectSchema({
    region_id: {type: "string", enum: [...REGION_IDS]},
  }, ["region_id"]),
  collect_sample: objectSchema({
    discovery_id: {type: "string", enum: [...DISCOVERY_IDS]},
  }, ["discovery_id"]),
  register_discovery: objectSchema({
    discovery_id: {type: "string", enum: [...DISCOVERY_IDS]},
  }, ["discovery_id"]),
  speak: objectSchema({}, []),
  wait: objectSchema({}, []),
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const keys = Object.keys(value);
  return keys.length === expected.length && expected.every((key) => Object.hasOwn(value, key));
}

function isIntegerInRange(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= minimum && value <= maximum;
}

function isBoundedId(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0 && value.length <= 80;
}

function isOneOf(value: unknown, allowed: readonly string[]): value is string {
  return typeof value === "string" && allowed.includes(value);
}

export function validToolArguments(name: string, value: unknown): boolean {
  if (!isRecord(value)) return false;
  switch (name) {
    case "till":
    case "harvest":
      return hasExactKeys(value, ["plot"]) && isIntegerInRange(value.plot, 0, 255);
    case "plant":
      return hasExactKeys(value, ["plot", "seed_item_id"])
        && isIntegerInRange(value.plot, 0, 255)
        && isOneOf(value.seed_item_id, SEED_IDS);
    case "buy":
    case "sell":
    case "prepare_supplies":
    case "propose_trade":
      return hasExactKeys(value, ["item_id", "quantity"])
        && isBoundedId(value.item_id)
        && isIntegerInRange(value.quantity, 1, 100);
    case "build":
      return hasExactKeys(value, ["building_type", "building_id"])
        && isOneOf(value.building_type, BUILDING_TYPES)
        && isBoundedId(value.building_id);
    case "travel":
      return hasExactKeys(value, ["region_id", "duration_minutes"])
        && isOneOf(value.region_id, REGION_IDS)
        && isIntegerInRange(value.duration_minutes, 10, 240);
    case "survey":
      return hasExactKeys(value, ["region_id"])
        && isOneOf(value.region_id, REGION_IDS);
    case "collect_sample":
    case "register_discovery":
      return hasExactKeys(value, ["discovery_id"])
        && isOneOf(value.discovery_id, DISCOVERY_IDS);
    case "speak":
    case "wait":
      return hasExactKeys(value, []);
    default:
      return false;
  }
}

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
