/** Compatibility only: old direct callers that require synchronous extraction. */
import type { DecisionRequest, ActionIntent } from "../protocol.ts";
import type { AgentContext } from "../agents.ts";
import type { MemoryEvent } from "../memory.ts";
import type { ReadPort } from "../agent_loop.ts";
import type { ProviderTraceEvent } from "../provider_stream.ts";
import {
  chatMessages,
  importantChatActors,
  type ChatActor,
} from "./build_context.ts";
import {
  extractionTurns,
  movementExtractionInstructions,
  inspectMovementHandoffs,
} from "../chat_action_extraction.ts";
import { RelationshipDialogue } from "../relationship_dialogue.ts";
export interface ChatCatalog {
  actors: string[];
  places: string[];
  items: string[];
}
type Complete = (
  messages: Record<string, unknown>[],
  phase: string,
  emit: (e: ProviderTraceEvent) => void,
  signal?: AbortSignal,
  json?: boolean,
  scope?: Pick<DecisionRequest, "session_id" | "game_minute">,
) => Promise<string>;
export const CHAT_KINDS = [
  "visit",
  "date",
  "companionship",
  "trade",
  "plant",
  "harvest",
  "build",
  "rest",
] as const;
export function validateHandoffs(
  value: unknown,
  catalog: ChatCatalog,
  reply: string,
): Record<string, unknown>[] {
  return inspectHandoffs(value, catalog, reply).accepted;
}
export function inspectHandoffs(
  value: unknown,
  catalog: ChatCatalog,
  reply: string,
): {
  accepted: Record<string, unknown>[];
  rejected: { index: number; reason: string }[];
} {
  const accepted: Record<string, unknown>[] = [];
  const rejected: { index: number; reason: string }[] = [];
  if (!Array.isArray(value) || value.length > 3)
    return {
      accepted,
      rejected: [{ index: -1, reason: "invalid_handoff_list" }],
    };
  for (const [index, raw] of value.entries()) {
    const reject = (reason: string) => rejected.push({ index, reason });
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      reject("invalid_handoff_object");
      continue;
    }
    const r = {
      target_actor_id: "",
      place_id: "",
      item_id: "",
      quantity: 0,
      gold: 0,
      delay_minutes: 0,
      ...raw,
    } as Record<string, unknown>;
    if (
      Object.keys(r).some(
        (k) =>
          ![
            "kind",
            "status",
            "target_actor_id",
            "place_id",
            "item_id",
            "quantity",
            "gold",
            "delay_minutes",
            "confidence",
            "reply_evidence",
            "trade_side",
            "building_type",
            "plot",
          ].includes(k),
      )
    ) {
      reject("unknown_fields");
      continue;
    }
    r.trade_side ??= "none";
    r.building_type ??= "";
    r.plot ??= -1;
    if (
      !["none", "buy", "sell"].includes(String(r.trade_side)) ||
      ![
        "",
        "well",
        "waterwheel",
        "greenhouse",
        "beehive",
        "windmill",
        "chicken_coop",
        "food_workshop",
      ].includes(String(r.building_type)) ||
      !Number.isSafeInteger(r.plot) ||
      Number(r.plot) < -1 ||
      Number(r.plot) > 999
    ) {
      reject("invalid_action_fields");
      continue;
    }
    if (
      !CHAT_KINDS.includes(r.kind as any) ||
      !["agreed", "cancelled"].includes(String(r.status))
    ) {
      reject("invalid_kind_or_status");
      continue;
    }
    if (
      typeof r.confidence !== "number" ||
      !Number.isFinite(r.confidence) ||
      r.confidence < 0.9 ||
      r.confidence > 1
    ) {
      reject("insufficient_confidence");
      continue;
    }
    if (
      typeof r.reply_evidence !== "string" ||
      r.reply_evidence.replace(/\s+/g, "").length < 2 ||
      !reply.replace(/\s+/g, "").includes(r.reply_evidence.replace(/\s+/g, ""))
    ) {
      reject("reply_evidence_mismatch");
      continue;
    }
    if (
      typeof r.target_actor_id !== "string" ||
      (r.target_actor_id !== "" && !catalog.actors.includes(r.target_actor_id))
    ) {
      reject("unknown_actor_id");
      continue;
    }
    if (
      typeof r.place_id !== "string" ||
      (r.place_id !== "" && !catalog.places.includes(r.place_id))
    ) {
      reject("unknown_place_id");
      continue;
    }
    if (
      typeof r.item_id !== "string" ||
      (r.item_id !== "" && !catalog.items.includes(r.item_id))
    ) {
      reject("unknown_item_id");
      continue;
    }
    if (
      !Number.isSafeInteger(r.quantity) ||
      Number(r.quantity) < 0 ||
      Number(r.quantity) > 1000 ||
      !Number.isSafeInteger(r.gold) ||
      Number(r.gold) < 0 ||
      Number(r.gold) > 1000000 ||
      !Number.isSafeInteger(r.delay_minutes) ||
      Number(r.delay_minutes) < 0 ||
      Number(r.delay_minutes) > 10080
    ) {
      reject("invalid_quantity_gold_or_delay");
      continue;
    }
    if (
      (["date", "companionship", "trade"].includes(String(r.kind)) &&
        !r.target_actor_id) ||
      (r.kind === "visit" && !r.target_actor_id && !r.place_id)
    ) {
      reject("missing_action_target");
      continue;
    }
    if (
      ["trade", "plant"].includes(String(r.kind)) &&
      (!r.item_id || !r.quantity)
    ) {
      reject("missing_item_or_quantity");
      continue;
    }
    if (
      (r.kind === "trade" && r.trade_side === "none") ||
      (r.kind === "build" && !r.building_type)
    ) {
      reject("missing_trade_side_or_building");
      continue;
    }
    // No quotations, explanations, notes or model-created prose leave the chat channel.
    const handoff = Object.fromEntries(
      [
        "kind",
        "status",
        "target_actor_id",
        "place_id",
        "item_id",
        "quantity",
        "gold",
        "delay_minutes",
        "trade_side",
        "building_type",
        "plot",
      ].map((k) => [k, r[k]]),
    );
    if (!accepted.some((x) => JSON.stringify(x) === JSON.stringify(handoff)))
      accepted.push(handoff);
  }
  return { accepted, rejected };
}
export function parseExtraction(text: string): Record<string, unknown> {
  const fenced = text.trim().match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  const value = JSON.parse(fenced ? fenced[1] : text);
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.keys(value).some((k) => !["handoffs", "relationship"].includes(k)) ||
    !Array.isArray(value.handoffs) ||
    value.handoffs.length > 3
  )
    throw new Error("invalid_chat_extraction");
  return value;
}
export function relationshipAction(
  r: DecisionRequest,
  context: AgentContext,
  value: unknown,
  reply: string,
  observation: Record<string, unknown>,
): ActionIntent["actions"] {
  if (
    !value ||
    typeof value !== "object" ||
    r.chat_room ||
    !context.allowed_command_tools.includes("resolve_relationship_dialogue")
  )
    return [];
  const v = value as Record<string, unknown>;
  if (
    Object.keys(v).some(
      (k) => !["decision", "reply_evidence", "player_evidence"].includes(k),
    ) ||
    !["confirm", "decline", "end"].includes(String(v.decision))
  )
    return [];
  if (
    typeof v.reply_evidence !== "string" ||
    v.reply_evidence.length < 2 ||
    !reply.includes(v.reply_evidence) ||
    typeof v.player_evidence !== "string" ||
    v.player_evidence.length < 2 ||
    !r.dialogue_input?.includes(v.player_evidence)
  )
    return [];
  const live = new RelationshipDialogue();
  live.observe(
    "query_world",
    { domain: "actors", section: "relationship", id: "player" },
    observation,
  );
  if (
    !live.player ||
    (v.decision === "confirm" && live.player.status === "dating") ||
    (v.decision === "end" && live.player.status !== "dating")
  )
    return [];
  // Exact current player quotation is used only by the game's existing consent validator,
  // never passed to the action model or its memories.
  return [
    {
      action_id: `chat-relation:${r.request_id}`,
      idempotency_key: `${r.session_id}:chat-relation:${r.request_id}`,
      tool_name: "resolve_relationship_dialogue",
      tool_version: 1,
      arguments: {
        decision: v.decision,
        player_quote: r.dialogue_input,
        note: "当前对话的明确关系意愿",
      },
    },
  ];
}
export function renderHandoffs(handoffs: Record<string, unknown>[]): string {
  return handoffs.map((h) => JSON.stringify(h)).join("\n");
}

