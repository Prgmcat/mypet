package httpapi

import (
	"net/http"
	"time"

	"github.com/Prgmcat/mypet/server/internal/store"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type Server struct {
	store   *store.Store
	version string
}

func New(st *store.Store, version string) http.Handler {
	s := &Server{store: st, version: version}
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))

	r.Get("/api/health", s.health)
	r.Post("/api/setup", s.setup)
	r.Post("/api/auth/register", s.register)
	r.Post("/api/auth/login", s.login)
	r.Post("/api/auth/reset-password", s.resetPassword)

	r.Group(func(r chi.Router) {
		r.Use(s.auth)
		r.Get("/api/me", s.me)
		r.Post("/api/auth/logout", s.logout)
		r.Patch("/api/account/password", s.changePassword)
		r.Get("/api/devices", s.listDevices)
		r.Delete("/api/devices/{deviceID}", s.revokeDevice)

		r.Get("/api/pets", s.listPets)
		r.Post("/api/pets", s.createPet)
		r.Get("/api/pets/{petID}", s.getPet)
		r.Patch("/api/pets/{petID}", s.updatePet)
		r.Delete("/api/pets/{petID}", s.deletePet)
		r.Post("/api/pets/{petID}/restore", s.restorePet)

		r.Group(func(r chi.Router) {
			r.Use(s.adminOnly)
			r.Get("/api/admin/users", s.adminListUsers)
			r.Patch("/api/admin/users/{userID}/status", s.adminSetUserStatus)
			r.Post("/api/admin/users/{userID}/reset-code", s.adminCreateResetCode)
			r.Post("/api/admin/invites", s.adminCreateInvite)
		})
	})

	return r
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeData(w, r, http.StatusOK, map[string]any{"status": "ok", "version": s.version})
}
