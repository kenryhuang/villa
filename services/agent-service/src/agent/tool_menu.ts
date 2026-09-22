import { GAME_ENV, QUERY_CATALOG } from "./environment.ts";
import { commandDomain } from "./tools.ts";
import { discoverTools } from "./discovery.ts";
import { buildTools } from "./build_context.ts";
import type { LoopBudget } from "../budget/loop_budget.ts";

export class ToolMenu {
  readonly opened = new Set<string>();
  readonly basic = ["speak", "wait", "public_wait"];
  readonly enabled = new Set(this.basic);
  readonly domains: string[];
  readonly authorized: readonly string[];
  constructor(authorized: readonly string[], publicAgent: boolean) {
    this.authorized = authorized;
    this.domains = publicAgent
      ? ["public", "environment", "social", "memory"]
      : Object.keys(GAME_ENV.domains).filter((d) => d !== "public");
  }
  discover(args: Record<string, unknown>) {
    return discoverTools(
      args,
      this.opened,
      this.enabled,
      this.authorized,
      this.basic,
      this.basic,
    );
  }
  build(budget: LoopBudget) {
    const queryDomains = [...this.opened].filter((d) => QUERY_CATALOG[d]);
    const reads = budget.canRead
      ? [
          "discover_tools",
          "inspect_self_resources",
          "recall_memory",
          ...(queryDomains.length ? ["query_world"] : []),
          ...(queryDomains.includes("map") ? ["query_map"] : []),
          ...(this.opened.has("memory")
            ? ["inspect_event", "inspect_history_segment"]
            : []),
        ]
      : [];
    const available = this.authorized.filter(
      (n) => !this.basic.includes(n) && this.opened.has(commandDomain(n)),
    );
    const commands = budget.remainingActions
      ? this.authorized.filter((n) => this.enabled.has(n))
      : [];
    return {
      reads,
      commands,
      queryDomains,
      tools: buildTools(reads, queryDomains, this.domains, available, commands),
      catalog: Object.fromEntries(
        queryDomains.map((d) => [d, QUERY_CATALOG[d]]),
      ),
    };
  }
}
