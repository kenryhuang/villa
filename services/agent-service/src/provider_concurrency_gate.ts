type Release = () => void;

interface Waiter {
  signal?: AbortSignal;
  resolve: (release: Release) => void;
  reject: (reason: unknown) => void;
  abort?: () => void;
}

function cancellationReason(signal: AbortSignal): unknown {
  return signal.reason ?? new Error("provider_cancelled");
}

export class ProviderConcurrencyGate {
  readonly #limit: number;
  #active = 0;
  readonly #queue: Waiter[] = [];

  constructor(limit: number) {
    if (!Number.isSafeInteger(limit) || limit < 1) throw new Error("invalid_provider_concurrency");
    this.#limit = limit;
  }

  async run<T>(signal: AbortSignal | undefined, operation: () => Promise<T>): Promise<T> {
    const release = await this.#acquire(signal);
    try {
      return await operation();
    } finally {
      release();
    }
  }

  #acquire(signal: AbortSignal | undefined): Promise<Release> {
    if (signal?.aborted) return Promise.reject(cancellationReason(signal));
    if (this.#active < this.#limit) {
      this.#active += 1;
      return Promise.resolve(this.#releaseOnce());
    }
    return new Promise<Release>((resolve, reject) => {
      const waiter: Waiter = {signal, resolve, reject};
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
    });
  }

  #releaseOnce(): Release {
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.#active -= 1;
      this.#grantNext();
    };
  }

  #grantNext(): void {
    while (this.#queue.length > 0 && this.#active < this.#limit) {
      const waiter = this.#queue.shift()!;
      if (waiter.abort) waiter.signal?.removeEventListener("abort", waiter.abort);
      if (waiter.signal?.aborted) {
        waiter.reject(cancellationReason(waiter.signal));
        continue;
      }
      this.#active += 1;
      waiter.resolve(this.#releaseOnce());
    }
  }
}
