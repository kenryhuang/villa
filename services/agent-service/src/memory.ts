import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { basename, join } from "node:path";
import { DatabaseSync } from "node:sqlite";

export interface MemoryEvent {
  event_id: string;
  kind: string;
  game_minute: number;
  payload: Record<string, unknown>;
  importance?: number;
}

export interface CheckpointRecord { path: string; sha256: string; session_id: string; }

const DATABASE_VERSION = 2;

export function removeLegacyCheckpointDatabases(directory: string): void {
  mkdirSync(directory, {recursive: true});
  for (const entry of readdirSync(directory, {withFileTypes: true})) {
    if (!entry.isFile() || !/\.sqlite(?:-(?:wal|shm))?$/.test(entry.name)) continue;
    rmSync(join(directory, entry.name), {force: true});
  }
}

export function scoreImportance(event: Record<string, unknown>): number {
  let score = 1;
  const kind = String(event.kind || "");
  if (["discovery", "harvest", "trade", "dialogue", "failure"].includes(kind)) score += 3;
  if (kind === "discovery") score += 3;
  if (kind === "failure") score += 2;
  const delta = event.resource_delta;
  if (typeof delta === "object" && delta !== null && !Array.isArray(delta)) {
    score += Math.min(3, Object.values(delta).reduce((sum, value) => sum + Math.abs(Number(value) || 0), 0));
  }
  return score;
}

export class MemoryRepository {
  readonly #db: DatabaseSync;
  readonly path: string;
  readonly upgradedFromPreV2: boolean;

  constructor(path: string) {
    this.path = path;
    const existed = existsSync(path);
    this.#db = new DatabaseSync(path);
    const versionRow = this.#db.prepare("PRAGMA user_version").get() as Record<string, unknown>;
    const previousVersion = Number(versionRow.user_version ?? 0);
    this.upgradedFromPreV2 = existed && previousVersion !== DATABASE_VERSION;
    if (this.upgradedFromPreV2) this.#resetSchema();
    this.#initialize();
  }

