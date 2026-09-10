import type { AgentContext, AgentDefinition } from "./agents.ts";
import type { ProviderConfig } from "./config.ts";
import type { MemoryEvent } from "./memory.ts";
import {existsSync, readFileSync, writeFileSync, renameSync} from "node:fs";
import type { ActionIntent, DecisionRequest } from "./protocol.ts";
import {ProviderConcurrencyGate} from "./provider_concurrency_gate.ts";
import {
  AgentStreamAssembler,
  decodeProviderSse,
  type ProviderTraceEvent,
  type ProviderRawOutput,
} from "./provider_stream.ts";
import {executeReadTool, readToolDescription, toolDescription, toolArgumentErrors} from "./tool_contracts.ts";

const DIALOGUE_COMMANDS = new Set([
  "propose_activity", "enroll_activity", "leave_activity", "cancel_activity", "contribute_route_repair", "send_message", "propose_trade", "counter_trade", "accept_trade", "reject_trade",
  "cancel_trade", "propose_cooperation", "counter_cooperation", "accept_cooperation",
  "public_food_plan", "public_wait", "reject_cooperation", "commit_contribution", "cancel_cooperation", "speak", "move", "rent_production", "offer_intelligence", "buy_intelligence", "share_intelligence", "propose_investigation", "accept_investigation", "cancel_investigation", "propose_joint_project", "accept_joint_project", "exit_joint_project", "propose_work", "counter_work", "accept_work", "cancel_work", "start_learning", "start_leisure", "manage_building", "propose_delivery", "cancel_delivery", "revise_project", "submit_project", "retry_project", "cancel_project", "publish_commission", "propose_player_commission", "claim_commission", "deliver_commission", "suggest_behavior",
]);

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function pick(value: unknown, keys: string[]): Record<string, unknown> {
  const source = record(value);
  return Object.fromEntries(keys.filter((key) => key in source).map((key) => [key, source[key]]));
}

function brief(value: unknown, depth = 2): unknown {
  if (typeof value === "string") return value.length > 600 ? value.slice(0, 600) + "…" : value;
  if (value === null || typeof value !== "object") return value;
  if (depth <= 0) return "[details available through inspection]";
  if (Array.isArray(value)) return value.slice(0, 8).map((entry) => brief(entry, depth - 1));
  return Object.fromEntries(Object.entries(value).slice(0, 16).map(([key, entry]) => [key, brief(entry, depth - 1)]));
}

function projectBrief(value: unknown): Record<string, unknown> {
  const project = record(value);
  if (Object.keys(project).length === 0) return {};
  return {...pick(project, ["id", "status", "reason", "created", "deadline"]),
    goal: record(project.plan).goal,
    steps: Object.fromEntries(Object.entries(record(project.steps)).map(([id, step]) => [id, pick(step, ["status", "error"])]))};
}

export function buildDialogueContext(context: AgentContext): Omit<AgentContext, "market_view"> {
  const {market_view: _market, ...base} = context;
  const actor = context.actor_context;
  const living = record(actor.living_world);
  const buildings = Array.isArray(actor.player_buildings) ? actor.player_buildings : [];
  const plots = Array.isArray(actor.farm) ? actor.farm : [];
  const recent = Array.isArray(living.recent_projects) ? living.recent_projects : [];
  const own = context.known_actors.find((entry) => entry.actor_id === context.agent.agent_id);
  return {...base,
    actor_context: {
      ...pick(actor, ["self", "relationships", "world_map", "crop_options", "characters", "exploration", "environment", "social"]),
      current_activity: brief(pick(own, ["observable_status", "current_public_state"])),
      farm_summary: {plot_count: plots.length, states: plots.reduce((counts: Record<string, number>, plot: unknown) => {
        const state = String(record(plot).state ?? "unknown"); counts[state] = (counts[state] ?? 0) + 1; return counts;
      }, {})},
      player_buildings: buildings.map((building) => ({...pick(building, ["building_id", "instance_id", "name", "owner_id", "position", "construction_complete", "rental_fees"]),
        production: pick(record(building).production, ["maintenance_state", "maintenance_paused", "maintenance_days_remaining", "max_queue_slots"])})),
      living_world: {...pick(living, ["capabilities", "commissions", "own_claims", "suggestion", "society", "interruptions", "work"]),
        project: living.project ?? {}, recent_projects: recent.slice(0, 2).map(projectBrief)},
      detail_policy: "This is a compact conversation view. Inspect tools read the original complete snapshot, including plots, building recipes and active terms. Do not treat omitted detail as absence.",
    },
    global_public_events: context.global_public_events.slice(-3).map((event) => brief(pick(event, ["event_type", "game_minute", "actor_id", "payload"])) as Record<string, unknown>),
    own_event_delta: context.own_event_delta.slice(-4).map((event) => brief(pick(event, ["event_type", "game_minute", "payload"])) as Record<string, unknown>),
    known_actors: context.known_actors.slice(0, 16).map((actor) => brief(pick(actor, ["actor_id", "display_name", "public_role", "observable_status", "relationship"])) as Record<string, unknown>),
    memories: context.memories.slice(0, 6).map((memory) => brief(pick(memory, ["summary", "kind", "game_minute", "payload"])) as Record<string, unknown>),
  };
}

