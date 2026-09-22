import type { MemoryRepository, MemoryEvent } from "../memory.ts";
import type { ChatPort } from "../chat_provider.ts";
import { actionActor } from "../context_channels.ts";
import type { DialogueTurn } from "./intent_extraction.ts";
import { randomUUID } from "node:crypto";
import type { ProviderTraceEvent } from "../provider_stream.ts";

export interface IntentJob extends DialogueTurn {
  request_id: string;
  session_id: string;
  session_epoch: number;
  game_minute: number;
  room: string;
  generation: string;
}

/** Durable outbox. A crash leaves the original job eligible for replay. */
export class ChatIntentWorker {
  #running = false;
  #scheduled = false;
  #closed = false;
  #controller = new AbortController();
  #timer: ReturnType<typeof setInterval>;
  private memory: MemoryRepository;
  private provider: ChatPort;
  constructor(memory: MemoryRepository, provider: ChatPort) {
    this.memory = memory;
    this.provider = provider;
    this.#timer = setInterval(() => {
      if (memory.closed) this.close();
      else this.kick();
    }, 5000);
    this.#timer.unref();
  }

  enqueue(job: IntentJob): void {
    this.memory.appendEvent(job.session_id, `chat.jobs:${job.actor}`, {
      event_id: `intent-job:${job.request_id}`,
      kind: "ChatIntentPending",
      game_minute: job.game_minute,
      payload: { ...job },
    });
    this.kick();
  }

  kick(): void {
    if (
      this.#running ||
      this.#scheduled ||
      this.#closed ||
      !this.provider.extractIntents
    )
      return;
    this.#scheduled = true;
    setImmediate(() => {
      this.#scheduled = false;
      void this.drain();
    });
  }

  close(): void {
    this.#closed = true;
    clearInterval(this.#timer);
    this.#controller.abort();
  }

  async drain(): Promise<void> {
    if (
      this.#running ||
      this.#closed ||
      this.memory.closed ||
      !this.provider.extractIntents
    )
      return;
    this.#running = true;
    try {
      // One pass per kick; failed jobs remain durable and retry on a later tick.
      for (const entry of this.memory.pendingIntentJobs()) {
        if (this.#closed || this.memory.closed) break;
        const job = entry.payload as unknown as IntentJob;
        // A restored queued source can survive a new game epoch; an in-flight result cannot.
        const runEpoch = this.memory.sessionEpoch(job.session_id);
        const current = () =>
          !this.#closed &&
          !this.memory.closed &&
          this.memory.sessionEpoch(job.session_id) === runEpoch &&
          this.memory.chatContextGeneration(job.session_id, job.room) ===
            job.generation &&
          this.memory.inspectEvent(job.session_id, entry.actor, entry.event_id)
            .found === true;
        if (!current()) {
          if (!this.memory.closed) this.finish(entry, job, "cancelled");
          continue;
        }
        const failures = this.memory.intentJobErrorCount(
          job.session_id,
          job.actor,
          job.request_id,
        );
        if (failures >= 3) {
          this.finish(entry, job, "failed");
          continue;
        }
        const attempt = randomUUID();
        let sequence = 0;
        const record = (payload: Record<string, unknown>) => {
          if (!current()) return;
          this.memory.appendEvent(job.session_id, entry.actor, {
            event_id: `intent-trace:${attempt}:${sequence++}`,
            kind: "ChatIntentTrace",
            game_minute: job.game_minute,
            payload: {
              job_id: entry.event_id,
              attempt_id: attempt,
              timestamp_msec: Date.now(),
              ...payload,
            },
          });
        };
        record({ status: "running" });
        try {
          const intents = await this.provider.extractIntents(
            job,
            (trace: ProviderTraceEvent) => record({ trace }),
            this.#controller.signal,
          );
          if (!current()) continue;
          if (intents.length)
            this.memory.appendEvent(job.session_id, actionActor(job.actor), {
              event_id: `chat-intents:${job.request_id}`,
              kind: "ChatIntentExtracted",
              game_minute: job.game_minute,
              payload: {
                source: "latest_dialogue_turn",
                source_request_id: job.request_id,
                intents,
              },
            });
          record({
            status: intents.length ? "completed" : "empty",
            accepted: intents,
          });
          this.finish(entry, job, intents.length ? "completed" : "empty");
        } catch (error) {
          if (this.#closed || this.memory.closed) break;
          if (!current()) continue;
          const reason =
            error instanceof Error ? error.message : "extraction_failed";
          const retryable =
            failures < 2 &&
            !/daily_budget|invalid_intent|invalid_dialogue_intents|intent_evidence|JSON/.test(
              reason,
            );
          this.memory.appendEvent(job.session_id, entry.actor, {
            event_id: `intent-error:${job.request_id}:${Date.now()}`,
            kind: "ChatIntentError",
            game_minute: job.game_minute,
            payload: {
              job_id: entry.event_id,
              error: reason,
              retryable,
              retry_at: Date.now() + 30000,
            },
          });
          if (!retryable) this.finish(entry, job, "failed");
        }
      }
    } finally {
      this.#running = false;
    }
  }

  private finish(
    entry: MemoryEvent & { actor: string },
    job: IntentJob,
    status: string,
  ): void {
    this.memory.appendEvent(job.session_id, entry.actor, {
      event_id: `intent-done:${job.request_id}`,
      kind: "ChatIntentFinished",
      game_minute: job.game_minute,
      payload: { job_id: entry.event_id, status },
    });
  }
}
