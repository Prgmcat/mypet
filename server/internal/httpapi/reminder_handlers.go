package httpapi

import (
	"net/http"
	"sort"
	"time"

	"github.com/Prgmcat/mypet/server/internal/store"
	"github.com/go-chi/chi/v5"
)

func (s *Server) listReminders(w http.ResponseWriter, r *http.Request) {
	if err := s.store.EnsureReminders(r.Context()); err != nil {
		writeStoreError(w, r, err)
		return
	}
	status := r.URL.Query().Get("status")
	switch status {
	case "", "pending", "done", "skipped", "all":
	default:
		writeError(w, r, http.StatusBadRequest, 10002, "status must be pending, done, skipped or all")
		return
	}
	reminders, err := s.store.ListReminders(r.Context(), currentUser(r).ID, status)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, reminders)
}

func (s *Server) updateReminder(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Action      string `json:"action"`
		SnoozeHours int    `json:"snoozeHours"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	id := chi.URLParam(r, "reminderID")
	switch body.Action {
	case "complete":
		inst, err := s.store.GetReminderForUser(r.Context(), id, currentUser(r).ID)
		if err != nil {
			writeStoreError(w, r, err)
			return
		}
		if inst.Role == "viewer" {
			writeError(w, r, http.StatusForbidden, 30007, "viewer cannot complete reminders")
			return
		}
		reminder, err := s.store.CompleteReminder(r.Context(), id, store.UserActor(currentUser(r).ID))
		if err != nil {
			writeStoreError(w, r, err)
			return
		}
		s.store.Audit(r.Context(), "user", currentUser(r).ID, "complete_reminder", "reminder", id, "{}")
		writeData(w, r, http.StatusOK, reminder)
	case "snooze":
		hours := body.SnoozeHours
		if hours <= 0 {
			hours = 24
		}
		if hours > 168 {
			hours = 168
		}
		until := time.Now().UTC().Add(time.Duration(hours) * time.Hour).Format(time.RFC3339)
		reminder, err := s.store.SnoozeReminder(r.Context(), id, currentUser(r).ID, until)
		if err != nil {
			writeStoreError(w, r, err)
			return
		}
		s.store.Audit(r.Context(), "user", currentUser(r).ID, "snooze_reminder", "reminder", id, "{}")
		writeData(w, r, http.StatusOK, reminder)
	case "skip":
		reminder, err := s.store.SkipReminder(r.Context(), id, currentUser(r).ID)
		if err != nil {
			writeStoreError(w, r, err)
			return
		}
		s.store.Audit(r.Context(), "user", currentUser(r).ID, "skip_reminder", "reminder", id, "{}")
		writeData(w, r, http.StatusOK, reminder)
	default:
		writeError(w, r, http.StatusBadRequest, 10002, "action must be complete, snooze or skip")
	}
}

func (s *Server) listReminderRules(w http.ResponseWriter, r *http.Request) {
	rules, err := s.store.ListReminderRules(r.Context(), chi.URLParam(r, "petID"), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, rules)
}

func (s *Server) updateReminderRule(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Enabled        *bool  `json:"enabled"`
		IntervalDays   *int   `json:"intervalDays"`
		AdvanceOffsets *[]int `json:"advanceOffsets"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if body.IntervalDays != nil && (*body.IntervalDays <= 0 || *body.IntervalDays > 3650) {
		writeError(w, r, http.StatusBadRequest, 10002, "intervalDays must be between 1 and 3650")
		return
	}
	if body.AdvanceOffsets != nil {
		if len(*body.AdvanceOffsets) == 0 || len(*body.AdvanceOffsets) > 6 {
			writeError(w, r, http.StatusBadRequest, 10002, "advanceOffsets must contain 1 to 6 values")
			return
		}
		seen := map[int]bool{}
		clean := make([]int, 0, len(*body.AdvanceOffsets))
		for _, offset := range *body.AdvanceOffsets {
			if offset < 0 || offset > 365 || seen[offset] {
				writeError(w, r, http.StatusBadRequest, 10002, "advanceOffsets must be unique values between 0 and 365")
				return
			}
			seen[offset] = true
			clean = append(clean, offset)
		}
		sort.Sort(sort.Reverse(sort.IntSlice(clean)))
		body.AdvanceOffsets = &clean
	}
	rule, err := s.store.UpdateReminderRule(r.Context(), chi.URLParam(r, "ruleID"), currentUser(r).ID,
		body.Enabled, body.IntervalDays, body.AdvanceOffsets)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "update_reminder_rule", "reminder_rule", rule.ID, "{}")
	writeData(w, r, http.StatusOK, rule)
}
