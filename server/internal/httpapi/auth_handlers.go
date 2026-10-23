package httpapi

import (
	"errors"
	"net"
	"net/http"
	"strings"
	"time"
	"unicode"

	"github.com/Prgmcat/mypet/server/internal/auth"
	"github.com/Prgmcat/mypet/server/internal/store"
	"github.com/go-chi/chi/v5"
)

func (s *Server) setup(w http.ResponseWriter, r *http.Request) {
	if !isLoopback(r.RemoteAddr) {
		writeError(w, r, http.StatusForbidden, 20004, "setup is only allowed from localhost")
		return
	}
	n, err := s.store.CountUsers(r.Context())
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, 50001, "database error")
		return
	}
	if n > 0 {
		writeError(w, r, http.StatusConflict, 30001, "already initialized")
		return
	}
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if !validUsername(body.Username) || !validPassword(body.Password) {
		writeError(w, r, http.StatusBadRequest, 10002, "username or password does not meet requirements")
		return
	}
	hash, err := auth.HashPassword(body.Password)
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, 50002, "password hashing failed")
		return
	}
	u, err := s.store.CreateAdmin(r.Context(), body.Username, hash)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "admin", u.ID, "setup", "user", u.ID, "{}")
	writeData(w, r, http.StatusCreated, u)
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	var body struct {
		InviteCode  string `json:"inviteCode"`
		Username    string `json:"username"`
		Password    string `json:"password"`
		DisplayName string `json:"displayName"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if strings.TrimSpace(body.InviteCode) == "" || !validUsername(body.Username) || !validPassword(body.Password) {
		writeError(w, r, http.StatusBadRequest, 10002, "invalid invite code, username or password")
		return
	}
	hash, err := auth.HashPassword(body.Password)
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, 50002, "password hashing failed")
		return
	}
	display := strings.TrimSpace(body.DisplayName)
	if display == "" {
		display = body.Username
	}
	u, err := s.store.CreateUserWithInvite(r.Context(), auth.HashToken(strings.ToUpper(strings.TrimSpace(body.InviteCode))), body.Username, hash, display)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", u.ID, "register", "user", u.ID, "{}")
	writeData(w, r, http.StatusCreated, u)
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username   string `json:"username"`
		Password   string `json:"password"`
		DeviceName string `json:"deviceName"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	username := strings.TrimSpace(body.Username)
	limitKey := strings.ToLower(username) + "|" + clientHost(r)
	if locked, d := s.loginLimiter.locked(limitKey); locked {
		w.Header().Set("Retry-After", strconvSeconds(d))
		writeError(w, r, http.StatusTooManyRequests, 40002, "too many failed attempts, try again later")
		return
	}
	u, hash, err := s.store.FindUserByUsername(r.Context(), username)
	if err != nil || !auth.VerifyPassword(hash, body.Password) || u.Status != "active" {
		s.loginLimiter.fail(limitKey)
		writeError(w, r, http.StatusUnauthorized, 20005, "invalid username or password")
		return
	}
	s.loginLimiter.reset(limitKey)
	deviceName := strings.TrimSpace(body.DeviceName)
	if deviceName == "" {
		deviceName = "Android"
	}
	plain, tokenHash, err := auth.NewToken()
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, 50003, "token generation failed")
		return
	}
	d, err := s.store.CreateDevice(r.Context(), u.ID, deviceName, tokenHash)
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, 50004, "device creation failed")
		return
	}
	s.store.Audit(r.Context(), "user", u.ID, "login", "device", d.ID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{
		"token":  plain,
		"user":   u,
		"device": d,
	})
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	writeData(w, r, http.StatusOK, map[string]any{"user": currentUser(r), "device": currentDevice(r)})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	u, d := currentUser(r), currentDevice(r)
	if err := s.store.RevokeDevice(r.Context(), d.ID, u.ID); err != nil && !errors.Is(err, store.ErrNotFound) {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", u.ID, "logout", "device", d.ID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) changePassword(w http.ResponseWriter, r *http.Request) {
	var body struct {
		OldPassword string `json:"oldPassword"`
		NewPassword string `json:"newPassword"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if !validPassword(body.NewPassword) {
		writeError(w, r, http.StatusBadRequest, 10002, "new password does not meet requirements")
		return
	}
	u, hash, err := s.store.FindUserByUsername(r.Context(), currentUser(r).Username)
	if err != nil || !auth.VerifyPassword(hash, body.OldPassword) {
		writeError(w, r, http.StatusBadRequest, 30002, "old password is incorrect")
		return
	}
	newHash, err := auth.HashPassword(body.NewPassword)
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, 50002, "password hashing failed")
		return
	}
	if err := s.store.UpdatePassword(r.Context(), u.ID, newHash, currentDevice(r).ID); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", u.ID, "change_password", "user", u.ID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) resetPassword(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username    string `json:"username"`
		Code        string `json:"code"`
		NewPassword string `json:"newPassword"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if !validPassword(body.NewPassword) {
		writeError(w, r, http.StatusBadRequest, 10002, "new password does not meet requirements")
		return
	}
	hash, err := auth.HashPassword(body.NewPassword)
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, 50002, "password hashing failed")
		return
	}
	err = s.store.ResetPasswordWithCode(r.Context(), strings.TrimSpace(body.Username), auth.HashToken(strings.TrimSpace(body.Code)), hash)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) listDevices(w http.ResponseWriter, r *http.Request) {
	devices, err := s.store.ListDevices(r.Context(), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, devices)
}

