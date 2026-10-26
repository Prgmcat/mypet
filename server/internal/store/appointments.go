package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"

	"github.com/Prgmcat/mypet/server/internal/auth"
	"github.com/Prgmcat/mypet/server/internal/db"
)

// Appointment types reuse the health record vocabulary so completing one can
// produce a record with the same type.
var appointmentDefaultOffsets = map[string][]int{
	"vaccine":    {14, 7, 1, 0},
	"deworming":  {3, 1, 0},
	"checkup":    {7, 1, 0},
	"medical":    {1, 0},
	"medication": {0},
	"grooming":   {1, 0},
	"other":      {0},
}

func appointmentOffsets(typ string) []int {
	if v, ok := appointmentDefaultOffsets[typ]; ok {
		return v
	}
	return []int{0}
}

func appointmentRecordType(typ string) string {
	if _, ok := appointmentDefaultOffsets[typ]; ok {
		return typ
	}
	return "other"
}

const appointmentSelect = `SELECT a.id, a.pet_id, p.name, a.type, a.title, a.scheduled_at,
	a.note, a.advance_offsets, a.status, COALESCE(a.snoozed_until, ''),
	COALESCE(a.completed_at, ''), COALESCE(a.record_id, ''),
	CASE WHEN p.owner_user_id = ? THEN 'owner' ELSE pm.role END
	FROM appointments a
	JOIN pets p ON p.id = a.pet_id AND p.deleted_at IS NULL
	LEFT JOIN pet_members pm ON pm.pet_id = p.id AND pm.user_id = ? AND pm.status = 'active'
	WHERE (p.owner_user_id = ? OR pm.id IS NOT NULL)`

func scanAppointment(row scanner) (Appointment, error) {
	var a Appointment
	var offsets string
	if err := row.Scan(&a.ID, &a.PetID, &a.PetName, &a.Type, &a.Title, &a.ScheduledAt,
		&a.Note, &offsets, &a.Status, &a.SnoozedUntil, &a.CompletedAt, &a.RecordID, &a.Role); err != nil {
		return Appointment{}, err
	}
	a.AdvanceOffsets = decodeOffsets(offsets)
	return a, nil
}

