package store

import (
	"context"
	"errors"
	"testing"
)

func TestMemberInviteAndRemoval(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)
	carol, err := s.CreateAdmin(ctx, "carol", "hash")
	if err != nil {
		t.Fatal(err)
	}
	pet, err := s.CreatePet(ctx, owner.ID, PetInput{Name: "Mimi", Species: "cat"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.AddMember(ctx, pet.ID, owner.ID, "carol", "viewer"); err != nil {
		t.Fatalf("add member: %v", err)
	}
	pets, err := s.ListPetsForUser(ctx, carol.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(pets) != 1 || pets[0].Role != "viewer" {
		t.Fatalf("expected shared read-only pet, got %+v", pets)
	}
	if err := s.RemoveMember(ctx, pet.ID, carol.ID); err != nil {
		t.Fatal(err)
	}
	pets, err = s.ListPetsForUser(ctx, carol.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(pets) != 0 {
		t.Fatalf("expected no shared pets after removal, got %+v", pets)
	}
}

func TestShareGrantLifecycle(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)
	pet, err := s.CreatePet(ctx, owner.ID, PetInput{Name: "Mimi", Species: "cat"})
	if err != nil {
		t.Fatal(err)
	}
	grant, err := s.CreateShareGrant(ctx, pet.ID, owner.ID, "co_caregiver", 7, "1234")
	if err != nil {
		t.Fatal(err)
	}
	if grant.Token == "" || !grant.HasPasscode {
		t.Fatalf("unexpected grant: %+v", grant)
	}
	resolved, err := s.ResolveShareGrant(ctx, grant.Token)
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if resolved.PetID != pet.ID || resolved.Role != "co_caregiver" || resolved.PasscodeHash == "" {
		t.Fatalf("unexpected resolved grant: %+v", resolved)
	}
	if _, err := s.ResolveShareGrant(ctx, "wrong-token"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected not found for wrong token, got %v", err)
	}
	if err := s.RevokeShareGrant(ctx, grant.ID, owner.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ResolveShareGrant(ctx, grant.Token); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected revoked grant to be rejected, got %v", err)
	}
	if err := s.RevokeShareGrant(ctx, grant.ID, owner.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("second revoke should report not found, got %v", err)
	}
}

func TestDeleteWeightFallsBackToLatest(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)
	pet, err := s.CreatePet(ctx, owner.ID, PetInput{Name: "Mimi", Species: "cat"})
	if err != nil {
		t.Fatal(err)
	}
	first, err := s.CreateWeight(ctx, pet.ID, owner.ID, WeightInput{MeasuredAt: "2026-09-01", WeightKg: 4.2})
	if err != nil {
		t.Fatal(err)
	}
	second, err := s.CreateWeight(ctx, pet.ID, owner.ID, WeightInput{MeasuredAt: "2026-10-01", WeightKg: 4.8})
	if err != nil {
		t.Fatal(err)
	}
	current, err := s.GetPetForUser(ctx, pet.ID, owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	if current.CurrentWeightKg != 4.8 {
		t.Fatalf("expected 4.8, got %v", current.CurrentWeightKg)
	}
	if _, err := s.DeleteWeight(ctx, second.ID); err != nil {
		t.Fatal(err)
	}
	current, err = s.GetPetForUser(ctx, pet.ID, owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	if current.CurrentWeightKg != 4.2 {
		t.Fatalf("expected fallback 4.2, got %v", current.CurrentWeightKg)
	}
	if _, err := s.DeleteWeight(ctx, first.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.DeleteWeight(ctx, first.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected not found on second delete, got %v", err)
	}
}

func TestShareGrantRejectsInvalidRole(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)
	pet, err := s.CreatePet(ctx, owner.ID, PetInput{Name: "Mimi", Species: "cat"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateShareGrant(ctx, pet.ID, owner.ID, "admin", 7, ""); !errors.Is(err, ErrInvalidRole) {
		t.Fatalf("expected invalid role, got %v", err)
	}
}
