package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/Prgmcat/mypet/server/internal/auth"
	"github.com/Prgmcat/mypet/server/internal/db"
)

const dateLayout = "2006-01-02"

// Reminder types that can generate a health record when completed.
var recordReminderTypes = map[string]bool{
	"vaccine":    true,
	"deworming":  true,
	"checkup":    true,
	"grooming":   true,
	"medication": false,
	"birthday":   false,
}

var defaultRuleIntervals = map[string]int{
	"vaccine":   365,
	"deworming": 90,
	"checkup":   365,
	"birthday":  365,
	"grooming":  30,
}

var defaultAdvanceOffsets = map[string][]int{
	"vaccine":   {14, 7, 1, 0},
	"deworming": {3, 0},
	"checkup":   {7, 1},
	"birthday":  {1},
	"grooming":  {1},
}

func defaultOffsets(typ string) []int {
	if v, ok := defaultAdvanceOffsets[typ]; ok {
		return v
	}
	return []int{1, 0}
}

func defaultInterval(typ string) int {
	if v, ok := defaultRuleIntervals[typ]; ok {
		return v
	}
	return 365
}

func encodeOffsets(v []int) string {
	if len(v) == 0 {
		v = []int{0}
	}
	raw, _ := json.Marshal(v)
	return string(raw)
}

func decodeOffsets(raw string) []int {
	var v []int
	if err := json.Unmarshal([]byte(raw), &v); err != nil || len(v) == 0 {
		return []int{0}
	}
	return v
}

func daysBetween(from, to string) int {
	a, errA := time.Parse(dateLayout, from)
	b, errB := time.Parse(dateLayout, to)
	if errA != nil || errB != nil {
		return 0
	}
	return int(b.Sub(a).Hours() / 24)
}

func addDays(date string, days int) string {
	d, err := time.Parse(dateLayout, date)
	if err != nil {
		return date
	}
	return d.AddDate(0, 0, days).Format(dateLayout)
}

func today() string { return time.Now().UTC().Format(dateLayout) }