func (s *Server) revokeDevice(w http.ResponseWriter, r *http.Request) {
	deviceID := chi.URLParam(r, "deviceID")
	if err := s.store.RevokeDevice(r.Context(), deviceID, currentUser(r).ID); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "revoke_device", "device", deviceID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) adminListDevices(w http.ResponseWriter, r *http.Request) {
	devices, err := s.store.ListAllDevices(r.Context())
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, devices)
}

func (s *Server) adminRevokeDevice(w http.ResponseWriter, r *http.Request) {
	deviceID := chi.URLParam(r, "deviceID")
	if err := s.store.RevokeDeviceAsAdmin(r.Context(), deviceID); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "admin", currentUser(r).ID, "admin_revoke_device", "device", deviceID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) adminListUsers(w http.ResponseWriter, r *http.Request) {
	users, err := s.store.ListUsers(r.Context())
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, users)
}

func (s *Server) adminSetUserStatus(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Status string `json:"status"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if body.Status != "active" && body.Status != "disabled" {
		writeError(w, r, http.StatusBadRequest, 10002, "status must be active or disabled")
		return
	}
	userID := chi.URLParam(r, "userID")
	if err := s.store.SetUserStatus(r.Context(), userID, body.Status); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "admin", currentUser(r).ID, "set_user_status", "user", userID, `{"status":"`+body.Status+`"}`)
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) adminCreateResetCode(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "userID")
	u, err := s.store.UserByID(r.Context(), userID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	code, err := s.store.CreateResetCode(r.Context(), currentUser(r).ID, u.Username, 15*time.Minute)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "admin", currentUser(r).ID, "create_reset_code", "user", userID, "{}")
	writeData(w, r, http.StatusCreated, map[string]any{"code": code, "expiresInMinutes": 15})
}

func (s *Server) adminListInvites(w http.ResponseWriter, r *http.Request) {
	invites, err := s.store.ListInvites(r.Context())
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, invites)
}

func (s *Server) adminRevokeInvite(w http.ResponseWriter, r *http.Request) {
	inviteID := chi.URLParam(r, "inviteID")
	if err := s.store.RevokeInvite(r.Context(), inviteID); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "admin", currentUser(r).ID, "revoke_invite", "invite", inviteID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) adminCreateInvite(w http.ResponseWriter, r *http.Request) {
	var body struct {
		MaxUses  int `json:"maxUses"`
		TTLHours int `json:"ttlHours"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if body.MaxUses <= 0 {
		body.MaxUses = 1
	}
	if body.TTLHours <= 0 {
		body.TTLHours = 168
	}
	code, expires, err := s.store.CreateInvite(r.Context(), currentUser(r).ID, body.MaxUses, time.Duration(body.TTLHours)*time.Hour)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "admin", currentUser(r).ID, "create_invite", "invite", "", "{}")
	writeData(w, r, http.StatusCreated, map[string]any{"code": code, "expiresAt": expires})
}

func isLoopback(remoteAddr string) bool {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		host = remoteAddr
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func validUsername(s string) bool {
	s = strings.TrimSpace(s)
	if len(s) < 4 || len(s) > 20 {
		return false
	}
	for _, r := range s {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_' {
			return false
		}
	}
	return true
}

func validPassword(s string) bool {
	if len(s) < 8 || len(s) > 32 {
		return false
	}
	var hasLetter, hasDigit bool
	for _, r := range s {
		if unicode.IsLetter(r) {
			hasLetter = true
		}
		if unicode.IsDigit(r) {
			hasDigit = true
		}
	}
	return hasLetter && hasDigit
}

func writeStoreError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, r, http.StatusNotFound, 30003, "not found")
	case errors.Is(err, store.ErrConflict):
		writeError(w, r, http.StatusConflict, 30004, "username already exists")
	case errors.Is(err, store.ErrInvalidInvite):
		writeError(w, r, http.StatusBadRequest, 30005, "invite code is invalid, expired or used")
	case errors.Is(err, store.ErrInvalidCode):
		writeError(w, r, http.StatusBadRequest, 30006, "reset code is invalid or expired")
	case errors.Is(err, store.ErrForbidden):
		writeError(w, r, http.StatusForbidden, 30007, "forbidden")
	default:
		writeError(w, r, http.StatusInternalServerError, 50000, "internal server error")
	}
}
