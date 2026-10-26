CREATE TABLE IF NOT EXISTS appointments (
    id TEXT PRIMARY KEY,
    pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'other',
    title TEXT NOT NULL,
    scheduled_at TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    advance_offsets TEXT NOT NULL DEFAULT '[3,1,0]',
    status TEXT NOT NULL DEFAULT 'pending',
    snoozed_until TEXT,
    completed_at TEXT,
    completed_by_type TEXT,
    completed_by_user_id TEXT,
    completed_by_grant_id TEXT,
    record_id TEXT REFERENCES health_records(id) ON DELETE SET NULL,
    created_by_type TEXT NOT NULL DEFAULT 'user',
    created_by_user_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_appointments_pet ON appointments(pet_id, status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_appointments_user ON appointments(status, scheduled_at);