// SyncReminderForRecord keeps the rule that belongs to a health record in sync
// with the record's nextDueAt. It is a no-op for record types without reminders.
func (s *Store) SyncReminderForRecord(ctx context.Context, record HealthRecord) error {
	if _, ok := defaultRuleIntervals[record.Type]; !ok {
		return nil
	}
	if strings.TrimSpace(record.NextDueAt) == "" {
		return s.recalculateRule(ctx, record.PetID, record.Type)
	}
	now := db.Now()
	interval := daysBetween(record.OccurredAt, record.NextDueAt)
	if interval <= 0 {
		interval = defaultInterval(record.Type)
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO reminder_rules(
		id, pet_id, type, interval_days, anchor_record_id, next_due_at, advance_offsets, enabled, created_at, updated_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
		ON CONFLICT(pet_id, type) DO UPDATE SET
			interval_days = excluded.interval_days,
			anchor_record_id = excluded.anchor_record_id,
			next_due_at = excluded.next_due_at,
			enabled = 1,
			updated_at = excluded.updated_at`,
		auth.NewID(), record.PetID, record.Type, interval, record.ID, record.NextDueAt,
		encodeOffsets(defaultOffsets(record.Type)), now, now)
	if err != nil {
		return err
	}
	// Pending instances describe the previous due date; drop them so the list
	// only ever shows the current occurrence.
	_, err = s.db.ExecContext(ctx, `DELETE FROM reminder_instances
		WHERE pet_id = ? AND rule_id IN (SELECT id FROM reminder_rules WHERE pet_id = ? AND type = ?)
		AND status IN ('pending', 'snoozed') AND due_at <> ?`,
		record.PetID, record.PetID, record.Type, record.NextDueAt)
	if err != nil {
		return err
	}
	return s.ensureInstance(ctx, record.PetID, record.Type, record.NextDueAt)
}

// RecalculateReminder rebuilds a rule from the latest remaining record of that type.
func (s *Store) RecalculateReminder(ctx context.Context, petID, typ string) error {
	if _, ok := defaultRuleIntervals[typ]; !ok {
		return nil
	}
	return s.recalculateRule(ctx, petID, typ)
}

// recalculateRule rebuilds a rule from the latest remaining record of that type.
func (s *Store) recalculateRule(ctx context.Context, petID, typ string) error {
	var recordID, occurredAt, nextDue string
	err := s.db.QueryRowContext(ctx, `SELECT id, occurred_at, next_due_at FROM health_records
		WHERE pet_id = ? AND type = ? AND deleted_at IS NULL AND next_due_at IS NOT NULL AND next_due_at <> ''
		ORDER BY occurred_at DESC, created_at DESC LIMIT 1`, petID, typ).
		Scan(&recordID, &occurredAt, &nextDue)
	if errors.Is(err, sql.ErrNoRows) {
		_, err = s.db.ExecContext(ctx, `UPDATE reminder_rules SET enabled = 0, next_due_at = NULL, anchor_record_id = NULL, updated_at = ?
			WHERE pet_id = ? AND type = ?`, db.Now(), petID, typ)
		if err != nil {
			return err
		}
		_, err = s.db.ExecContext(ctx, `DELETE FROM reminder_instances WHERE pet_id = ? AND status IN ('pending','snoozed')
			AND rule_id IN (SELECT id FROM reminder_rules WHERE pet_id = ? AND type = ?)`, petID, petID, typ)
		return err
	}
	if err != nil {
		return err
	}
	interval := daysBetween(occurredAt, nextDue)
	if interval <= 0 {
		interval = defaultInterval(typ)
	}
	_, err = s.db.ExecContext(ctx, `UPDATE reminder_rules SET interval_days = ?, anchor_record_id = ?, next_due_at = ?,
		enabled = 1, updated_at = ? WHERE pet_id = ? AND type = ?`,
		interval, recordID, nextDue, db.Now(), petID, typ)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `DELETE FROM reminder_instances WHERE pet_id = ? AND status IN ('pending','snoozed')
		AND rule_id IN (SELECT id FROM reminder_rules WHERE pet_id = ? AND type = ?) AND due_at <> ?`,
		petID, petID, typ, nextDue)
	if err != nil {
		return err
	}
	return s.ensureInstance(ctx, petID, typ, nextDue)
}

// SyncBirthdayRule keeps a yearly birthday reminder aligned with the pet profile.
func (s *Store) SyncBirthdayRule(ctx context.Context, pet Pet) error {
	if strings.TrimSpace(pet.Birthday) == "" {
		return nil
	}
	birthday, err := time.Parse(dateLayout, pet.Birthday)
	if err != nil {
		return nil
	}
	now := time.Now().UTC()
	next := time.Date(now.Year(), birthday.Month(), birthday.Day(), 0, 0, 0, 0, time.UTC)
	if next.Before(time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)) {
		next = next.AddDate(1, 0, 0)
	}
	nextDate := next.Format(dateLayout)
	nowStr := db.Now()
	_, err = s.db.ExecContext(ctx, `INSERT INTO reminder_rules(
		id, pet_id, type, interval_days, anchor_record_id, next_due_at, advance_offsets, enabled, created_at, updated_at)
		VALUES(?, ?, 'birthday', 365, NULL, ?, ?, 1, ?, ?)
		ON CONFLICT(pet_id, type) DO UPDATE SET
			next_due_at = excluded.next_due_at,
			enabled = 1,
			updated_at = excluded.updated_at
		WHERE reminder_rules.type = 'birthday'`, auth.NewID(), pet.ID, nextDate,
		encodeOffsets(defaultOffsets("birthday")), nowStr, nowStr)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `DELETE FROM reminder_instances WHERE pet_id = ? AND status IN ('pending','snoozed')
		AND rule_id IN (SELECT id FROM reminder_rules WHERE pet_id = ? AND type = 'birthday') AND due_at <> ?`,
		pet.ID, pet.ID, nextDate)
	if err != nil {
		return err
	}
	return s.ensureInstance(ctx, pet.ID, "birthday", nextDate)
}

func (s *Store) ensureInstance(ctx context.Context, petID, typ, dueAt string) error {
	var ruleID string
	err := s.db.QueryRowContext(ctx, `SELECT id FROM reminder_rules WHERE pet_id = ? AND type = ? AND enabled = 1`,
		petID, typ).Scan(&ruleID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	now := db.Now()
	occurrence := ruleID + ":" + dueAt
	_, err = s.db.ExecContext(ctx, `INSERT INTO reminder_instances(
		id, rule_id, pet_id, occurrence_key, due_at, status, created_at, updated_at)
		VALUES(?, ?, ?, ?, ?, 'pending', ?, ?)
		ON CONFLICT(occurrence_key) DO NOTHING`,
		auth.NewID(), ruleID, petID, occurrence, dueAt, now, now)
	return err
}

// EnsureReminders materialises instances for every enabled rule and releases
// snoozed instances whose snooze window has elapsed.
func (s *Store) EnsureReminders(ctx context.Context) error {
	rows, err := s.db.QueryContext(ctx, `SELECT pet_id, type, next_due_at FROM reminder_rules
		WHERE enabled = 1 AND next_due_at IS NOT NULL AND next_due_at <> ''`)
	if err != nil {
		return err
	}
	type ruleKey struct{ petID, typ, due string }
	var rules []ruleKey
	for rows.Next() {
		var k ruleKey
		if err := rows.Scan(&k.petID, &k.typ, &k.due); err != nil {
			rows.Close()
			return err
		}
		rules = append(rules, k)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	for _, k := range rules {
		if err := s.ensureInstance(ctx, k.petID, k.typ, k.due); err != nil {
			return err
		}
	}
	_, err = s.db.ExecContext(ctx, `UPDATE reminder_instances SET status = 'pending', updated_at = ?
		WHERE status = 'snoozed' AND snoozed_until IS NOT NULL AND snoozed_until <= ?`, db.Now(), db.Now())
	return err
}

func (s *Store) ListReminders(ctx context.Context, userID, status string) ([]ReminderInstance, error) {
	var query strings.Builder
	query.WriteString(`SELECT i.id, i.rule_id, i.pet_id, i.occurrence_key, i.due_at, i.status,
		COALESCE(i.snoozed_until,''), COALESCE(i.completed_at,''), COALESCE(i.record_id,''),
		p.name, r.type, r.advance_offsets, CASE WHEN p.owner_user_id = ? THEN 'owner' ELSE pm.role END
		FROM reminder_instances i
		JOIN pets p ON p.id = i.pet_id AND p.deleted_at IS NULL
		JOIN reminder_rules r ON r.id = i.rule_id
		LEFT JOIN pet_members pm ON pm.pet_id = p.id AND pm.user_id = ? AND pm.status = 'active'
		WHERE (p.owner_user_id = ? OR pm.id IS NOT NULL)`)
	args := []any{userID, userID, userID}
	switch status {
	case "done":
		query.WriteString(` AND i.status = 'done'`)
	case "skipped":
		query.WriteString(` AND i.status = 'skipped'`)
	case "all":
		query.WriteString(` AND i.status IN ('pending','snoozed','done','skipped')`)
	default:
		query.WriteString(` AND i.status IN ('pending','snoozed')`)
	}
	if status == "done" || status == "skipped" || status == "all" {
		query.WriteString(` ORDER BY i.due_at DESC, i.created_at DESC LIMIT 500`)
	} else {
		query.WriteString(` ORDER BY i.due_at ASC, i.created_at ASC LIMIT 500`)
	}
	rows, err := s.db.QueryContext(ctx, query.String(), args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]ReminderInstance, 0)
	for rows.Next() {
		var i ReminderInstance
		var offsets string
		if err := rows.Scan(&i.ID, &i.RuleID, &i.PetID, &i.OccurrenceKey, &i.DueAt, &i.Status,
			&i.SnoozedUntil, &i.CompletedAt, &i.RecordID, &i.PetName, &i.Type, &offsets, &i.Role); err != nil {
			return nil, err
		}
		i.AdvanceOffsets = decodeOffsets(offsets)
		out = append(out, i)
	}
	return out, rows.Err()
}

func (s *Store) GetReminderForUser(ctx context.Context, id, userID string) (ReminderInstance, error) {
	row := s.db.QueryRowContext(ctx, `SELECT i.id, i.rule_id, i.pet_id, i.occurrence_key, i.due_at, i.status,
		COALESCE(i.snoozed_until,''), COALESCE(i.completed_at,''), COALESCE(i.record_id,''),
		p.name, r.type, r.advance_offsets, CASE WHEN p.owner_user_id = ? THEN 'owner' ELSE pm.role END
		FROM reminder_instances i
		JOIN pets p ON p.id = i.pet_id AND p.deleted_at IS NULL
		JOIN reminder_rules r ON r.id = i.rule_id
		LEFT JOIN pet_members pm ON pm.pet_id = p.id AND pm.user_id = ? AND pm.status = 'active'
		WHERE i.id = ? AND (p.owner_user_id = ? OR pm.id IS NOT NULL)`,
		userID, userID, id, userID)
	var i ReminderInstance
	var offsets string
	err := row.Scan(&i.ID, &i.RuleID, &i.PetID, &i.OccurrenceKey, &i.DueAt, &i.Status,
		&i.SnoozedUntil, &i.CompletedAt, &i.RecordID, &i.PetName, &i.Type, &offsets, &i.Role)
	if errors.Is(err, sql.ErrNoRows) {
		return ReminderInstance{}, ErrNotFound
	}
	i.AdvanceOffsets = decodeOffsets(offsets)
	return i, err
}

// CompleteReminder marks an occurrence done, writes the resulting health
// record for care types, and advances the rule to its next due date.
func (s *Store) CompleteReminder(ctx context.Context, id string, actor Actor) (ReminderInstance, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return ReminderInstance{}, err
	}
	defer tx.Rollback()

	var inst ReminderInstance
	var interval int
	var ruleType string
	err = tx.QueryRowContext(ctx, `SELECT i.id, i.rule_id, i.pet_id, i.due_at, i.status, r.type, r.interval_days
		FROM reminder_instances i JOIN reminder_rules r ON r.id = i.rule_id
		WHERE i.id = ?`, id).
		Scan(&inst.ID, &inst.RuleID, &inst.PetID, &inst.DueAt, &inst.Status, &ruleType, &interval)
	if errors.Is(err, sql.ErrNoRows) {
		return ReminderInstance{}, ErrNotFound
	}
	if err != nil {
		return ReminderInstance{}, err
	}
	if inst.Status == "done" || inst.Status == "skipped" {
		return ReminderInstance{}, ErrConflict
	}
	if interval <= 0 {
		interval = defaultInterval(ruleType)
	}
	now := db.Now()
	date := today()
	nextDue := addDays(inst.DueAt, interval)
	var recordID any
	if recordReminderTypes[ruleType] {
		rid := auth.NewID()
		_, err = tx.ExecContext(ctx, `INSERT INTO health_records(
			id, pet_id, type, occurred_at, title, payload, hospital, doctor, next_due_at,
			source, created_by_type, created_by_user_id, created_by_grant_id, version, created_at, updated_at)
			VALUES(?, ?, ?, ?, ?, '{}', '', '', ?, 'reminder', ?, ?, ?, 1, ?, ?)`,
			rid, inst.PetID, ruleType, date, reminderRecordTitle(ruleType), nextDue,
			defaultString(actor.Type, "user"), nullString(actor.UserID), nullString(actor.GrantID), now, now)
		if err != nil {
			return ReminderInstance{}, err
		}
		recordID = rid
	}
	_, err = tx.ExecContext(ctx, `UPDATE reminder_instances SET status = 'done', completed_at = ?,
		completed_by_type = ?, completed_by_user_id = ?, completed_by_grant_id = ?, record_id = ?, updated_at = ?
		WHERE id = ?`, now, defaultString(actor.Type, "user"), nullString(actor.UserID),
		nullString(actor.GrantID), recordID, now, id)
	if err != nil {
		return ReminderInstance{}, err
	}
	_, err = tx.ExecContext(ctx, `UPDATE reminder_rules SET next_due_at = ?, anchor_record_id = ?, updated_at = ?
		WHERE id = ?`, nextDue, recordID, now, inst.RuleID)
	if err != nil {
		return ReminderInstance{}, err
	}
	if err := tx.Commit(); err != nil {
		return ReminderInstance{}, err
	}
	var typ string
	_ = s.db.QueryRowContext(ctx, `SELECT type FROM reminder_rules WHERE id = ?`, inst.RuleID).Scan(&typ)
	_ = s.ensureInstance(ctx, inst.PetID, typ, nextDue)
	return s.GetReminder(ctx, id)
}

// GetReminder loads one instance without applying user permissions; callers
// must resolve access first.
func (s *Store) GetReminder(ctx context.Context, id string) (ReminderInstance, error) {
	row := s.db.QueryRowContext(ctx, `SELECT i.id, i.rule_id, i.pet_id, i.occurrence_key, i.due_at, i.status,
		COALESCE(i.snoozed_until,''), COALESCE(i.completed_at,''), COALESCE(i.record_id,''),
		p.name, r.type, r.advance_offsets, ''
		FROM reminder_instances i
		JOIN pets p ON p.id = i.pet_id
		JOIN reminder_rules r ON r.id = i.rule_id
		WHERE i.id = ?`, id)
	var i ReminderInstance
	var offsets string
	err := row.Scan(&i.ID, &i.RuleID, &i.PetID, &i.OccurrenceKey, &i.DueAt, &i.Status,
		&i.SnoozedUntil, &i.CompletedAt, &i.RecordID, &i.PetName, &i.Type, &offsets, &i.Role)
	if errors.Is(err, sql.ErrNoRows) {
		return ReminderInstance{}, ErrNotFound
	}
	i.AdvanceOffsets = decodeOffsets(offsets)
	return i, err
}

func reminderRecordTitle(typ string) string {
	switch typ {
	case "vaccine":
		return "疫苗加强"
	case "deworming":
		return "驱虫"
	case "checkup":
		return "定期体检"
	case "grooming":
		return "洗护"
	default:
		return "照护记录"
	}
}

func (s *Store) SnoozeReminder(ctx context.Context, id, userID string, until string) (ReminderInstance, error) {
	inst, err := s.GetReminderForUser(ctx, id, userID)
	if err != nil {
		return ReminderInstance{}, err
	}
	if inst.Role == "viewer" {
		return ReminderInstance{}, ErrForbidden
	}
	res, err := s.db.ExecContext(ctx, `UPDATE reminder_instances SET status = 'snoozed', snoozed_until = ?, updated_at = ?
		WHERE id = ? AND status IN ('pending','snoozed')`, until, db.Now(), id)
	if err != nil {
		return ReminderInstance{}, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ReminderInstance{}, ErrConflict
	}
	return s.GetReminderForUser(ctx, id, userID)
}

func (s *Store) SkipReminder(ctx context.Context, id, userID string) (ReminderInstance, error) {
	inst, err := s.GetReminderForUser(ctx, id, userID)
	if err != nil {
		return ReminderInstance{}, err
	}
	if inst.Role == "viewer" {
		return ReminderInstance{}, ErrForbidden
	}
	res, err := s.db.ExecContext(ctx, `UPDATE reminder_instances SET status = 'skipped', updated_at = ?
		WHERE id = ? AND status IN ('pending','snoozed')`, db.Now(), id)
	if err != nil {
		return ReminderInstance{}, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ReminderInstance{}, ErrConflict
	}
	return s.GetReminderForUser(ctx, id, userID)
}

func (s *Store) ListReminderRules(ctx context.Context, petID, userID string) ([]ReminderRule, error) {
	pet, err := s.GetPetForUser(ctx, petID, userID)
	if err != nil {
		return nil, err
	}
	_ = pet
	rows, err := s.db.QueryContext(ctx, `SELECT id, pet_id, type, interval_days, COALESCE(anchor_record_id,''),
		COALESCE(next_due_at,''), advance_offsets, enabled FROM reminder_rules WHERE pet_id = ? ORDER BY type`, petID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]ReminderRule, 0)
	for rows.Next() {
		var r ReminderRule
		var enabled int
		var raw string
		if err := rows.Scan(&r.ID, &r.PetID, &r.Type, &r.IntervalDays, &r.AnchorRecordID, &r.NextDueAt, &raw, &enabled); err != nil {
			return nil, err
		}
		r.Enabled = enabled == 1
		r.AdvanceOffsets = decodeOffsets(raw)
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *Store) UpdateReminderRule(ctx context.Context, ruleID, userID string, enabled *bool, intervalDays *int, offsets *[]int) (ReminderRule, error) {
	var petID, typ, nextDue, rawOffsets string
	var currentEnabled int
	var currentInterval int
	err := s.db.QueryRowContext(ctx, `SELECT pet_id, type, interval_days, COALESCE(next_due_at,''), advance_offsets, enabled
		FROM reminder_rules WHERE id = ?`, ruleID).
		Scan(&petID, &typ, &currentInterval, &nextDue, &rawOffsets, &currentEnabled)
	if errors.Is(err, sql.ErrNoRows) {
		return ReminderRule{}, ErrNotFound
	}
	if err != nil {
		return ReminderRule{}, err
	}
	pet, err := s.GetPetForUser(ctx, petID, userID)
	if err != nil {
		return ReminderRule{}, err
	}
	if pet.Role != "owner" {
		return ReminderRule{}, ErrForbidden
	}
	if enabled != nil {
		currentEnabled = 0
		if *enabled {
			currentEnabled = 1
		}
	}
	if intervalDays != nil && *intervalDays > 0 && *intervalDays <= 3650 {
		currentInterval = *intervalDays
	}
	if offsets != nil {
		rawOffsets = encodeOffsets(*offsets)
	}
	_, err = s.db.ExecContext(ctx, `UPDATE reminder_rules SET enabled = ?, interval_days = ?, advance_offsets = ?, updated_at = ?
		WHERE id = ?`, currentEnabled, currentInterval, rawOffsets, db.Now(), ruleID)
	if err != nil {
		return ReminderRule{}, err
	}
	if intervalDays != nil {
		// Re-anchor the next due date from the record that started this cycle.
		var anchor string
		if err := s.db.QueryRowContext(ctx, `SELECT COALESCE(anchor_record_id, '') FROM reminder_rules WHERE id = ?`, ruleID).
			Scan(&anchor); err == nil && anchor != "" {
			var occurred string
			if err := s.db.QueryRowContext(ctx, `SELECT occurred_at FROM health_records WHERE id = ?`, anchor).
				Scan(&occurred); err == nil {
				nextDue = addDays(occurred, currentInterval)
				if _, err := s.db.ExecContext(ctx, `UPDATE reminder_rules SET next_due_at = ? WHERE id = ?`, nextDue, ruleID); err != nil {
					return ReminderRule{}, err
				}
				if _, err := s.db.ExecContext(ctx, `DELETE FROM reminder_instances WHERE rule_id = ? AND status IN ('pending','snoozed') AND due_at <> ?`, ruleID, nextDue); err != nil {
					return ReminderRule{}, err
				}
			}
		}
	}
	if currentEnabled == 1 && nextDue != "" {
		if err := s.ensureInstance(ctx, petID, typ, nextDue); err != nil {
			return ReminderRule{}, err
		}
	}
	var r ReminderRule
	var enabledInt int
	err = s.db.QueryRowContext(ctx, `SELECT id, pet_id, type, interval_days, COALESCE(anchor_record_id,''),
		COALESCE(next_due_at,''), advance_offsets, enabled FROM reminder_rules WHERE id = ?`, ruleID).
		Scan(&r.ID, &r.PetID, &r.Type, &r.IntervalDays, &r.AnchorRecordID, &r.NextDueAt, &rawOffsets, &enabledInt)
	r.Enabled = enabledInt == 1
	r.AdvanceOffsets = decodeOffsets(rawOffsets)
	return r, err
}
