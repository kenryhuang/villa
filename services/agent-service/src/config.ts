import { readFileSync } from "node:fs";
import { resolve } from "node:path";

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
  checkpointRoot: string;
  provider: ProviderConfig;
}

type JsonRecord = Record<string, unknown>;

const isRecord = (value: unknown): value is JsonRecord =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function objectSection(root: JsonRecord, key: string): JsonRecord {
  const value = root[key];
  if (!isRecord(value)) throw new Error(`${key} must be an object`);
  return value;
}

function rejectUnknown(value: JsonRecord, allowed: readonly string[], prefix: string): void {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) throw new Error(`unknown ${prefix}field: ${key}`);
  }
}

function requiredString(value: JsonRecord, key: string, field: string): string {
  const result = value[key];
  if (typeof result !== "string" || !result.trim()) throw new Error(`${field} is required`);
  return result.trim();
}

function integer(value: JsonRecord, key: string, field: string, fallback: number, minimum: number, maximum: number): number {
  if (value[key] === undefined) return fallback;
  const result = value[key];
  if (!Number.isSafeInteger(result) || Number(result) < minimum || Number(result) > maximum) throw new Error(`${field} is invalid`);
  return Number(result);
}

function decimal(value: JsonRecord, key: string, field: string, fallback: number, minimum: number, maximum: number): number {
  if (value[key] === undefined) return fallback;
  const result = value[key];
  if (typeof result !== "number" || !Number.isFinite(result) || result < minimum || result > maximum) throw new Error(`${field} is invalid`);
  return result;
}

export function selectConfigPath(argv: string[], serviceRoot: string): string {
  const configIndex = argv.indexOf("--config");
  if (configIndex < 0) return resolve(serviceRoot, "config/agent-service.local.json");
  const selected = argv[configIndex + 1];
  if (!selected || selected.startsWith("--")) throw new Error("--config requires a path");
  return resolve(serviceRoot, selected);
}

export function loadConfigFile(configPath: string, serviceRoot: string): ServiceConfig {
  let source: string;
  try { source = readFileSync(configPath, "utf8"); }
  catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to read Agent service config ${configPath}: ${detail}`);
  }
  let parsed: unknown;
  try { parsed = JSON.parse(source); }
  catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`Invalid Agent service config JSON: ${detail}`);
  }
  if (!isRecord(parsed)) throw new Error("Agent service config must be an object");
  rejectUnknown(parsed, ["service", "provider", "memory"], "top-level ");
  const service = objectSection(parsed, "service");
  const provider = objectSection(parsed, "provider");
  const memory = objectSection(parsed, "memory");
  rejectUnknown(service, ["host", "port"], "service ");
  rejectUnknown(provider, ["base_url", "api_key", "model", "timeout_ms", "max_output_tokens", "temperature"], "provider ");
  rejectUnknown(memory, ["database_path", "checkpoint_root"], "memory ");

  const baseUrl = requiredString(provider, "base_url", "provider.base_url").replace(/\/+$/, "");
  let parsedUrl: URL;
  try { parsedUrl = new URL(baseUrl); }
  catch { throw new Error("provider.base_url is invalid"); }
  if (!["http:", "https:"].includes(parsedUrl.protocol)) throw new Error("provider.base_url is invalid");

  return {
    host: service.host === undefined ? "127.0.0.1" : requiredString(service, "host", "service.host"),
    port: integer(service, "port", "service.port", 8787, 1, 65535),
    databasePath: resolve(serviceRoot, requiredString(memory, "database_path", "memory.database_path")),
    checkpointRoot: resolve(serviceRoot, requiredString(memory, "checkpoint_root", "memory.checkpoint_root")),
    provider: {
      baseUrl,
      apiKey: requiredString(provider, "api_key", "provider.api_key"),
      model: requiredString(provider, "model", "provider.model"),
      timeoutMs: integer(provider, "timeout_ms", "provider.timeout_ms", 10_000, 100, 120_000),
      maxOutputTokens: integer(provider, "max_output_tokens", "provider.max_output_tokens", 1200, 64, 16_384),
      temperature: decimal(provider, "temperature", "provider.temperature", 0.4, 0, 2),
    },
  };
}
