package httpapi

import (
	"errors"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/Prgmcat/mypet/server/internal/store"
	"github.com/go-chi/chi/v5"
)

var validAppointmentTypes = map[string]bool{
	"vaccine":    true,
	"deworming":  true,
	"checkup":    true,
	"medical":    true,
	"medication": true,
	"grooming":   true,
	"other":      true,
}

func (s *Server) listAppointments(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	if !validAppointmentStatus(status) {
		writeError(w, r, http.StatusBadRequest, 10002, "status must be pending, done, skipped or all")
		return
	}
	appointments, err := s.store.ListAppointments(r.Context(), currentUser(r).ID, "", status)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, appointments)
}

func (s *Server) listPetAppointments(w http.ResponseWriter, r *http.Request) {
	pet, err := s.store.GetPetForUser(r.Context(), chi.URLParam(r, "petID"), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	status := r.URL.Query().Get("status")
	if !validAppointmentStatus(status) {
		writeError(w, r, http.StatusBadRequest, 10002, "status must be pending, done, skipped or all")
		return
	}
	appointments, err := s.store.ListAppointments(r.Context(), currentUser(r).ID, pet.ID, status)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, appointments)
}

func (s *Server) createAppointment(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requireRecordWrite(w, r)
	if !ok {
		return
	}
	var in store.AppointmentInput
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if err := validateAppointmentInput(&in); err != nil {
		writeError(w, r, http.StatusBadRequest, 10002, err.Error())
		return
	}
	appointment, err := s.store.CreateAppointment(r.Context(), pet.ID, store.UserActor(currentUser(r).ID), in)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "create_appointment", "appointment", appointment.ID, "{}")
	writeData(w, r, http.StatusCreated, appointment)
}

func (s *Server) updateAppointment(w http.ResponseWriter, r *http.Request) {
	appointment, ok := s.requireAppointmentWrite(w, r)
	if !ok {
		return
	}
	var body struct {
		Type           *string `json:"type"`
		Title          *string `json:"title"`
		ScheduledAt    *string `json:"scheduledAt"`
		Note           *string `json:"note"`
		AdvanceOffsets *[]int  `json:"advanceOffsets"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if body.Type != nil {
		value := strings.TrimSpace(*body.Type)
		if !validAppointmentTypes[value] {
			writeError(w, r, http.StatusBadRequest, 10002, "invalid appointment type")
			return
		}
		body.Type = &value
	}
	if body.Title != nil {
		value := strings.TrimSpace(*body.Title)
		if value == "" || len([]rune(value)) > 60 {
			writeError(w, r, http.StatusBadRequest, 10002, "title is required and must be at most 60 characters")
			return
		}
		body.Title = &value
	}
	if body.ScheduledAt != nil {
		value := strings.TrimSpace(*body.ScheduledAt)
		if !validDate(value) {
			writeError(w, r, http.StatusBadRequest, 10002, "scheduledAt must be YYYY-MM-DD")
			return
		}
		body.ScheduledAt = &value
	}
	if body.Note != nil {
		value := strings.TrimSpace(*body.Note)
		if len([]rune(value)) > 2000 {
			writeError(w, r, http.StatusBadRequest, 10002, "note must be at most 2000 characters")
			return
		}
		body.Note = &value
	}
	if body.AdvanceOffsets != nil {
		clean, err := normalizeOffsets(*body.AdvanceOffsets)
		if err != nil {
			writeError(w, r, http.StatusBadRequest, 10002, err.Error())
			return
		}
		body.AdvanceOffsets = &clean
	}
	patch := store.AppointmentPatch{
		Type:           body.Type,
		Title:          body.Title,
		ScheduledAt:    body.ScheduledAt,
		Note:           body.Note,
		AdvanceOffsets: body.AdvanceOffsets,
	}
	updated, err := s.store.UpdateAppointment(r.Context(), appointment.ID, patch)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "update_appointment", "appointment", updated.ID, "{}")
	writeData(w, r, http.StatusOK, updated)
}

func (s *Server) deleteAppointment(w http.ResponseWriter, r *http.Request) {
	appointment, ok := s.requireAppointmentWrite(w, r)
	if !ok {
		return
	}
	if err := s.store.DeleteAppointment(r.Context(), appointment.ID); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "delete_appointment", "appointment", appointment.ID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) completeAppointment(w http.ResponseWriter, r *http.Request) {
	appointment, ok := s.requireAppointmentWrite(w, r)
	if !ok {
		return
	}
	done, err := s.store.CompleteAppointment(r.Context(), appointment.ID, store.UserActor(currentUser(r).ID))
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "complete_appointment", "appointment", done.ID, "{}")
	writeData(w, r, http.StatusOK, done)
}

func (s *Server) skipAppointment(w http.ResponseWriter, r *http.Request) {
	appointment, ok := s.requireAppointmentWrite(w, r)
	if !ok {
		return
	}
	skipped, err := s.store.SkipAppointment(r.Context(), appointment.ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "skip_appointment", "appointment", skipped.ID, "{}")
	writeData(w, r, http.StatusOK, skipped)
}

func (s *Server) snoozeAppointment(w http.ResponseWriter, r *http.Request) {
	appointment, ok := s.requireAppointmentWrite(w, r)
	if !ok {
		return
	}
	var body struct {
		Hours int `json:"hours"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	hours := body.Hours
	if hours <= 0 {
		hours = 24
	}
	if hours > 168 {
		hours = 168
	}
	until := time.Now().UTC().Add(time.Duration(hours) * time.Hour).Format(time.RFC3339)
	snoozed, err := s.store.SnoozeAppointment(r.Context(), appointment.ID, until)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "snooze_appointment", "appointment", snoozed.ID, "{}")
	writeData(w, r, http.StatusOK, snoozed)
}

