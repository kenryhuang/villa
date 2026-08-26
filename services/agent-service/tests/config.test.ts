import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { loadConfigFile, selectConfigPath } from "../src/config.ts";

const validConfig = () => ({
  service: {host: "127.0.0.1", port: 9001},
  provider: {
    base_url: "http://127.0.0.1:9000/v1/",
    api_key: "test-key",
    model: "test-model",
    timeout_ms: 30000,
    max_output_tokens: 1600,
    temperature: 0.25,
  },
  memory: {database_path: "data/test.sqlite", checkpoint_root: "data/checkpoints"},
});

const withTempConfig = (value: unknown, run: (path: string, root: string) => void): void => {
  const root = mkdtempSync(join(tmpdir(), "villa-agent-config-"));
  const path = join(root, "agent-service.json");
  writeFileSync(path, typeof value === "string" ? value : JSON.stringify(value), "utf8");
  try { run(path, root); } finally { rmSync(root, {recursive: true, force: true}); }
};

test("loads strict service Provider and memory settings from JSON", () => {
  withTempConfig(validConfig(), (path, root) => {
    const config = loadConfigFile(path, root);
    assert.equal(config.host, "127.0.0.1");
    assert.equal(config.port, 9001);
    assert.equal(config.provider.baseUrl, "http://127.0.0.1:9000/v1");
    assert.equal(config.provider.apiKey, "test-key");
    assert.equal(config.provider.model, "test-model");
    assert.equal(config.provider.timeoutMs, 30000);
    assert.equal(config.provider.maxOutputTokens, 1600);
    assert.equal(config.provider.temperature, 0.25);
    assert.equal(config.databasePath, resolve(root, "data/test.sqlite"));
    assert.equal(config.checkpointRoot, resolve(root, "data/checkpoints"));
  });
});

test("selects the default or explicit config path without environment variables", () => {
  const root = resolve("service-root");
  assert.equal(
    selectConfigPath(["node", "src/server.ts"], root),
    resolve(root, "config/agent-service.local.json"),
  );
  assert.equal(
    selectConfigPath(["node", "src/server.ts", "--config", "custom/config.json"], root),
    resolve(root, "custom/config.json"),
  );
  assert.throws(
    () => selectConfigPath(["node", "src/server.ts", "--config"], root),
    /--config requires a path/,
  );
});

test("rejects missing malformed and incomplete configuration files", () => {
  const root = mkdtempSync(join(tmpdir(), "villa-agent-config-errors-"));
  try {
    assert.throws(() => loadConfigFile(join(root, "missing.json"), root), /Unable to read Agent service config/);
    withTempConfig("{bad-json", (path, serviceRoot) => {
      assert.throws(() => loadConfigFile(path, serviceRoot), /Invalid Agent service config JSON/);
    });
    const missingKey = validConfig();
    delete (missingKey.provider as Record<string, unknown>).api_key;
    withTempConfig(missingKey, (path, serviceRoot) => {
      assert.throws(() => loadConfigFile(path, serviceRoot), /provider.api_key is required/);
    });
  } finally { rmSync(root, {recursive: true, force: true}); }
});

test("rejects invalid URLs ranges and section shapes", () => {
  for (const [mutate, expected] of [
    [(value: ReturnType<typeof validConfig>) => { value.provider.base_url = "not-a-url"; }, /provider.base_url is invalid/],
    [(value: ReturnType<typeof validConfig>) => { value.service.port = 70000; }, /service.port is invalid/],
    [(value: ReturnType<typeof validConfig>) => { value.provider.temperature = 3; }, /provider.temperature is invalid/],
    [(value: ReturnType<typeof validConfig>) => { (value as unknown as Record<string, unknown>).service = []; }, /service must be an object/],
    [(value: ReturnType<typeof validConfig>) => { (value as unknown as Record<string, unknown>).extra = {}; }, /unknown top-level field: extra/],
  ] as const) {
    const value = validConfig(); mutate(value);
    withTempConfig(value, (path, root) => assert.throws(() => loadConfigFile(path, root), expected));
  }
});

test("does not consult Provider environment variables", () => {
  const previous = process.env.AGENT_PROVIDER_API_KEY;
  process.env.AGENT_PROVIDER_API_KEY = "environment-key-must-be-ignored";
  try {
    const value = validConfig();
    delete (value.provider as Record<string, unknown>).api_key;
    withTempConfig(value, (path, root) => {
      assert.throws(() => loadConfigFile(path, root), /provider.api_key is required/);
    });
  } finally {
    if (previous === undefined) delete process.env.AGENT_PROVIDER_API_KEY;
    else process.env.AGENT_PROVIDER_API_KEY = previous;
  }
});
