CREATE TABLE IF NOT EXISTS share_grants (
    id TEXT PRIMARY KEY,
    pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
    created_by_user_id TEXT NOT NULL REFERENCES users(id),
    token_hash TEXT NOT NULL UNIQUE,
    role TEXT NOT NULL DEFAULT 'viewer',
    expires_at TEXT NOT NULL,
    passcode_hash TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL,
    revoked_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_share_grants_pet ON share_grants(pet_id, status);
CREATE INDEX IF NOT EXISTS idx_share_grants_status_expiry ON share_grants(status, expires_at);