  #resetSchema(): void {
    this.#db.exec("BEGIN IMMEDIATE");
    try {
      this.#db.exec(`
        DROP TABLE IF EXISTS memory_fts;
        DROP TABLE IF EXISTS idempotency;
        DROP TABLE IF EXISTS long_term_memories;
        DROP TABLE IF EXISTS events;
        DROP TABLE IF EXISTS sessions;
      `);
      this.#db.exec("COMMIT");
    } catch (error) {
      this.#db.exec("ROLLBACK");
      throw error;
    }
  }

  #initialize(): void {
    this.#db.exec(`
      PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS sessions(session_id TEXT PRIMARY KEY, epoch INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS events(
        event_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, agent_id TEXT NOT NULL,
        kind TEXT NOT NULL, game_minute INTEGER NOT NULL, importance REAL NOT NULL, payload_json TEXT NOT NULL,
        compacted INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS events_lookup ON events(session_id, agent_id, game_minute DESC);
      CREATE TABLE IF NOT EXISTS long_term_memories(
        memory_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, agent_id TEXT NOT NULL,
        summary TEXT NOT NULL, importance REAL NOT NULL, source_ids_json TEXT NOT NULL, valid INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE IF NOT EXISTS idempotency(idempotency_key TEXT PRIMARY KEY, response_json TEXT NOT NULL);
    `);
    const eventColumns = this.#db.prepare("PRAGMA table_info(events)").all() as Record<string, unknown>[];
    if (!eventColumns.some((column) => column.name === "compacted")) {
      this.#db.exec("ALTER TABLE events ADD COLUMN compacted INTEGER NOT NULL DEFAULT 0");
    }
    this.#db.exec(`
      DROP TABLE IF EXISTS memory_fts;
      CREATE VIRTUAL TABLE memory_fts USING fts5(memory_id UNINDEXED, session_id UNINDEXED, agent_id UNINDEXED, summary);
      INSERT INTO memory_fts(memory_id, session_id, agent_id, summary)
        SELECT memory_id, session_id, agent_id, summary FROM long_term_memories WHERE valid=1;
      PRAGMA user_version=2;
    `);
  }

  syncSession(sessionId: string, epoch: number): void {
    if (!sessionId || !Number.isSafeInteger(epoch) || epoch < 0) throw new Error("invalid_session");
    this.#db.prepare(`INSERT INTO sessions(session_id, epoch, updated_at) VALUES(?,?,?)
      ON CONFLICT(session_id) DO UPDATE SET epoch=excluded.epoch, updated_at=excluded.updated_at`).run(sessionId, epoch, Date.now());
  }

  resetSession(sessionId: string, epoch: number): void {
    if (!sessionId || !Number.isSafeInteger(epoch) || epoch < 0) throw new Error("invalid_session");
    this.#db.exec("BEGIN IMMEDIATE");
    try {
      this.#db.prepare("DELETE FROM events WHERE session_id=?").run(sessionId);
      this.#db.prepare("DELETE FROM long_term_memories WHERE session_id=?").run(sessionId);
      this.#db.prepare("DELETE FROM memory_fts WHERE session_id=?").run(sessionId);
      this.syncSession(sessionId, epoch);
      this.#db.exec("COMMIT");
    } catch (error) {
      this.#db.exec("ROLLBACK");
      throw error;
    }
  }

  appendEvent(sessionId: string, agentId: string, event: MemoryEvent): boolean {
    if (!sessionId || !agentId || !event.event_id || !event.kind || !Number.isSafeInteger(event.game_minute)) throw new Error("invalid_event");
    const result = this.#db.prepare(`INSERT OR IGNORE INTO events
      (event_id, session_id, agent_id, kind, game_minute, importance, payload_json) VALUES(?,?,?,?,?,?,?)`).run(
      event.event_id, sessionId, agentId, event.kind, event.game_minute,
      event.importance ?? scoreImportance({kind: event.kind, ...event.payload}), JSON.stringify(event.payload),
    );
    return Number(result.changes) === 1;
  }

  recent(sessionId: string, agentId: string, limit: number): MemoryEvent[] {
    const bounded = Math.max(1, Math.min(100, Math.trunc(limit)));
    const rows = this.#db.prepare(`SELECT event_id, kind, game_minute, importance, payload_json FROM events
      WHERE session_id=? AND agent_id=? ORDER BY game_minute DESC, rowid DESC LIMIT ?`).all(sessionId, agentId, bounded) as Record<string, unknown>[];
    return rows.map((row) => ({
      event_id: String(row.event_id), kind: String(row.kind), game_minute: Number(row.game_minute),
      importance: Number(row.importance), payload: JSON.parse(String(row.payload_json)),
    }));
  }

  recall(sessionId: string, agentId: string, query: string, limit = 8): Record<string, unknown>[] {
    if (!query.trim()) return this.longTermRecent(sessionId, agentId, limit);
    const bounded = Math.max(1, Math.min(20, limit));
    const cleaned = query.replace(/["']/g, " ").trim();
    let rows = this.#db.prepare(`SELECT memory_id, summary FROM memory_fts WHERE memory_fts MATCH ? AND session_id=? AND agent_id=? LIMIT ?`)
      .all(cleaned, sessionId, agentId, bounded) as Record<string, unknown>[];
    if (rows.length === 0) {
      rows = this.#db.prepare(`SELECT memory_id, summary FROM long_term_memories
        WHERE session_id=? AND agent_id=? AND valid=1 AND summary LIKE ? ORDER BY rowid DESC LIMIT ?`)
        .all(sessionId, agentId, `%${cleaned}%`, bounded) as Record<string, unknown>[];
    }
    return rows.map((row) => ({memory_id: String(row.memory_id), summary: String(row.summary)}));
  }

  longTermRecent(sessionId: string, agentId: string, limit = 8): Record<string, unknown>[] {
    const rows = this.#db.prepare(`SELECT memory_id, summary, importance, source_ids_json FROM long_term_memories
      WHERE session_id=? AND agent_id=? AND valid=1 ORDER BY rowid DESC LIMIT ?`)
      .all(sessionId, agentId, Math.max(1, Math.min(20, limit))) as Record<string, unknown>[];
    return rows.map((row) => ({
      memory_id: String(row.memory_id), summary: String(row.summary), importance: Number(row.importance),
      source_ids: JSON.parse(String(row.source_ids_json)),
    }));
  }

  shouldCompact(sessionId: string, agentId: string): boolean {
    const row = this.#db.prepare("SELECT COUNT(*) AS count FROM events WHERE session_id=? AND agent_id=? AND importance>=4 AND compacted=0")
      .get(sessionId, agentId) as Record<string, unknown>;
    return Number(row.count) >= 20;
  }

  compactionCandidates(sessionId: string, agentId: string, limit = 20): MemoryEvent[] {
    const rows = this.#db.prepare(`SELECT event_id, kind, game_minute, importance, payload_json FROM events
      WHERE session_id=? AND agent_id=? AND importance>=4 AND compacted=0
      ORDER BY game_minute ASC, rowid ASC LIMIT ?`)
      .all(sessionId, agentId, Math.max(1, Math.min(50, limit))) as Record<string, unknown>[];
    return rows.map((row) => ({
      event_id: String(row.event_id), kind: String(row.kind), game_minute: Number(row.game_minute),
      importance: Number(row.importance), payload: JSON.parse(String(row.payload_json)),
    }));
  }

  storeLongTermMemory(sessionId: string, agentId: string, memoryId: string, summary: string, importance: number, sourceIds: string[]): void {
    if (!sessionId || !agentId || !memoryId || !summary.trim() || sourceIds.length === 0) throw new Error("invalid_long_term_memory");
    const boundedSummary = summary.trim().slice(0, 1200);
    this.#db.exec("BEGIN IMMEDIATE");
    try {
      this.#db.prepare(`INSERT INTO long_term_memories(memory_id,session_id,agent_id,summary,importance,source_ids_json,valid)
        VALUES(?,?,?,?,?,?,1) ON CONFLICT(memory_id) DO UPDATE SET summary=excluded.summary, importance=excluded.importance,
        source_ids_json=excluded.source_ids_json, valid=1`).run(memoryId, sessionId, agentId, boundedSummary, importance, JSON.stringify(sourceIds));
      this.#db.prepare("DELETE FROM memory_fts WHERE memory_id=?").run(memoryId);
      this.#db.prepare("INSERT INTO memory_fts(memory_id,session_id,agent_id,summary) VALUES(?,?,?,?)")
        .run(memoryId, sessionId, agentId, boundedSummary);
      const placeholders = sourceIds.map(() => "?").join(",");
      this.#db.prepare(`UPDATE events SET compacted=1 WHERE session_id=? AND agent_id=? AND event_id IN (${placeholders})`)
        .run(sessionId, agentId, ...sourceIds);
      this.#db.exec("COMMIT");
    } catch (error) {
      this.#db.exec("ROLLBACK");
      throw error;
    }
  }

  storeIdempotent(key: string, response: unknown): boolean {
    const result = this.#db.prepare("INSERT OR IGNORE INTO idempotency(idempotency_key,response_json) VALUES(?,?)")
      .run(key, JSON.stringify(response));
    return Number(result.changes) === 1;
  }

  getIdempotent(key: string): unknown | undefined {
    const row = this.#db.prepare("SELECT response_json FROM idempotency WHERE idempotency_key=?").get(key) as Record<string, unknown> | undefined;
    return row ? JSON.parse(String(row.response_json)) : undefined;
  }

  exportCheckpoint(sessionId: string, directory: string, checkpointId: string): CheckpointRecord {
    if (!/^[A-Za-z0-9_-]{1,80}$/.test(checkpointId)) throw new Error("invalid_checkpoint_id");
    mkdirSync(directory, {recursive: true});
    const checkpointPath = join(directory, `${checkpointId}.sqlite`);
    const target = new MemoryRepository(checkpointPath);
    const session = this.#db.prepare("SELECT epoch FROM sessions WHERE session_id=?").get(sessionId) as Record<string, unknown> | undefined;
    target.resetSession(sessionId, Number(session?.epoch ?? 0));
    const rows = this.#db.prepare("SELECT event_id, agent_id, kind, game_minute, importance, payload_json FROM events WHERE session_id=?")
      .all(sessionId) as Record<string, unknown>[];
    for (const row of rows) target.appendEvent(sessionId, String(row.agent_id), {
      event_id: String(row.event_id), kind: String(row.kind), game_minute: Number(row.game_minute),
      importance: Number(row.importance), payload: JSON.parse(String(row.payload_json)),
    });
    const memories = this.#db.prepare(`SELECT memory_id, agent_id, summary, importance, source_ids_json FROM long_term_memories
      WHERE session_id=? AND valid=1`).all(sessionId) as Record<string, unknown>[];
    for (const row of memories) target.storeLongTermMemory(
      sessionId, String(row.agent_id), String(row.memory_id), String(row.summary), Number(row.importance),
      JSON.parse(String(row.source_ids_json)) as string[],
    );
    target.close();
    const sha256 = createHash("sha256").update(readFileSync(checkpointPath)).digest("hex");
    return {path: checkpointPath, sha256, session_id: sessionId};
  }

  importCheckpoint(checkpointPath: string, expectedSha256: string, sessionId: string): void {
    if (basename(checkpointPath) !== checkpointPath.split(/[\\/]/).pop()) throw new Error("invalid_checkpoint_path");
    const actual = createHash("sha256").update(readFileSync(checkpointPath)).digest("hex");
    if (actual !== expectedSha256) throw new Error("checkpoint_checksum_mismatch");
    const source = new DatabaseSync(checkpointPath, {readOnly: true});
    const session = source.prepare("SELECT epoch FROM sessions WHERE session_id=?").get(sessionId) as Record<string, unknown> | undefined;
    if (!session) { source.close(); throw new Error("checkpoint_session_mismatch"); }
    const rows = source.prepare("SELECT event_id, agent_id, kind, game_minute, importance, payload_json FROM events WHERE session_id=?")
      .all(sessionId) as Record<string, unknown>[];
    const memories = source.prepare(`SELECT memory_id, agent_id, summary, importance, source_ids_json FROM long_term_memories
      WHERE session_id=? AND valid=1`).all(sessionId) as Record<string, unknown>[];
    this.#db.exec("BEGIN IMMEDIATE");
    try {
      this.#db.prepare("DELETE FROM events WHERE session_id=?").run(sessionId);
      this.#db.prepare("DELETE FROM long_term_memories WHERE session_id=?").run(sessionId);
      this.#db.prepare("DELETE FROM memory_fts WHERE session_id=?").run(sessionId);
      this.syncSession(sessionId, Number(session.epoch));
      for (const row of rows) this.appendEvent(sessionId, String(row.agent_id), {
        event_id: String(row.event_id), kind: String(row.kind), game_minute: Number(row.game_minute),
        importance: Number(row.importance), payload: JSON.parse(String(row.payload_json)),
      });
      for (const row of memories) {
        const sourceIds = JSON.parse(String(row.source_ids_json)) as string[];
        this.#db.prepare(`INSERT INTO long_term_memories(memory_id,session_id,agent_id,summary,importance,source_ids_json,valid)
          VALUES(?,?,?,?,?,?,1)`).run(row.memory_id, sessionId, row.agent_id, row.summary, row.importance, row.source_ids_json);
        this.#db.prepare("INSERT INTO memory_fts(memory_id,session_id,agent_id,summary) VALUES(?,?,?,?)")
          .run(row.memory_id, sessionId, row.agent_id, row.summary);
        if (sourceIds.length > 0) {
          const placeholders = sourceIds.map(() => "?").join(",");
          this.#db.prepare(`UPDATE events SET compacted=1 WHERE session_id=? AND agent_id=? AND event_id IN (${placeholders})`)
            .run(sessionId, row.agent_id, ...sourceIds);
        }
      }
      this.#db.exec("COMMIT");
    } catch (error) {
      this.#db.exec("ROLLBACK");
      source.close();
      throw error;
    }
    source.close();
  }

  close(): void { this.#db.close(); }
}