// ListAppointments returns appointments for every pet the user can access.
// An empty petID means all pets. Status accepts pending, done, skipped or all;
// pending includes snoozed appointments.
func (s *Store) ListAppointments(ctx context.Context, userID, petID, status string) ([]Appointment, error) {
	query := appointmentSelect
	args := []any{userID, userID, userID}
	if petID != "" {
		query += ` AND a.pet_id = ?`
		args = append(args, petID)
	}
	switch status {
	case "done":
		query += ` AND a.status = 'done'`
	case "skipped":
		query += ` AND a.status = 'skipped'`
	case "all":
		query += ` AND a.status IN ('pending','snoozed','done','skipped')`
	default:
		query += ` AND a.status IN ('pending','snoozed')`
	}
	if status == "done" || status == "skipped" || status == "all" {
		query += ` ORDER BY a.scheduled_at DESC, a.created_at DESC LIMIT 500`
	} else {
		query += ` ORDER BY a.scheduled_at ASC, a.created_at ASC LIMIT 500`
	}
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Appointment, 0)
	for rows.Next() {
		a, err := scanAppointment(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// GetAppointmentForUser loads one appointment after checking pet access.
func (s *Store) GetAppointmentForUser(ctx context.Context, id, userID string) (Appointment, error) {
	row := s.db.QueryRowContext(ctx, appointmentSelect+` AND a.id = ?`, userID, userID, userID, id)
	a, err := scanAppointment(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Appointment{}, ErrNotFound
	}
	return a, err
}

// GetAppointment loads one appointment without applying user permissions;
// callers must resolve access first.
func (s *Store) GetAppointment(ctx context.Context, id string) (Appointment, error) {
	row := s.db.QueryRowContext(ctx, `SELECT a.id, a.pet_id, p.name, a.type, a.title, a.scheduled_at,
		a.note, a.advance_offsets, a.status, COALESCE(a.snoozed_until, ''),
		COALESCE(a.completed_at, ''), COALESCE(a.record_id, ''), ''
		FROM appointments a JOIN pets p ON p.id = a.pet_id
		WHERE a.id = ?`, id)
	a, err := scanAppointment(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Appointment{}, ErrNotFound
	}
	return a, err
}

func (s *Store) CreateAppointment(ctx context.Context, petID string, actor Actor, in AppointmentInput) (Appointment, error) {
	if len(in.AdvanceOffsets) == 0 {
		in.AdvanceOffsets = appointmentOffsets(in.Type)
	}
	now := db.Now()
	id := auth.NewID()
	_, err := s.db.ExecContext(ctx, `INSERT INTO appointments(
		id, pet_id, type, title, scheduled_at, note, advance_offsets, status,
		created_by_type, created_by_user_id, created_at, updated_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?)`,
		id, petID, in.Type, in.Title, in.ScheduledAt, in.Note,
		encodeOffsets(in.AdvanceOffsets), defaultString(actor.Type, "user"),
		nullString(actor.UserID), now, now)
	if err != nil {
		return Appointment{}, err
	}
	return s.GetAppointment(ctx, id)
}

// UpdateAppointment edits an appointment that has not been handled yet.
func (s *Store) UpdateAppointment(ctx context.Context, id string, patch AppointmentPatch) (Appointment, error) {
	current, err := s.GetAppointment(ctx, id)
	if err != nil {
		return Appointment{}, err
	}
	if current.Status == "done" || current.Status == "skipped" {
		return Appointment{}, ErrConflict
	}
	typ := current.Type
	title := current.Title
	scheduled := current.ScheduledAt
	note := current.Note
	offsets := current.AdvanceOffsets
	if patch.Type != nil {
		typ = *patch.Type
	}
	if patch.Title != nil {
		title = *patch.Title
	}
	if patch.ScheduledAt != nil {
		scheduled = *patch.ScheduledAt
	}
	if patch.Note != nil {
		note = *patch.Note
	}
	if patch.AdvanceOffsets != nil && len(*patch.AdvanceOffsets) > 0 {
		offsets = *patch.AdvanceOffsets
	}
	_, err = s.db.ExecContext(ctx, `UPDATE appointments SET type = ?, title = ?, scheduled_at = ?,
		note = ?, advance_offsets = ?, status = 'pending', snoozed_until = NULL, updated_at = ?
		WHERE id = ?`, typ, title, scheduled, note, encodeOffsets(offsets), db.Now(), id)
	if err != nil {
		return Appointment{}, err
	}
	return s.GetAppointment(ctx, id)
}

func (s *Store) DeleteAppointment(ctx context.Context, id string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM appointments WHERE id = ?`, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// CompleteAppointment marks an appointment done and writes the linked health
// record. The record's occurrence date is the day the task was handled.
func (s *Store) CompleteAppointment(ctx context.Context, id string, actor Actor) (Appointment, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Appointment{}, err
	}
	defer tx.Rollback()

	var petID, typ, title, note, status string
	err = tx.QueryRowContext(ctx, `SELECT pet_id, type, title, note, status FROM appointments WHERE id = ?`, id).
		Scan(&petID, &typ, &title, &note, &status)
	if errors.Is(err, sql.ErrNoRows) {
		return Appointment{}, ErrNotFound
	}
	if err != nil {
		return Appointment{}, err
	}
	if status == "done" || status == "skipped" {
		return Appointment{}, ErrConflict
	}

	payload := json.RawMessage(`{}`)
	if note != "" {
		raw, _ := json.Marshal(map[string]string{"note": note})
		payload = raw
	}
	now := db.Now()
	recordID := auth.NewID()
	_, err = tx.ExecContext(ctx, `INSERT INTO health_records(
		id, pet_id, type, occurred_at, title, payload, hospital, doctor, next_due_at,
		source, created_by_type, created_by_user_id, created_by_grant_id, version, created_at, updated_at)
		VALUES(?, ?, ?, ?, ?, ?, '', '', NULL, 'appointment', ?, ?, ?, 1, ?, ?)`,
		recordID, petID, appointmentRecordType(typ), today(), title, string(payload),
		defaultString(actor.Type, "user"), nullString(actor.UserID), nullString(actor.GrantID), now, now)
	if err != nil {
		return Appointment{}, err
	}
	_, err = tx.ExecContext(ctx, `UPDATE appointments SET status = 'done', completed_at = ?,
		completed_by_type = ?, completed_by_user_id = ?, completed_by_grant_id = ?,
		record_id = ?, updated_at = ? WHERE id = ?`,
		now, defaultString(actor.Type, "user"), nullString(actor.UserID), nullString(actor.GrantID),
		recordID, now, id)
	if err != nil {
		return Appointment{}, err
	}
	if err := tx.Commit(); err != nil {
		return Appointment{}, err
	}
	return s.GetAppointment(ctx, id)
}

func (s *Store) SkipAppointment(ctx context.Context, id string) (Appointment, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE appointments SET status = 'skipped', updated_at = ?
		WHERE id = ? AND status IN ('pending','snoozed')`, db.Now(), id)
	if err != nil {
		return Appointment{}, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return Appointment{}, ErrConflict
	}
	return s.GetAppointment(ctx, id)
}

func (s *Store) SnoozeAppointment(ctx context.Context, id, until string) (Appointment, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE appointments SET status = 'snoozed', snoozed_until = ?, updated_at = ?
		WHERE id = ? AND status IN ('pending','snoozed')`, until, db.Now(), id)
	if err != nil {
		return Appointment{}, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return Appointment{}, ErrConflict
	}
	return s.GetAppointment(ctx, id)
}
