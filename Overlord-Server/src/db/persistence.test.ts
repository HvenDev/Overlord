import { describe, expect, test } from "bun:test";
import Database from "bun:sqlite";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

describe("SQLite persistence", () => {
  test("keeps application records and binary data after the database is reopened", () => {
    const dataDir = mkdtempSync(path.join(tmpdir(), "overlord-sqlite-persistence-"));
    const databasePath = path.join(dataDir, "overlord.db");

    try {
      const firstConnection = new Database(databasePath);
      firstConnection.exec(`
        CREATE TABLE persisted_state (
          id TEXT PRIMARY KEY,
          settings_json TEXT NOT NULL,
          bytes BLOB NOT NULL
        )
      `);
      firstConnection
        .prepare("INSERT INTO persisted_state (id, settings_json, bytes) VALUES (?, ?, ?)")
        .run("state-1", JSON.stringify({ saved: true }), Buffer.from([0, 1, 2, 255]));
      firstConnection.close();

      const reopenedConnection = new Database(databasePath, { readonly: true });
      const saved = reopenedConnection
        .query<{ id: string; settings_json: string; bytes: Uint8Array }>(
          "SELECT id, settings_json, bytes FROM persisted_state WHERE id = ?",
        )
        .get("state-1");

      expect(saved?.id).toBe("state-1");
      expect(JSON.parse(saved?.settings_json || "{}")).toEqual({ saved: true });
      expect(Array.from(saved?.bytes || [])).toEqual([0, 1, 2, 255]);
      reopenedConnection.close();
    } finally {
      rmSync(dataDir, { recursive: true, force: true });
    }
  });
});
