import { mkdirSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, resolve } from "node:path";
import { AgentRegistry } from "./agents.ts";
import { createApp } from "./app.ts";
import { loadConfig } from "./config.ts";
import { MemoryRepository } from "./memory.ts";
import { OpenAICompatibleProvider } from "./provider.ts";

const config = loadConfig();
const databasePath = resolve(config.databasePath);
mkdirSync(dirname(databasePath), {recursive: true});
const memory = new MemoryRepository(databasePath);
const app = createApp({
  memory,
  registry: AgentRegistry.loadDefault(),
  provider: new OpenAICompatibleProvider(config.provider),
  checkpointRoot: resolve("data/checkpoints"),
});
const server = createServer(app);
server.listen(config.port, config.host, () => {
  process.stdout.write(JSON.stringify({status: "started", host: config.host, port: config.port}) + "\n");
});
const shutdown = (): void => server.close(() => { memory.close(); process.exit(0); });
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
