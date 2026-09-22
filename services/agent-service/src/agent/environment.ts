import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
export const QUERY_CATALOG: Record<
  string,
  { sections: string[]; default_section: string; hint: string }
> = JSON.parse(
  readFileSync(
    fileURLToPath(
      new URL("../../../../data/agents/query_catalog.json", import.meta.url),
    ),
    "utf8",
  ),
);

export const GAME_ENV = JSON.parse(
  readFileSync(
    fileURLToPath(
      new URL("../../../../data/agents/game_env.json", import.meta.url),
    ),
    "utf8",
  ),
);