export async function legacyRespond(
  complete: Complete,
  r: DecisionRequest,
  context: AgentContext,
  history: MemoryEvent[],
  actors: ChatActor[],
  read: ReadPort,
  emit: (e: ProviderTraceEvent) => void,
  signal?: AbortSignal,
  summary = "",
): Promise<ActionIntent> {
  actors = importantChatActors(r, actors);
  const messages = chatMessages(r, context, history, actors, summary);
  const reply = await complete(messages, "dialogue", emit, signal, false, r);
  let handoffs: Record<string, unknown>[] = [];
  let actions: ActionIntent["actions"] = [],
    extractionFailed = false;
  try {
    const turns = extractionTurns(r, history, reply);
    // Only this player's message and this NPC's new reply enter extraction.
    const places: {
      id: string;
      name?: string;
      aliases?: unknown;
      owner_id?: string;
      kind?: string;
    }[] = [];
    for (let cursor = 0; cursor < 30; cursor += 10) {
      const map = await read(
        "query_world",
        { domain: "map", section: "regions", cursor, limit: 10 },
        signal,
      );
      for (const row of Array.isArray(map.items) ? map.items : [])
        if (typeof row.id === "string")
          places.push({ id: row.id, name: row.name, aliases: row.aliases });
      if (!map.ok || Number(map.next_cursor ?? -1) < 0) break;
    }
    // Player-owned buildings are not part of the named-region map catalogue.
    if (
      /温室|风车|工坊|蜂箱|鸡舍|水井|水车|建筑|\b(?:greenhouse|windmill|workshop|building)\b/i.test(
        JSON.stringify(turns),
      )
    ) {
      for (let cursor = 0; cursor < 100; cursor += 10) {
        const buildings = await read(
          "query_world",
          { domain: "buildings", section: "list", cursor, limit: 10 },
          signal,
        );
        for (const row of Array.isArray(buildings.items)
          ? buildings.items
          : []) {
          const id = row.building_id ?? row.id;
          if (typeof id === "string" && !places.some((p) => p.id === id))
            places.push({
              id,
              name: row.name,
              owner_id: row.owner_id,
              kind: "building",
            });
        }
        if (!buildings.ok || Number(buildings.next_cursor ?? -1) < 0) break;
      }
    }
    const scopedActors = [
      {
        id: "player",
        name:
          r.chat_participants?.find((a) => a.actor_id === "player")
            ?.display_name ?? "玩家",
      },
      ...actors,
    ];
    const instructions = movementExtractionInstructions(places, scopedActors);
    const raw = await complete(
      [
        { role: "system", content: JSON.stringify(instructions) },
        {
          role: "user",
          content: JSON.stringify({ speaker: r.agent_id, conversation: turns }),
        },
      ],
      "extract_actions",
      emit,
      signal,
      true,
    );
    const extracted = parseExtraction(raw);
    const inspection = inspectMovementHandoffs(
      extracted.handoffs,
      places,
      scopedActors.map((a) => a.id),
      turns,
      r.agent_id,
    );
    handoffs = inspection.accepted;
    emit({
      type: "loop",
      payload: {
        event: "chat.extraction_result",
        source_event_id: `dialogue:${r.request_id}`,
        candidates: extracted.handoffs,
        accepted: handoffs,
        rejected: inspection.rejected,
        relationship_candidate: extracted.relationship ?? null,
      },
    });
    if (extracted.relationship && !r.chat_room) {
      const relationship = await read(
        "query_world",
        { domain: "actors", section: "relationship", id: "player" },
        signal,
      );
      actions = relationshipAction(
        r,
        context,
        extracted.relationship,
        reply,
        relationship,
      );
    }
    extractionFailed = inspection.rejected.length > 0;
    if (extractionFailed)
      emit({
        type: "loop",
        payload: {
          event: "chat.extraction_failed",
          code: "invalid_handoff_fields",
          accepted_count: handoffs.length,
          rejected: inspection.rejected,
        },
      });
    emit({
      type: "loop",
      payload: {
        event: "chat.handoffs_extracted",
        count: handoffs.length,
        handoffs,
      },
    });
  } catch (error) {
    if (signal?.aborted) throw error;
    extractionFailed = true;
    // Never improvise an action or send raw chat to a fallback model on extraction failure.
    emit({
      type: "loop",
      payload: {
        event: "chat.extraction_failed",
        code: "chat_extraction_failed",
        reason:
          error instanceof SyntaxError
            ? "invalid_json"
            : error instanceof Error
              ? error.message
              : "unknown",
        actions_submitted: 0,
      },
    });
  }
  return {
    protocol_version: 2,
    decision_id: `chat:${r.request_id}`,
    request_id: r.request_id,
    agent_id: r.agent_id,
    expected_revision: r.world_revision,
    actions,
    speech: reply,
    chat_extraction_failed: extractionFailed,
    decision_summary:
      "Chat reply; extracted game intentions await a fresh action loop",
    chat_handoffs: handoffs,
    chat_isolated: true,
  };
}
