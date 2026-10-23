CREATE TABLE IF NOT EXISTS health_records (
    id TEXT PRIMARY KEY,
    pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    title TEXT NOT NULL,
    payload TEXT NOT NULL DEFAULT '{}',
    hospital TEXT NOT NULL DEFAULT '',
    doctor TEXT NOT NULL DEFAULT '',
    next_due_at TEXT,
    source TEXT NOT NULL DEFAULT 'manual',
    created_by_type TEXT NOT NULL DEFAULT 'user',
    created_by_user_id TEXT,
    created_by_grant_id TEXT,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_records_pet_time ON health_records(pet_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_records_pet_type_time ON health_records(pet_id, type, occurred_at DESC);

CREATE TABLE IF NOT EXISTS weight_records (
    id TEXT PRIMARY KEY,
    pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
    measured_at TEXT NOT NULL,
    weight_kg REAL NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    created_by_type TEXT NOT NULL DEFAULT 'user',
    created_by_user_id TEXT,
    created_by_grant_id TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_weights_pet_time ON weight_records(pet_id, measured_at DESC);

CREATE TABLE IF NOT EXISTS attachments (
    id TEXT PRIMARY KEY,
    pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
    record_id TEXT REFERENCES health_records(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    original_name TEXT NOT NULL DEFAULT '',
    mime TEXT NOT NULL,
    size INTEGER NOT NULL,
    sha256 TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_attachments_record ON attachments(record_id);
CREATE INDEX IF NOT EXISTS idx_attachments_pet ON attachments(pet_id);
