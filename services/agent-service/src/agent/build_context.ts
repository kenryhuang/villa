import { buildRules } from "./policy.ts";
import { readDefinition } from "./tools.ts";
import { toolDescription } from "../tool_contracts.ts";
import type { AgentContext } from "../agents.ts";
import type { DecisionRequest } from "../protocol.ts";
import type { LoopServices, LoopConfig } from "../agent_loop.ts";
import { GAME_ENV } from "./environment.ts";

export const buildGameEnv = (domains: string[]) => ({
  GameEnv: GAME_ENV.description,
  domains: Object.fromEntries(domains.map((d) => [d, GAME_ENV.domains[d]])),
});
export const buildRole = (context: AgentContext) => {
  const { goals, ...identity } = context.agent;
  return structuredClone(identity);
};
export const buildResources = (request: DecisionRequest) =>
  structuredClone(request.resources);
export const buildExperience = (services: LoopServices) => services.experience;
export const buildMemory = (services: LoopServices) => ({
  core_memories: services.core_memories ?? [],
  relevant_memories: services.memories,
});
export const buildGoals = (
  request: DecisionRequest,
  context: AgentContext,
) => ({
  role_goals: [...context.agent.goals],
  goal_refs: request.goal_refs ?? [],
  dialogue_followups: request.dialogue_followups ?? [],
});
export const buildConfirmedDialogue = (services: LoopServices) => ({
  confirmed_dialogue: services.confirmed_dialogue ?? [],
  dialogue_policy:
    "对话提取是带来源的待判断信息。confirmed/agreed 才是双方确认的约定，proposed/requested 不是双方同意，information 是陈述而非权威世界事实；取消和较新修订优先。查询核实人物、地点、活动、物品、数量、价格和权限再行动。未完成多步约定须持久化目标，不能把计划当完成。",
});

export function buildContext(
  request: DecisionRequest,
  context: AgentContext,
  services: LoopServices,
  config: LoopConfig,
  domains: string[],
  actionLimit: number,
) {
  const dialogue = request.trigger === "dialogue";
  const header = {
    identity: buildRole(context),
    resources: buildResources(request),
    experience: buildExperience(services),
    ...buildMemory(services),
    turn: {
      loop_id: request.request_id,
      trigger: request.trigger,
      game_minute: request.game_minute,
      dialogue_input: request.dialogue_input,
      ...buildGoals(request, context),
      executed_actions: [] as Record<string, unknown>[],
      ...buildConfirmedDialogue(services),
      dialogue_event_id: dialogue
        ? `dialogue:${request.request_id}`
        : undefined,
      query_catalog: {} as Record<string, unknown>,
      budget: {
        remaining_read_rounds: config.max_read_rounds,
        remaining_read_calls: config.max_read_calls,
        max_read_calls_per_round: 4,
        max_actions: actionLimit,
      },
    },
  };
  const messages: Record<string, unknown>[] = [
    {
      role: "system",
      content: JSON.stringify({
        ...buildGameEnv(domains),
        ...buildRules(request, actionLimit, Boolean(services.execute)),
      }),
    },
    { role: "user", content: JSON.stringify(header) },
  ];
  return { header, messages };
}

export function buildTools(
  readNames: string[],
  queryDomains: string[],
  domains: string[],
  available: readonly string[],
  commands: readonly string[],
): Record<string, unknown>[] {
  return [
    ...readNames.map((name) =>
      readDefinition(
        name,
        ["query_world", "query_map"].includes(name) ? queryDomains : domains,
        available,
      ),
    ),
    ...commands.map((name) => toolDescription(name, true)),
  ];
}
