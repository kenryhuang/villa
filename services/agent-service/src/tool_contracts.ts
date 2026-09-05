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
const TEXT_SCHEMA = {type: "string", minLength: 1, maxLength: 1000};
const NOTE_SCHEMA = {type: "string", maxLength: 500};
const AGREEMENT_ID_SCHEMA = {type: "string", minLength: 1, maxLength: 80};
const ITEM_QUANTITIES_SCHEMA = {type: "object", additionalProperties: {type: "integer", minimum: 1, maximum: 1000000}};
const ASSET_BUNDLE_SCHEMA = objectSchema({
  items: ITEM_QUANTITIES_SCHEMA,
  gold: {type: "integer", minimum: 0, maximum: 1000000000},
}, ["items", "gold"]);
const COMMITMENT_SCHEMA = objectSchema({participant_id: ITEM_ID_SCHEMA, items: ITEM_QUANTITIES_SCHEMA, gold: {type: "integer", minimum: 0, maximum: 1000000000}}, ["participant_id", "items", "gold"]);
const COOPERATION_TERMS_PROPERTIES = {
  commitments: {type: "array", items: COMMITMENT_SCHEMA, minItems: 2, maxItems: 3},
  reward_split: {type: "object", additionalProperties: {type: "integer", minimum: 1, maximum: 1000}},
  deadline_minutes: {type: "integer", minimum: 60, maximum: 5760},
};

function objectSchema(properties: Record<string, unknown>, required: string[]): JsonSchema {
  return {type: "object", properties, required, additionalProperties: false};
}

