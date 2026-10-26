package httpapi

import (
	"net/http"
	"time"

	"github.com/Prgmcat/mypet/server/internal/store"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type Server struct {
	store        *store.Store
	version      string
	guestLimiter *attemptLimiter
	loginLimiter *attemptLimiter
}

func New(st *store.Store, version string) http.Handler {
	s := &Server{
		store:        st,
		version:      version,
		guestLimiter: newAttemptLimiter(5, 10*time.Minute),
		loginLimiter: newAttemptLimiter(5, 15*time.Minute),
	}
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(methodOverride)

	r.Get("/api/health", s.health)
	r.Post("/api/setup", s.setup)
	r.Post("/api/auth/register", s.register)
	r.Post("/api/auth/login", s.login)
	r.Post("/api/auth/reset-password", s.resetPassword)

	r.Get("/g/{token}", s.guestPage)
	r.Get("/api/guest/{token}/pet", s.guestPet)
	r.Get("/api/guest/{token}/reminders", s.guestReminders)
	r.Post("/api/guest/{token}/reminders/{reminderID}/complete", s.guestCompleteReminder)
	r.Post("/api/guest/{token}/records", s.guestCreateRecord)
	r.Post("/api/guest/{token}/uploads", s.guestUpload)

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

		r.Get("/api/pets/{petID}/records", s.listRecords)
		r.Post("/api/pets/{petID}/records", s.createRecord)
		r.Patch("/api/records/{recordID}", s.updateRecord)
		r.Delete("/api/records/{recordID}", s.deleteRecord)
		r.Post("/api/records/{recordID}/restore", s.restoreRecord)
		r.Get("/api/pets/{petID}/timeline", s.timeline)
		r.Get("/api/pets/{petID}/weights", s.listWeights)
		r.Post("/api/pets/{petID}/weights", s.createWeight)
		r.Delete("/api/weights/{weightID}", s.deleteWeight)
		r.Post("/api/pets/{petID}/avatar", s.uploadPetAvatar)
		r.Get("/api/pets/{petID}/avatar", s.getPetAvatar)
		r.Post("/api/pets/{petID}/attachments", s.uploadAttachment)
		r.Get("/api/attachments/{attachmentID}", s.downloadAttachment)

		r.Get("/api/reminders", s.listReminders)
		r.Patch("/api/reminders/{reminderID}", s.updateReminder)
		r.Get("/api/pets/{petID}/reminder-rules", s.listReminderRules)
		r.Put("/api/reminder-rules/{ruleID}", s.updateReminderRule)

		r.Get("/api/appointments", s.listAppointments)
		r.Get("/api/pets/{petID}/appointments", s.listPetAppointments)
		r.Post("/api/pets/{petID}/appointments", s.createAppointment)
		r.Patch("/api/appointments/{appointmentID}", s.updateAppointment)
		r.Delete("/api/appointments/{appointmentID}", s.deleteAppointment)
		r.Post("/api/appointments/{appointmentID}/complete", s.completeAppointment)
		r.Post("/api/appointments/{appointmentID}/skip", s.skipAppointment)
		r.Post("/api/appointments/{appointmentID}/snooze", s.snoozeAppointment)

		r.Get("/api/pets/{petID}/members", s.listMembers)
		r.Post("/api/pets/{petID}/members", s.addMember)
		r.Delete("/api/pets/{petID}/members/{userID}", s.removeMember)
		r.Get("/api/share-grants", s.listShareGrants)
		r.Post("/api/pets/{petID}/share-grants", s.createShareGrant)
		r.Post("/api/share-grants/{grantID}/revoke", s.revokeShareGrant)

		r.Group(func(r chi.Router) {
			r.Use(s.adminOnly)
			r.Get("/api/admin/devices", s.adminListDevices)
			r.Delete("/api/admin/devices/{deviceID}", s.adminRevokeDevice)
			r.Get("/api/admin/users", s.adminListUsers)
			r.Patch("/api/admin/users/{userID}/status", s.adminSetUserStatus)
			r.Post("/api/admin/users/{userID}/reset-code", s.adminCreateResetCode)
			r.Get("/api/admin/invites", s.adminListInvites)
			r.Post("/api/admin/invites", s.adminCreateInvite)
			r.Post("/api/admin/invites/{inviteID}/revoke", s.adminRevokeInvite)
		})
	})

	return r
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeData(w, r, http.StatusOK, map[string]any{"status": "ok", "version": s.version})
}
