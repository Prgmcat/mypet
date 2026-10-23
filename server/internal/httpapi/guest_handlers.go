package httpapi

import (
	"crypto/subtle"
	_ "embed"
	"io"
	"net"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/Prgmcat/mypet/server/internal/auth"
	"github.com/Prgmcat/mypet/server/internal/store"
	"github.com/go-chi/chi/v5"
)

const maxGuestUploadBytes = 10 << 20

//go:embed web/guest.html
var guestPage []byte

type attemptRecord struct {
	failures    int
	lockedUntil time.Time
}

// attemptLimiter is a small in-memory lockout used by login and guest passcodes.
type attemptLimiter struct {
	mu          sync.Mutex
	m           map[string]*attemptRecord
	maxFailures int
	lockFor     time.Duration
}

func newAttemptLimiter(maxFailures int, lockFor time.Duration) *attemptLimiter {
	return &attemptLimiter{
		m:           map[string]*attemptRecord{},
		maxFailures: maxFailures,
		lockFor:     lockFor,
	}
}

func (l *attemptLimiter) locked(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	a, ok := l.m[key]
	if !ok {
		return false, 0
	}
	if time.Now().Before(a.lockedUntil) {
		return true, time.Until(a.lockedUntil)
	}
	return false, 0
}

func (l *attemptLimiter) fail(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	a, ok := l.m[key]
	if !ok {
		a = &attemptRecord{}
		l.m[key] = a
	}
	a.failures++
	if a.failures >= l.maxFailures {
		a.failures = 0
		a.lockedUntil = time.Now().Add(l.lockFor)
	}
}

func (l *attemptLimiter) reset(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.m, key)
}

func clientHost(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func (s *Server) resolveGuest(w http.ResponseWriter, r *http.Request) (store.ShareGrant, bool) {
	token := strings.TrimSpace(chi.URLParam(r, "token"))
	grant, err := s.store.ResolveShareGrant(r.Context(), token)
	if err != nil {
		writeError(w, r, http.StatusNotFound, 30010, "share link is invalid, expired or revoked")
		return store.ShareGrant{}, false
	}
	if grant.PasscodeHash == "" {
		return grant, true
	}
	key := grant.ID + "|" + clientHost(r)
	if locked, d := s.guestLimiter.locked(key); locked {
		w.Header().Set("Retry-After", strconvSeconds(d))
		writeError(w, r, http.StatusTooManyRequests, 40001, "too many attempts, try again later")
		return store.ShareGrant{}, false
	}
	passcode := strings.TrimSpace(r.Header.Get("X-Share-Passcode"))
	if passcode == "" {
		writeError(w, r, http.StatusUnauthorized, 20007, "passcode required")
		return store.ShareGrant{}, false
	}
	if subtle.ConstantTimeCompare([]byte(auth.HashToken(passcode)), []byte(grant.PasscodeHash)) != 1 {
		s.guestLimiter.fail(key)
		writeError(w, r, http.StatusUnauthorized, 20007, "invalid passcode")
		return store.ShareGrant{}, false
	}
	s.guestLimiter.reset(key)
	return grant, true
}

func strconvSeconds(d time.Duration) string {
	sec := int(d.Seconds())
	if sec < 1 {
		sec = 1
	}
	return strconv.Itoa(sec)
}

func (s *Server) guestPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	_, _ = w.Write(guestPage)
}

func (s *Server) guestPet(w http.ResponseWriter, r *http.Request) {
	grant, ok := s.resolveGuest(w, r)
	if !ok {
		return
	}
	pet, err := s.store.GetPet(r.Context(), grant.PetID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, map[string]any{
		"pet":         pet,
		"role":        grant.Role,
		"expiresAt":   grant.ExpiresAt,
		"canComplete": grant.Role == "co_caregiver",
	})
}

func (s *Server) guestReminders(w http.ResponseWriter, r *http.Request) {
	grant, ok := s.resolveGuest(w, r)
	if !ok {
		return
	}
	if err := s.store.EnsureReminders(r.Context()); err != nil {
		writeStoreError(w, r, err)
		return
	}
	reminders, err := s.store.ListRemindersForPet(r.Context(), grant.PetID, r.URL.Query().Get("status"))
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, reminders)
}

func (s *Server) guestCompleteReminder(w http.ResponseWriter, r *http.Request) {
	grant, ok := s.resolveGuest(w, r)
	if !ok {
		return
	}
	if grant.Role != "co_caregiver" {
		writeError(w, r, http.StatusForbidden, 30007, "viewer cannot complete reminders")
		return
	}
	reminderID := chi.URLParam(r, "reminderID")
	inst, err := s.store.GetReminder(r.Context(), reminderID)
	if err != nil || inst.PetID != grant.PetID {
		writeStoreError(w, r, store.ErrNotFound)
		return
	}
	reminder, err := s.store.CompleteReminder(r.Context(), reminderID, store.GuestActor(grant.ID))
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "guest", grant.ID, "complete_reminder", "reminder", reminderID, "{}")
	writeData(w, r, http.StatusOK, reminder)
}

func (s *Server) guestCreateRecord(w http.ResponseWriter, r *http.Request) {
	grant, ok := s.resolveGuest(w, r)
	if !ok {
		return
	}
	if grant.Role != "co_caregiver" {
		writeError(w, r, http.StatusForbidden, 30007, "viewer cannot create records")
		return
	}
	var in store.RecordInput
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if err := validateRecordInput(&in); err != nil {
		writeError(w, r, http.StatusBadRequest, 10002, err.Error())
		return
	}
	in.Source = "guest"
	record, err := s.store.CreateRecordAs(r.Context(), grant.PetID, in, store.GuestActor(grant.ID))
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if err := s.store.SyncReminderForRecord(r.Context(), record); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "guest", grant.ID, "create_record", "record", record.ID, "{}")
	writeData(w, r, http.StatusCreated, record)
}

func (s *Server) guestUpload(w http.ResponseWriter, r *http.Request) {
	grant, ok := s.resolveGuest(w, r)
	if !ok {
		return
	}
	if grant.Role != "co_caregiver" {
		writeError(w, r, http.StatusForbidden, 30007, "viewer cannot upload photos")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxGuestUploadBytes+1<<20)
	if err := r.ParseMultipartForm(maxGuestUploadBytes); err != nil {
		writeError(w, r, http.StatusBadRequest, 10003, "file is too large or invalid multipart form")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, r, http.StatusBadRequest, 10004, "file field is required")
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxGuestUploadBytes+1))
	if err != nil {
		writeError(w, r, http.StatusBadRequest, 10005, "could not read file")
		return
	}
	if len(data) > maxGuestUploadBytes {
		writeError(w, r, http.StatusRequestEntityTooLarge, 10006, "file exceeds 10 MB")
		return
	}
	mime := http.DetectContentType(data)
	switch mime {
	case "image/jpeg", "image/png", "image/webp":
	default:
		writeError(w, r, http.StatusBadRequest, 10007, "only JPEG, PNG or WebP are allowed")
		return
	}
	recordID := strings.TrimSpace(r.FormValue("recordId"))
	if recordID != "" {
		record, err := s.store.GetRecord(r.Context(), recordID)
		if err != nil || record.PetID != grant.PetID {
			writeError(w, r, http.StatusBadRequest, 10008, "record does not belong to this pet")
			return
		}
	}
	attachment, err := s.store.SaveAttachment(r.Context(), grant.PetID, recordID, filepath.Base(header.Filename), mime, data)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "guest", grant.ID, "upload_attachment", "attachment", attachment.ID, "{}")
	writeData(w, r, http.StatusCreated, attachment)
}
