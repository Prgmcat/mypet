package store

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/Prgmcat/mypet/server/internal/auth"
	"github.com/Prgmcat/mypet/server/internal/db"
)

var (
	ErrInvalidRole = errors.New("invalid role")
	ErrSelfMember  = errors.New("cannot invite the owner")
)

type PetMember struct {
	ID          string `json:"id"`
	PetID       string `json:"petId"`
	UserID      string `json:"userId"`
	Username    string `json:"username"`
	DisplayName string `json:"displayName"`
	Role        string `json:"role"`
	Status      string `json:"status"`
	JoinedAt    string `json:"joinedAt"`
}

type ShareGrant struct {
	ID           string `json:"id"`
	PetID        string `json:"petId"`
	PetName      string `json:"petName,omitempty"`
	Role         string `json:"role"`
	ExpiresAt    string `json:"expiresAt"`
	HasPasscode  bool   `json:"hasPasscode"`
	Status       string `json:"status"`
	CreatedAt    string `json:"createdAt"`
	RevokedAt    string `json:"revokedAt,omitempty"`
	Token        string `json:"token,omitempty"`
	PasscodeHash string `json:"-"`
}

func validShareRole(role string) bool { return role == "viewer" || role == "co_caregiver" }

func (s *Store) ListMembers(ctx context.Context, petID string) ([]PetMember, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT m.id, m.pet_id, m.user_id, u.username, u.display_name, m.role, m.status, m.joined_at
		FROM pet_members m JOIN users u ON u.id = m.user_id
		WHERE m.pet_id = ? AND m.status = 'active' ORDER BY m.joined_at ASC`, petID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]PetMember, 0)
	for rows.Next() {
		var m PetMember
		if err := rows.Scan(&m.ID, &m.PetID, &m.UserID, &m.Username, &m.DisplayName, &m.Role, &m.Status, &m.JoinedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (s *Store) AddMember(ctx context.Context, petID, petOwnerID, username, role string) (PetMember, error) {
	if !validShareRole(role) {
		return PetMember{}, ErrInvalidRole
	}
	u, _, err := s.FindUserByUsername(ctx, username)
	if err != nil {
		return PetMember{}, err
	}
	if u.ID == petOwnerID {
		return PetMember{}, ErrSelfMember
	}
	now := db.Now()
	id := auth.NewID()
	_, err = s.db.ExecContext(ctx, `INSERT INTO pet_members(id, pet_id, user_id, role, status, invited_by_user_id, joined_at)
		VALUES(?, ?, ?, ?, 'active', ?, ?)
		ON CONFLICT(pet_id, user_id) DO UPDATE SET role = excluded.role, status = 'active',
			invited_by_user_id = excluded.invited_by_user_id, joined_at = excluded.joined_at`,
		id, petID, u.ID, role, petOwnerID, now)
	if err != nil {
		return PetMember{}, err
	}
	var m PetMember
	err = s.db.QueryRowContext(ctx, `SELECT m.id, m.pet_id, m.user_id, u.username, u.display_name, m.role, m.status, m.joined_at
		FROM pet_members m JOIN users u ON u.id = m.user_id WHERE m.pet_id = ? AND m.user_id = ?`, petID, u.ID).
		Scan(&m.ID, &m.PetID, &m.UserID, &m.Username, &m.DisplayName, &m.Role, &m.Status, &m.JoinedAt)
	return m, err
}

func (s *Store) RemoveMember(ctx context.Context, petID, userID string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE pet_members SET status = 'removed' WHERE pet_id = ? AND user_id = ? AND status = 'active'`,
		petID, userID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) CreateShareGrant(ctx context.Context, petID, creatorID, role string, ttlDays int, passcode string) (ShareGrant, error) {
	if !validShareRole(role) {
		return ShareGrant{}, ErrInvalidRole
	}
	plain, hash, err := auth.NewToken()
	if err != nil {
		return ShareGrant{}, err
	}
	var passHash any
	if passcode != "" {
		passHash = auth.HashToken(passcode)
	}
	now := db.Now()
	expires := time.Now().UTC().AddDate(0, 0, ttlDays).Format(time.RFC3339)
	g := ShareGrant{
		ID: auth.NewID(), PetID: petID, Role: role, ExpiresAt: expires,
		HasPasscode: passcode != "", Status: "active", CreatedAt: now, Token: plain,
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO share_grants(
		id, pet_id, created_by_user_id, token_hash, role, expires_at, passcode_hash, status, created_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, 'active', ?)`,
		g.ID, petID, creatorID, hash, role, expires, passHash, now)
	if err != nil {
		return ShareGrant{}, err
	}
	return g, nil
}

func (s *Store) ListShareGrants(ctx context.Context, userID string) ([]ShareGrant, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT g.id, g.pet_id, p.name, g.role, g.expires_at,
		CASE WHEN g.passcode_hash IS NULL OR g.passcode_hash = '' THEN 0 ELSE 1 END,
		CASE WHEN g.status = 'active' AND g.expires_at <= ? THEN 'expired' ELSE g.status END,
		g.created_at, COALESCE(g.revoked_at, '')
		FROM share_grants g JOIN pets p ON p.id = g.pet_id
		WHERE g.created_by_user_id = ? ORDER BY g.created_at DESC`, db.Now(), userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]ShareGrant, 0)
	for rows.Next() {
		var g ShareGrant
		var hasPasscode int
		if err := rows.Scan(&g.ID, &g.PetID, &g.PetName, &g.Role, &g.ExpiresAt, &hasPasscode, &g.Status, &g.CreatedAt, &g.RevokedAt); err != nil {
			return nil, err
		}
		g.HasPasscode = hasPasscode == 1
		out = append(out, g)
	}
	return out, rows.Err()
}

