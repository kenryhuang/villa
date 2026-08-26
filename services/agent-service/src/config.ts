export interface ProviderConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
  timeoutMs: number;
  maxOutputTokens: number;
  temperature: number;
}

export interface ServiceConfig {
  host: string;
  port: number;
  databasePath: string;
  provider: ProviderConfig;
}

type Environment = Record<string, string | undefined>;

function required(env: Environment, key: string): string {
  const value = env[key]?.trim();
  if (!value) throw new Error(`${key} is required`);
  return value;
}

function integer(env: Environment, key: string, fallback: number, minimum: number, maximum: number): number {
  if (!env[key]) return fallback;
  const value = Number(env[key]);
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) throw new Error(`${key} is invalid`);
  return value;
}

function decimal(env: Environment, key: string, fallback: number, minimum: number, maximum: number): number {
  if (!env[key]) return fallback;
  const value = Number(env[key]);
  if (!Number.isFinite(value) || value < minimum || value > maximum) throw new Error(`${key} is invalid`);
  return value;
}

export function loadConfig(env: Environment = process.env): ServiceConfig {
  const baseUrl = required(env, "AGENT_PROVIDER_BASE_URL").replace(/\/+$/, "");
  new URL(baseUrl);
  return {
    host: env.AGENT_SERVICE_HOST?.trim() || "127.0.0.1",
    port: integer(env, "AGENT_SERVICE_PORT", 8787, 1, 65535),
    databasePath: env.AGENT_MEMORY_DB?.trim() || "data/agent-memory.sqlite",
    provider: {
      baseUrl,
      apiKey: required(env, "AGENT_PROVIDER_API_KEY"),
      model: required(env, "AGENT_PROVIDER_MODEL"),
      timeoutMs: integer(env, "AGENT_PROVIDER_TIMEOUT_MS", 10_000, 100, 120_000),
      maxOutputTokens: integer(env, "AGENT_PROVIDER_MAX_OUTPUT_TOKENS", 1200, 64, 16_384),
      temperature: decimal(env, "AGENT_PROVIDER_TEMPERATURE", 0.4, 0, 2),
    },
  };
}
