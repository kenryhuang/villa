import { readFileSync } from "node:fs";
import { resolve } from "node:path";

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
  agent: Pick<AgentDefinition, "agent_id" | "display_name" | "role_id" | "soul" | "goals">;
  snapshot: Record<string, unknown>;
  recent_events: readonly Record<string, unknown>[];
  memories: readonly Record<string, unknown>[];
  allowed_tools: readonly string[];
}

export class AgentRegistry {
  readonly #agents = new Map<string, AgentDefinition>();

  constructor(roles: RoleDefinition[], profiles: ProfileDefinition[]) {
    const roleMap = new Map(roles.map((role) => [role.role_id, role]));
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
    snapshot: Record<string, unknown>,
    events: readonly Record<string, unknown>[],
    memories: readonly Record<string, unknown>[],
  ): AgentContext {
    const agent = this.#agents.get(agentId);
    if (!agent) throw new Error(`Unknown Agent: ${agentId}`);
    return {
      agent: {agent_id: agent.agent_id, display_name: agent.display_name, role_id: agent.role_id, soul: structuredClone(agent.soul), goals: [...agent.goals]},
      snapshot: structuredClone(snapshot), recent_events: structuredClone(events), memories: structuredClone(memories),
      allowed_tools: [...agent.tools],
    };
  }
}
