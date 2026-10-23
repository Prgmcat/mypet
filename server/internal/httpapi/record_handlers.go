package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/Prgmcat/mypet/server/internal/store"
	"github.com/go-chi/chi/v5"
)

const maxUploadBytes = 20 << 20

func (s *Server) listRecords(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requireRecordRead(w, r)
	if !ok {
		return
	}
	records, err := s.store.ListRecords(r.Context(), pet.ID, r.URL.Query().Get("type"))
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, records)
}

func (s *Server) createRecord(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requireRecordWrite(w, r)
	if !ok {
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
	record, err := s.store.CreateRecord(r.Context(), pet.ID, currentUser(r).ID, in)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if err := s.store.SyncReminderForRecord(r.Context(), record); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "create_record", "record", record.ID, "{}")
	writeData(w, r, http.StatusCreated, record)
}

func (s *Server) updateRecord(w http.ResponseWriter, r *http.Request) {
	recordID := chi.URLParam(r, "recordID")
	record, pet, ok := s.requireRecordEdit(w, r, recordID)
	if !ok {
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
	updated, err := s.store.UpdateRecord(r.Context(), record.ID, in)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if record.Type != updated.Type {
		if err := s.store.RecalculateReminder(r.Context(), record.PetID, record.Type); err != nil {
			writeStoreError(w, r, err)
			return
		}
	}
	if err := s.store.SyncReminderForRecord(r.Context(), updated); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "update_record", "record", record.ID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"record": updated, "petId": pet.ID})
}

func (s *Server) deleteRecord(w http.ResponseWriter, r *http.Request) {
	record, _, ok := s.requireRecordEdit(w, r, chi.URLParam(r, "recordID"))
	if !ok {
		return
	}
	if err := s.store.DeleteRecord(r.Context(), record.ID); err != nil {
		writeStoreError(w, r, err)
		return
	}
	if err := s.store.RecalculateReminder(r.Context(), record.PetID, record.Type); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "delete_record", "record", record.ID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) restoreRecord(w http.ResponseWriter, r *http.Request) {
	// Restore is only used by the owner from the record's pet page; resolve the
	// record first, then verify ownership of its pet.
	recordID := chi.URLParam(r, "recordID")
	petID, err := s.store.PetIDForRecord(r.Context(), recordID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	pet, err := s.store.GetPetForUser(r.Context(), petID, currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if pet.Role != "owner" {
		writeError(w, r, http.StatusForbidden, 30007, "only the owner can restore records")
		return
	}
	record, err := s.store.RestoreRecord(r.Context(), recordID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if err := s.store.SyncReminderForRecord(r.Context(), record); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "restore_record", "record", recordID, "{}")
	writeData(w, r, http.StatusOK, record)
}

type timelineEntry struct {
	Kind   string              `json:"kind"`
	At     string              `json:"at"`
	Record *store.HealthRecord `json:"record,omitempty"`
	Weight *store.WeightRecord `json:"weight,omitempty"`
}

func (s *Server) timeline(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requireRecordRead(w, r)
	if !ok {
		return
	}
	typ := strings.TrimSpace(r.URL.Query().Get("type"))
	records, err := s.store.ListRecords(r.Context(), pet.ID, typ)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	entries := make([]timelineEntry, 0, len(records))
	for i := range records {
		rec := records[i]
		entries = append(entries, timelineEntry{Kind: "record", At: rec.OccurredAt, Record: &rec})
	}
	if typ == "" || typ == "weight" {
		weights, err := s.store.ListWeights(r.Context(), pet.ID)
		if err != nil {
			writeStoreError(w, r, err)
			return
		}
		for i := range weights {
			weight := weights[i]
			entries = append(entries, timelineEntry{Kind: "weight", At: weight.MeasuredAt, Weight: &weight})
		}
	}
	sort.SliceStable(entries, func(i, j int) bool {
		if entries[i].At == entries[j].At {
			return entries[i].Kind == "weight" && entries[j].Kind != "weight"
		}
		return entries[i].At > entries[j].At
	})
	writeData(w, r, http.StatusOK, entries)
}

func (s *Server) listWeights(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requireRecordRead(w, r)
	if !ok {
		return
	}
	weights, err := s.store.ListWeights(r.Context(), pet.ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, weights)
}

func (s *Server) createWeight(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requireRecordWrite(w, r)
	if !ok {
		return
	}
	var in store.WeightInput
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if !validDate(in.MeasuredAt) || in.WeightKg <= 0 || in.WeightKg > 120 {
		writeError(w, r, http.StatusBadRequest, 10002, "invalid date or weight")
		return
	}
	weight, err := s.store.CreateWeight(r.Context(), pet.ID, currentUser(r).ID, in)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "create_weight", "weight", weight.ID, "{}")
	writeData(w, r, http.StatusCreated, weight)
}

func (s *Server) uploadPetAvatar(w http.ResponseWriter, r *http.Request) {
	pet, err := s.store.GetPetForUser(r.Context(), chi.URLParam(r, "petID"), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if pet.Role != "owner" {
		writeError(w, r, http.StatusForbidden, 30007, "only the owner can change the avatar")
		return
	}
	const maxAvatar = 5 << 20
	r.Body = http.MaxBytesReader(w, r.Body, maxAvatar+1<<20)
	if err := r.ParseMultipartForm(maxAvatar); err != nil {
		writeError(w, r, http.StatusBadRequest, 10003, "file is too large or invalid multipart form")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, r, http.StatusBadRequest, 10004, "file field is required")
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxAvatar+1))
	if err != nil || len(data) > maxAvatar {
		writeError(w, r, http.StatusRequestEntityTooLarge, 10006, "avatar must be at most 5 MB")
		return
	}
	mime := http.DetectContentType(data)
	switch mime {
	case "image/jpeg", "image/png", "image/webp":
	default:
		writeError(w, r, http.StatusBadRequest, 10007, "only JPEG, PNG or WebP are allowed")
		return
	}
	attachment, err := s.store.SaveAttachment(r.Context(), pet.ID, "", filepath.Base(header.Filename), mime, data)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	updated, err := s.store.SetPetAvatar(r.Context(), pet.ID, currentUser(r).ID, attachment.ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "set_pet_avatar", "pet", pet.ID, "{}")
	writeData(w, r, http.StatusOK, updated)
}

