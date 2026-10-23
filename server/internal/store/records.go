package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/Prgmcat/mypet/server/internal/auth"
	"github.com/Prgmcat/mypet/server/internal/db"
)

func (s *Store) CreateRecord(ctx context.Context, petID, userID string, in RecordInput) (HealthRecord, error) {
	return s.CreateRecordAs(ctx, petID, in, UserActor(userID))
}

func (s *Store) CreateRecordAs(ctx context.Context, petID string, in RecordInput, actor Actor) (HealthRecord, error) {
	if len(in.Payload) == 0 || string(in.Payload) == "null" {
		in.Payload = json.RawMessage(`{}`)
	}
	now := db.Now()
	id := auth.NewID()
	_, err := s.db.ExecContext(ctx, `INSERT INTO health_records(
		id, pet_id, type, occurred_at, title, payload, hospital, doctor, next_due_at,
		source, created_by_type, created_by_user_id, created_by_grant_id, version, created_at, updated_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`,
		id, petID, in.Type, in.OccurredAt, in.Title, string(in.Payload),
		in.Hospital, in.Doctor, nullString(in.NextDueAt), defaultString(in.Source, "manual"),
		defaultString(actor.Type, "user"), nullString(actor.UserID), nullString(actor.GrantID), now, now)
	if err != nil {
		return HealthRecord{}, err
	}
	return s.GetRecord(ctx, id)
}

func (s *Store) ListRecords(ctx context.Context, petID, typ string) ([]HealthRecord, error) {
	query := `SELECT id, pet_id, type, occurred_at, title, payload, hospital, doctor, next_due_at,
		source, created_by_type, COALESCE(created_by_user_id, ''), version, created_at, updated_at
		FROM health_records WHERE pet_id = ? AND deleted_at IS NULL`
	args := []any{petID}
	if strings.TrimSpace(typ) != "" {
		query += ` AND type = ?`
		args = append(args, typ)
	}
	query += ` ORDER BY occurred_at DESC, created_at DESC LIMIT 500`
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]HealthRecord, 0)
	for rows.Next() {
		r, err := scanRecord(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for i := range out {
		atts, err := s.listAttachments(ctx, out[i].ID)
		if err != nil {
			return nil, err
		}
		out[i].Attachments = atts
	}
	return out, nil
}

func (s *Store) GetRecord(ctx context.Context, id string) (HealthRecord, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, pet_id, type, occurred_at, title, payload, hospital, doctor, next_due_at,
		source, created_by_type, COALESCE(created_by_user_id, ''), version, created_at, updated_at
		FROM health_records WHERE id = ? AND deleted_at IS NULL`, id)
	r, err := scanRecord(row)
	if errors.Is(err, sql.ErrNoRows) {
		return HealthRecord{}, ErrNotFound
	}
	if err != nil {
		return HealthRecord{}, err
	}
	r.Attachments, err = s.listAttachments(ctx, r.ID)
	return r, err
}

func (s *Store) UpdateRecord(ctx context.Context, id string, in RecordInput) (HealthRecord, error) {
	if len(in.Payload) == 0 || string(in.Payload) == "null" {
		in.Payload = json.RawMessage(`{}`)
	}
	res, err := s.db.ExecContext(ctx, `UPDATE health_records SET type = ?, occurred_at = ?, title = ?,
		payload = ?, hospital = ?, doctor = ?, next_due_at = ?, source = ?, version = version + 1, updated_at = ?
		WHERE id = ? AND deleted_at IS NULL`,
		in.Type, in.OccurredAt, in.Title, string(in.Payload), in.Hospital, in.Doctor,
		nullString(in.NextDueAt), defaultString(in.Source, "manual"), db.Now(), id)
	if err != nil {
		return HealthRecord{}, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return HealthRecord{}, ErrNotFound
	}
	return s.GetRecord(ctx, id)
}

func (s *Store) DeleteRecord(ctx context.Context, id string) error {
	now := db.Now()
	res, err := s.db.ExecContext(ctx, `UPDATE health_records SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL`, now, now, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) RestoreRecord(ctx context.Context, id string) (HealthRecord, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE health_records SET deleted_at = NULL, updated_at = ? WHERE id = ? AND deleted_at IS NOT NULL`, db.Now(), id)
	if err != nil {
		return HealthRecord{}, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return HealthRecord{}, ErrNotFound
	}
	return s.GetRecord(ctx, id)
}

func (s *Store) CreateWeight(ctx context.Context, petID, userID string, in WeightInput) (WeightRecord, error) {
	return s.CreateWeightAs(ctx, petID, in, UserActor(userID))
}

func (s *Store) CreateWeightAs(ctx context.Context, petID string, in WeightInput, actor Actor) (WeightRecord, error) {
	now := db.Now()
	id := auth.NewID()
	_, err := s.db.ExecContext(ctx, `INSERT INTO weight_records(
		id, pet_id, measured_at, weight_kg, note, created_by_type, created_by_user_id, created_by_grant_id, created_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)`, id, petID, in.MeasuredAt, in.WeightKg, in.Note,
		defaultString(actor.Type, "user"), nullString(actor.UserID), nullString(actor.GrantID), now)
	if err != nil {
		return WeightRecord{}, err
	}
	// Keep the profile weight aligned with the latest measurement.
	_, _ = s.db.ExecContext(ctx, `UPDATE pets SET current_weight_kg = (
		SELECT weight_kg FROM weight_records WHERE pet_id = ?
		ORDER BY measured_at DESC, created_at DESC LIMIT 1), updated_at = ? WHERE id = ?`,
		petID, now, petID)
	return WeightRecord{
		ID: id, PetID: petID, MeasuredAt: in.MeasuredAt, WeightKg: in.WeightKg,
		Note: in.Note, CreatedByType: defaultString(actor.Type, "user"),
		CreatedByUserID: actor.UserID, CreatedAt: now,
	}, nil
}