func (s *Store) RevokeShareGrant(ctx context.Context, grantID, ownerID string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE share_grants SET status = 'revoked', revoked_at = ?
		WHERE id = ? AND status = 'active'
		AND pet_id IN (SELECT id FROM pets WHERE owner_user_id = ?)`, db.Now(), grantID, ownerID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// ResolveShareGrant validates a guest token and its lifetime.
func (s *Store) ResolveShareGrant(ctx context.Context, token string) (ShareGrant, error) {
	var g ShareGrant
	var passHash sql.NullString
	err := s.db.QueryRowContext(ctx, `SELECT g.id, g.pet_id, p.name, g.role, g.expires_at,
		COALESCE(g.passcode_hash, ''), g.status, g.created_at, COALESCE(g.revoked_at, '')
		FROM share_grants g JOIN pets p ON p.id = g.pet_id AND p.deleted_at IS NULL
		WHERE g.token_hash = ? AND g.status = 'active' AND g.expires_at > ?`,
		auth.HashToken(token), db.Now()).
		Scan(&g.ID, &g.PetID, &g.PetName, &g.Role, &g.ExpiresAt, &passHash, &g.Status, &g.CreatedAt, &g.RevokedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return ShareGrant{}, ErrNotFound
	}
	if err != nil {
		return ShareGrant{}, err
	}
	if passHash.Valid {
		g.PasscodeHash = passHash.String
		g.HasPasscode = passHash.String != ""
	}
	return g, nil
}

// GetPet loads a pet without user scoping. Callers must already have verified
// a guest grant or member relationship.
func (s *Store) GetPet(ctx context.Context, petID string) (Pet, error) {
	row := s.db.QueryRowContext(ctx, `SELECT p.id, p.owner_user_id, p.name, p.species, p.breed, p.sex,
		p.birthday, p.birthday_estimated, p.neutered, p.avatar_path, p.current_weight_kg,
		p.allergies, p.chronic_conditions, p.medications, p.identity_no, p.status, p.version,
		p.created_at, p.updated_at, '' AS role
		FROM pets p WHERE p.id = ? AND p.deleted_at IS NULL`, petID)
	p, err := scanPet(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Pet{}, ErrNotFound
	}
	return p, err
}

// ListRemindersForPet lists reminder instances for a guest-visible pet.
func (s *Store) ListRemindersForPet(ctx context.Context, petID, status string) ([]ReminderInstance, error) {
	query := `SELECT i.id, i.rule_id, i.pet_id, i.occurrence_key, i.due_at, i.status,
		COALESCE(i.snoozed_until,''), COALESCE(i.completed_at,''), COALESCE(i.record_id,''),
		p.name, r.type, r.advance_offsets, ''
		FROM reminder_instances i
		JOIN pets p ON p.id = i.pet_id
		JOIN reminder_rules r ON r.id = i.rule_id
		WHERE i.pet_id = ?`
	args := []any{petID}
	if status == "done" || status == "skipped" || status == "all" {
		if status != "all" {
			query += ` AND i.status = ?`
			args = append(args, status)
		}
		query += ` ORDER BY i.due_at DESC LIMIT 200`
	} else {
		query += ` AND i.status IN ('pending','snoozed') ORDER BY i.due_at ASC LIMIT 200`
	}
	rows, err := s.db.QueryContext(ctx, query, args...)
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
