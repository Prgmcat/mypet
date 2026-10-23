package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math/rand/v2"
	"strings"
	"time"

	"github.com/Prgmcat/mypet/server/internal/auth"
	"github.com/Prgmcat/mypet/server/internal/db"
)

var (
	ErrNotFound      = errors.New("not found")
	ErrConflict      = errors.New("conflict")
	ErrInvalidInvite = errors.New("invalid invite")
	ErrInvalidCode   = errors.New("invalid code")
	ErrForbidden     = errors.New("forbidden")
)

type Store struct {
	db *db.DB
}

func New(d *db.DB) *Store { return &Store{db: d} }

func (s *Store) CountUsers(ctx context.Context) (int, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM users`).Scan(&n)
	return n, err
}

func (s *Store) CreateAdmin(ctx context.Context, username, passwordHash string) (User, error) {
	now := db.Now()
	id := auth.NewID()
	_, err := s.db.ExecContext(ctx, `INSERT INTO users(id, username, password_hash, display_name, is_admin, status, created_at, updated_at)
		VALUES(?, ?, ?, ?, 1, 'active', ?, ?)`, id, username, passwordHash, username, now, now)
	if err != nil {
		if isUnique(err) {
			return User{}, ErrConflict
		}
		return User{}, err
	}
	return s.UserByID(ctx, id)
}

func (s *Store) FindUserByUsername(ctx context.Context, username string) (User, string, error) {
	var u User
	var hash string
	err := s.db.QueryRowContext(ctx, `SELECT id, username, password_hash, display_name, is_admin, status, created_at
		FROM users WHERE username = ? COLLATE NOCASE`, username).
		Scan(&u.ID, &u.Username, &hash, &u.DisplayName, &u.IsAdmin, &u.Status, &u.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return User{}, "", ErrNotFound
	}
	return u, hash, err
}

func (s *Store) UserByID(ctx context.Context, id string) (User, error) {
	var u User
	err := s.db.QueryRowContext(ctx, `SELECT id, username, display_name, is_admin, status, created_at
		FROM users WHERE id = ?`, id).
		Scan(&u.ID, &u.Username, &u.DisplayName, &u.IsAdmin, &u.Status, &u.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return User{}, ErrNotFound
	}
	return u, err
}

func (s *Store) ListUsers(ctx context.Context) ([]User, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, username, display_name, is_admin, status, created_at
		FROM users ORDER BY created_at ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]User, 0)
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.DisplayName, &u.IsAdmin, &u.Status, &u.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

func (s *Store) SetUserStatus(ctx context.Context, userID, status string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE users SET status = ?, updated_at = ? WHERE id = ?`, status, db.Now(), userID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	if status != "active" {
		_, _ = s.db.ExecContext(ctx, `UPDATE devices SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL`, db.Now(), userID)
	}
	return nil
}

func (s *Store) CreateUserWithInvite(ctx context.Context, inviteHash, username, passwordHash, displayName string) (User, error) {
	now := db.Now()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback()

	res, err := tx.ExecContext(ctx, `UPDATE invite_codes
		SET used_count = used_count + 1,
		    status = CASE WHEN used_count + 1 >= max_uses THEN 'used' ELSE status END
		WHERE code_hash = ? AND status = 'active' AND expires_at > ? AND used_count < max_uses`, inviteHash, now)
	if err != nil {
		return User{}, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return User{}, ErrInvalidInvite
	}

	id := auth.NewID()
	_, err = tx.ExecContext(ctx, `INSERT INTO users(id, username, password_hash, display_name, is_admin, status, created_at, updated_at)
		VALUES(?, ?, ?, ?, 0, 'active', ?, ?)`, id, username, passwordHash, displayName, now, now)
	if err != nil {
		if isUnique(err) {
			return User{}, ErrConflict
		}
		return User{}, err
	}
	if err := tx.Commit(); err != nil {
		return User{}, err
	}
	return s.UserByID(ctx, id)
}

func (s *Store) CreateDevice(ctx context.Context, userID, name, tokenHash string) (Device, error) {
	now := db.Now()
	id := auth.NewID()
	_, err := s.db.ExecContext(ctx, `INSERT INTO devices(id, user_id, name, token_hash, created_at)
		VALUES(?, ?, ?, ?, ?)`, id, userID, name, tokenHash, now)
	if err != nil {
		return Device{}, err
	}
	return Device{ID: id, Name: name, CreatedAt: now}, nil
}