func (s *Server) requireAppointmentWrite(w http.ResponseWriter, r *http.Request) (store.Appointment, bool) {
	appointment, err := s.store.GetAppointmentForUser(r.Context(), chi.URLParam(r, "appointmentID"), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return store.Appointment{}, false
	}
	if appointment.Role != "owner" && appointment.Role != "co_caregiver" {
		writeError(w, r, http.StatusForbidden, 30007, "no permission to change appointments")
		return store.Appointment{}, false
	}
	if appointment.Status == "done" || appointment.Status == "skipped" {
		writeError(w, r, http.StatusConflict, 30008, "appointment is already handled")
		return store.Appointment{}, false
	}
	return appointment, true
}

func validAppointmentStatus(status string) bool {
	switch status {
	case "", "pending", "done", "skipped", "all":
		return true
	default:
		return false
	}
}

func validateAppointmentInput(in *store.AppointmentInput) error {
	in.Type = strings.TrimSpace(in.Type)
	in.Title = strings.TrimSpace(in.Title)
	in.ScheduledAt = strings.TrimSpace(in.ScheduledAt)
	in.Note = strings.TrimSpace(in.Note)
	if !validAppointmentTypes[in.Type] {
		return errors.New("invalid appointment type")
	}
	if in.Title == "" || len([]rune(in.Title)) > 60 {
		return errors.New("title is required and must be at most 60 characters")
	}
	if !validDate(in.ScheduledAt) {
		return errors.New("scheduledAt must be YYYY-MM-DD")
	}
	if len([]rune(in.Note)) > 2000 {
		return errors.New("note must be at most 2000 characters")
	}
	if len(in.AdvanceOffsets) > 0 {
		clean, err := normalizeOffsets(in.AdvanceOffsets)
		if err != nil {
			return err
		}
		in.AdvanceOffsets = clean
	}
	return nil
}

func normalizeOffsets(values []int) ([]int, error) {
	if len(values) == 0 || len(values) > 6 {
		return nil, errors.New("advanceOffsets must contain 1 to 6 values")
	}
	seen := map[int]bool{}
	clean := make([]int, 0, len(values))
	for _, offset := range values {
		if offset < 0 || offset > 365 || seen[offset] {
			return nil, errors.New("advanceOffsets must be unique values between 0 and 365")
		}
		seen[offset] = true
		clean = append(clean, offset)
	}
	sort.Sort(sort.Reverse(sort.IntSlice(clean)))
	return clean, nil
}
