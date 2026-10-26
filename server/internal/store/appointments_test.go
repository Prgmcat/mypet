package store

import (
	"context"
	"testing"
	"time"
)

func TestAppointmentLifecycle(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)
	pet, err := s.CreatePet(ctx, owner.ID, PetInput{Name: "Mimi", Species: "cat"})
	if err != nil {
		t.Fatalf("create pet: %v", err)
	}
	scheduled := time.Now().UTC().AddDate(0, 0, 7).Format(dateLayout)

	appointment, err := s.CreateAppointment(ctx, pet.ID, UserActor(owner.ID), AppointmentInput{
		Type: "deworming", Title: "体外驱虫", ScheduledAt: scheduled, Note: "用大宠爱",
	})
	if err != nil {
		t.Fatalf("create appointment: %v", err)
	}
	if appointment.Status != "pending" || len(appointment.AdvanceOffsets) == 0 {
		t.Fatalf("unexpected appointment: %+v", appointment)
	}

	pending, err := s.ListAppointments(ctx, owner.ID, pet.ID, "pending")
	if err != nil {
		t.Fatalf("list pending: %v", err)
	}
	if len(pending) != 1 || pending[0].ID != appointment.ID {
		t.Fatalf("expected pending appointment, got %+v", pending)
	}

	title := "体内驱虫"
	updated, err := s.UpdateAppointment(ctx, appointment.ID, AppointmentPatch{Title: &title})
	if err != nil {
		t.Fatalf("update appointment: %v", err)
	}
	if updated.Title != title {
		t.Fatalf("title not updated: %+v", updated)
	}

	done, err := s.CompleteAppointment(ctx, appointment.ID, UserActor(owner.ID))
	if err != nil {
		t.Fatalf("complete appointment: %v", err)
	}
	if done.Status != "done" || done.RecordID == "" {
		t.Fatalf("expected done appointment with record, got %+v", done)
	}
	record, err := s.GetRecord(ctx, done.RecordID)
	if err != nil {
		t.Fatalf("get linked record: %v", err)
	}
	if record.Type != "deworming" || record.Source != "appointment" || record.Title != title {
		t.Fatalf("unexpected record: %+v", record)
	}
	if record.NextDueAt != "" {
		t.Fatalf("appointment record should not set nextDueAt, got %q", record.NextDueAt)
	}

	if _, err := s.CompleteAppointment(ctx, appointment.ID, UserActor(owner.ID)); err != ErrConflict {
		t.Fatalf("expected conflict on double complete, got %v", err)
	}

	doneList, err := s.ListAppointments(ctx, owner.ID, "", "done")
	if err != nil {
		t.Fatalf("list done: %v", err)
	}
	if len(doneList) != 1 || doneList[0].ID != appointment.ID {
		t.Fatalf("expected done appointment, got %+v", doneList)
	}
}

func TestAppointmentSkipAndSnooze(t *testing.T) {
	ctx := context.Background()
	s, _ := newTestStore(t)
	owner := mustAdmin(t, s)
	pet, err := s.CreatePet(ctx, owner.ID, PetInput{Name: "Mimi", Species: "cat"})
	if err != nil {
		t.Fatalf("create pet: %v", err)
	}
	scheduled := time.Now().UTC().AddDate(0, 0, 3).Format(dateLayout)

	first, err := s.CreateAppointment(ctx, pet.ID, UserActor(owner.ID), AppointmentInput{
		Type: "grooming", Title: "洗澡", ScheduledAt: scheduled,
	})
	if err != nil {
		t.Fatalf("create appointment: %v", err)
	}
	snoozed, err := s.SnoozeAppointment(ctx, first.ID, time.Now().UTC().Add(time.Hour).Format(time.RFC3339))
	if err != nil {
		t.Fatalf("snooze: %v", err)
	}
	if snoozed.Status != "snoozed" || snoozed.SnoozedUntil == "" {
		t.Fatalf("unexpected snoozed appointment: %+v", snoozed)
	}
	pending, err := s.ListAppointments(ctx, owner.ID, "", "pending")
	if err != nil {
		t.Fatalf("list pending: %v", err)
	}
	if len(pending) != 1 || pending[0].Status != "snoozed" {
		t.Fatalf("snoozed appointment should stay pending, got %+v", pending)
	}

	second, err := s.CreateAppointment(ctx, pet.ID, UserActor(owner.ID), AppointmentInput{
		Type: "checkup", Title: "体检", ScheduledAt: scheduled,
	})
	if err != nil {
		t.Fatalf("create second appointment: %v", err)
	}
	skipped, err := s.SkipAppointment(ctx, second.ID)
	if err != nil {
		t.Fatalf("skip: %v", err)
	}
	if skipped.Status != "skipped" || skipped.RecordID != "" {
		t.Fatalf("unexpected skipped appointment: %+v", skipped)
	}
	if _, err := s.CompleteAppointment(ctx, second.ID, UserActor(owner.ID)); err != ErrConflict {
		t.Fatalf("expected conflict completing skipped, got %v", err)
	}
}
