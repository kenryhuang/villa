export interface LoopConfig {
  max_read_rounds: number;
  max_read_calls: number;
  max_actions: number;
  max_dialogue_actions: number;
  compact_at_tokens: number;
  compact_target_tokens: number;
  max_input_tokens: number;
  max_compactions: number;
}
export const DEFAULT_LOOP: LoopConfig = {
  max_read_rounds: 6,
  max_read_calls: 12,
  max_actions: 3,
  max_dialogue_actions: 1,
  compact_at_tokens: 48000,
  compact_target_tokens: 32000,
  max_input_tokens: 64000,
  max_compactions: 6,
};
export function validateLoopConfig(value: unknown): LoopConfig {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error("invalid_loop_config");
  const result = { ...DEFAULT_LOOP, ...value };
  for (const [k, v] of Object.entries(result))
    if (!(k in DEFAULT_LOOP) || !Number.isSafeInteger(v) || Number(v) < 1)
      throw new Error("invalid_loop_config");
  if (
    !(
      result.compact_target_tokens < result.compact_at_tokens &&
      result.compact_at_tokens < result.max_input_tokens
    ) ||
    result.max_actions > 3 ||
    result.max_dialogue_actions > result.max_actions ||
    result.max_read_calls > 64 ||
    result.max_read_rounds > 16 ||
    result.max_compactions > 8
  )
    throw new Error("invalid_loop_config");
  return result;
}

/** A failed execution still consumes a slot. Reflection cannot reset budgets. */
export class LoopBudget {
  reads = 0;
  readRounds = 0;
  actions = 0;
  rounds = 0;
  readonly config: LoopConfig;
  readonly actionLimit: number;
  constructor(config: LoopConfig, actionLimit: number) {
    this.config = config;
    this.actionLimit = actionLimit;
  }
  get canRead(): boolean {
    return (
      this.reads < this.config.max_read_calls &&
      this.readRounds < this.config.max_read_rounds
    );
  }
  snapshot() {
    return {
      remaining_read_rounds: Math.max(
        0,
        this.config.max_read_rounds - this.readRounds,
      ),
      remaining_read_calls: this.canRead
        ? this.config.max_read_calls - this.reads
        : 0,
      max_read_calls_per_round: this.canRead
        ? Math.min(4, this.config.max_read_calls - this.reads)
        : 0,
      max_actions: this.remainingActions,
    };
  }
  get remainingActions(): number {
    return this.actionLimit - this.actions;
  }
  nextRound(): void {
    if (++this.rounds > this.config.max_read_rounds + this.actionLimit + 3)
      throw new Error("loop_round_budget_exhausted");
  }
  takeAction(): void {
    if (this.remainingActions <= 0) throw new Error("action_budget_exhausted");
    this.actions++;
  }
}
