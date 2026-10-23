package store

import (
	"context"
	"errors"
	"testing"
)

func TestRevokeDeviceIsIdempotentAndHidden(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)

	device, err := s.CreateDevice(ctx, owner.ID, "Pixel 9", "token-hash-1")
	if err != nil {
		t.Fatalf("create device: %v", err)
	}
	devices, err := s.ListDevices(ctx, owner.ID)
	if err != nil {
		t.Fatalf("list devices: %v", err)
	}
	if len(devices) != 1 || devices[0].ID != device.ID {
		t.Fatalf("expected the active device, got %+v", devices)
	}

	if err := s.RevokeDevice(ctx, device.ID, owner.ID); err != nil {
		t.Fatalf("revoke device: %v", err)
	}
	// Revoking twice, or from a stale list, must not report not found.
	if err := s.RevokeDevice(ctx, device.ID, owner.ID); err != nil {
		t.Fatalf("repeat revoke should succeed: %v", err)
	}
	devices, err = s.ListDevices(ctx, owner.ID)
	if err != nil {
		t.Fatalf("list devices: %v", err)
	}
	if len(devices) != 0 {
		t.Fatalf("revoked devices should be hidden, got %+v", devices)
	}
	if err := s.RevokeDevice(ctx, "missing", owner.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("unknown device should be not found, got %v", err)
	}

	other, err := s.CreateDevice(ctx, owner.ID, "Tablet", "token-hash-2")
	if err != nil {
		t.Fatalf("create device: %v", err)
	}
	if err := s.RevokeDeviceAsAdmin(ctx, other.ID); err != nil {
		t.Fatalf("admin revoke: %v", err)
	}
	if err := s.RevokeDeviceAsAdmin(ctx, other.ID); err != nil {
		t.Fatalf("repeat admin revoke should succeed: %v", err)
	}
	if err := s.RevokeDeviceAsAdmin(ctx, "missing"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("unknown device should be not found for admin, got %v", err)
	}
}