const TOOL_PARAMETERS: Readonly<Record<string, JsonSchema>> = {
  till: objectSchema({plot: PLOT_SCHEMA}, ["plot"]),
  harvest: objectSchema({plot: PLOT_SCHEMA, agreement_id: AGREEMENT_ID_SCHEMA}, ["plot"]),
  plant: objectSchema({
    plot: PLOT_SCHEMA,
    seed_item_id: {type: "string", enum: [...SEED_IDS]},
  }, ["plot", "seed_item_id"]),
  buy: objectSchema({item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA, agreement_id: AGREEMENT_ID_SCHEMA}, ["item_id", "quantity"]),
  sell: objectSchema({item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA, agreement_id: AGREEMENT_ID_SCHEMA}, ["item_id", "quantity"]),
  prepare_supplies: objectSchema({item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA}, ["item_id", "quantity"]),
  send_message: objectSchema({target_actor_id: ITEM_ID_SCHEMA, text: TEXT_SCHEMA, urgency: {type: "string", enum: ["normal", "urgent"]}}, ["target_actor_id", "text", "urgency"]),
  propose_trade: objectSchema({target_actor_id: ITEM_ID_SCHEMA, give: ASSET_BUNDLE_SCHEMA, receive: ASSET_BUNDLE_SCHEMA, expires_in_minutes: {type: "integer", minimum: 1, maximum: 10080}, note: NOTE_SCHEMA}, ["target_actor_id", "give", "receive", "expires_in_minutes", "note"]),
  counter_trade: objectSchema({offer_id: ITEM_ID_SCHEMA, give: ASSET_BUNDLE_SCHEMA, receive: ASSET_BUNDLE_SCHEMA, expires_in_minutes: {type: "integer", minimum: 1, maximum: 10080}, note: NOTE_SCHEMA}, ["offer_id", "give", "receive", "expires_in_minutes", "note"]),
  accept_trade: objectSchema({offer_id: ITEM_ID_SCHEMA}, ["offer_id"]),
  reject_trade: objectSchema({offer_id: ITEM_ID_SCHEMA, reason_code: ITEM_ID_SCHEMA}, ["offer_id", "reason_code"]),
  cancel_trade: objectSchema({offer_id: ITEM_ID_SCHEMA}, ["offer_id"]),
  propose_cooperation: objectSchema({
    objective_id: {type: "string", enum: ["joint_crop_supply", "exploration_sample", "material_procurement", "shared_construction"]},
    participants: {type: "array", items: ITEM_ID_SCHEMA, minItems: 1, maxItems: 2, uniqueItems: true},
    ...COOPERATION_TERMS_PROPERTIES,
    note: NOTE_SCHEMA,
  }, ["objective_id", "participants", "commitments", "reward_split", "deadline_minutes", "note"]),
  counter_cooperation: objectSchema({
    agreement_id: ITEM_ID_SCHEMA,
    revised_terms: objectSchema({...COOPERATION_TERMS_PROPERTIES}, ["commitments", "reward_split", "deadline_minutes"]),
    note: NOTE_SCHEMA,
  }, ["agreement_id", "revised_terms", "note"]),
  accept_cooperation: objectSchema({agreement_id: ITEM_ID_SCHEMA, terms_version: {type: "integer", minimum: 1, maximum: 1000}}, ["agreement_id", "terms_version"]),
  reject_cooperation: objectSchema({agreement_id: ITEM_ID_SCHEMA, reason_code: ITEM_ID_SCHEMA}, ["agreement_id", "reason_code"]),
  commit_contribution: objectSchema({agreement_id: ITEM_ID_SCHEMA, contribution_id: ITEM_ID_SCHEMA}, ["agreement_id", "contribution_id"]),
  cancel_cooperation: objectSchema({agreement_id: ITEM_ID_SCHEMA, reason_code: ITEM_ID_SCHEMA}, ["agreement_id", "reason_code"]),
  build: objectSchema({
    building_type: {type: "string", enum: [...BUILDING_TYPES]},
    building_id: ITEM_ID_SCHEMA,
	agreement_id: AGREEMENT_ID_SCHEMA,
  }, ["building_type", "building_id"]),
  travel: objectSchema({
    region_id: {type: "string", enum: [...REGION_IDS]},
    duration_minutes: {type: "integer", minimum: 10, maximum: 240},
  }, ["region_id", "duration_minutes"]),
  survey: objectSchema({
    region_id: {type: "string", enum: [...REGION_IDS]},
	agreement_id: AGREEMENT_ID_SCHEMA,
  }, ["region_id"]),
  collect_sample: objectSchema({
    discovery_id: {type: "string", enum: [...DISCOVERY_IDS]},
	agreement_id: AGREEMENT_ID_SCHEMA,
  }, ["discovery_id"]),
  register_discovery: objectSchema({
    discovery_id: {type: "string", enum: [...DISCOVERY_IDS]},
  }, ["discovery_id"]),
  propose_role_change: objectSchema({
    target_role_id: {type: "string", enum: [...ROLE_IDS]},
    motivation: {type: "string", minLength: 1, maxLength: 300},
  }, ["target_role_id", "motivation"]),
  speak: objectSchema({target_actor_id: ITEM_ID_SCHEMA, text: TEXT_SCHEMA}, ["target_actor_id", "text"]),
  wait: objectSchema({reason: {type: "string", minLength: 1, maxLength: 300}}, ["reason"]),
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

function hasExactKeysWithOptionalAgreement(value: Record<string, unknown>, expected: readonly string[]): boolean {
	return hasExactKeys(value, expected)
		|| (hasExactKeys(value, [...expected, "agreement_id"]) && isBoundedId(value.agreement_id));
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

function isText(value: unknown, maximum: number, allowEmpty = false): value is string {
  return typeof value === "string" && value.length <= maximum && (allowEmpty || value.trim().length > 0);
}

function isAssetBundle(value: unknown): value is {items: Record<string, number>; gold: number} {
  if (!isRecord(value) || !hasExactKeys(value, ["items", "gold"]) || !isRecord(value.items)
    || !isIntegerInRange(value.gold, 0, 1_000_000_000)) return false;
  return Object.keys(value.items).every(isBoundedId)
    && Object.values(value.items).every((quantity) => isIntegerInRange(quantity, 1, 1_000_000));
}

function validOfferTerms(value: Record<string, unknown>, idField: "target_actor_id" | "offer_id"): boolean {
  if (!(hasExactKeys(value, [idField, "give", "receive", "expires_in_minutes", "note"])
    && isBoundedId(value[idField]) && isAssetBundle(value.give) && isAssetBundle(value.receive)
    && isIntegerInRange(value.expires_in_minutes, 1, 10080) && isText(value.note, 500, true))) return false;
  const give = value.give as {items: Record<string, number>; gold: number};
  const receive = value.receive as {items: Record<string, number>; gold: number};
  return (give.gold > 0 || Object.keys(give.items).length > 0)
    && (receive.gold > 0 || Object.keys(receive.items).length > 0)
    && Object.keys(give.items).every((itemId) => !Object.hasOwn(receive.items, itemId));
}

function validCommitment(value: unknown): boolean {
  return isRecord(value) && hasExactKeys(value, ["participant_id", "items", "gold"])
    && isBoundedId(value.participant_id) && isRecord(value.items)
    && Object.keys(value.items).every(isBoundedId)
    && Object.values(value.items).every((quantity) => isIntegerInRange(quantity, 1, 1_000_000))
    && isIntegerInRange(value.gold, 0, 1_000_000_000);
}

function validCooperationTerms(value: unknown): boolean {
  if (!isRecord(value) || !hasExactKeys(value, ["commitments", "reward_split", "deadline_minutes"])
    || !Array.isArray(value.commitments) || value.commitments.length < 2 || value.commitments.length > 3
    || !value.commitments.every(validCommitment) || !isRecord(value.reward_split)
    || !isIntegerInRange(value.deadline_minutes, 60, 5760)) return false;
  return Object.keys(value.reward_split).every(isBoundedId)
    && Object.values(value.reward_split).every((weight) => isIntegerInRange(weight, 1, 1000));
}

export function validToolArguments(name: string, value: unknown): boolean {
  if (!isRecord(value)) return false;
  switch (name) {
    case "till":
    case "harvest":
	  return hasExactKeysWithOptionalAgreement(value, ["plot"]) && isIntegerInRange(value.plot, 0, 255);
    case "plant":
      return hasExactKeys(value, ["plot", "seed_item_id"])
        && isIntegerInRange(value.plot, 0, 255)
        && isOneOf(value.seed_item_id, SEED_IDS);
    case "buy":
    case "sell":
	  return hasExactKeysWithOptionalAgreement(value, ["item_id", "quantity"])
		&& isBoundedId(value.item_id)
		&& isIntegerInRange(value.quantity, 1, 100);
    case "prepare_supplies":
      return hasExactKeys(value, ["item_id", "quantity"])
        && isBoundedId(value.item_id)
        && isIntegerInRange(value.quantity, 1, 100);
    case "send_message":
      return hasExactKeys(value, ["target_actor_id", "text", "urgency"])
        && isBoundedId(value.target_actor_id) && isText(value.text, 1000)
        && isOneOf(value.urgency, ["normal", "urgent"]);
    case "propose_trade": return validOfferTerms(value, "target_actor_id");
    case "counter_trade": return validOfferTerms(value, "offer_id");
    case "accept_trade":
    case "cancel_trade":
      return hasExactKeys(value, ["offer_id"]) && isBoundedId(value.offer_id);
    case "reject_trade":
      return hasExactKeys(value, ["offer_id", "reason_code"])
        && isBoundedId(value.offer_id) && isBoundedId(value.reason_code);
    case "propose_cooperation": {
      if (!hasExactKeys(value, ["objective_id", "participants", "commitments", "reward_split", "deadline_minutes", "note"])
        || !isOneOf(value.objective_id, ["joint_crop_supply", "exploration_sample", "material_procurement", "shared_construction"])
        || !Array.isArray(value.participants) || value.participants.length < 1 || value.participants.length > 2
        || !value.participants.every(isBoundedId) || new Set(value.participants).size !== value.participants.length
        || !isText(value.note, 500, true)) return false;
      return validCooperationTerms({commitments: value.commitments, reward_split: value.reward_split, deadline_minutes: value.deadline_minutes});
    }
    case "counter_cooperation":
      return hasExactKeys(value, ["agreement_id", "revised_terms", "note"])
        && isBoundedId(value.agreement_id) && validCooperationTerms(value.revised_terms)
        && isText(value.note, 500, true);
    case "accept_cooperation":
      return hasExactKeys(value, ["agreement_id", "terms_version"])
        && isBoundedId(value.agreement_id) && isIntegerInRange(value.terms_version, 1, 1000);
    case "reject_cooperation":
    case "cancel_cooperation":
      return hasExactKeys(value, ["agreement_id", "reason_code"])
        && isBoundedId(value.agreement_id) && isBoundedId(value.reason_code);
    case "commit_contribution":
      return hasExactKeys(value, ["agreement_id", "contribution_id"])
        && isBoundedId(value.agreement_id) && isBoundedId(value.contribution_id);
    case "build":
	  return hasExactKeysWithOptionalAgreement(value, ["building_type", "building_id"])
        && isOneOf(value.building_type, BUILDING_TYPES)
        && isBoundedId(value.building_id);
    case "travel":
      return hasExactKeys(value, ["region_id", "duration_minutes"])
        && isOneOf(value.region_id, REGION_IDS)
        && isIntegerInRange(value.duration_minutes, 10, 240);
    case "survey":
	  return hasExactKeysWithOptionalAgreement(value, ["region_id"])
        && isOneOf(value.region_id, REGION_IDS);
	case "collect_sample":
	  return hasExactKeysWithOptionalAgreement(value, ["discovery_id"])
		&& isOneOf(value.discovery_id, DISCOVERY_IDS);
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
      return hasExactKeys(value, ["target_actor_id", "text"])
        && isBoundedId(value.target_actor_id) && isText(value.text, 1000);
    case "wait":
      return hasExactKeys(value, ["reason"]) && isText(value.reason, 300);
    default:
      return false;
  }
}

export function toolDescription(name: string): Record<string, unknown> {
  const parameters = TOOL_PARAMETERS[name];
  if (!parameters) throw new Error(`unknown_tool_contract:${name}`);
  const farmingDescriptions: Record<string, string> = {
    harvest: "Harvest a mature crop for produce, or clear a withered crop to leave tilled soil with no items or inventory rewards. Rejects growing and dormant crops. Use the plot state and available_actions from the current farm context.",
    plant: "Plant one seed on a tilled plot. Check crop_options (or inspect_crop_options) for plantable_plots, unavailable_reason, and seed_quantity. Season names in public_world_state are authoritative; do not infer planting validity from an empty plot or numeric season alone.",
  };
  return {
    type: "function",
    function: {
      name,
      description: farmingDescriptions[name] ?? `Role-authorized ${name} command. Return only arguments grounded in the supplied context.`,
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
