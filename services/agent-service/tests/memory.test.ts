import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {DatabaseSync} from "node:sqlite";
import test from "node:test";
import * as MemoryModule from "../src/memory.ts";

const {MemoryRepository, scoreImportance} = MemoryModule;

test("clears every pre-v2 Agent table once and removes only checkpoint databases", () => {
  const directory = mkdtempSync(join(tmpdir(), "villa-agent-v2-migration-"));
  const databasePath = join(directory, "memory.sqlite");
  const old = new MemoryRepository(databasePath);
  old.syncSession("old-save", 1);
  old.appendEvent("old-save", "farmer_ahe", {event_id: "old-event", kind: "decision", game_minute: 1, payload: {}});
  old.storeLongTermMemory("old-save", "farmer_ahe", "old-memory", "旧记忆", 8, ["old-event"]);
  old.storeIdempotent("old-key", {protocol_version: 1});
  old.close();
  const raw = new DatabaseSync(databasePath);
  raw.exec("PRAGMA user_version=1");
  raw.close();

  const upgraded = new MemoryRepository(databasePath);
  assert.equal(upgraded.upgradedFromPreV2, true);
  assert.deepEqual(upgraded.recent("old-save", "farmer_ahe", 10), []);
  assert.deepEqual(upgraded.longTermRecent("old-save", "farmer_ahe", 10), []);
  assert.equal(upgraded.getIdempotent("old-key"), undefined);
  upgraded.syncSession("new-save", 2);
  upgraded.appendEvent("new-save", "farmer_ahe", {event_id: "new-event", kind: "decision", game_minute: 2, payload: {}});
  upgraded.close();

  const checkpointRoot = join(directory, "checkpoints");
  mkdirSync(checkpointRoot);
  for (const name of ["old.sqlite", "old.sqlite-wal", "old.sqlite-shm", "keep.txt"]) writeFileSync(join(checkpointRoot, name), name);
  const removeLegacyCheckpointDatabases = (MemoryModule as Record<string, unknown>).removeLegacyCheckpointDatabases;
  assert.equal(typeof removeLegacyCheckpointDatabases, "function");
  if (typeof removeLegacyCheckpointDatabases === "function") removeLegacyCheckpointDatabases(checkpointRoot);
  assert.equal(existsSync(join(checkpointRoot, "old.sqlite")), false);
  assert.equal(existsSync(join(checkpointRoot, "old.sqlite-wal")), false);
  assert.equal(existsSync(join(checkpointRoot, "old.sqlite-shm")), false);
  assert.equal(existsSync(join(checkpointRoot, "keep.txt")), true);

  const reopened = new MemoryRepository(databasePath);
  assert.equal(reopened.upgradedFromPreV2, false);
  assert.equal(reopened.recent("new-save", "farmer_ahe", 10).length, 1);
  reopened.close();
  rmSync(directory, {recursive: true, force: true});
});

test("isolates ordered memories and makes outcomes idempotent", () => {
  const directory = mkdtempSync(join(tmpdir(), "villa-agent-memory-"));
  const repository = new MemoryRepository(join(directory, "memory.sqlite"));
  repository.syncSession("save-a", 1);
  repository.appendEvent("save-a", "lao_li", {event_id: "e2", kind: "market", game_minute: 20, payload: {item: "salt"}});
  repository.appendEvent("save-a", "lao_li", {event_id: "e1", kind: "dialogue", game_minute: 10, payload: {text: "你好"}});
  repository.appendEvent("save-a", "xuezhe_lin", {event_id: "e3", kind: "discovery", game_minute: 30, payload: {region: "creek"}});
  assert.deepEqual(repository.recent("save-a", "lao_li", 10).map((event) => event.event_id), ["e2", "e1"]);
  assert.equal(repository.recent("save-a", "xuezhe_lin", 10).length, 1);
  assert.equal(repository.storeIdempotent("outcome:k1", {ok: true}), true);
  assert.equal(repository.storeIdempotent("outcome:k1", {ok: false}), false);
  assert.deepEqual(repository.getIdempotent("outcome:k1"), {ok: true});
  repository.close();
  rmSync(directory, {recursive: true, force: true});
});

test("scores important events and round trips one session checkpoint", () => {
  assert.ok(scoreImportance({kind: "discovery", resource_delta: {crystal: 1}}) > scoreImportance({kind: "market_tick"}));
  const directory = mkdtempSync(join(tmpdir(), "villa-agent-checkpoint-"));
  const source = new MemoryRepository(join(directory, "source.sqlite"));
  source.syncSession("save-a", 3);
  source.appendEvent("save-a", "farmer_ahe", {event_id: "important", kind: "harvest", game_minute: 80, payload: {quantity: 4}});
  source.appendEvent("save-b", "farmer_ahe", {event_id: "other", kind: "harvest", game_minute: 80, payload: {quantity: 9}});
  const checkpoint = source.exportCheckpoint("save-a", directory, "checkpoint-a");
  const restored = new MemoryRepository(join(directory, "restored.sqlite"));
  restored.importCheckpoint(checkpoint.path, checkpoint.sha256, "save-a");
  assert.equal(restored.recent("save-a", "farmer_ahe", 10).length, 1);
  assert.equal(restored.recent("save-b", "farmer_ahe", 10).length, 0);
  source.close(); restored.close();
  rmSync(directory, {recursive: true, force: true});
});

test("compacts twenty important events into searchable long-term memory", () => {
  const directory = mkdtempSync(join(tmpdir(), "villa-agent-compaction-"));
  const repository = new MemoryRepository(join(directory, "memory.sqlite"));
  repository.syncSession("save-a", 1);
  for (let index = 0; index < 20; index += 1) {
    repository.appendEvent("save-a", "xuezhe_lin", {
      event_id: `discovery-${index}`, kind: "discovery", game_minute: index,
      payload: {region: "north_creek", specimen: `sample-${index}`}, importance: 7,
    });
  }
  assert.equal(repository.shouldCompact("save-a", "xuezhe_lin"), true);
  const candidates = repository.compactionCandidates("save-a", "xuezhe_lin", 20);
  assert.equal(candidates.length, 20);
  repository.storeLongTermMemory(
    "save-a", "xuezhe_lin", "memory-north-creek",
    "学者林在北溪发现了一组新样本。", 8, candidates.map((event) => event.event_id),
  );
  assert.equal(repository.shouldCompact("save-a", "xuezhe_lin"), false);
  assert.equal(repository.recall("save-a", "xuezhe_lin", "北溪", 5).length, 1);
  assert.equal(repository.recall("save-a", "farmer_ahe", "北溪", 5).length, 0);
  const checkpoint = repository.exportCheckpoint("save-a", directory, "with-memory");
  const restored = new MemoryRepository(join(directory, "restored.sqlite"));
  restored.importCheckpoint(checkpoint.path, checkpoint.sha256, "save-a");
  assert.equal(restored.recall("save-a", "xuezhe_lin", "北溪", 5).length, 1);
  repository.close(); restored.close();
  rmSync(directory, {recursive: true, force: true});
});
