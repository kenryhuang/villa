import { mkdirSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { AgentRegistry } from "./agents.ts";
import { createApp } from "./app.ts";
import { loadConfigFile, selectConfigPath } from "./config.ts";
import { MemoryRepository, removeLegacyCheckpointDatabases } from "./memory.ts";
import { OpenAICompatibleProvider } from "./provider.ts";

const serviceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const config = loadConfigFile(selectConfigPath(process.argv, serviceRoot), serviceRoot);
const databasePath = config.databasePath;
mkdirSync(dirname(databasePath), {recursive: true});
const memory = new MemoryRepository(databasePath);
if (memory.upgradedFromPreV2) removeLegacyCheckpointDatabases(config.checkpointRoot);
const app = createApp({
  memory,
  registry: AgentRegistry.loadDefault(),
  provider: new OpenAICompatibleProvider(config.provider),
  checkpointRoot: config.checkpointRoot,
});
const server = createServer(app);
server.listen(config.port, config.host, () => {
  process.stdout.write(JSON.stringify({status: "started", host: config.host, port: config.port}) + "\n");
});
const shutdown = (): void => server.close(() => { memory.close(); process.exit(0); });
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
