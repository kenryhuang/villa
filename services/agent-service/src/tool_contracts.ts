type JsonSchema = Record<string, unknown>;
import type {AgentContext} from "./agents.ts";

export const READ_TOOL_NAMES = [
  "inspect_map", "inspect_buildings", "inspect_building", "inspect_characters",
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

const WORK_TERMS = objectSchema({
  worker_id: ITEM_ID_SCHEMA, recipient_id: ITEM_ID_SCHEMA, kind: {type: "string", enum: ["delivery", "processing", "supply"]},
  item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA, wage: {type: "integer", minimum: 0, maximum: 100000},
  building_id: {type: "string", maxLength: 100}, recipe_id: {type: "string", maxLength: 100},
  max_fee: {type: "integer", minimum: 0, maximum: 100000}, deadline_minutes: {type: "integer", minimum: 30, maximum: 10080},
  cycles: {type: "integer", minimum: 1, maximum: 7}, interval_minutes: {type: "integer", minimum: 0, maximum: 1080},
  parent_contract: {type: "string", maxLength: 100}, note: {type: "string", maxLength: 300},
}, ["worker_id", "recipient_id", "kind", "item_id", "quantity", "wage", "building_id", "recipe_id", "max_fee", "deadline_minutes", "cycles", "interval_minutes", "parent_contract", "note"]);

const TOOL_PARAMETERS: Readonly<Record<string, JsonSchema>> = {
  propose_investigation: objectSchema({worker_id: ITEM_ID_SCHEMA, funder_id: ITEM_ID_SCHEMA, region_id: {type: "string", enum: [...REGION_IDS]}, reward: {type: "integer", minimum: 0, maximum: 100000}, deadline_minutes: {type: "integer", minimum: 60, maximum: 10080}, allow_old_report: {type: "boolean"}, require_sample: {type: "boolean"}}, ["worker_id", "funder_id", "region_id", "reward", "deadline_minutes", "allow_old_report", "require_sample"]),
  accept_investigation: objectSchema({assignment_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["assignment_id", "version"]),
  cancel_investigation: objectSchema({assignment_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["assignment_id", "version"]),
  propose_activity: objectSchema({kind: {type: "string", enum: ["fishing", "golf"]}, starts_in: {type: "integer", minimum: 60, maximum: 1080}, duration: {type: "integer", minimum: 120, maximum: 1080}, capacity: {type: "integer", minimum: 2, maximum: 16}, minimum: {type: "integer", minimum: 1, maximum: 16}, ticket: {type: "integer", minimum: 0, maximum: 50}, sponsor: {type: "integer", minimum: 0, maximum: 1000}, reward: {type: "integer", minimum: 0, maximum: 100}, food_quantity: {type: "integer", minimum: 1, maximum: 16}, food_price: {type: "integer", minimum: 1, maximum: 100}}, ["kind", "starts_in", "duration", "capacity", "minimum", "ticket", "sponsor", "reward", "food_quantity", "food_price"]),
  public_activity_plan: objectSchema({expected_version: {type: "integer", minimum: 1, maximum: 1000000000}, reason: {type: "string", minLength: 1, maxLength: 100}, terms: objectSchema({kind: {type: "string", enum: ["fishing", "golf"]}, starts_in: {type: "integer", minimum: 60, maximum: 1080}, duration: {type: "integer", minimum: 120, maximum: 1080}, capacity: {type: "integer", minimum: 2, maximum: 16}, minimum: {type: "integer", minimum: 1, maximum: 16}, ticket: {type: "integer", minimum: 0, maximum: 50}, sponsor: {type: "integer", minimum: 0, maximum: 1000}, reward: {type: "integer", minimum: 0, maximum: 100}, food_quantity: {type: "integer", minimum: 1, maximum: 16}, food_price: {type: "integer", minimum: 1, maximum: 100}}, ["kind", "starts_in", "duration", "capacity", "minimum", "ticket", "sponsor", "reward", "food_quantity", "food_price"])}, ["expected_version", "reason", "terms"]),
  enroll_activity: objectSchema({event_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["event_id", "version"]),
  leave_activity: objectSchema({event_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["event_id", "version"]),
  cancel_activity: objectSchema({event_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["event_id", "version"]),
  public_repair_plan: objectSchema({expected_version: {type: "integer", minimum: 1, maximum: 1000000000}, reason: {type: "string", minLength: 1, maxLength: 100}}, ["expected_version", "reason"]),
  contribute_route_repair: objectSchema({event_id: ITEM_ID_SCHEMA, materials: objectSchema({wood: {type: "integer", minimum: 1, maximum: 6}, stone: {type: "integer", minimum: 1, maximum: 4}}, []), labor_minutes: {type: "integer", minimum: 0, maximum: 60}}, ["event_id", "materials", "labor_minutes"]),
  offer_intelligence: objectSchema({target_actor_id: ITEM_ID_SCHEMA, discovery_id: ITEM_ID_SCHEMA, price: {type: "integer", minimum: 1, maximum: 100000}, ttl: {type: "integer", minimum: 10, maximum: 1080}}, ["target_actor_id", "discovery_id", "price", "ttl"]),
  buy_intelligence: objectSchema({offer_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["offer_id", "version"]),
  share_intelligence: objectSchema({target_actor_id: ITEM_ID_SCHEMA, discovery_id: ITEM_ID_SCHEMA}, ["target_actor_id", "discovery_id"]),
  propose_joint_project: objectSchema({partner_id: ITEM_ID_SCHEMA, plan: {type: "object"}, partner_gold: {type: "integer", minimum: 0, maximum: 1000000}, partner_materials: ITEM_QUANTITIES_SCHEMA, partner_profit_percent: {type: "integer", minimum: 1, maximum: 99}, equipment_id: ITEM_ID_SCHEMA}, ["partner_id", "plan", "partner_gold", "partner_materials", "partner_profit_percent"]),
  accept_joint_project: objectSchema({venture_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["venture_id", "version"]),
  exit_joint_project: objectSchema({venture_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["venture_id", "version"]),
  propose_work: WORK_TERMS,
  counter_work: objectSchema({contract_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}, terms: WORK_TERMS}, ["contract_id", "version", "terms"]),
  accept_work: objectSchema({contract_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["contract_id", "version"]),
  cancel_work: objectSchema({contract_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["contract_id", "version"]),
  start_learning: objectSchema({skill_id: {type: "string", enum: ["ingredient_selection"]}}, ["skill_id"]),
  start_leisure: objectSchema({activity: {type: "string", enum: ["visit", "rest"]}, partner_id: ITEM_ID_SCHEMA}, ["activity", "partner_id"]),
  manage_building: objectSchema({building_id: ITEM_ID_SCHEMA, operation: {type: "string", enum: ["maintain", "pricing", "open", "close"]}, fee: {type: "integer", minimum: 0, maximum: 1000000}, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["building_id", "operation", "fee", "version"]),
  submit_project: objectSchema({goal: {type: "string", minLength: 1, maxLength: 500}, budget: {type: "integer", minimum: 0, maximum: 1000000}, deadline_minutes: {type: "integer", minimum: 60, maximum: 10080}, materials: ITEM_QUANTITIES_SCHEMA, steps: {type: "array", minItems: 1, maxItems: 12, items: objectSchema({id: ITEM_ID_SCHEMA, capability: {type: "string", enum: ["buy", "sell", "move", "rent", "wait_production", "reserve_plot", "build", "wait_construction", "set_policy", "claim", "deliver"]}, depends_on: {type: "array", items: ITEM_ID_SCHEMA}, arguments: {type: "object"}}, ["id", "capability", "depends_on", "arguments"])}}, ["goal", "budget", "deadline_minutes", "materials", "steps"]),
  propose_delivery: objectSchema({task_id: {type: "string", maxLength: 100}, version: {type: "integer", minimum: 0, maximum: 1000000}, recipient_id: ITEM_ID_SCHEMA, item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA, reward: {type: "integer", minimum: 0, maximum: 1000000}, deadline_minutes: {type: "integer", minimum: 1, maximum: 1080}, schedule: {type: "string", enum: ["now", "after_step", "queue"]}, note: NOTE_SCHEMA}, ["task_id", "version", "recipient_id", "item_id", "quantity", "reward", "deadline_minutes", "schedule", "note"]),
  cancel_delivery: objectSchema({task_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}}, ["task_id", "version"]),
  revise_project: objectSchema({project_id: ITEM_ID_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}, plan: {type: "object"}, source: {type: "string", enum: ["dialogue", "self_review"]}}, ["project_id", "version", "plan", "source"]),
  public_food_plan: objectSchema({expected_version: {type: "integer", minimum: 1, maximum: 1000000000}, reason: {type: "string", minLength: 1, maxLength: 100}, quantity: {type: "integer", minimum: 1, maximum: 12}, unit_reward: {type: "integer", minimum: 1, maximum: 200}, deadline_minutes: {type: "integer", minimum: 60, maximum: 1080}}, ["expected_version", "reason", "quantity", "unit_reward", "deadline_minutes"]),
  public_wait: objectSchema({expected_version: {type: "integer", minimum: 1, maximum: 1000000000}, reason: {type: "string", minLength: 1, maxLength: 100}}, ["expected_version", "reason"]),
  retry_project: objectSchema({project_id: ITEM_ID_SCHEMA}, ["project_id"]),
  cancel_project: objectSchema({project_id: ITEM_ID_SCHEMA}, ["project_id"]),
  suggest_behavior: objectSchema({text: {type: "string", minLength: 1, maxLength: 500}, ttl: {type: "integer", minimum: 1, maximum: 1080}}, ["text", "ttl"]),
  publish_commission: objectSchema({demand_id: ITEM_ID_SCHEMA, item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA, unit_reward: {type: "integer", minimum: 1, maximum: 1000000}, kind: {type: "string", enum: ["purchase", "processing"]}, max_claims: {type: "integer", minimum: 1, maximum: 10}, deadline_minutes: {type: "integer", minimum: 1, maximum: 10080}}, ["demand_id", "item_id", "quantity", "unit_reward", "kind", "max_claims", "deadline_minutes"]),
  propose_player_commission: objectSchema({demand_id: ITEM_ID_SCHEMA, item_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA, unit_reward: {type: "integer", minimum: 1, maximum: 1000000}, kind: {type: "string", enum: ["purchase", "processing"]}, max_claims: {type: "integer", minimum: 1, maximum: 10}, deadline_minutes: {type: "integer", minimum: 1, maximum: 10080}}, ["demand_id", "item_id", "quantity", "unit_reward", "kind", "max_claims", "deadline_minutes"]),
  claim_commission: objectSchema({commission_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA}, ["commission_id", "quantity"]),
  deliver_commission: objectSchema({claim_id: ITEM_ID_SCHEMA, quantity: QUANTITY_SCHEMA, version: {type: "integer", minimum: 1, maximum: 1000000}, order_id: {type: "string", maxLength: 100}}, ["claim_id", "quantity", "version", "order_id"]),
  move: objectSchema({x: {type: "number", minimum: -176, maximum: 80}, z: {type: "number", minimum: -80, maximum: 144}}, ["x", "z"]),
  rent_production: objectSchema({building_id: ITEM_ID_SCHEMA, recipe_id: ITEM_ID_SCHEMA, batches: QUANTITY_SCHEMA, max_fee: {type: "integer", minimum: 0, maximum: 1000000}}, ["building_id", "recipe_id", "batches", "max_fee"]),
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
    discovery_id: ITEM_ID_SCHEMA,
	agreement_id: AGREEMENT_ID_SCHEMA,
  }, ["discovery_id"]),
  register_discovery: objectSchema({
    discovery_id: ITEM_ID_SCHEMA,
  }, ["discovery_id"]),
  propose_role_change: objectSchema({
    target_role_id: {type: "string", enum: [...ROLE_IDS]},
    motivation: {type: "string", minLength: 1, maxLength: 300},
  }, ["target_role_id", "motivation"]),
  speak: objectSchema({target_actor_id: ITEM_ID_SCHEMA, text: TEXT_SCHEMA}, ["target_actor_id", "text"]),
  wait: objectSchema({reason: {type: "string", minLength: 1, maxLength: 300}}, ["reason"]),
};

const READ_TOOL_PARAMETERS: Readonly<Record<ReadToolName, JsonSchema>> = {
  inspect_map: objectSchema({}, []),
  inspect_buildings: objectSchema({}, []),
  inspect_building: objectSchema({building_id: ITEM_ID_SCHEMA}, ["building_id"]),
  inspect_characters: objectSchema({}, []),
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

function validWorkTerms(v: unknown): boolean {
  return isRecord(v) && hasExactKeys(v, WORK_TERMS.required as string[]) && isBoundedId(v.worker_id) && isBoundedId(v.recipient_id)
    && isOneOf(v.kind, ["delivery", "processing", "supply"]) && isBoundedId(v.item_id)
    && isIntegerInRange(v.quantity, 1, 100) && isIntegerInRange(v.wage, 0, 100000) && isIntegerInRange(v.max_fee, 0, 100000)
    && isText(v.building_id, 100, true) && isText(v.recipe_id, 100, true) && isText(v.parent_contract, 100, true) && isText(v.note, 300, true)
    && isIntegerInRange(v.deadline_minutes, 30, 10080) && isIntegerInRange(v.cycles, 1, 7) && isIntegerInRange(v.interval_minutes, 0, 1080)
    && (v.cycles === 1 || v.interval_minutes >= 60) && (v.kind !== "processing" || (isBoundedId(v.building_id) && isBoundedId(v.recipe_id)));
}

export function validToolArguments(name: string, value: unknown): boolean {
  if (!isRecord(value)) return false;
  switch (name) {
    case "propose_investigation": return hasExactKeys(value, ["worker_id", "funder_id", "region_id", "reward", "deadline_minutes", "allow_old_report", "require_sample"]) && isBoundedId(value.worker_id) && isBoundedId(value.funder_id) && value.worker_id !== value.funder_id && isOneOf(value.region_id, REGION_IDS) && isIntegerInRange(value.reward, 0, 100000) && isIntegerInRange(value.deadline_minutes, 60, 10080) && typeof value.allow_old_report === "boolean" && typeof value.require_sample === "boolean";
    case "accept_investigation": case "cancel_investigation": return hasExactKeys(value, ["assignment_id", "version"]) && isBoundedId(value.assignment_id) && isIntegerInRange(value.version, 1, 1000000);
    case "propose_activity": return hasExactKeys(value, ["kind", "starts_in", "duration", "capacity", "minimum", "ticket", "sponsor", "reward", "food_quantity", "food_price"]) && ["fishing", "golf"].includes(String(value.kind)) && isIntegerInRange(value.starts_in, 60, 1080) && isIntegerInRange(value.duration, 120, 1080) && isIntegerInRange(value.capacity, 2, 16) && isIntegerInRange(value.minimum, 1, Number(value.capacity)) && isIntegerInRange(value.ticket, 0, 50) && isIntegerInRange(value.sponsor, 0, 1000) && isIntegerInRange(value.reward, 0, 100) && isIntegerInRange(value.food_quantity, 1, Number(value.capacity)) && isIntegerInRange(value.food_price, 1, 100);
    case "public_activity_plan": return hasExactKeys(value, ["expected_version", "reason", "terms"]) && isIntegerInRange(value.expected_version, 1, 1000000000) && isText(value.reason, 100) && validToolArguments("propose_activity", value.terms);
    case "enroll_activity": case "leave_activity": case "cancel_activity": return hasExactKeys(value, ["event_id", "version"]) && isBoundedId(value.event_id) && isIntegerInRange(value.version, 1, 1000000);
    case "public_repair_plan": return hasExactKeys(value, ["expected_version", "reason"]) && isIntegerInRange(value.expected_version, 1, 1000000000) && isText(value.reason, 100);
    case "contribute_route_repair": return hasExactKeys(value, ["event_id", "materials", "labor_minutes"]) && isBoundedId(value.event_id) && isRecord(value.materials) && Object.entries(value.materials).every(([k,v]) => (k === "wood" || k === "stone") && isIntegerInRange(v, 1, k === "wood" ? 6 : 4)) && isIntegerInRange(value.labor_minutes, 0, 60) && (Object.keys(value.materials).length > 0 || Number(value.labor_minutes) > 0);
    case "offer_intelligence": return hasExactKeys(value, ["target_actor_id", "discovery_id", "price", "ttl"]) && isBoundedId(value.target_actor_id) && isBoundedId(value.discovery_id) && isIntegerInRange(value.price, 1, 100000) && isIntegerInRange(value.ttl, 10, 1080);
    case "buy_intelligence": return hasExactKeys(value, ["offer_id", "version"]) && isBoundedId(value.offer_id) && isIntegerInRange(value.version, 1, 1000000);
    case "share_intelligence": return hasExactKeys(value, ["target_actor_id", "discovery_id"]) && isBoundedId(value.target_actor_id) && isBoundedId(value.discovery_id);
    case "propose_joint_project": return validVenture(value);
    case "accept_joint_project": case "exit_joint_project": return hasExactKeys(value, ["venture_id", "version"]) && isBoundedId(value.venture_id) && isIntegerInRange(value.version, 1, 1000000);
    case "propose_work": return validWorkTerms(value);
    case "counter_work": return hasExactKeys(value, ["contract_id", "version", "terms"]) && isBoundedId(value.contract_id) && isIntegerInRange(value.version, 1, 1000000) && validWorkTerms(value.terms);
    case "accept_work": case "cancel_work": return hasExactKeys(value, ["contract_id", "version"]) && isBoundedId(value.contract_id) && isIntegerInRange(value.version, 1, 1000000);
    case "start_learning": return hasExactKeys(value, ["skill_id"]) && value.skill_id === "ingredient_selection";
    case "start_leisure": return hasExactKeys(value, ["activity", "partner_id"]) && isOneOf(value.activity, ["visit", "rest"]) && isBoundedId(value.partner_id);
    case "manage_building": return hasExactKeys(value, ["building_id", "operation", "fee", "version"]) && isBoundedId(value.building_id) && isOneOf(value.operation, ["maintain", "pricing", "open", "close"]) && isIntegerInRange(value.fee, 0, 1000000) && isIntegerInRange(value.version, 1, 1000000);
    case "propose_delivery": return hasExactKeys(value, ["task_id", "version", "recipient_id", "item_id", "quantity", "reward", "deadline_minutes", "schedule", "note"]) && isText(value.task_id, 100, true) && isIntegerInRange(value.version, 0, 1000000) && isBoundedId(value.recipient_id) && isBoundedId(value.item_id) && isIntegerInRange(value.quantity, 1, 100) && isIntegerInRange(value.reward, 0, 1000000) && isIntegerInRange(value.deadline_minutes, 1, 1080) && isOneOf(value.schedule, ["now", "after_step", "queue"]) && isText(value.note, 500, true);
    case "cancel_delivery": return hasExactKeys(value, ["task_id", "version"]) && isBoundedId(value.task_id) && isIntegerInRange(value.version, 1, 1000000);
    case "revise_project": return hasExactKeys(value, ["project_id", "version", "plan", "source"]) && isBoundedId(value.project_id) && isIntegerInRange(value.version, 1, 1000000) && validProject(value.plan) && isOneOf(value.source, ["dialogue", "self_review"]);
    case "public_wait": return hasExactKeys(value, ["expected_version", "reason"]) && isIntegerInRange(value.expected_version, 1, 1000000000) && isText(value.reason, 100);
    case "public_food_plan": return hasExactKeys(value, ["expected_version", "reason", "quantity", "unit_reward", "deadline_minutes"]) && isIntegerInRange(value.expected_version, 1, 1000000000) && isText(value.reason, 100) && isIntegerInRange(value.quantity, 1, 12) && isIntegerInRange(value.unit_reward, 1, 200) && isIntegerInRange(value.deadline_minutes, 60, 1080);
    case "submit_project": return validProject(value);
    case "retry_project": case "cancel_project": return hasExactKeys(value, ["project_id"]) && isBoundedId(value.project_id);
    case "suggest_behavior": return hasExactKeys(value, ["text", "ttl"]) && isText(value.text, 500) && isIntegerInRange(value.ttl, 1, 1080);
    case "propose_player_commission": case "publish_commission": return hasExactKeys(value, ["demand_id", "item_id", "quantity", "unit_reward", "kind", "max_claims", "deadline_minutes"]) && isBoundedId(value.demand_id) && isBoundedId(value.item_id) && isIntegerInRange(value.quantity, 1, 100) && isIntegerInRange(value.unit_reward, 1, 1000000) && isOneOf(value.kind, ["purchase", "processing"]) && isIntegerInRange(value.max_claims, 1, 10) && isIntegerInRange(value.deadline_minutes, 1, 10080);
    case "claim_commission": return hasExactKeys(value, ["commission_id", "quantity"]) && isBoundedId(value.commission_id) && isIntegerInRange(value.quantity, 1, 100);
    case "deliver_commission": return hasExactKeys(value, ["claim_id", "quantity", "version", "order_id"]) && isBoundedId(value.claim_id) && isIntegerInRange(value.quantity, 1, 100) && isIntegerInRange(value.version, 1, 1000000) && isText(value.order_id, 100, true);
    case "move": return hasExactKeys(value, ["x", "z"]) && typeof value.x === "number" && Number.isFinite(value.x) && value.x >= -176 && value.x <= 80 && typeof value.z === "number" && Number.isFinite(value.z) && value.z >= -80 && value.z <= 144;
    case "rent_production":
      return hasExactKeys(value, ["building_id", "recipe_id", "batches", "max_fee"])
        && isBoundedId(value.building_id) && isBoundedId(value.recipe_id)
        && isIntegerInRange(value.batches, 1, 100) && isIntegerInRange(value.max_fee, 0, 1000000);
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
		&& isBoundedId(value.discovery_id);
    case "register_discovery":
      return hasExactKeys(value, ["discovery_id"])
        && isBoundedId(value.discovery_id);
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

function validVenture(value: Record<string, unknown>): boolean {
  const fields = ["partner_id", "plan", "partner_gold", "partner_materials", "partner_profit_percent"];
  if (Object.hasOwn(value, "equipment_id")) fields.push("equipment_id");
  if (!hasExactKeys(value, fields) || !isBoundedId(value.partner_id) || !isRecord(value.plan) || !validProject(value.plan)
      || !isIntegerInRange(value.partner_gold, 0, Number(value.plan.budget)) || !isIntegerInRange(value.partner_profit_percent, 1, 99)
      || !isRecord(value.partner_materials)) return false;
  const plan = value.plan as {materials: Record<string, number>; steps: Array<{capability: string; arguments: Record<string, unknown>}>};
  if (!Object.entries(value.partner_materials).every(([id, qty]) => isIntegerInRange(qty, 1, Number(plan.materials[id])))) return false;
  return !Object.hasOwn(value, "equipment_id") || (isBoundedId(value.equipment_id) && plan.steps.some(step => step.capability === "rent" && step.arguments.building_id === value.equipment_id));
}

export function toolDescription(name: string): Record<string, unknown> {
  const parameters = TOOL_PARAMETERS[name];
  if (!parameters) throw new Error(`unknown_tool_contract:${name}`);
  const farmingDescriptions: Record<string, string> = {
    move: "Walk to world coordinates x,z on the current farm3d map (east=+x, south=+z). Use inspect_map/inspect_characters for a destination. Building and market targets resolve to reachable interaction points. Physical travel occupies your schedule and may fail if blocked. No teleport. Use this for repositioning or visiting; buy/sell/rent_production and farming already include walking, so do not add a redundant move.",
    buy: "In farm3d, walk to the market then buy the specified item and quantity using your account. One call includes the entire trip and purchase; no preceding move required. No money or goods change until arrival; current price, stock and funds are checked there. in_progress means traveling, not purchased.",
    sell: "In farm3d, walk to the market then sell the specified item and quantity from your inventory. One call includes travel and the sale, with current price and stock checked on arrival. in_progress is not a completed sale.",
    prepare_supplies: "In farm3d, walk to the market and buy supplies using your own account. One call includes walking and buying; no preceding move required. Price, stock and funds are checked on arrival. in_progress means traveling, not purchased.",
    travel: "In farm3d travel walks to the named real region. Arrival and minimum game time are required; no teleport. Wait for completed outcome before survey. Actor schedule is occupied. Regions creek, forest and hills are current-map field sites, not new map unlocks.",
    survey: "Investigate only after actual arrival at the named field site, consuming ONE bread and 20 game minutes at the site. Returns a durable observation ID only on completion, never a guaranteed resource. Seeded daily sites can have no sample; inspect exploration reports afterwards.",
    collect_sample: "Collect one finite sample from a known, fresh, physically reached report discovery_id. One sample per daily site, even across actors; cannot repeatedly mint samples. No-find reports cannot supply samples.",
    propose_activity: "Propose and prepay a voluntary fishing/golf activity. Supply procurement and reward must be covered by actual sponsor cash, not projected tickets. Capacity/site conflict and all costs are verified. NPCs attend only as spectators. Minimum enrollment and food shortfall cancels with refunds.",
    enroll_activity: "Independently accept a current activity, pay own ticket and reserve own schedule. Walk to its site to attend. NPCs are spectators; no fabricated scores. Reject by issuing no enrollment.",
    leave_activity: "Withdraw own enrollment and refund ticket before the activity starts.",
    cancel_activity: "Organizer cancels own activity; refund tickets and unused assets, preserving already completed supplier payments.",
    public_activity_plan: "Public coordinator only: actual funded activity, maximum sponsor 500, shared daily budget and cooldown. Essential food takes priority; waiting is allowed. terms use the same ten fields as propose_activity.",
    public_repair_plan: "Public coordinator only: fund repair materials through existing commissions and actual labor subsidy from the shared daily budget. Only a currently blocked unfunded route qualifies; natural recovery/wait is valid.",
    contribute_route_repair: "Must physically arrive at environment.repair_site first. Donate owned wood/stone within remaining quota and optionally work up to 60 actual game minutes. Paid labor requires existing public funding; leaving stops labor accumulation. Route recovery stops further spending.",
    offer_intelligence: "Offer one known fresh report to target_actor_id for a bounded price. Only a value summary is shown before confirmation. Player must confirm in UI; this never authorizes payment. Already known/public reports cannot be charged. Do not disclose protected contents in speech; use share_intelligence for free disclosure.",
    buy_intelligence: "Accept only an offer addressed to you with current offer_id/version. Your real money and knowledge access transfer atomically. Known/public facts are free; failed payment grants nothing. Never buy on behalf of player.",
    share_intelligence: "Explicitly disclose a known fresh report for free to target_actor_id. This grants usable report and map information; the recipient can never be charged for that same known report afterwards. Use before discussing otherwise protected contents.",
    propose_investigation: "Propose voluntary funding between worker_id and funder_id; you must be one party. Other party independently accepts, player via UI. Acceptance escrows TWO bread from funder and reward; actual travel consumes one bread, survey one. allow_old_report controls reuse of eligible existing evidence. require_sample=true pays reward only if actual sample is delivered; no-find returns reward with an honest report. Unused supplies/funds refund; consumed supplies do not. Deadline 60..10080 minutes. No promised discoveries.",
    accept_investigation: "Independently accept the other party's current investigation proposal. Requires free investigator schedule and funded bread/reward. Execution physically travels, surveys, returns and delivers a report/sample. Proposal or acceptance alone is not a completed investigation.",
    cancel_investigation: "Cancel your own investigation at current version. Stop future fieldwork, return unused bread and unpaid reward. Consumed provisions are not fabricated back; never claim a failed investigation found resources.",
    propose_work: "Voluntarily offer a paid job to a DIFFERENT worker_id from your own account. Use living_world.work and actor schedules. Exact delivery/processing/supply terms require the other party's current-version acceptance; no work or charge on proposal. quantity is units for delivery/supply, batches for processing. Employer escrows wage per cycle plus inputs and max_fee for processing; supply worker provides own goods. Recipient receives goods after actual transport. parent_contract optionally links work you subcontract while retaining liability. Do not accept for player or invent IDs.",
    counter_work: "Negotiate an existing proposed job with exact contract_id, current version and complete replacement terms. Keep worker and parent unchanged. Only the other participant can accept this revision. Never report a counteroffer as accepted.",
    accept_work: "Voluntarily accept the other party's latest proposed terms using current contract_id and version. Your real schedule must be free if you are the worker; accepted wages/inputs are prepaid. Failure to deliver does not complete any parent commission.",
    cancel_work: "Cancel your own job contract at its current version. Future cycles stop; completed payments remain valid. Begun processing settles and unused assets return to employer. Picked-up cargo requires return travel.",
    start_learning: "Choose ingredient_selection training at village_inn only with free schedule and 30 actual gold. Physically travel and study 120 game minutes. Completion unlocks tagged-ingredient recipes such as grilled_fish in autonomous projects; acceptance alone unlocks nothing.",
    start_leisure: "Choose visit or rest with a real partner_id using free time. Travel and spend 60 minutes; actual visits can improve relations. You may choose this instead of paid work. No instant reputation reward.",
    manage_building: "Only manage a building you own. Use current service policy version. pricing sets actual fee for each existing recipe; maintain pays original maintenance cost. Never change another owner's building.",
    propose_joint_project: "Propose your original executable project DAG with exact partner_gold and partner_materials within the plan's total budget/materials, and partner_profit_percent 1..99. Partner must independently accept. You operate and own any constructed building. Capital return and surplus share use only actual remaining project receipts; costs can cause loss. No profits paid before realized income.",
    accept_joint_project: "As the proposed partner only, accept venture_id at current version. Your exact contribution is transferred into original project escrow atomically with the operator's contribution. Check risk, ownership and return terms before accepting.",
    exit_joint_project: "As a participant, request exit from venture_id at its current version. Uncommitted work cancels; begun production must settle first. Actual remaining funds/materials return according to accepted contribution and split terms.",
    propose_trade: "Create a proposal for target_actor_id. give is what YOU supply from your own inventory; receive is what the OTHER actor supplies to you upon acceptance. You only need to own give, not receive. A player recipient must explicitly confirm in the game UI. A proposal reserves assets but is not a completed trade.",
    counter_trade: "Replace a received offer with your counterproposal. give is your contribution; receive is what you request from the other actor. The previous offer becomes invalid; the recipient must accept the new proposal.",
    propose_delivery: "If you voluntarily accept a player's delivery request, propose exact cargo, recipient, reward, deadline and schedule from living_world.interruptions. Ask for missing terms first. Empty task_id and version 0 means new; existing ID and exact version renegotiates before pickup. A player confirmation card authorizes escrow. Do not claim accepted or delivered before confirmation/execution. Choose now, after_step or queue to respect existing obligations; decline conflicting requests.",
    cancel_delivery: "Cancel only your own delivery with its current version. Unpaid reward and cargo return to player; picked-up cargo requires an actual return trip. Does not cancel the main project.",
    revise_project: "Accept an optional suggestion by revising only uncommitted future project steps. Supply current project version, full revised plan and source dialogue/self_review. Escrow budget/materials and all begun steps or commission commitments must stay unchanged. This changes actual future actions; it never reverses committed production.",
    public_food_plan: "Public coordinator only: use authorized public_coordination indicators and budget to propose limited bread procurement for an actual unmet food gap. Uses existing public funds and real commission escrow. Existing incoming supply, public stock, cooldown and daily limit must be respected. No private control or new money. Provide current expected_version and a short factual reason (at most 100 characters). unit_reward must be <= 200 even if competing offers pay more; choose a lawful offer or public_wait.",
    public_wait: "Public coordinator only: explicitly choose no new intervention based on existing supply, budget, cooldown or evidence. Provide the current version and factual reason. Existing accepted public contracts continue.",
    submit_project: "Choose an autonomous goal based on actual opportunities, submit a budgeted DAG using actor_context.living_world.rules. No need for a player request or commission. Materials and budget are escrowed from YOUR account. Buy, sell and rent steps automatically walk to their market/building before acting; explicit move is only needed for other destinations. Plan acceptance is not completion. Decline if economics or resources are unsuitable. Inspect market prices, building fees and legal sites first. goal is a short objective (at most 500 characters, preferably under 200), not a full economic analysis.",
    retry_project: "Revalidate blocked steps of your existing project after a relevant change. Do not retry blindly.",
    cancel_project: "Cancel your project and return unused escrow; committed work must finish first.",
    suggest_behavior: "Record a concise optional behavioral intention for your next decisions, not a guaranteed promise. text must be at most 500 characters; aim for under 300. Do not include a wait command in the same response.",
    wait: "Choose no action. This must be the only command in the response. If recording an intention or sending a message, omit wait.",
    propose_player_commission: "Only when the player asks you to draft their commission: propose exact goods, quantity, unit reward, type, deadline and claim slots. This opens a player confirmation card after dialogue closes. No money is moved and nothing is published until the player confirms. Ask for missing essential terms first.",
    publish_commission: "Publish a purchase or new-processing demand using ONLY your own funds, prepaid into escrow. Never spend player money. Player terms require their UI confirmation.",
    claim_commission: "Claim an available quantity of a funded public commission, up to its remaining quota and claim slots.",
    deliver_commission: "Deliver real inventory for a claimed commission at its current version; processing requires order_id of new production started after claim. Reward transfers only after validation.",
    rent_production: "Walk to a real building, then place a paid processing order owned by any actor. One call includes walking and ordering; do not call move first. Nothing is debited before arrival. Inspect buildings for the exact instance building_id, recipe, fee per batch, shared queue and maintenance state. Supply your own ingredients; the per-building policy defines permitted recipes and reserved owner capacity; total fee must not exceed max_fee, is escrowed while queued and paid to owner_id on actual start. Self-use has zero fee. Output is delivered automatically to your inventory after game-time processing. Consider input cost, rental fee and market sale value before ordering; in_progress may mean walking to the building or awaiting production; only completion means goods were delivered.",
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

// Diagnostic only: validToolArguments remains the authoritative semantic check.
// Never echo argument values (which can contain dialogue) into error messages.
export function toolArgumentErrors(name: string, value: unknown): string[] {
  const schema = TOOL_PARAMETERS[name] ?? READ_TOOL_PARAMETERS[name as ReadToolName];
  if (!schema) return ["unauthorized_tool"];
  const errors: string[] = [];
  function inspect(s: JsonSchema, v: unknown, path: string): void {
    if (errors.length >= 8) return;
    const fail = (message: string) => { errors.push(`${path}: ${message}`); };
    if (s.type === "object") {
      if (!isRecord(v)) { fail("must be an object"); return; }
      const props = (s.properties ?? {}) as Record<string, JsonSchema>;
      for (const key of (s.required ?? []) as string[]) if (!Object.hasOwn(v, key)) fail(`missing required field ${key}`);
      for (const [key, entry] of Object.entries(v)) {
        if (props[key]) inspect(props[key], entry, `${path}.${key}`);
        else if (s.additionalProperties === false) fail(`unexpected field ${key}`);
        else if (isRecord(s.additionalProperties)) inspect(s.additionalProperties, entry, `${path}.*`);
      }
    } else if (s.type === "string") {
      if (typeof v !== "string") { fail("must be a string"); return; }
      if (typeof s.maxLength === "number" && v.length > s.maxLength) fail(`length ${v.length} exceeds maximum ${s.maxLength}`);
      if (typeof s.minLength === "number" && v.trim().length < s.minLength) fail(`minimum length is ${s.minLength}`);
    } else if (s.type === "integer") {
      if (!Number.isSafeInteger(v)) { fail("must be an integer"); return; }
      if (typeof s.minimum === "number" && Number(v) < s.minimum) fail(`minimum is ${s.minimum}`);
      if (typeof s.maximum === "number" && Number(v) > s.maximum) fail(`maximum is ${s.maximum}`);
    } else if (s.type === "array") {
      if (!Array.isArray(v)) { fail("must be an array"); return; }
      if (typeof s.minItems === "number" && v.length < s.minItems) fail(`minimum items is ${s.minItems}`);
      if (typeof s.maxItems === "number" && v.length > s.maxItems) fail(`maximum items is ${s.maxItems}`);
      if (s.uniqueItems && new Set(v.map(entry => JSON.stringify(entry))).size !== v.length) fail("items must be unique");
      if (isRecord(s.items)) v.forEach((entry, index) => inspect(s.items as JsonSchema, entry, `${path}[${index}]`));
    }
    if (Array.isArray(s.enum) && !s.enum.includes(v)) fail(`must be one of ${s.enum.join(", ")}`);
  }
  inspect(schema, value, name);
  if (errors.length === 0 && !validToolArguments(name, value) && Object.hasOwn(TOOL_PARAMETERS, name)) {
    errors.push(`${name}: arguments violate the tool contract; use exact fields and valid project dependencies from the supplied rules`);
  }
  return errors.slice(0, 8);
}

export function validReadToolArguments(name: string, value: unknown): boolean {
  if (!isRecord(value)) return false;
  switch (name as ReadToolName) {
    case "inspect_map":
    case "inspect_buildings":
    case "inspect_characters":
      return hasExactKeys(value, []);
    case "inspect_building":
      return hasExactKeys(value, ["building_id"]) && isBoundedId(value.building_id);
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
    case "inspect_map": return {map: structuredClone(context.actor_context.world_map ?? {})};
    case "inspect_buildings": return {buildings: structuredClone(context.actor_context.player_buildings ?? [])};
    case "inspect_building": return found(findRecord(context.actor_context.player_buildings, "building_id", String(args.building_id)) ?? findRecord(context.actor_context.player_buildings, "instance_id", String(args.building_id)));
    case "inspect_characters": return {characters: structuredClone(context.actor_context.characters ?? [])};
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
    case "inspect_region": {
      const map = isRecord(context.actor_context.world_map) ? context.actor_context.world_map : {};
      return found(findRecord(map.regions, "id", String(args.region_id))
        ?? findRecord(context.public_world_state.regions ?? context.actor_context.regions, "region_id", String(args.region_id)));
    }
    case "inspect_known_discoveries": return {discoveries: structuredClone(context.actor_context.known_discoveries ?? context.public_world_state.known_discoveries ?? [])};
    default: throw new Error("provider_unknown_read_tool");
  }
}


export function validProject(v: Record<string, unknown>): boolean {
  if (!hasExactKeys(v, ["goal", "budget", "deadline_minutes", "materials", "steps"]) || !isText(v.goal, 500) || !isIntegerInRange(v.budget, 0, 1000000) || !isIntegerInRange(v.deadline_minutes, 60, 10080) || !isRecord(v.materials) || Object.keys(v.materials).length > 32 || !Object.keys(v.materials).every(isBoundedId) || !Object.values(v.materials).every(n => isIntegerInRange(n, 1, 1000000)) || !Array.isArray(v.steps) || v.steps.length < 1 || v.steps.length > 12) return false;
  const seen = new Map<string, {capability: string; ancestors: Set<string>}>();
  for (const step of v.steps) {
    if (!isRecord(step) || !hasExactKeys(step, ["id", "capability", "depends_on", "arguments"]) || !isBoundedId(step.id) || step.id.length > 40 || seen.has(step.id) || !Array.isArray(step.depends_on) || !step.depends_on.every(id => typeof id === "string" && seen.has(id)) || !isRecord(step.arguments)) return false;
    const a = step.arguments;
    const id = (key: string) => isBoundedId(a[key]);
    const n = (key: string, min = 1, max = 100) => isIntegerInRange(a[key], min, max);
    const keys = (...expected: string[]) => hasExactKeys(a, expected);
    let valid = false;
    switch (step.capability) {
      case "buy": case "sell": valid = keys("item_id", "quantity", "limit") && id("item_id") && n("quantity") && n("limit", 0, 1000000); break;
      case "move": valid = keys("x", "z") && typeof a.x === "number" && Number.isFinite(a.x) && a.x >= -176 && a.x <= 80 && typeof a.z === "number" && Number.isFinite(a.z) && a.z >= -80 && a.z <= 144; break;
      case "rent": valid = validToolArguments("rent_production", a); break;
      case "wait_production": valid = keys("order_step") && id("order_step"); break;
      case "reserve_plot": valid = (keys("gx", "gz") || (keys("gx", "gz", "building_type") && isOneOf(a.building_type, ["windmill", "food_workshop"]))) && n("gx", -1024, 1024) && n("gz", -1024, 1024); break;
      case "build": valid = keys("lease_step") && id("lease_step"); break;
      case "wait_construction": valid = keys("build_step") && id("build_step"); break;
      case "set_policy": valid = keys("build_step", "open", "fee") && id("build_step") && typeof a.open === "boolean" && n("fee", 0, 1000000); break;
      case "claim": valid = validToolArguments("claim_commission", a); break;
      case "deliver": valid = keys("claim_step", "quantity", "order_step") && id("claim_step") && n("quantity") && isText(a.order_step, 100, true); break;
    }
    if (!valid) return false;
    const ancestors = new Set<string>();
    for (const dep of step.depends_on as string[]) { ancestors.add(dep); for (const prior of seen.get(dep)!.ancestors) ancestors.add(prior); }
    const refs: Record<string, Record<string, string>> = {wait_production: {order_step: "rent"}, build: {lease_step: "reserve_plot"}, wait_construction: {build_step: "build"}, set_policy: {build_step: "build"}, deliver: {claim_step: "claim", order_step: "rent"}};
    for (const [field, cap] of Object.entries(refs[String(step.capability)] ?? {})) {
      if (step.capability === "deliver" && field === "order_step" && a[field] === "") continue;
      if (typeof a[field] !== "string" || !ancestors.has(a[field]) || seen.get(a[field])?.capability !== cap) return false;
    }
    if (step.capability === "rent" && typeof a.building_id === "string" && a.building_id.startsWith("@")) { const ref = a.building_id.slice(1); if (!ancestors.has(ref) || seen.get(ref)?.capability !== "build") return false; }
    seen.set(step.id, {capability: String(step.capability), ancestors});
  }
  return true;
}
