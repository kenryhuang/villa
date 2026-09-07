import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type {DecisionRequest} from "./protocol.ts";

export interface Soul {
  traits: string[];
  values: string[];
  speech_style: string;
  risk_tolerance: number;
}

interface RoleDefinition {
  role_id: string;
  goals: string[];
  tools: string[];
  read_tools?: string[];
  decision_interval_hours: [number, number];
}

interface ProfileDefinition {
  agent_id: string;
  npc_id: string;
  display_name: string;
  role_id: string;
  soul: Soul;
  initial_resources: Record<string, unknown>;
}

export interface AgentDefinition extends ProfileDefinition {
  goals: string[];
  tools: string[];
  decision_interval_hours: [number, number];
}

export interface AgentContext {
  agent: Pick<AgentDefinition, "agent_id" | "display_name" | "soul"> & {active_role: string; goals: readonly string[]};
  actor_context: Record<string, unknown>;
  public_world_state: Record<string, unknown>;
  global_public_events: readonly Record<string, unknown>[];
  known_actors: readonly Record<string, unknown>[];
  own_event_delta: readonly Record<string, unknown>[];
  market_summary: Record<string, unknown>;
  market_view: Record<string, unknown>;
  interaction_view: Record<string, unknown>;
  agreement_view: Record<string, unknown>;
  memories: readonly Record<string, unknown>[];
  allowed_read_tools: readonly string[];
  allowed_command_tools: readonly string[];
}

const GENERAL_COMMAND_TOOLS = [
	"rent_production", "submit_project", "retry_project", "cancel_project", "publish_commission", "propose_player_commission", "claim_commission", "deliver_commission", "suggest_behavior",
  "send_message", "propose_trade", "counter_trade", "accept_trade",
  "reject_trade", "cancel_trade", "speak", "wait", "propose_role_change",
  "propose_cooperation", "counter_cooperation", "accept_cooperation",
  "reject_cooperation", "commit_contribution", "cancel_cooperation",
] as const;

export class AgentRegistry {
  readonly #agents = new Map<string, AgentDefinition>();
  readonly #roles = new Map<string, RoleDefinition>();

  constructor(roles: RoleDefinition[], profiles: ProfileDefinition[]) {
    const roleMap = new Map(roles.map((role) => [role.role_id, role]));
    for (const role of roles) {
      if (!role.role_id || this.#roles.has(role.role_id)) throw new Error(`Invalid role: ${role.role_id}`);
      this.#roles.set(role.role_id, structuredClone(role));
    }
    for (const profile of profiles) {
      const role = roleMap.get(profile.role_id);
      if (!role || this.#agents.has(profile.agent_id)) throw new Error(`Invalid Agent profile: ${profile.agent_id}`);
      this.#agents.set(profile.agent_id, {
        ...structuredClone(profile), goals: [...role.goals], tools: [...role.tools],
        decision_interval_hours: [...role.decision_interval_hours] as [number, number],
      });
    }
  }

  static loadDefault(): AgentRegistry {
    const root = resolve(process.cwd(), "../../data/agents");
    return new AgentRegistry(
      JSON.parse(readFileSync(resolve(root, "roles.json"), "utf8")),
      JSON.parse(readFileSync(resolve(root, "profiles.json"), "utf8")),
    );
  }

  ids(): string[] { return [...this.#agents.keys()].sort(); }

  get(agentId: string): AgentDefinition | undefined {
    const value = this.#agents.get(agentId);
    return value ? structuredClone(value) : undefined;
  }

  buildContext(
    agentId: string,
    request: DecisionRequest,
    memories: readonly Record<string, unknown>[],
  ): AgentContext {
    const agent = this.#agents.get(agentId);
    if (!agent) throw new Error(`Unknown Agent: ${agentId}`);
    if (request.agent_id !== agentId) throw new Error(`Agent mismatch: ${agentId}`);
    const role = this.#roles.get(request.active_role);
    if (!role) throw new Error(`Unknown role: ${request.active_role}`);
    const goals = request.goals.filter((goal) => role.goals.includes(goal));
    const allowedReadTools = request.allowed_read_tools.filter((tool) => [...(role.read_tools ?? []), "inspect_map", "inspect_buildings", "inspect_building", "inspect_characters"].includes(tool));
    const localCommands = new Set([...role.tools, ...GENERAL_COMMAND_TOOLS]);
    const allowedCommandTools = request.allowed_command_tools.filter((tool) => localCommands.has(tool));
    return {
      agent: {agent_id: agent.agent_id, display_name: agent.display_name, soul: structuredClone(agent.soul), active_role: role.role_id, goals},
      actor_context: structuredClone(request.actor_context),
      public_world_state: structuredClone(request.public_world_state),
      global_public_events: structuredClone(request.global_public_events),
      known_actors: structuredClone(request.known_actors),
      own_event_delta: structuredClone(request.own_event_delta),
      market_summary: structuredClone(request.market_summary),
      market_view: structuredClone(request.market_view),
      interaction_view: structuredClone(request.interaction_view),
      agreement_view: structuredClone(request.agreement_view),
      memories: structuredClone(memories),
      allowed_read_tools: allowedReadTools,
      allowed_command_tools: allowedCommandTools,
    };
  }
}
