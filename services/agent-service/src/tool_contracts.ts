type JsonSchema = Record<string, unknown>;
import type {AgentContext} from "./agents.ts";

export const READ_TOOL_NAMES = [
  "inspect_market_item", "compare_market_items", "inspect_known_actor",
  "inspect_relationship", "inspect_trade_offer", "inspect_agreement",
  "inspect_role_option", "inspect_self_resources", "inspect_farm_plots",
  "inspect_crop_options", "inspect_market_depth", "inspect_price_history",
  "inspect_region", "inspect_known_discoveries",
] as const;
export type ReadToolName = typeof READ_TOOL_NAMES[number];

export const SEED_IDS = [
  "tomato_seed", "carrot_seed", "potato_seed", "grain_seed",
  "lavender_seed", "grape_seed", "lemon_sapling",
] as const;

export const BUILDING_TYPES = ["barn", "greenhouse", "workshop"] as const;
export const REGION_IDS = ["creek", "hills", "forest"] as const;
export const DISCOVERY_IDS = [
  "crop:moonflower", "terrain:cliff", "crop:stardust_fruit",
] as const;
export const ROLE_IDS = ["farmer", "merchant", "explorer"] as const;

const PLOT_SCHEMA = {type: "integer", minimum: 0, maximum: 255};
const ITEM_ID_SCHEMA = {type: "string", minLength: 1, maxLength: 80};
const QUANTITY_SCHEMA = {type: "integer", minimum: 1, maximum: 100};
const ID_LIST_SCHEMA = {type: "array", items: ITEM_ID_SCHEMA, minItems: 1, maxItems: 20, uniqueItems: true};

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
  propose_role_change: objectSchema({
    target_role_id: {type: "string", enum: [...ROLE_IDS]},
    motivation: {type: "string", minLength: 1, maxLength: 300},
  }, ["target_role_id", "motivation"]),
  speak: objectSchema({}, []),
  wait: objectSchema({}, []),
};

