import { existsSync, readFileSync, writeFileSync, renameSync } from "node:fs";
import type { DecisionRequest } from "../protocol.ts";
const record = (value: unknown): Record<string, any> =>
  value && typeof value === "object" ? (value as any) : {};
/** Persistent per-session, per-game-day reservation, shared by foreground and background phases. */
export class ProviderBudget {
  readonly #dailyUsage = new Map<string, { day: number; reserved: number }>();
  readonly #budgetPath?: string;

  reserve(
    request: Pick<DecisionRequest, "session_id" | "game_minute">,
    body: Record<string, unknown>,
  ): void {
    const day = Math.floor(request.game_minute / 1080);
    const key = request.session_id;
    const previous = this.#dailyUsage.get(key);
    const usage =
      previous && day <= previous.day ? previous : { day, reserved: 0 };
    // UTF-8 bytes conservatively bound visible prompt tokens. Reserve completion
    // capacity and template overhead before every network round, including retries.
    const upperBound =
      new TextEncoder().encode(JSON.stringify(body)).length +
      Number(body.max_tokens ?? 16384) +
      8192;
    if (usage.reserved + upperBound > 8_000_000)
      throw new Error("provider_daily_budget_exhausted");
    usage.reserved += upperBound;
    this.#dailyUsage.set(key, usage);
    if (this.#budgetPath) {
      writeFileSync(
        this.#budgetPath + ".tmp",
        JSON.stringify(Object.fromEntries(this.#dailyUsage), null, 2) + "\n",
      );
      renameSync(this.#budgetPath + ".tmp", this.#budgetPath);
    }
  }

  constructor(budgetPath?: string) {
    this.#budgetPath = budgetPath;
    if (budgetPath && existsSync(budgetPath)) {
      const saved = JSON.parse(readFileSync(budgetPath, "utf8"));
      for (const [id, value] of Object.entries(saved)) {
        const row = record(value);
        if (
          !Number.isSafeInteger(row.day) ||
          Number(row.day) < 0 ||
          !Number.isSafeInteger(row.reserved) ||
          Number(row.reserved) < 0 ||
          Number(row.reserved) > 8_000_000
        )
          throw new Error("provider_budget_store_invalid");
        this.#dailyUsage.set(id, {
          day: Number(row.day),
          reserved: Number(row.reserved),
        });
      }
    }
  }
  reserved(session: string): number {
    return this.#dailyUsage.get(session)?.reserved ?? 0;
  }
}