func (s *Store) UserByToken(ctx context.Context, tokenHash string) (User, Device, error) {
	var u User
	var d Device
	var lastSeen sql.NullString
	err := s.db.QueryRowContext(ctx, `SELECT u.id, u.username, u.display_name, u.is_admin, u.status, u.created_at,
		d.id, d.name, d.last_seen_at, d.created_at
		FROM devices d JOIN users u ON u.id = d.user_id
		WHERE d.token_hash = ? AND d.revoked_at IS NULL AND u.status = 'active'`, tokenHash).
		Scan(&u.ID, &u.Username, &u.DisplayName, &u.IsAdmin, &u.Status, &u.CreatedAt,
			&d.ID, &d.Name, &lastSeen, &d.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return User{}, Device{}, ErrNotFound
	}
	if err != nil {
		return User{}, Device{}, err
	}
	if lastSeen.Valid {
		d.LastSeenAt = lastSeen.String
	}
	_, _ = s.db.ExecContext(ctx, `UPDATE devices SET last_seen_at = ? WHERE id = ?`, db.Now(), d.ID)
	return u, d, nil
}

func (s *Store) ListDevices(ctx context.Context, userID string) ([]Device, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, name, last_seen_at, created_at, revoked_at
		FROM devices WHERE user_id = ? ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Device, 0)
	for rows.Next() {
		var d Device
		var lastSeen, revoked sql.NullString
		if err := rows.Scan(&d.ID, &d.Name, &lastSeen, &d.CreatedAt, &revoked); err != nil {
			return nil, err
		}
		if lastSeen.Valid {
			d.LastSeenAt = lastSeen.String
		}
		if revoked.Valid {
			d.RevokedAt = revoked.String
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (s *Store) RevokeDevice(ctx context.Context, deviceID, userID string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE devices SET revoked_at = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL`, db.Now(), deviceID, userID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) ListAllDevices(ctx context.Context) ([]AdminDevice, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT d.id, d.user_id, u.username, d.name, d.last_seen_at, d.created_at, d.revoked_at
		FROM devices d JOIN users u ON u.id = d.user_id ORDER BY d.created_at DESC LIMIT 1000`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]AdminDevice, 0)
	for rows.Next() {
		var d AdminDevice
		var lastSeen, revoked sql.NullString
		if err := rows.Scan(&d.ID, &d.UserID, &d.Username, &d.Name, &lastSeen, &d.CreatedAt, &revoked); err != nil {
			return nil, err
		}
		if lastSeen.Valid {
			d.LastSeenAt = lastSeen.String
		}
		if revoked.Valid {
			d.RevokedAt = revoked.String
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (s *Store) RevokeDeviceAsAdmin(ctx context.Context, deviceID string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE devices SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL`, db.Now(), deviceID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) UpdatePassword(ctx context.Context, userID, passwordHash, keepDeviceID string) error {
	now := db.Now()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?`, passwordHash, now, userID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE devices SET revoked_at = ? WHERE user_id = ? AND id <> ? AND revoked_at IS NULL`, now, userID, keepDeviceID); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) CreateInvite(ctx context.Context, adminID string, maxUses int, ttl time.Duration) (string, string, error) {
	plain, hash, err := auth.NewInviteCode()
	if err != nil {
		return "", "", err
	}
	expires := time.Now().UTC().Add(ttl).Format(time.RFC3339)
	_, err = s.db.ExecContext(ctx, `INSERT INTO invite_codes(id, code_hash, created_by_user_id, max_uses, used_count, expires_at, status, created_at)
		VALUES(?, ?, ?, ?, 0, ?, 'active', ?)`, auth.NewID(), hash, adminID, maxUses, expires, db.Now())
	if err != nil {
		return "", "", err
	}
	return plain, expires, nil
}

func (s *Store) ListInvites(ctx context.Context) ([]InviteCode, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, max_uses, used_count, expires_at, status, created_at
		FROM invite_codes ORDER BY created_at DESC LIMIT 200`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]InviteCode, 0)
	for rows.Next() {
		var invite InviteCode
		if err := rows.Scan(&invite.ID, &invite.MaxUses, &invite.UsedCount, &invite.ExpiresAt, &invite.Status, &invite.CreatedAt); err != nil {
			return nil, err
		}
		if invite.Status == "active" && invite.ExpiresAt <= db.Now() {
			invite.Status = "expired"
		}
		out = append(out, invite)
	}
	return out, rows.Err()
}

func (s *Store) RevokeInvite(ctx context.Context, id string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE invite_codes SET status = 'revoked' WHERE id = ? AND status = 'active'`, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) CreateResetCode(ctx context.Context, adminID, username string, ttl time.Duration) (string, error) {
	u, _, err := s.FindUserByUsername(ctx, username)
	if err != nil {
		return "", err
	}
	plain, hash, err := auth.NewResetCode()
	if err != nil {
		return "", err
	}
	expires := time.Now().UTC().Add(ttl).Format(time.RFC3339)
	_, err = s.db.ExecContext(ctx, `INSERT INTO password_reset_codes(id, user_id, code_hash, expires_at, created_by_admin_id, created_at)
		VALUES(?, ?, ?, ?, ?, ?)`, auth.NewID(), u.ID, hash, expires, adminID, db.Now())
	if err != nil {
		return "", err
	}
	return plain, nil
}

func (s *Store) ResetPasswordWithCode(ctx context.Context, username, codeHash, newHash string) error {
	now := db.Now()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var userID, codeID string
	err = tx.QueryRowContext(ctx, `SELECT r.id, r.user_id FROM password_reset_codes r
		JOIN users u ON u.id = r.user_id
		WHERE u.username = ? COLLATE NOCASE AND r.code_hash = ? AND r.used_at IS NULL AND r.expires_at > ?`,
		username, codeHash, now).Scan(&codeID, &userID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInvalidCode
	}
	if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE password_reset_codes SET used_at = ? WHERE id = ?`, now, codeID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?`, newHash, now, userID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE devices SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL`, now, userID); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) CreatePet(ctx context.Context, ownerID string, in PetInput) (Pet, error) {
	now := db.Now()
	for attempt := 0; attempt < 5; attempt++ {
		id := auth.NewID()
		identity := fmt.Sprintf("PET%d%06d", time.Now().Year(), rand.IntN(1000000))
		_, err := s.db.ExecContext(ctx, `INSERT INTO pets(
			id, owner_user_id, name, species, breed, sex, birthday, birthday_estimated, neutered,
			avatar_path, current_weight_kg, allergies, chronic_conditions, medications, identity_no,
			status, version, created_at, updated_at)
			VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', 1, ?, ?)`,
			id, ownerID, in.Name, in.Species, in.Breed, in.Sex, nullString(in.Birthday), in.BirthdayEstimated,
			in.Neutered, nullString(in.AvatarPath), nullFloat(in.CurrentWeightKg), in.Allergies,
			in.ChronicConditions, in.Medications, identity, now, now)
		if err != nil {
			if isUnique(err) && strings.Contains(err.Error(), "identity_no") {
				continue
			}
			return Pet{}, err
		}
		return s.GetPetForUser(ctx, id, ownerID)
	}
	return Pet{}, fmt.Errorf("could not allocate identity number")
}

