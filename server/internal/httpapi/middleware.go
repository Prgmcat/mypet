package httpapi

import (
	"context"
	"net/http"
	"strings"

	"github.com/Prgmcat/mypet/server/internal/auth"
	"github.com/Prgmcat/mypet/server/internal/store"
)

type ctxKey string

const (
	ctxUser   ctxKey = "user"
	ctxDevice ctxKey = "device"
)

// methodOverride lets restrictive HTTP tunnels that only forward GET/POST
// carry PATCH/PUT/DELETE through the X-HTTP-Method-Override header.
func methodOverride(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			switch strings.ToUpper(strings.TrimSpace(r.Header.Get("X-HTTP-Method-Override"))) {
			case http.MethodPatch, http.MethodPut, http.MethodDelete:
				r.Method = strings.ToUpper(strings.TrimSpace(r.Header.Get("X-HTTP-Method-Override")))
			}
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			writeError(w, r, http.StatusUnauthorized, 20001, "missing bearer token")
			return
		}
		token := strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
		u, d, err := s.store.UserByToken(r.Context(), auth.HashToken(token))
		if err != nil {
			writeError(w, r, http.StatusUnauthorized, 20002, "invalid or revoked token")
			return
		}
		ctx := context.WithValue(r.Context(), ctxUser, u)
		ctx = context.WithValue(ctx, ctxDevice, d)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *Server) adminOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u := currentUser(r)
		if !u.IsAdmin {
			writeError(w, r, http.StatusForbidden, 20003, "admin only")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func currentUser(r *http.Request) store.User {
	u, _ := r.Context().Value(ctxUser).(store.User)
	return u
}

func currentDevice(r *http.Request) store.Device {
	d, _ := r.Context().Value(ctxDevice).(store.Device)
	return d
}
