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

const DATABASE_VERSION = 3;

function eventContextPayload(id:unknown,raw:string):Record<string,unknown> {
  const payload=JSON.parse(raw) as Record<string,unknown>;
  if(raw.length<=180)return payload;
  // IDs/arguments often precede failure_code in serialized outcomes. Keep the
  // actual result visible rather than cutting off why an action failed.
  const result=Object.fromEntries(["tool_name","status","failure_code","failure_details","hud_message","resource_delta"]
    .filter(k=>Object.hasOwn(payload,k)).map(k=>[k,payload[k]]));
  return {...result,excerpt:raw.slice(0,180),source_event_id:id,details_available:true};
}

export function removeLegacyCheckpointDatabases(directory: string): void {
  mkdirSync(directory, {recursive: true});
  for (const entry of readdirSync(directory, {withFileTypes: true})) {
    if (!entry.isFile() || !/\.sqlite(?:-(?:wal|shm))?$/.test(entry.name)) continue;
    rmSync(join(directory, entry.name), {force: true});
  }
}

export function scoreImportance(event: Record<string, unknown>): number {
  let score = 1;
  const kind = String(event.kind || "").toLowerCase();
  const tool = String(event.tool_name || "");
  if (/goal|contract|discovery|discovered/.test(kind)) score += 5;
  if (/failed|rejected/.test(kind)) score += 5;
  if (kind === "actioncompleted" && /trade|cooperation|investigation|intelligence|commission|delivery/.test(tool)) score += 4;
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
  closed = false;
  readonly upgradedFromPreV2: boolean;

  constructor(path: string) {
    this.path = path;
    const existed = existsSync(path);
    this.#db = new DatabaseSync(path);
    const versionRow = this.#db.prepare("PRAGMA user_version").get() as Record<string, unknown>;
    const previousVersion = Number(versionRow.user_version ?? 0);
    this.upgradedFromPreV2 = existed && previousVersion < 2;
    // Migrate in place: old experiences are never discarded on a version change.
    if (previousVersion > DATABASE_VERSION) throw new Error("memory_schema_newer_than_service");
    if(existed && previousVersion < DATABASE_VERSION && !existsSync(path+".pre-v3.sqlite")) {
      this.#db.prepare("VACUUM INTO ?").run(path+".pre-v3.sqlite");
    }
    this.#initialize();
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
    const table = this.#db.prepare("SELECT sql FROM sqlite_master WHERE name='events'").get() as {sql: string};
    if (!table.sql.includes("PRIMARY KEY(event_id, session_id, agent_id)")) {
      const hadCompacted = (this.#db.prepare("PRAGMA table_info(events)").all() as {name:string}[]).some(c=>c.name==="compacted");
      this.#db.exec(`BEGIN IMMEDIATE;
        ALTER TABLE events RENAME TO events_legacy;
        CREATE TABLE events(event_id TEXT NOT NULL, session_id TEXT NOT NULL, agent_id TEXT NOT NULL,
          kind TEXT NOT NULL, game_minute INTEGER NOT NULL, importance REAL NOT NULL,
          payload_json TEXT NOT NULL, compacted INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY(event_id, session_id, agent_id));
        INSERT INTO events(event_id,session_id,agent_id,kind,game_minute,importance,payload_json,compacted)
          SELECT event_id,session_id,agent_id,kind,game_minute,importance,payload_json,${hadCompacted?"compacted":"0"} FROM events_legacy ORDER BY rowid;
        DROP TABLE events_legacy;
        CREATE INDEX events_lookup ON events(session_id,agent_id,game_minute DESC);
        COMMIT;`);
    }
    const eventColumns = this.#db.prepare("PRAGMA table_info(events)").all() as Record<string, unknown>[];
    if (!eventColumns.some((column) => column.name === "compacted")) {
      this.#db.exec("ALTER TABLE events ADD COLUMN compacted INTEGER NOT NULL DEFAULT 0");
    }
    this.#db.exec(`
      DROP TABLE IF EXISTS memory_fts;
      CREATE VIRTUAL TABLE memory_fts USING fts5(memory_id UNINDEXED, session_id UNINDEXED, agent_id UNINDEXED, summary);
      INSERT INTO memory_fts(memory_id, session_id, agent_id, summary)
        SELECT memory_id, session_id, agent_id, summary FROM long_term_memories WHERE valid=1;
      CREATE TABLE IF NOT EXISTS resource_snapshots(
        session_id TEXT NOT NULL, agent_id TEXT NOT NULL, epoch INTEGER NOT NULL,
        revision INTEGER NOT NULL, snapshot_json TEXT NOT NULL, PRIMARY KEY(session_id,agent_id));
      CREATE TABLE IF NOT EXISTS history_heads(
        session_id TEXT NOT NULL,agent_id TEXT NOT NULL,through_sequence INTEGER NOT NULL,summary TEXT NOT NULL,
        PRIMARY KEY(session_id,agent_id));
      CREATE TABLE IF NOT EXISTS history_segments(
        session_id TEXT NOT NULL, agent_id TEXT NOT NULL, segment_id TEXT NOT NULL,
        summary_json TEXT NOT NULL, PRIMARY KEY(session_id,agent_id,segment_id));
      PRAGMA user_version=3;
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
      this.#db.prepare("DELETE FROM resource_snapshots WHERE session_id=?").run(sessionId);
      this.#db.prepare("DELETE FROM history_segments WHERE session_id=?").run(sessionId);
      this.#db.prepare("DELETE FROM history_heads WHERE session_id=?").run(sessionId);
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
    return Number(row.count) >= 1;
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
    const rows = this.#db.prepare("SELECT event_id, agent_id, kind, game_minute, importance, payload_json FROM events WHERE session_id=? ORDER BY rowid")
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
    for (const row of this.#db.prepare("SELECT * FROM resource_snapshots WHERE session_id=?").all(sessionId) as Record<string, unknown>[]) {
      target.syncResources(sessionId, String(row.agent_id), Number(row.epoch), Number(row.revision), JSON.parse(String(row.snapshot_json)));
    }
    for(const row of this.#db.prepare("SELECT * FROM history_heads WHERE session_id=?").all(sessionId) as Record<string,unknown>[]){
      const sourceIds=this.#db.prepare("SELECT event_id FROM events WHERE session_id=? AND agent_id=? AND rowid<=? ORDER BY rowid").all(sessionId,row.agent_id,row.through_sequence) as {event_id:string}[];
      if(sourceIds.length)target.storeHistory(sessionId,String(row.agent_id),sourceIds.map(r=>r.event_id),String(row.summary));
    }
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
    const rows = source.prepare("SELECT event_id, agent_id, kind, game_minute, importance, payload_json FROM events WHERE session_id=? ORDER BY rowid")
      .all(sessionId) as Record<string, unknown>[];
    const memories = source.prepare(`SELECT memory_id, agent_id, summary, importance, source_ids_json FROM long_term_memories
      WHERE session_id=? AND valid=1`).all(sessionId) as Record<string, unknown>[];
    this.#db.exec("BEGIN IMMEDIATE");
    try {
      this.#db.prepare("DELETE FROM resource_snapshots WHERE session_id=?").run(sessionId);
      this.#db.prepare("DELETE FROM history_segments WHERE session_id=?").run(sessionId);
      this.#db.prepare("DELETE FROM history_heads WHERE session_id=?").run(sessionId);
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
      const hasResources = source.prepare("SELECT name FROM sqlite_master WHERE name='resource_snapshots'").get();
      if (hasResources) for (const row of source.prepare("SELECT * FROM resource_snapshots WHERE session_id=?").all(sessionId) as Record<string, unknown>[]) {
        this.syncResources(sessionId, String(row.agent_id), Number(row.epoch), Number(row.revision), JSON.parse(String(row.snapshot_json)));
      }
      if(source.prepare("SELECT name FROM sqlite_master WHERE name='history_heads'").get()){
        for(const row of source.prepare("SELECT * FROM history_heads WHERE session_id=?").all(sessionId) as Record<string,unknown>[]){
          const ids=(source.prepare("SELECT event_id FROM events WHERE session_id=? AND agent_id=? AND rowid<=? ORDER BY rowid").all(sessionId,row.agent_id,row.through_sequence) as {event_id:string}[]).map(r=>r.event_id);
          if(ids.length)this.storeHistory(sessionId,String(row.agent_id),ids,String(row.summary));
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

  syncResources(sessionId: string, agentId: string, epoch: number, revision: number, snapshot: Record<string, unknown>): void {
    if(!sessionId || !agentId || !Number.isSafeInteger(epoch) || epoch<0 || !Number.isSafeInteger(revision) || revision<0 ||
      !Number.isSafeInteger(snapshot.gold) || Number(snapshot.gold)<0)throw new Error("invalid_resource_snapshot");
    const previous = this.#db.prepare("SELECT epoch,revision FROM resource_snapshots WHERE session_id=? AND agent_id=?")
      .get(sessionId, agentId) as {epoch: number; revision: number} | undefined;
    if (previous && (epoch < previous.epoch || (epoch === previous.epoch && revision < previous.revision))) throw new Error("stale_resource_snapshot");
    this.#db.prepare(`INSERT INTO resource_snapshots VALUES(?,?,?,?,?) ON CONFLICT(session_id,agent_id)
      DO UPDATE SET epoch=excluded.epoch,revision=excluded.revision,snapshot_json=excluded.snapshot_json`)
      .run(sessionId, agentId, epoch, revision, JSON.stringify(snapshot));
  }

  experience(sessionId: string, agentId: string): Record<string, unknown> {
    const rows = (this.#db.prepare(`SELECT rowid AS sequence,event_id,kind,game_minute,payload_json FROM events
      WHERE session_id=? AND agent_id=? ORDER BY rowid DESC LIMIT 15`).all(sessionId, agentId) as Record<string, unknown>[]).reverse();
    const boundary=Number(rows[0]?.sequence ?? 0);
    const older=this.#db.prepare(`SELECT rowid AS sequence,event_id,kind,game_minute,payload_json FROM events
      WHERE session_id=? AND agent_id=? AND rowid<? ORDER BY rowid DESC LIMIT 4`).all(sessionId,agentId,boundary) as Record<string,unknown>[];
    older.reverse();
    const head=this.#db.prepare("SELECT through_sequence,summary FROM history_heads WHERE session_id=? AND agent_id=?").get(sessionId,agentId) as {through_sequence:number;summary:string}|undefined;
    const counts: Record<string, number> = {};
    for(const row of this.#db.prepare("SELECT kind,COUNT(*) AS n FROM events WHERE session_id=? AND agent_id=? AND rowid<? GROUP BY kind").all(sessionId,agentId,boundary) as {kind:string;n:number}[])counts[row.kind]=Number(row.n);
    const covered=Object.values(counts).reduce((n,v)=>n+v,0);
    return {older_summary: {narrative:head?.summary ?? "", narrative_through_sequence:head?.through_sequence ?? 0, covered_count: covered, covered_through_sequence: older.at(-1)?.sequence ?? 0,
      type_counts: counts, segment_count: Math.ceil(covered/32),
      recent_facts: older.map(row => ({event_id: row.event_id, game_minute: row.game_minute,
        kind: row.kind, text: String(row.payload_json).slice(0, 200)})),
      detail_policy: "Earlier facts are historical, not current balances or contract states. Use inspect_history_segment or inspect_event for sources."},
      recent_events: rows.map(row => ({sequence: row.sequence, event_id: row.event_id,
        kind: row.kind, game_minute: row.game_minute, payload:eventContextPayload(row.event_id,String(row.payload_json))}))};
  }

  inspectEvent(sessionId: string, agentId: string, id: string): Record<string, unknown> {
    const row = this.#db.prepare("SELECT event_id,kind,game_minute,payload_json FROM events WHERE session_id=? AND agent_id=? AND event_id=?")
      .get(sessionId, agentId, id) as Record<string, unknown> | undefined;
    return row ? {found: true, event_id: row.event_id, kind: row.kind, game_minute: row.game_minute, payload: JSON.parse(String(row.payload_json))} : {found: false};
  }

  historySegment(sessionId: string, agentId: string, offset = 0): Record<string, unknown> {
    const rows = this.#db.prepare(`SELECT event_id,kind,game_minute,payload_json FROM events
      WHERE session_id=? AND agent_id=? ORDER BY rowid LIMIT 5 OFFSET ?`).all(sessionId, agentId, offset) as Record<string, unknown>[];
    return {items: rows.map(r => ({event_id: r.event_id, kind: r.kind, game_minute: r.game_minute,
      payload: JSON.parse(String(r.payload_json))})), next_cursor: rows.length === 5 ? offset + 5 : null};
  }

  relevant(sessionId: string, agentId: string, query: string, limit = 6): Record<string, unknown>[] {
    const terms = new Set((query.toLowerCase().match(/[a-z0-9_]+|[\u3400-\u9fff]{2}/gu) ?? []));
    // Overlapping Chinese bigrams work without assuming English FTS tokenization.
    for (const span of query.match(/[\u3400-\u9fff]+/gu) ?? []) for (let i=0;i<span.length-1;i++) terms.add(span.slice(i,i+2));
    if (!terms.size) return [];
    const rows = this.#db.prepare(`SELECT memory_id,summary,importance,source_ids_json FROM long_term_memories
      WHERE session_id=? AND agent_id=? AND valid=1 ORDER BY rowid DESC`).all(sessionId, agentId) as Record<string, unknown>[];
    const raw = this.#db.prepare(`SELECT event_id,kind,game_minute,importance,payload_json FROM events
      WHERE session_id=? AND agent_id=? AND importance>=4 ORDER BY rowid DESC LIMIT 200`).all(sessionId, agentId) as Record<string, unknown>[];
    const candidates = [...rows.map(r => ({memory_id: r.memory_id, summary: String(r.summary), importance: Number(r.importance),
      source_event_ids: JSON.parse(String(r.source_ids_json)) as string[]})), ...raw.map(r => ({memory_id: `fact:${r.event_id}`,
      summary: `${r.kind} @${r.game_minute}: ${r.payload_json}`, importance: Number(r.importance), source_event_ids: [String(r.event_id)]}))];
    const seen = new Set<string>();
    return candidates.map((r,index) => ({...r, score: [...terms].reduce((n,t) => n + (r.summary.toLowerCase().includes(t) ? 1 : 0),0), index}))
      .filter(r => r.score > 0).sort((a,b) => b.score-a.score || b.importance-a.importance || a.index-b.index)
      .filter(r => { if (r.source_event_ids.some(id => seen.has(id))) return false; r.source_event_ids.forEach(id => seen.add(id)); return true; })
      .slice(0, Math.min(6, Math.max(1,limit))).map(({score,index,...r}) => ({...r,summary:r.summary.slice(0,500)}));
  }

  historyCandidates(sessionId:string,agentId:string):{previous:string;events:MemoryEvent[]} {
    const head=this.#db.prepare("SELECT through_sequence,summary FROM history_heads WHERE session_id=? AND agent_id=?").get(sessionId,agentId) as {through_sequence:number;summary:string}|undefined;
    const boundary=this.#db.prepare("SELECT rowid AS n FROM events WHERE session_id=? AND agent_id=? ORDER BY rowid DESC LIMIT 1 OFFSET 15").get(sessionId,agentId) as {n:number}|undefined;
    if(!boundary)return {previous:head?.summary??"",events:[]};
    const rows=this.#db.prepare(`SELECT event_id,kind,game_minute,importance,payload_json FROM events WHERE session_id=? AND agent_id=? AND rowid>? AND rowid<=? ORDER BY rowid LIMIT 32`)
      .all(sessionId,agentId,head?.through_sequence??0,boundary.n) as Record<string,unknown>[];
    return {previous:head?.summary??"",events:rows.map(r=>({event_id:String(r.event_id),kind:String(r.kind),game_minute:Number(r.game_minute),importance:Number(r.importance),payload:JSON.parse(String(r.payload_json))}))};
  }

  storeHistory(sessionId:string,agentId:string,eventIds:string[],summary:string):void {
    if(!summary.trim() || !eventIds.length)return;
    const row=this.#db.prepare(`SELECT MAX(rowid) AS n FROM events WHERE session_id=? AND agent_id=? AND event_id IN (${eventIds.map(()=>"?").join(",")})`).get(sessionId,agentId,...eventIds) as {n:number};
    this.#db.prepare(`INSERT INTO history_heads VALUES(?,?,?,?) ON CONFLICT(session_id,agent_id) DO UPDATE SET through_sequence=excluded.through_sequence,summary=excluded.summary WHERE excluded.through_sequence>=history_heads.through_sequence`)
      .run(sessionId,agentId,row.n,summary.slice(0,1200));
  }

  close(): void { this.closed = true; this.#db.close(); }
}
