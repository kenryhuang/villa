type Priority = "background" | "dialogue";
const PREEMPTED = new Error("provider_yield_to_dialogue");

interface Lease {
  priority: Priority;
  controller: AbortController;
}

interface Waiter {
  signal?: AbortSignal;
  priority: Priority;
  resolve: (lease: Lease) => void;
  reject: (reason: unknown) => void;
  abort?: () => void;
}

function cancellationReason(signal: AbortSignal): unknown {
  return signal.reason ?? new Error("provider_cancelled");
}

export class ProviderConcurrencyGate {
  readonly #limit: number;
  readonly #active = new Set<Lease>();
  readonly #queue: Waiter[] = [];

  constructor(limit: number) {
    if (!Number.isSafeInteger(limit) || limit < 1) throw new Error("invalid_provider_concurrency");
    this.#limit = limit;
  }

  async run<T>(signal: AbortSignal | undefined, operation: (signal: AbortSignal) => Promise<T>, priority: Priority = "background"): Promise<T> {
    while (true) {
      const lease = await this.#acquire(signal, priority);
      const combined = signal ? AbortSignal.any([signal, lease.controller.signal]) : lease.controller.signal;
      try {
        const result = await operation(combined);
        combined.throwIfAborted();
        return result;
      } catch (error) {
        if (signal?.aborted) throw cancellationReason(signal);
        // Only unfinished remote reads are preemptible. No game command has
        // committed inside this gate; restart that round after the dialogue.
        if (lease.controller.signal.reason !== PREEMPTED) throw error;
      } finally {
        this.#active.delete(lease);
        this.#grantNext();
      }
    }
  }

  #acquire(signal: AbortSignal | undefined, priority: Priority): Promise<Lease> {
    if (signal?.aborted) return Promise.reject(cancellationReason(signal));
    return new Promise<Lease>((resolve, reject) => {
      const waiter: Waiter = {signal, priority, resolve, reject};
      if (signal) {
        waiter.abort = () => {
          const index = this.#queue.indexOf(waiter);
          if (index >= 0) this.#queue.splice(index, 1);
          reject(cancellationReason(signal));
        };
        signal.addEventListener("abort", waiter.abort, {once: true});
        if (signal.aborted) {
          waiter.abort();
          return;
        }
      }
      this.#queue.push(waiter);
      this.#grantNext();
      if (priority === "dialogue" && this.#queue.includes(waiter)) {
        const background = [...this.#active].find((lease) => lease.priority === "background" && !lease.controller.signal.aborted);
        background?.controller.abort(PREEMPTED);
      }
    });
  }

  #grantNext(): void {
    while (this.#queue.length > 0 && this.#active.size < this.#limit) {
      const urgent = this.#queue.findIndex((waiter) => waiter.priority === "dialogue");
      const [waiter] = this.#queue.splice(urgent < 0 ? 0 : urgent, 1);
      if (waiter.abort) waiter.signal?.removeEventListener("abort", waiter.abort);
      if (waiter.signal?.aborted) {
        waiter.reject(cancellationReason(waiter.signal));
        continue;
      }
      const lease: Lease = {priority: waiter.priority, controller: new AbortController()};
      this.#active.add(lease);
      waiter.resolve(lease);
    }
  }
}