func (s *Store) ListPetsForUser(ctx context.Context, userID string) ([]Pet, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT p.id, p.owner_user_id, p.name, p.species, p.breed, p.sex,
		p.birthday, p.birthday_estimated, p.neutered, p.avatar_path, p.current_weight_kg,
		p.allergies, p.chronic_conditions, p.medications, p.identity_no, p.status, p.version,
		p.created_at, p.updated_at,
		CASE WHEN p.owner_user_id = ? THEN 'owner' ELSE pm.role END AS role
		FROM pets p
		LEFT JOIN pet_members pm ON pm.pet_id = p.id AND pm.user_id = ? AND pm.status = 'active'
		WHERE p.deleted_at IS NULL AND (p.owner_user_id = ? OR pm.id IS NOT NULL)
		ORDER BY p.created_at DESC`, userID, userID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Pet, 0)
	for rows.Next() {
		p, err := scanPet(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *Store) GetPetForUser(ctx context.Context, petID, userID string) (Pet, error) {
	row := s.db.QueryRowContext(ctx, `SELECT p.id, p.owner_user_id, p.name, p.species, p.breed, p.sex,
		p.birthday, p.birthday_estimated, p.neutered, p.avatar_path, p.current_weight_kg,
		p.allergies, p.chronic_conditions, p.medications, p.identity_no, p.status, p.version,
		p.created_at, p.updated_at,
		CASE WHEN p.owner_user_id = ? THEN 'owner' ELSE pm.role END AS role
		FROM pets p
		LEFT JOIN pet_members pm ON pm.pet_id = p.id AND pm.user_id = ? AND pm.status = 'active'
		WHERE p.id = ? AND p.deleted_at IS NULL AND (p.owner_user_id = ? OR pm.id IS NOT NULL)`,
		userID, userID, petID, userID)
	p, err := scanPet(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Pet{}, ErrNotFound
	}
	return p, err
}

func (s *Store) UpdatePet(ctx context.Context, petID, ownerID string, in PetInput) (Pet, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE pets SET name = ?, species = ?, breed = ?, sex = ?,
		birthday = ?, birthday_estimated = ?, neutered = ?, avatar_path = ?, current_weight_kg = ?,
		allergies = ?, chronic_conditions = ?, medications = ?, version = version + 1, updated_at = ?
		WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL`,
		in.Name, in.Species, in.Breed, in.Sex, nullString(in.Birthday), in.BirthdayEstimated,
		in.Neutered, nullString(in.AvatarPath), nullFloat(in.CurrentWeightKg), in.Allergies,
		in.ChronicConditions, in.Medications, db.Now(), petID, ownerID)
	if err != nil {
		return Pet{}, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return Pet{}, ErrNotFound
	}
	return s.GetPetForUser(ctx, petID, ownerID)
}

