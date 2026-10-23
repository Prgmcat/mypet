CREATE TABLE IF NOT EXISTS reminder_rules (
    id TEXT PRIMARY KEY,
    pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    interval_days INTEGER NOT NULL DEFAULT 365,
    anchor_record_id TEXT REFERENCES health_records(id) ON DELETE SET NULL,
    next_due_at TEXT,
    advance_offsets TEXT NOT NULL DEFAULT '[14,7,3,1,0]',
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(pet_id, type)
);
CREATE INDEX IF NOT EXISTS idx_reminder_rules_pet ON reminder_rules(pet_id, enabled);

CREATE TABLE IF NOT EXISTS reminder_instances (
    id TEXT PRIMARY KEY,
    rule_id TEXT NOT NULL REFERENCES reminder_rules(id) ON DELETE CASCADE,
    pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
    occurrence_key TEXT NOT NULL UNIQUE,
    due_at TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    snoozed_until TEXT,
    completed_at TEXT,
    completed_by_type TEXT,
    completed_by_user_id TEXT,
    completed_by_grant_id TEXT,
    record_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_reminder_instances_pet ON reminder_instances(pet_id, status, due_at);
CREATE INDEX IF NOT EXISTS idx_reminder_instances_rule ON reminder_instances(rule_id, due_at);
