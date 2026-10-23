package httpapi

import (
	"net/http"
	"strings"

	"github.com/Prgmcat/mypet/server/internal/store"
	"github.com/go-chi/chi/v5"
)

func (s *Server) listPets(w http.ResponseWriter, r *http.Request) {
	pets, err := s.store.ListPetsForUser(r.Context(), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, pets)
}

func (s *Server) createPet(w http.ResponseWriter, r *http.Request) {
	var in store.PetInput
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if err := validatePetInput(&in); err != nil {
		writeError(w, r, http.StatusBadRequest, 10002, err.Error())
		return
	}
	p, err := s.store.CreatePet(r.Context(), currentUser(r).ID, in)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if err := s.store.SyncBirthdayRule(r.Context(), p); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "create_pet", "pet", p.ID, "{}")
	writeData(w, r, http.StatusCreated, p)
}

func (s *Server) getPet(w http.ResponseWriter, r *http.Request) {
	p, err := s.store.GetPetForUser(r.Context(), chi.URLParam(r, "petID"), currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, p)
}

func (s *Server) updatePet(w http.ResponseWriter, r *http.Request) {
	var in store.PetInput
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, 10001, "invalid json")
		return
	}
	if err := validatePetInput(&in); err != nil {
		writeError(w, r, http.StatusBadRequest, 10002, err.Error())
		return
	}
	petID := chi.URLParam(r, "petID")
	existing, err := s.store.GetPetForUser(r.Context(), petID, currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if existing.Role != "owner" {
		writeError(w, r, http.StatusForbidden, 30007, "only the owner can edit this pet")
		return
	}
	p, err := s.store.UpdatePet(r.Context(), petID, currentUser(r).ID, in)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	if err := s.store.SyncBirthdayRule(r.Context(), p); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "update_pet", "pet", petID, "{}")
	writeData(w, r, http.StatusOK, p)
}

func (s *Server) deletePet(w http.ResponseWriter, r *http.Request) {
	petID := chi.URLParam(r, "petID")
	if err := s.store.DeletePet(r.Context(), petID, currentUser(r).ID); err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "delete_pet", "pet", petID, "{}")
	writeData(w, r, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) restorePet(w http.ResponseWriter, r *http.Request) {
	petID := chi.URLParam(r, "petID")
	p, err := s.store.RestorePet(r.Context(), petID, currentUser(r).ID)
	if err != nil {
		writeStoreError(w, r, err)
		return
	}
	s.store.Audit(r.Context(), "user", currentUser(r).ID, "restore_pet", "pet", petID, "{}")
	writeData(w, r, http.StatusOK, p)
}

func validatePetInput(in *store.PetInput) error {
	in.Name = strings.TrimSpace(in.Name)
	in.Species = strings.TrimSpace(in.Species)
	in.Breed = strings.TrimSpace(in.Breed)
	in.Sex = strings.TrimSpace(in.Sex)
	in.Neutered = strings.TrimSpace(in.Neutered)
	if in.Name == "" || len([]rune(in.Name)) > 20 {
		return errString("name is required and must be at most 20 characters")
	}
	if in.Species == "" {
		return errString("species is required")
	}
	if in.Sex == "" {
		in.Sex = "unknown"
	}
	if in.Neutered == "" {
		in.Neutered = "unknown"
	}
	if in.CurrentWeightKg < 0 || in.CurrentWeightKg > 120 {
		return errString("weight must be between 0 and 120 kg")
	}
	return nil
}

type errString string

func (e errString) Error() string { return string(e) }
