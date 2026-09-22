export type ReadPort = (
  name: string,
  args: Record<string, unknown>,
  signal?: AbortSignal,
) => Promise<Record<string, unknown>>;
export interface LoopServices {
  read: ReadPort;
  execute?: (
    action: import("../protocol.ts").ActionCommand,
    signal?: AbortSignal,
  ) => Promise<Record<string, unknown>>;
  experience: Record<string, unknown>;
  memories: readonly Record<string, unknown>[];
  core_memories?: readonly Record<string, unknown>[];
  confirmed_dialogue?: readonly Record<string, unknown>[];
}
