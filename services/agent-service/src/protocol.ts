export const PROTOCOL_VERSION = 1 as const;

export type Trigger = "schedule" | "event" | "dialogue" | "catch_up";
export type OutcomeStatus = "accepted" | "in_progress" | "completed" | "rejected" | "failed";

export interface DecisionRequest {
  protocol_version: 1;
  request_id: string;
  session_id: string;
  session_epoch: number;
  agent_id: string;
  trigger: Trigger;
  game_minute: number;
  world_revision: number;
  snapshot: Record<string, unknown>;
  event_delta: readonly Record<string, unknown>[];
  dialogue_input?: string;
}

export interface ActionIntent {
  protocol_version: 1;
  decision_id: string;
  request_id: string;
  agent_id: string;
  expected_revision: number;
  idempotency_key: string;
  tool_name: string;
  tool_version: 1;
  arguments: Record<string, unknown>;
  speech?: string;
  decision_summary: string;
}

export interface ActionOutcome {
  protocol_version: 1;
  decision_id: string;
  idempotency_key: string;
  status: OutcomeStatus;
  failure_code?: string;
  committed_revision: number;
  changed_entities: readonly string[];
  resource_delta: Record<string, number>;
  hud_message: string;
  game_minute: number;
}

export type ParseResult<T> = { ok: true; value: T } | { ok: false; error: string };

const TRIGGERS = new Set<Trigger>(["schedule", "event", "dialogue", "catch_up"]);
const OUTCOME_STATUSES = new Set<OutcomeStatus>(["accepted", "in_progress", "completed", "rejected", "failed"]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isId(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0 && value.length <= 160;
}

function isNonNegativeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

function failure<T>(error: string): ParseResult<T> {
  return { ok: false, error };
}

export function parseDecisionRequest(value: unknown): ParseResult<DecisionRequest> {
  if (!isRecord(value) || value.protocol_version !== PROTOCOL_VERSION) return failure("invalid_protocol_version");
  for (const field of ["request_id", "session_id", "agent_id"] as const) {
    if (!isId(value[field])) return failure(`invalid_${field}`);
  }
  if (!isNonNegativeInteger(value.session_epoch)) return failure("invalid_session_epoch");
  if (!isNonNegativeInteger(value.game_minute)) return failure("invalid_game_minute");
  if (!isNonNegativeInteger(value.world_revision)) return failure("invalid_world_revision");
  if (typeof value.trigger !== "string" || !TRIGGERS.has(value.trigger as Trigger)) return failure("invalid_trigger");
  if (!isRecord(value.snapshot)) return failure("invalid_snapshot");
  if (!Array.isArray(value.event_delta) || value.event_delta.some((event) => !isRecord(event))) return failure("invalid_event_delta");
  if (value.dialogue_input !== undefined && (typeof value.dialogue_input !== "string" || value.dialogue_input.length > 1000)) {
    return failure("invalid_dialogue_input");
  }
  return { ok: true, value: value as unknown as DecisionRequest };
}

export function parseActionIntent(value: unknown, allowedTools: readonly string[]): ParseResult<ActionIntent> {
  if (!isRecord(value) || value.protocol_version !== PROTOCOL_VERSION) return failure("invalid_protocol_version");
  for (const field of ["decision_id", "request_id", "agent_id", "idempotency_key", "tool_name"] as const) {
    if (!isId(value[field])) return failure(`invalid_${field}`);
  }
  if (value.tool_version !== 1) return failure("invalid_tool_version");
  if (!allowedTools.includes(String(value.tool_name))) return failure("unauthorized_tool");
  if (!isNonNegativeInteger(value.expected_revision)) return failure("invalid_expected_revision");
  if (!isRecord(value.arguments)) return failure("invalid_arguments");
  if (typeof value.decision_summary !== "string" || value.decision_summary.length > 500) return failure("invalid_decision_summary");
  if (value.speech !== undefined && (typeof value.speech !== "string" || value.speech.length > 500)) return failure("invalid_speech");
  return { ok: true, value: value as unknown as ActionIntent };
}

export function parseActionOutcome(value: unknown): ParseResult<ActionOutcome> {
  if (!isRecord(value) || value.protocol_version !== PROTOCOL_VERSION) return failure("invalid_protocol_version");
  for (const field of ["decision_id", "idempotency_key"] as const) {
    if (!isId(value[field])) return failure(`invalid_${field}`);
  }
  if (typeof value.status !== "string" || !OUTCOME_STATUSES.has(value.status as OutcomeStatus)) return failure("invalid_status");
  if (!isNonNegativeInteger(value.committed_revision) || !isNonNegativeInteger(value.game_minute)) return failure("invalid_revision_or_time");
  if (!Array.isArray(value.changed_entities) || value.changed_entities.some((entry) => !isId(entry))) return failure("invalid_changed_entities");
  if (!isRecord(value.resource_delta) || Object.values(value.resource_delta).some((entry) => typeof entry !== "number" || !Number.isSafeInteger(entry))) {
    return failure("invalid_resource_delta");
  }
  if (typeof value.hud_message !== "string" || value.hud_message.length > 500) return failure("invalid_hud_message");
  if (value.failure_code !== undefined && !isId(value.failure_code)) return failure("invalid_failure_code");
  return { ok: true, value: value as unknown as ActionOutcome };
}
