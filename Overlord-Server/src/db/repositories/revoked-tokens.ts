import { db } from "../connection";
import "../schema";
import { hashToken } from "./token-hash";

export function persistRevokedToken(token: string, expiresAt: number): void {
  db.run(
    `INSERT OR IGNORE INTO revoked_tokens (token_hash, expires_at) VALUES (?, ?)`,
    hashToken(token),
    expiresAt,
  );
}

export function persistRevokedTokenHash(tokenHash: string, expiresAt: number): void {
  db.run(
    `INSERT OR IGNORE INTO revoked_tokens (token_hash, expires_at) VALUES (?, ?)`,
    tokenHash,
    expiresAt,
  );
}

export function isTokenRevoked(token: string): boolean {
  const row = db.query<{ token_hash: string }>(
    `SELECT token_hash FROM revoked_tokens WHERE token_hash=?`,
  ).get(hashToken(token));
  return !!row;
}

export function loadAllRevokedTokenHashes(): Set<string> {
  const now = Math.floor(Date.now() / 1000);
  const rows = db.query<{ token_hash: string }>(
    `SELECT token_hash FROM revoked_tokens WHERE expires_at > ?`,
  ).all(now);
  return new Set(rows.map((r) => r.token_hash));
}

export function pruneExpiredRevokedTokens(): number {
  const now = Math.floor(Date.now() / 1000);
  const result = db.run(`DELETE FROM revoked_tokens WHERE expires_at <= ?`, now);
  return result.changes;
}
