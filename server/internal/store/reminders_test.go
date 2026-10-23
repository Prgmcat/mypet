package store

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/Prgmcat/mypet/server/internal/db"
)

func newTestStore(t *testing.T) (*Store, *db.DB) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "mypet.db")
	d, err := db.Open(path)
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	t.Cleanup(func() { d.Close() })
	if err := d.Migrate(context.Background()); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return New(d), d
}

func mustAdmin(t *testing.T, s *Store) User {
	t.Helper()
	u, err := s.CreateAdmin(context.Background(), "owner", "hash")
	if err != nil {
		t.Fatalf("create admin: %v", err)
	}
	return u
}

func TestReminderLifecycle(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)

	pet, err := s.CreatePet(ctx, owner.ID, PetInput{
		Name: "Mimi", Species: "cat", Birthday: "2020-05-01",
	})
	if err != nil {
		t.Fatalf("create pet: %v", err)
	}
	if err := s.SyncBirthdayRule(ctx, pet); err != nil {
		t.Fatalf("birthday rule: %v", err)
	}

	record, err := s.CreateRecord(ctx, pet.ID, owner.ID, RecordInput{
		Type: "vaccine", OccurredAt: "2026-01-01", Title: "猫三联",
		Payload: json.RawMessage(`{}`), NextDueAt: "2027-01-01",
	})
	if err != nil {
		t.Fatalf("create record: %v", err)
	}
	if err := s.SyncReminderForRecord(ctx, record); err != nil {
		t.Fatalf("sync record: %v", err)
	}
	if err := s.EnsureReminders(ctx); err != nil {
		t.Fatalf("ensure: %v", err)
	}

	pending, err := s.ListReminders(ctx, owner.ID, "pending")
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	var vaccine ReminderInstance
	for _, r := range pending {
		if r.Type == "vaccine" {
			vaccine = r
		}
	}
	if vaccine.ID == "" {
		t.Fatalf("expected pending vaccine reminder, got %+v", pending)
	}
	if vaccine.DueAt != "2027-01-01" {
		t.Fatalf("unexpected due date %q", vaccine.DueAt)
	}

	done, err := s.CompleteReminder(ctx, vaccine.ID, UserActor(owner.ID))
	if err != nil {
		t.Fatalf("complete: %v", err)
	}
	if done.Status != "done" {
		t.Fatalf("expected done, got %q", done.Status)
	}
	if done.RecordID == "" {
		t.Fatal("completion should create a health record")
	}

	rules, err := s.ListReminderRules(ctx, pet.ID, owner.ID)
	if err != nil {
		t.Fatalf("rules: %v", err)
	}
	var nextDue string
	for _, r := range rules {
		if r.Type == "vaccine" {
			nextDue = r.NextDueAt
		}
	}
	if nextDue != "2028-01-01" {
		t.Fatalf("expected next due 2028-01-01, got %q", nextDue)
	}

	pending, err = s.ListReminders(ctx, owner.ID, "pending")
	if err != nil {
		t.Fatalf("list after complete: %v", err)
	}
	foundNext := false
	for _, r := range pending {
		if r.Type == "vaccine" && r.DueAt == "2028-01-01" {
			foundNext = true
		}
	}
	if !foundNext {
		t.Fatalf("expected next vaccine occurrence, got %+v", pending)
	}
}

func TestUpdateRuleIntervalReanchorsNextDue(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)
	pet, err := s.CreatePet(ctx, owner.ID, PetInput{Name: "Mimi", Species: "cat"})
	if err != nil {
		t.Fatal(err)
	}
	record, err := s.CreateRecord(ctx, pet.ID, owner.ID, RecordInput{
		Type: "vaccine", OccurredAt: "2026-01-01", Title: "猫三联",
		Payload: json.RawMessage(`{}`), NextDueAt: "2027-01-01",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.SyncReminderForRecord(ctx, record); err != nil {
		t.Fatal(err)
	}
	rules, err := s.ListReminderRules(ctx, pet.ID, owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	var rule ReminderRule
	for _, r := range rules {
		if r.Type == "vaccine" {
			rule = r
		}
	}
	if rule.ID == "" {
		t.Fatalf("vaccine rule missing: %+v", rules)
	}
	interval := 30
	updated, err := s.UpdateReminderRule(ctx, rule.ID, owner.ID, nil, &interval, nil)
	if err != nil {
		t.Fatal(err)
	}
	if updated.NextDueAt != "2026-01-31" {
		t.Fatalf("expected re-anchored due date, got %q", updated.NextDueAt)
	}
	pending, err := s.ListReminders(ctx, owner.ID, "pending")
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, r := range pending {
		if r.Type == "vaccine" && r.DueAt == "2026-01-31" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected re-anchored occurrence, got %+v", pending)
	}
}

func TestDeleteRecordRecalculatesReminder(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)
	pet, err := s.CreatePet(ctx, owner.ID, PetInput{Name: "Dou", Species: "dog"})
	if err != nil {
		t.Fatal(err)
	}
	first, err := s.CreateRecord(ctx, pet.ID, owner.ID, RecordInput{
		Type: "deworming", OccurredAt: "2026-01-01", Title: "体内驱虫",
		Payload: json.RawMessage(`{}`), NextDueAt: "2026-04-01",
	})
	if err != nil {
		t.Fatal(err)
	}
	second, err := s.CreateRecord(ctx, pet.ID, owner.ID, RecordInput{
		Type: "deworming", OccurredAt: "2026-04-01", Title: "体内驱虫",
		Payload: json.RawMessage(`{}`), NextDueAt: "2026-07-01",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.SyncReminderForRecord(ctx, first); err != nil {
		t.Fatal(err)
	}
	if err := s.SyncReminderForRecord(ctx, second); err != nil {
		t.Fatal(err)
	}
	if err := s.DeleteRecord(ctx, second.ID); err != nil {
		t.Fatal(err)
	}
	if err := s.RecalculateReminder(ctx, pet.ID, "deworming"); err != nil {
		t.Fatal(err)
	}
	rules, err := s.ListReminderRules(ctx, pet.ID, owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(rules) != 1 || rules[0].NextDueAt != "2026-04-01" {
		t.Fatalf("expected rule to fall back to first record, got %+v", rules)
	}
}