func (s *Server) getPetAvatar(w http.ResponseWriter, r *http.Request) {
	pet, err := s.store.GetPetForUser(r.Context(), chi.URLParam(r, "petID"), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if pet.AvatarPath == "" {
		writeError(w, r, http.StatusNotFound, 30003, "avatar not set")
		return
	}
	attachment, path, err := s.store.GetAttachmentWithPath(r.Context(), pet.AvatarPath)
	if err != nil || attachment.PetID != pet.ID {
		writeError(w, r, http.StatusNotFound, 30003, "avatar not found")
		return
	}
	w.Header().Set("Content-Type", attachment.Mime)
	w.Header().Set("Cache-Control", "private, max-age=300")
	http.ServeFile(w, r, path)
}

func (s *Server) deleteWeight(w http.ResponseWriter, r *http.Request) {
	weightID := chi.URLParam(r, "weightID")
	weight, err := s.store.GetWeight(r.Context(), weightID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	pet, err := s.store.GetPetForUser(r.Context(), weight.PetID, currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if pet.Role == "viewer" || (pet.Role == "co_caregiver" && weight.CreatedByUserID != currentUser(r).ID) {
		writeError(w, r, http.StatusForbidden, 30007, "no permission to delete this weight record")
		return
	}
	if _, err := s.store.DeleteWeight(r.Context(), weightID); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "delete_weight", "weight", weightID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) uploadAttachment(w http.ResponseWriter, r *http.Request) {
	pet, ok := s.requireRecordWrite(w, r)
	if !ok {
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxUploadBytes+1<<20)
	if err := r.ParseMultipartForm(maxUploadBytes); err != nil {
		writeError(w, r, http.StatusBadRequest, 10003, "file is too large or invalid multipart form")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, r, http.StatusBadRequest, 10004, "file field is required")
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxUploadBytes+1))
	if err != nil {
		writeError(w, r, http.StatusBadRequest, 10005, "could not read file")
		return
	}
	if len(data) > maxUploadBytes {
		writeError(w, r, http.StatusRequestEntityTooLarge, 10006, "file exceeds 20 MB")
		return
	}
	mime := http.DetectContentType(data)
	switch mime {
	case "image/jpeg", "image/png", "image/webp", "application/pdf":
	default:
		writeError(w, r, http.StatusBadRequest, 10007, "only JPEG, PNG, WebP or PDF are allowed")
		return
	}
	recordID := strings.TrimSpace(r.FormValue("recordId"))
	if recordID != "" {
		record, err := s.store.GetRecord(r.Context(), recordID)
		if err != nil || record.PetID != pet.ID {
			writeError(w, r, http.StatusBadRequest, 10008, "record does not belong to this pet")
			return
		}
	}
	attachment, err := s.store.SaveAttachment(r.Context(), pet.ID, recordID, filepath.Base(header.Filename), mime, data)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "upload_attachment", "attachment", attachment.ID, "{}")
	writeData(w, r, http.StatusCreated, attachment)
}

