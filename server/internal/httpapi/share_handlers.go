package httpapi

import (
	"errors"
	"net/http"
	"regexp"
	"strings"

	"github.com/Prgmcat/mypet/server/internal/store"
	"github.com/go-chi/chi/v5"
)

var passcodePattern = regexp.MustCompile(`^[0-9]{4}$`)

func (s *Server) requirePetOwner(w http.ResponseWriter, r *http.Request) (store.Pet, bool) {
	pet, err := s.store.GetPetForUser(r.Context(), chi.URLParam(r, "petID"), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return store.Pet{}, false
	}
	if pet.Role != "owner" {
		writeError(w, r, http.StatusForbidden, 30007, "only the owner can manage sharing")
		return store.Pet{}, false
	}
	return pet, true
}

func (s *Server) listMembers(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requirePetOwner(w, r)
	if !ok {
		return
	}
	members, err := s.store.ListMembers(r.Context(), pet.ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, members)
}

func (s *Server) addMember(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requirePetOwner(w, r)
	if !ok {
		return
	}
	var body struct {
		Username string `json:"username"`
		Role     string `json:"role"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	body.Username = strings.TrimSpace(body.Username)
	if body.Username == "" {
		writeError(w, r, http.StatusBadRequest, 10002, "username is required")
		return
	}
	if body.Role == "" {
		body.Role = "viewer"
	}
	if body.Role != "viewer" && body.Role != "co_caregiver" {
		writeError(w, r, http.StatusBadRequest, 10002, "role must be viewer or co_caregiver")
		return
	}
	member, err := s.store.AddMember(r.Context(), pet.ID, pet.OwnerUserID, body.Username, body.Role)
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, r, http.StatusNotFound, 30008, "user not found")
		return
	case errors.Is(err, store.ErrSelfMember):
		writeError(w, r, http.StatusBadRequest, 30009, "cannot invite the pet owner")
		return
	case err != nil:
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "add_member", "pet", pet.ID, "{}")
	writeData(w, r, http.StatusCreated, member)
}

func (s *Server) removeMember(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requirePetOwner(w, r)
	if !ok {
		return
	}
	memberID := chi.URLParam(r, "userID")
	if err := s.store.RemoveMember(r.Context(), pet.ID, memberID); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "remove_member", "pet", pet.ID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) listShareGrants(w http.ResponseWriter, r *http.Request) {
	grants, err := s.store.ListShareGrants(r.Context(), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, grants)
}

func (s *Server) createShareGrant(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requirePetOwner(w, r)
	if !ok {
		return
	}
	var body struct {
		Role     string `json:"role"`
		TTLDays  int    `json:"ttlDays"`
		Passcode string `json:"passcode"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if body.Role == "" {
		body.Role = "viewer"
	}
	if body.Role != "viewer" && body.Role != "co_caregiver" {
		writeError(w, r, http.StatusBadRequest, 10002, "role must be viewer or co_caregiver")
		return
	}
	if body.TTLDays <= 0 {
		body.TTLDays = 7
	}
	if body.TTLDays < 1 || body.TTLDays > 30 {
		writeError(w, r, http.StatusBadRequest, 10002, "ttlDays must be between 1 and 30")
		return
	}
	body.Passcode = strings.TrimSpace(body.Passcode)
	if body.Passcode != "" && !passcodePattern.MatchString(body.Passcode) {
		writeError(w, r, http.StatusBadRequest, 10002, "passcode must be 4 digits")
		return
	}
	grant, err := s.store.CreateShareGrant(r.Context(), pet.ID, currentUser(r).ID, body.Role, body.TTLDays, body.Passcode)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "create_share_grant", "share_grant", grant.ID, "{}")
	writeData(w, r, http.StatusCreated, grant)
}

func (s *Server) revokeShareGrant(w http.ResponseWriter, r *http.Request) {
	grantID := chi.URLParam(r, "grantID")
	if err := s.store.RevokeShareGrant(r.Context(), grantID, currentUser(r).ID); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "revoke_share_grant", "share_grant", grantID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}
