package store

import (
	"context"
	"testing"
)

func TestPetAvatarSetAndPreservedOnUpdate(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)
	pet, err := s.CreatePet(ctx, owner.ID, PetInput{Name: "Mimi", Species: "cat"})
	if err != nil {
		t.Fatal(err)
	}
	attachment, err := s.SaveAttachment(ctx, pet.ID, "", "avatar.png", "image/png", []byte{137, 80, 78, 71})
	if err != nil {
		t.Fatal(err)
	}
	updated, err := s.SetPetAvatar(ctx, pet.ID, owner.ID, attachment.ID)
	if err != nil {
		t.Fatal(err)
	}
	if updated.AvatarPath != attachment.ID {
		t.Fatalf("expected avatar %q, got %q", attachment.ID, updated.AvatarPath)
	}
	// Editing other profile fields must not clear the avatar.
	after, err := s.UpdatePet(ctx, pet.ID, owner.ID, PetInput{
		Name: "Mimi", Species: "cat", Sex: "female", Neutered: "yes",
	})
	if err != nil {
		t.Fatal(err)
	}
	if after.AvatarPath != attachment.ID {
		t.Fatalf("avatar was cleared by update: %q", after.AvatarPath)
	}
}