func (s *Server) downloadAttachment(w http.ResponseWriter, r *http.Request) {
	attachment, path, err := s.store.GetAttachmentWithPath(r.Context(), chi.URLParam(r, "attachmentID"))
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	pet, err := s.store.GetPetForUser(r.Context(), attachment.PetID, currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if pet.Role == "viewer" {
		writeError(w, r, http.StatusForbidden, 30007, "viewer cannot download medical attachments")
		return
	}
	w.Header().Set("Content-Type", attachment.Mime)
	w.Header().Set("Content-Disposition", "inline; filename=\""+strings.ReplaceAll(attachment.OriginalName, "\"", "")+"\"")
	http.ServeFile(w, r, path)
}

func (s *Server) requireRecordRead(w http.ResponseWriter, r *http.Request) (store.Pet, bool) {
	pet, err := s.store.GetPetForUser(r.Context(), chi.URLParam(r, "petID"), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return store.Pet{}, false
	}
	if pet.Role == "viewer" {
		writeError(w, r, http.StatusForbidden, 30007, "viewer cannot read health records")
		return store.Pet{}, false
	}
	return pet, true
}

func (s *Server) requireRecordWrite(w http.ResponseWriter, r *http.Request) (store.Pet, bool) {
	pet, err := s.store.GetPetForUser(r.Context(), chi.URLParam(r, "petID"), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return store.Pet{}, false
	}
	if pet.Role != "owner" && pet.Role != "co_caregiver" {
		writeError(w, r, http.StatusForbidden, 30007, "no permission to write records")
		return store.Pet{}, false
	}
	return pet, true
}

func (s *Server) requireRecordEdit(w http.ResponseWriter, r *http.Request, recordID string) (store.HealthRecord, store.Pet, bool) {
	record, err := s.store.GetRecord(r.Context(), recordID)
	if err != nil {
		writeStoreError(w, r, err)
		return store.HealthRecord{}, store.Pet{}, false
	}
	pet, err := s.store.GetPetForUser(r.Context(), record.PetID, currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return store.HealthRecord{}, store.Pet{}, false
	}
	if pet.Role == "viewer" {
		writeError(w, r, http.StatusForbidden, 30007, "viewer cannot edit records")
		return store.HealthRecord{}, store.Pet{}, false
	}
	if pet.Role == "co_caregiver" && record.CreatedByUserID != currentUser(r).ID {
		writeError(w, r, http.StatusForbidden, 30007, "co-caregiver can only edit records they created")
		return store.HealthRecord{}, store.Pet{}, false
	}
	return record, pet, true
}

func validateRecordInput(in *store.RecordInput) error {
	in.Type = strings.TrimSpace(in.Type)
	in.Title = strings.TrimSpace(in.Title)
	in.OccurredAt = strings.TrimSpace(in.OccurredAt)
	in.Hospital = strings.TrimSpace(in.Hospital)
	in.Doctor = strings.TrimSpace(in.Doctor)
	in.NextDueAt = strings.TrimSpace(in.NextDueAt)
	if !validRecordType(in.Type) {
		return errors.New("invalid record type")
	}
	if in.Title == "" || len([]rune(in.Title)) > 60 {
		return errors.New("title is required and must be at most 60 characters")
	}
	if !validDate(in.OccurredAt) {
		return errors.New("occurredAt must be YYYY-MM-DD")
	}
	if in.NextDueAt != "" && !validDate(in.NextDueAt) {
		return errors.New("nextDueAt must be YYYY-MM-DD")
	}
	if len(in.Payload) == 0 {
		in.Payload = json.RawMessage(`{}`)
	}
	var payload map[string]any
	if err := json.Unmarshal(in.Payload, &payload); err != nil {
		return errors.New("payload must be a JSON object")
	}
	// Re-encode so invalid UTF-8 from a client is normalised before it is
	// stored and later returned inside the JSON envelope.
	normalized, err := json.Marshal(payload)
	if err != nil {
		return errors.New("payload must be a JSON object")
	}
	in.Payload = normalized
	return nil
}

func validRecordType(value string) bool {
	switch value {
	case "vaccine", "deworming", "checkup", "medical", "medication", "grooming", "diet", "other":
		return true
	default:
		return false
	}
}

func validDate(value string) bool {
	_, err := time.Parse("2006-01-02", value)
	return err == nil
}
