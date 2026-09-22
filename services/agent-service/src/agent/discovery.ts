import { QUERY_CATALOG } from "./environment.ts";
import { commandDomain } from "./tools.ts";

export function discoverTools(
  args: Record<string, unknown>,
  opened: Set<string>,
  enabledCommands: Set<string>,
  authorizedCommands: readonly string[],
  basicCommands: string[],
  basic: string[],
): Record<string, unknown> {
  for (const d of args.domains as string[]) opened.add(d);
  const available = authorizedCommands.filter(
    (n) => !basic.includes(n) && opened.has(commandDomain(n)),
  );
  const requested = args.actions as string[] | undefined;
  const rejected = requested?.filter((n) => !available.includes(n)) ?? [];
  // Discovery is a catalog lookup, not a command. A mistaken selection
  // returns useful feedback and never grants or executes an unknown action.
  const retained = available.filter((n) => enabledCommands.has(n));
  const defaults = available
    .filter((n) => (args.domains as string[]).includes(commandDomain(n)))
    .slice(0, 4);
  const selected = rejected.length
    ? retained
    : (requested ?? [...new Set([...retained, ...defaults])].slice(0, 6));
  enabledCommands.clear();
  [...basicCommands, ...selected].forEach((n) => enabledCommands.add(n));
  return {
    ok: rejected.length === 0,
    opened: [...opened],
    query_catalog: Object.fromEntries(
      [...opened]
        .filter((d) => QUERY_CATALOG[d])
        .map((d) => [d, QUERY_CATALOG[d]]),
    ),
    available_actions: available,
    enabled_actions: selected,
    ...(rejected.length
      ? { error: "invalid_action_selection", rejected_actions: rejected }
      : {}),
    next: "Domains are now open. query_catalog gives exact sections and requirements; skip overview and query facts directly with query_world(domain,section) or inspect_self_resources directly. actions accepts only exact names from available_actions, not read tools or natural-language descriptions. Omit actions to discover domains; explicit actions replaces the extra action menu. No action was executed.",
  };
}