async function withProviderTimeout<T>(
  timeoutMs: number,
  externalSignal: AbortSignal | undefined,
  operation: (signal: AbortSignal) => Promise<T>,
): Promise<T> {
  const controller = new AbortController();
  let abortSource: "timeout" | "external" | undefined;
  const timeout = setTimeout(() => {
    if (controller.signal.aborted) return;
    abortSource = "timeout";
    controller.abort();
  }, timeoutMs);
  const abortFromCaller = () => {
    if (controller.signal.aborted) return;
    abortSource = "external";
    controller.abort(externalSignal?.reason);
  };
  if (externalSignal?.aborted) abortFromCaller();
  else externalSignal?.addEventListener("abort", abortFromCaller, {once: true});
  try {
    return await operation(controller.signal);
  } catch (error) {
    if (abortSource === "timeout") throw new Error("provider_timeout");
    throw error;
  } finally {
    clearTimeout(timeout);
    externalSignal?.removeEventListener("abort", abortFromCaller);
  }
}

export class OpenAICompatibleProvider {
  readonly #config: ProviderConfig;
  readonly #concurrencyGate: ProviderConcurrencyGate;
  readonly #dailyUsage = new Map<string, {day: number; reserved: number}>();
  readonly #budgetPath?: string;

  #reserveTokens(request: Pick<DecisionRequest, "session_id" | "game_minute">, body: Record<string, unknown>): void {
    const day = Math.floor(request.game_minute / 1080);
    const key = request.session_id;
    const previous = this.#dailyUsage.get(key);
    const usage = previous && day <= previous.day ? previous : {day, reserved: 0};
    // UTF-8 bytes conservatively bound visible prompt tokens. Reserve completion
    // capacity and template overhead before every network round, including retries.
    const upperBound = new TextEncoder().encode(JSON.stringify(body)).length + Number(body.max_tokens ?? 16384) + 8192;
    if (usage.reserved + upperBound > 8_000_000) throw new Error("provider_daily_budget_exhausted");
    usage.reserved += upperBound;
    this.#dailyUsage.set(key, usage);
    if (this.#budgetPath) {
      writeFileSync(this.#budgetPath + ".tmp", JSON.stringify(Object.fromEntries(this.#dailyUsage), null, 2) + "\n");
      renameSync(this.#budgetPath + ".tmp", this.#budgetPath);
    }
  }

  constructor(config: ProviderConfig, budgetPath?: string) {
    this.#config = config;
    this.#concurrencyGate = new ProviderConcurrencyGate(config.maxConcurrency);
    this.#budgetPath = budgetPath;
    if (budgetPath && existsSync(budgetPath)) {
      const saved = JSON.parse(readFileSync(budgetPath, "utf8"));
      for (const [id, value] of Object.entries(saved)) {
        const row = record(value);
        if (!Number.isSafeInteger(row.day) || Number(row.day) < 0 || !Number.isSafeInteger(row.reserved) || Number(row.reserved) < 0 || Number(row.reserved) > 8_000_000) throw new Error("provider_budget_store_invalid");
        this.#dailyUsage.set(id, {day: Number(row.day), reserved: Number(row.reserved)});
      }
    }
  }

  async decide(request: DecisionRequest, context: AgentContext): Promise<ActionIntent> {
    return this.streamDecision(request, context, () => {});
  }

  async streamDecision(
    request: DecisionRequest,
    context: AgentContext,
    emit: (event: ProviderTraceEvent) => void,
    externalSignal?: AbortSignal,
  ): Promise<ActionIntent> {
    const endpoint = this.#config.baseUrl.endsWith("/chat/completions")
      ? this.#config.baseUrl : `${this.#config.baseUrl}/chat/completions`;
    const isDialogue = request.trigger === "dialogue";
    const work = record(record(context.actor_context.living_world).work);
    const pendingWork = Array.isArray(work.contracts) && work.contracts.some((value) => {
      const c = record(value), terms = record(c.terms);
      return c.status === "proposed" && [c.employer, terms.worker_id].includes(request.agent_id)
        && Array.isArray(c.accepted_by) && !c.accepted_by.includes(request.agent_id);
    });
    const pendingJoint = Array.isArray(work.ventures) && work.ventures.some((value) => {
      const v = record(value); return v.status === "proposed" && record(v.terms).partner_id === request.agent_id;
    });
    const exploration = record(context.actor_context.exploration);
    const pendingResearch = Array.isArray(exploration.assignments) && exploration.assignments.some(value => {
      const c = record(value), t = record(c.terms);
      return c.status === "proposed" && [t.worker_id, t.funder_id].includes(request.agent_id)
        && Array.isArray(c.accepted_by) && !c.accepted_by.includes(request.agent_id);
    });
    const pendingIntel = Array.isArray(exploration.offers) && exploration.offers.some(value => {
      const o = record(value); return o.status === "proposed" && o.buyer === request.agent_id && o.known === false;
    });
    const social = record(context.actor_context.social);
    const pendingEvent = Array.isArray(social.events) && social.events.some(value => {
      const e = record(value); return e.status === "enrolling" && e.owner !== request.agent_id && Array.isArray(e.enrolled) && !e.enrolled.includes(request.agent_id);
    });
    const negotiating = !isDialogue && (pendingWork || pendingJoint || pendingResearch || pendingIntel || pendingEvent);
    const commandLimit = isDialogue || negotiating ? 1 : 3;
    const allowedCommands = isDialogue
      ? context.allowed_command_tools.filter((name) => DIALOGUE_COMMANDS.has(name))
      : [...context.allowed_command_tools];
    let systemContent = isDialogue
      ? "You are a game NPC Agent speaking directly with the player. Reply in character in one to three concise sentences. You may use local read tools, then optionally issue at most one authorized interaction command. Never perform farming, travel, harvesting, or market speculation during dialogue. A rental command is a request to queue production: while dialogue pauses the world, Godot defers and revalidates it after resume. Never describe a proposal, queued request, or processing order as completed goods. If you promise a trade or rental, issue the corresponding authorized command in this response; otherwise clearly say no operation was submitted. Never invent world assets."
      : "You are a game NPC Agent. You may use local read tools to inspect only the supplied context, then use zero to three authorized command tools in execution order. For farm3d, inspect actor_context.living_world and prefer submit_project for multi-step goals that you choose yourself. Choose milestones and budgets from resources and opportunities; decline uneconomic plans. Existing accepted projects execute without more model calls. Use no command when no action is needed. Put travel or build last. Never invent world assets.";
    const {market_view: _marketView, ...fullPromptContext} = context;
    if (negotiating) systemContent = "You are independently reviewing another actor's voluntary proposal. Use living_world.work for exact parties, cargo_provider, contributions, current version and prior performance. Choose at most ONE authorized command: accept, counter, decline/cancel, wait, or prioritize another goal. You are not required to accept. For delivery, the EMPLOYER supplies cargo on acceptance: empty proposal escrow does NOT mean the worker supplies goods. Only supply kind uses worker-owned goods. Evaluate time, wage and obligations concisely; avoid re-analyzing the entire economy. The executor stops a batch on an asynchronous order, so do not combine negotiations behind production/travel. Do not claim agreement or delivery without its actual receipt.";
    const promptContext = isDialogue || negotiating ? buildDialogueContext(context) : fullPromptContext;
    systemContent += " Exploration proposals and intelligence are in actor_context.exploration. A funded investigation escrows the funder's two bread and reward only after both parties consent; no sample means no guaranteed reward. Buy only valuable unknown intelligence you can afford. Declining or waiting is valid. Unknown paid reports expose summary only; never invent their contents or coordinates. Use share_intelligence to authorize a free disclosure before revealing usable private findings.";
    if (pendingEvent) systemContent += " A voluntary local activity is listed in actor_context.social. Independently weigh your interests, ticket price, route and prior commitments; you may enroll as a spectator, decline or prioritize another goal. Never fabricate a score or assume other actors enrolled. One command per review.";
    const userContent = isDialogue
      ? {context: promptContext, dialogue_input: request.dialogue_input ?? ""}
      : promptContext;
    const messages: Record<string, unknown>[] = [
      {role: "system", content: systemContent},
      {role: "user", content: JSON.stringify(userContent)},
    ];
    let readRounds = 0;
    let corrections = 0;
    let timeoutRetried = false;
    const correctCommands = (error: unknown, output: ProviderRawOutput): void => {
      externalSignal?.throwIfAborted();
      const code = error instanceof Error ? error.message : "";
      if (!["provider_invalid_intent:invalid_arguments", "provider_invalid_intent:wait_must_be_exclusive",
        "provider_invalid_tool_arguments", "provider_incomplete_tool_call", "provider_output_truncated",
        "provider_too_many_tool_calls"].includes(code)) throw error;
      const errors = output.message.tool_calls.flatMap(call => {
        try { return toolArgumentErrors(call.function.name, JSON.parse(call.function.arguments)); }
        catch { return [`${call.function.name || "tool"}: incomplete or invalid JSON; submit a complete JSON object`]; }
      });
      if (code.endsWith("wait_must_be_exclusive")) errors.push("wait must be the only command; omit wait when recording an intention or sending a message");
      if (code === "provider_too_many_tool_calls") errors.push(`maximum commands is ${commandLimit}`);
      if (code === "provider_output_truncated") errors.push("output was truncated; keep text and analysis short and regenerate the entire batch");
      emit({type: "output", output: {...output, validation_errors: [code, ...errors].slice(0, 9)}});
      if (corrections >= 1) throw error;
      corrections += 1;
      // Never execute the valid subset of a rejected batch or add more read rounds.
      readRounds = 2;
      const feedback = {ok: false, error: code, details: errors.slice(0, 8),
        message: "The entire command batch was rejected. No commands were executed. Correct all arguments and reissue the complete intended batch once, or return no action. Do not change permissions or assume any proposal succeeded. Use short goal/text fields; respect every schema limit, including public unit_reward <= 200."};
      const calls = output.message.tool_calls;
      const ids = calls.map(call => call.id);
      const usableHistory = ids.every(id => id.trim()) && new Set(ids).size === ids.length && calls.every(call => {
        try { JSON.parse(call.function.arguments); return true; } catch { return false; }
      });
      if (usableHistory && calls.length > 0) {
        messages.push({role: "assistant", content: output.message.content || null, tool_calls: calls});
        messages.push(...calls.map(call => ({role: "tool", tool_call_id: call.id, name: call.function.name, content: JSON.stringify(feedback)})));
      } else {
        // Do not put malformed tool calls back into the provider message history.
        messages.push({role: "system", content: JSON.stringify(feedback)});
      }
    };
    while (true) {
      externalSignal?.throwIfAborted();
      const availableReads = readRounds < 2 ? [...context.allowed_read_tools] : [];
      // Keep the embedded capability list in agreement with this round's tool menu.
      const roundContext = {...promptContext, allowed_read_tools: availableReads};
      messages[1] = {role: "user", content: JSON.stringify(isDialogue
        ? {context: roundContext, dialogue_input: request.dialogue_input ?? ""} : roundContext)};
      messages[0] = {role: "system", content: `${systemContent} You have at most two read-only rounds, with ${Math.max(0, 2 - readRounds)} remaining. Batch useful reads. Never mix read tools and command tools in one response. After reading, use only the current command tools or return no action. Keep analysis concise; do not repeatedly enumerate speculative plans. Context is a snapshot: commission deadlines may pass while you decide; Godot revalidates before spending.${isDialogue ? " For greetings or questions about what you are doing, answer directly from your activity/project and recent events without tools. Inspect only when details are needed for this player's request; do not start an economic analysis during small talk." : ""}`};
      const providerBody: Record<string, unknown> = {
        model: this.#config.model,
        // Concise population plans and voluntary negotiations still need reasoning.
        // Only dialogue and bounded recovery rounds use the fast non-thinking path.
        enable_thinking: !(isDialogue || corrections > 0 || timeoutRetried),
        temperature: this.#config.temperature,
        max_tokens: this.#config.maxOutputTokens,
        stream: true,
        stream_options: {include_usage: true},
        messages: structuredClone(messages),
        tool_choice: "auto",
        tools: [
          ...availableReads.map(readToolDescription),
          ...allowedCommands.map(toolDescription),
        ],
      };
      if ((providerBody.tools as unknown[]).length === 0) {
        delete providerBody.tool_choice;
        delete providerBody.tools;
      }
      emit({type: "input", body: structuredClone(providerBody)});
      this.#reserveTokens(request, providerBody);
      const queuedAt = performance.now();
      let queueWaitMs = 0;
      let round: {assembler: AgentStreamAssembler; rawOutput: ReturnType<AgentStreamAssembler["rawOutput"]>};
      try {
        round = await this.#concurrencyGate.run(
          externalSignal,
          (scheduledSignal) => withProviderTimeout(
            this.#config.timeoutMs,
            scheduledSignal,
            async (signal) => {
              queueWaitMs = performance.now() - queuedAt;
              const response = await fetch(endpoint, {
                method: "POST",
                signal,
                headers: {"content-type": "application/json", authorization: `Bearer ${this.#config.apiKey}`},
                body: JSON.stringify(providerBody),
              });
              if (!response.ok) throw new Error(`provider_http_${response.status}`);
              if (!response.body) throw new Error("provider_missing_stream_body");
              const roundAssembler = new AgentStreamAssembler();
              for await (const chunk of decodeProviderSse(response.body)) {
                for (const event of roundAssembler.accept(chunk)) emit(event);
              }
              return {assembler: roundAssembler, rawOutput: roundAssembler.rawOutput()};
            },
          ),
          isDialogue ? "dialogue" : "background",
        );
      } catch (error) {
        // No command has left this service yet. Retry one timed-out autonomous
        // round without extended thinking; cancellation is never retried.
        if (!isDialogue && !timeoutRetried && !externalSignal?.aborted && error instanceof Error && error.message === "provider_timeout") {
          timeoutRetried = true;
          messages.push({role: "system", content: "The previous provider round timed out; no commands were submitted. Decide briefly from the available facts, or return no action."});
          continue;
        }
        throw error;
      }
      const {assembler, rawOutput} = round;
      const reservation = this.#dailyUsage.get(request.session_id)!;
      rawOutput.metrics = {queue_wait_ms: queueWaitMs, game_day: reservation.day, reserved_tokens_day: reservation.reserved};
      emit({type: "output", output: rawOutput});
      externalSignal?.throwIfAborted();
      // Check names even when another call has broken JSON or a truncated body.
      if (rawOutput.message.tool_calls.some(call => call.function.name &&
        !context.allowed_read_tools.includes(call.function.name) && !allowedCommands.includes(call.function.name))) {
        throw new Error("provider_invalid_intent:unauthorized_tool");
      }
      let calls: ReturnType<AgentStreamAssembler["toolCalls"]>;
      try {
        if (rawOutput.finish_reason === "length") throw new Error("provider_output_truncated");
        calls = assembler.toolCalls();
      } catch (error) {
        correctCommands(error, rawOutput);
        continue;
      }
      const reads = calls.filter((call) => context.allowed_read_tools.includes(call.name));
      if (reads.length > 0) {
        // Unknown tools still fail closed. A mixed batch never executes commands.
        if (calls.some((call) => !context.allowed_read_tools.includes(call.name) && !allowedCommands.includes(call.name))) {
          throw new Error("provider_invalid_intent:unauthorized_tool");
        }
        let correction = reads.length !== calls.length;
        const canRead = readRounds < 2;
        const results = calls.map((call) => {
          let result: Record<string, unknown>;
          if (!context.allowed_read_tools.includes(call.name)) {
            result = {ok: false, error: "command_not_executed", message: "Reissue in a command-only response after inspecting read results."};
          } else if (!canRead) {
            correction = true;
            result = {ok: false, error: "read_round_limit", message: "No read rounds remain. Decide using existing results or return no action."};
          } else {
            try { result = executeReadTool(context, call.name, call.arguments); }
            catch (error) {
              if (!(error instanceof Error) || error.message !== "provider_invalid_read_arguments") throw error;
              correction = true;
              result = {ok: false, error: "invalid_read_arguments", message: "Use the advertised JSON schema; arrays must be JSON arrays, not strings."};
            }
          }
          return {role: "tool", tool_call_id: call.id, name: call.name, content: JSON.stringify(result)};
        });
        if (correction) {
          if (corrections >= 1) throw new Error("provider_tool_correction_exhausted");
          corrections += 1;
        }
        if (canRead) readRounds += 1;
        messages.push({role: "assistant", content: rawOutput.message.content || null, tool_calls: rawOutput.message.tool_calls});
        messages.push(...results);
        continue;
      }
      try {
        return assembler.finish(request, allowedCommands, commandLimit).intent;
      } catch (error) {
        correctCommands(error, rawOutput);
      }
    }
  }