func (s *Store) DeletePet(ctx context.Context, petID, ownerID string) error {
	now := db.Now()
	res, err := s.db.ExecContext(ctx, `UPDATE pets SET status = 'archived', deleted_at = ?, updated_at = ?
		WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL`, now, now, petID, ownerID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) RestorePet(ctx context.Context, petID, ownerID string) (Pet, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE pets SET status = 'active', deleted_at = NULL, updated_at = ?
		WHERE id = ? AND owner_user_id = ? AND deleted_at IS NOT NULL`, db.Now(), petID, ownerID)
	if err != nil {
		return Pet{}, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return Pet{}, ErrNotFound
	}
	return s.GetPetForUser(ctx, petID, ownerID)
}

func (s *Store) Audit(ctx context.Context, actorType, actorID, action, targetType, targetID, detail string) {
	if detail == "" {
		detail = "{}"
	}
	_, _ = s.db.ExecContext(ctx, `INSERT INTO audit_events(id, actor_type, actor_id, action, target_type, target_id, detail, created_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?)`, auth.NewID(), actorType, actorID, action, targetType, targetID, detail, db.Now())
}

type scanner interface {
	Scan(dest ...any) error
}

func scanPet(row scanner) (Pet, error) {
	var p Pet
	var birthday, avatar sql.NullString
	var weight sql.NullFloat64
	err := row.Scan(&p.ID, &p.OwnerUserID, &p.Name, &p.Species, &p.Breed, &p.Sex,
		&birthday, &p.BirthdayEstimated, &p.Neutered, &avatar, &weight,
		&p.Allergies, &p.ChronicConditions, &p.Medications, &p.IdentityNo, &p.Status, &p.Version,
		&p.CreatedAt, &p.UpdatedAt, &p.Role)
	if err != nil {
		return Pet{}, err
	}
	if birthday.Valid {
		p.Birthday = birthday.String
	}
	if avatar.Valid {
		p.AvatarPath = avatar.String
	}
	if weight.Valid {
		p.CurrentWeightKg = weight.Float64
	}
	return p, nil
}

func nullString(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}

func nullFloat(f float64) any {
	if f == 0 {
		return nil
	}
	return f
}

func isUnique(err error) bool {
	return err != nil && strings.Contains(strings.ToLower(err.Error()), "unique constraint")
}