func (s *Store) ListWeights(ctx context.Context, petID string) ([]WeightRecord, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, pet_id, measured_at, weight_kg, note, created_by_type,
		COALESCE(created_by_user_id, ''), created_at FROM weight_records WHERE pet_id = ? ORDER BY measured_at ASC`, petID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]WeightRecord, 0)
	for rows.Next() {
		var w WeightRecord
		if err := rows.Scan(&w.ID, &w.PetID, &w.MeasuredAt, &w.WeightKg, &w.Note, &w.CreatedByType, &w.CreatedByUserID, &w.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

func (s *Store) SaveAttachment(ctx context.Context, petID, recordID, originalName, mime string, data []byte) (Attachment, error) {
	ext := safeExt(originalName, mime)
	name := auth.NewID() + ext
	relPath := filepath.ToSlash(filepath.Join("uploads", petID, name))
	diskPath := filepath.Join(filepath.Dir(s.db.Path), filepath.FromSlash(relPath))
	if err := os.MkdirAll(filepath.Dir(diskPath), 0o700); err != nil {
		return Attachment{}, err
	}
	if err := os.WriteFile(diskPath, data, 0o600); err != nil {
		return Attachment{}, err
	}
	sum := sha256.Sum256(data)
	digest := hex.EncodeToString(sum[:])
	now := db.Now()
	id := auth.NewID()
	var rec any
	if strings.TrimSpace(recordID) != "" {
		rec = recordID
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO attachments(id, pet_id, record_id, file_path, original_name, mime, size, sha256, created_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)`, id, petID, rec, relPath, originalName, mime, len(data), digest, now)
	if err != nil {
		_ = os.Remove(diskPath)
		return Attachment{}, err
	}
	return Attachment{
		ID: id, PetID: petID, RecordID: recordID, OriginalName: originalName,
		Mime: mime, Size: int64(len(data)), SHA256: digest, CreatedAt: now,
	}, nil
}

func (s *Store) GetAttachmentWithPath(ctx context.Context, id string) (Attachment, string, error) {
	var a Attachment
	var recordID sql.NullString
	var relPath string
	err := s.db.QueryRowContext(ctx, `SELECT id, pet_id, record_id, file_path, original_name, mime, size, sha256, created_at
		FROM attachments WHERE id = ?`, id).
		Scan(&a.ID, &a.PetID, &recordID, &relPath, &a.OriginalName, &a.Mime, &a.Size, &a.SHA256, &a.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Attachment{}, "", ErrNotFound
	}
	if err != nil {
		return Attachment{}, "", err
	}
	if recordID.Valid {
		a.RecordID = recordID.String
	}
	diskPath := filepath.Join(filepath.Dir(s.db.Path), filepath.FromSlash(relPath))
	return a, diskPath, nil
}

func (s *Store) listAttachments(ctx context.Context, recordID string) ([]Attachment, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, pet_id, record_id, original_name, mime, size, sha256, created_at
		FROM attachments WHERE record_id = ? ORDER BY created_at ASC`, recordID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Attachment, 0)
	for rows.Next() {
		var a Attachment
		var rec sql.NullString
		if err := rows.Scan(&a.ID, &a.PetID, &rec, &a.OriginalName, &a.Mime, &a.Size, &a.SHA256, &a.CreatedAt); err != nil {
			return nil, err
		}
		if rec.Valid {
			a.RecordID = rec.String
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func scanRecord(row scanner) (HealthRecord, error) {
	var r HealthRecord
	var payload string
	var nextDue sql.NullString
	err := row.Scan(&r.ID, &r.PetID, &r.Type, &r.OccurredAt, &r.Title, &payload,
		&r.Hospital, &r.Doctor, &nextDue, &r.Source, &r.CreatedByType,
		&r.CreatedByUserID, &r.Version, &r.CreatedAt, &r.UpdatedAt)
	if err != nil {
		return HealthRecord{}, err
	}
	if nextDue.Valid {
		r.NextDueAt = nextDue.String
	}
	var decoded any
	if err := json.Unmarshal([]byte(payload), &decoded); err == nil {
		normalized, err := json.Marshal(decoded)
		if err == nil {
			r.Payload = json.RawMessage(normalized)
		}
	}
	if len(r.Payload) == 0 {
		r.Payload = json.RawMessage(`{}`)
	}
	return r, nil
}

func safeExt(name, mime string) string {
	ext := strings.ToLower(filepath.Ext(name))
	switch ext {
	case ".jpg", ".jpeg", ".png", ".webp", ".pdf":
		return ext
	}
	switch mime {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	case "application/pdf":
		return ".pdf"
	default:
		return ".bin"
	}
}

func defaultString(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func (s *Store) UploadsDir() string {
	return filepath.Join(filepath.Dir(s.db.Path), "uploads")
}

func (s *Store) PetIDForRecord(ctx context.Context, recordID string) (string, error) {
	var petID string
	err := s.db.QueryRowContext(ctx, `SELECT pet_id FROM health_records WHERE id = ?`, recordID).Scan(&petID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	return petID, err
}