  async compactMemory(agent: AgentDefinition, events: MemoryEvent[], sessionId = "memory"): Promise<{summary: string; importance: number}> {
    if (events.length === 0) throw new Error("memory_compaction_requires_events");
    const payload = await this.#concurrencyGate.run(
      undefined,
      (scheduledSignal) => withProviderTimeout(
        this.#config.timeoutMs,
        scheduledSignal,
        async (signal) => {
          const endpoint = this.#config.baseUrl.endsWith("/chat/completions")
            ? this.#config.baseUrl : `${this.#config.baseUrl}/chat/completions`;
          this.#reserveTokens({session_id: sessionId, game_minute: Math.max(...events.map(e => e.game_minute))}, {events, max_tokens: Math.min(600, this.#config.maxOutputTokens)});
          const response = await fetch(endpoint, {
            method: "POST", signal,
            headers: {"content-type": "application/json", authorization: `Bearer ${this.#config.apiKey}`},
            body: JSON.stringify({
              model: this.#config.model, temperature: Math.min(0.3, this.#config.temperature),
              max_tokens: Math.min(600, this.#config.maxOutputTokens), response_format: {type: "json_object"},
              messages: [
                {role: "system", content: "Compress verified NPC events into one factual long-term memory. Return JSON with summary and importance (1-10). Do not invent facts."},
                {role: "user", content: JSON.stringify({agent: {id: agent.agent_id, soul: agent.soul, goals: agent.goals}, events})},
              ],
            }),
          });
          if (!response.ok) throw new Error(`provider_http_${response.status}`);
          return await response.json() as Record<string, unknown>;
        },
      ),
    );
    const choice = (payload.choices as Array<Record<string, unknown>> | undefined)?.[0];
    const message = choice?.message as Record<string, unknown> | undefined;
    if (typeof message?.content !== "string") throw new Error("provider_missing_memory_content");
    let value: unknown;
    try { value = JSON.parse(message.content); } catch { throw new Error("provider_invalid_memory_json"); }
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("provider_invalid_memory");
    const record = value as Record<string, unknown>;
    if (typeof record.summary !== "string" || !record.summary.trim() || record.summary.length > 1200) throw new Error("provider_invalid_memory_summary");
    if (!Number.isSafeInteger(record.importance) || Number(record.importance) < 1 || Number(record.importance) > 10) throw new Error("provider_invalid_memory_importance");
    return {summary: record.summary.trim(), importance: Number(record.importance)};
  }
}