const READ_TOOL_PARAMETERS: Readonly<Record<ReadToolName, JsonSchema>> = {
  inspect_market_item: objectSchema({item_id: ITEM_ID_SCHEMA}, ["item_id"]),
  compare_market_items: objectSchema({item_ids: ID_LIST_SCHEMA}, ["item_ids"]),
  inspect_known_actor: objectSchema({actor_id: ITEM_ID_SCHEMA}, ["actor_id"]),
  inspect_relationship: objectSchema({actor_id: ITEM_ID_SCHEMA}, ["actor_id"]),
  inspect_trade_offer: objectSchema({offer_id: ITEM_ID_SCHEMA}, ["offer_id"]),
  inspect_agreement: objectSchema({agreement_id: ITEM_ID_SCHEMA}, ["agreement_id"]),
  inspect_role_option: objectSchema({role_id: ITEM_ID_SCHEMA}, ["role_id"]),
  inspect_self_resources: objectSchema({item_ids: ID_LIST_SCHEMA}, ["item_ids"]),
  inspect_farm_plots: objectSchema({}, []),
  inspect_crop_options: objectSchema({}, []),
  inspect_market_depth: objectSchema({item_id: ITEM_ID_SCHEMA}, ["item_id"]),
  inspect_price_history: objectSchema({item_id: ITEM_ID_SCHEMA}, ["item_id"]),
  inspect_region: objectSchema({region_id: ITEM_ID_SCHEMA}, ["region_id"]),
  inspect_known_discoveries: objectSchema({}, []),
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

function isIdList(value: unknown): value is string[] {
  return Array.isArray(value) && value.length >= 1 && value.length <= 20
    && value.every(isBoundedId) && new Set(value).size === value.length;
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
    case "propose_role_change":
      return hasExactKeys(value, ["target_role_id", "motivation"])
        && isOneOf(value.target_role_id, ROLE_IDS)
        && typeof value.motivation === "string"
        && value.motivation.trim().length > 0
        && value.motivation.length <= 300;
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

export function validReadToolArguments(name: string, value: unknown): boolean {
  if (!isRecord(value)) return false;
  switch (name as ReadToolName) {
    case "compare_market_items":
    case "inspect_self_resources":
      return hasExactKeys(value, ["item_ids"]) && isIdList(value.item_ids);
    case "inspect_market_item":
    case "inspect_market_depth":
    case "inspect_price_history":
      return hasExactKeys(value, ["item_id"]) && isBoundedId(value.item_id);
    case "inspect_known_actor":
    case "inspect_relationship":
      return hasExactKeys(value, ["actor_id"]) && isBoundedId(value.actor_id);
    case "inspect_trade_offer":
      return hasExactKeys(value, ["offer_id"]) && isBoundedId(value.offer_id);
    case "inspect_agreement":
      return hasExactKeys(value, ["agreement_id"]) && isBoundedId(value.agreement_id);
    case "inspect_role_option":
      return hasExactKeys(value, ["role_id"]) && isBoundedId(value.role_id);
    case "inspect_region":
      return hasExactKeys(value, ["region_id"]) && isBoundedId(value.region_id);
    case "inspect_farm_plots":
    case "inspect_crop_options":
    case "inspect_known_discoveries":
      return hasExactKeys(value, []);
    default:
      return false;
  }
}

export function readToolDescription(name: string): Record<string, unknown> {
  const parameters = READ_TOOL_PARAMETERS[name as ReadToolName];
  if (!parameters) throw new Error(`unknown_read_tool_contract:${name}`);
  return {
    type: "function",
    function: {
      name,
      description: `Read only from this decision's immutable, visibility-filtered context using ${name}.`,
      parameters: structuredClone(parameters),
    },
  };
}

function collectionValue(container: Record<string, unknown>, field: string): unknown {
  return Object.hasOwn(container, field) ? container[field] : undefined;
}

function findRecord(value: unknown, idField: string, id: string): unknown {
  if (Array.isArray(value)) return value.find((entry) => isRecord(entry) && entry[idField] === id);
  if (isRecord(value)) return value[id];
  return undefined;
}

function found(value: unknown): Record<string, unknown> {
  return value === undefined ? {found: false} : {found: true, value: structuredClone(value)};
}

export function executeReadTool(context: AgentContext, name: string, args: Record<string, unknown>): Record<string, unknown> {
  if (!context.allowed_read_tools.includes(name)) throw new Error("provider_unauthorized_read_tool");
  if (!validReadToolArguments(name, args)) throw new Error("provider_invalid_read_arguments");
  switch (name as ReadToolName) {
    case "inspect_market_item": return found(context.market_view[String(args.item_id)]);
    case "compare_market_items": return {items: Object.fromEntries((args.item_ids as string[]).map((id) => [id, structuredClone(context.market_view[id] ?? null)]))};
    case "inspect_known_actor": return found(findRecord(context.known_actors, "actor_id", String(args.actor_id)));
    case "inspect_relationship": return found(findRecord(collectionValue(context.actor_context, "relationships"), "actor_id", String(args.actor_id)));
    case "inspect_trade_offer": return found(findRecord(collectionValue(context.interaction_view, "active_offers") ?? collectionValue(context.interaction_view, "offers"), "offer_id", String(args.offer_id)));
    case "inspect_agreement": return found(findRecord(collectionValue(context.agreement_view, "active_agreements") ?? collectionValue(context.agreement_view, "agreements"), "agreement_id", String(args.agreement_id)));
    case "inspect_role_option": return found(findRecord(collectionValue(context.public_world_state, "role_options"), "role_id", String(args.role_id)));
    case "inspect_self_resources": {
      const self = isRecord(context.actor_context.self) ? context.actor_context.self : {};
      const inventory = isRecord(self.inventory) ? self.inventory : {};
      return {gold: typeof self.gold === "number" ? self.gold : 0, items: Object.fromEntries((args.item_ids as string[]).map((id) => [id, inventory[id] ?? 0]))};
    }
    case "inspect_farm_plots": return {plots: structuredClone(context.actor_context.farm ?? [])};
    case "inspect_crop_options": return {crop_options: structuredClone(context.actor_context.crop_options ?? context.public_world_state.crop_options ?? [])};
    case "inspect_market_depth": return found(isRecord(context.market_view[String(args.item_id)]) ? (context.market_view[String(args.item_id)] as Record<string, unknown>).depth : undefined);
    case "inspect_price_history": return found(isRecord(context.market_view[String(args.item_id)]) ? (context.market_view[String(args.item_id)] as Record<string, unknown>).price_history : undefined);
    case "inspect_region": return found(findRecord(context.public_world_state.regions ?? context.actor_context.regions, "region_id", String(args.region_id)));
    case "inspect_known_discoveries": return {discoveries: structuredClone(context.actor_context.known_discoveries ?? context.public_world_state.known_discoveries ?? [])};
    default: throw new Error("provider_unknown_read_tool");
  }
}
