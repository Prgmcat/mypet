package store

import "encoding/json"

type User struct {
	ID          string `json:"id"`
	Username    string `json:"username"`
	DisplayName string `json:"displayName"`
	IsAdmin     bool   `json:"isAdmin"`
	Status      string `json:"status"`
	CreatedAt   string `json:"createdAt"`
}

type Device struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	LastSeenAt string `json:"lastSeenAt,omitempty"`
	CreatedAt  string `json:"createdAt"`
	RevokedAt  string `json:"revokedAt,omitempty"`
}

type Pet struct {
	ID                string  `json:"id"`
	OwnerUserID       string  `json:"ownerUserId"`
	Name              string  `json:"name"`
	Species           string  `json:"species"`
	Breed             string  `json:"breed"`
	Sex               string  `json:"sex"`
	Birthday          string  `json:"birthday,omitempty"`
	BirthdayEstimated bool    `json:"birthdayEstimated"`
	Neutered          string  `json:"neutered"`
	AvatarPath        string  `json:"avatarPath,omitempty"`
	CurrentWeightKg   float64 `json:"currentWeightKg,omitempty"`
	Allergies         string  `json:"allergies,omitempty"`
	ChronicConditions string  `json:"chronicConditions,omitempty"`
	Medications       string  `json:"medications,omitempty"`
	IdentityNo        string  `json:"identityNo"`
	Status            string  `json:"status"`
	Version           int     `json:"version"`
	CreatedAt         string  `json:"createdAt"`
	UpdatedAt         string  `json:"updatedAt"`
	Role              string  `json:"role,omitempty"`
}

type PetInput struct {
	Name              string  `json:"name"`
	Species           string  `json:"species"`
	Breed             string  `json:"breed"`
	Sex               string  `json:"sex"`
	Birthday          string  `json:"birthday"`
	BirthdayEstimated bool    `json:"birthdayEstimated"`
	Neutered          string  `json:"neutered"`
	AvatarPath        string  `json:"avatarPath"`
	CurrentWeightKg   float64 `json:"currentWeightKg"`
	Allergies         string  `json:"allergies"`
	ChronicConditions string  `json:"chronicConditions"`
	Medications       string  `json:"medications"`
}

type HealthRecord struct {
	ID              string          `json:"id"`
	PetID           string          `json:"petId"`
	Type            string          `json:"type"`
	OccurredAt      string          `json:"occurredAt"`
	Title           string          `json:"title"`
	Payload         json.RawMessage `json:"payload"`
	Hospital        string          `json:"hospital,omitempty"`
	Doctor          string          `json:"doctor,omitempty"`
	NextDueAt       string          `json:"nextDueAt,omitempty"`
	Source          string          `json:"source"`
	CreatedByType   string          `json:"createdByType"`
	CreatedByUserID string          `json:"createdByUserId,omitempty"`
	Version         int             `json:"version"`
	CreatedAt       string          `json:"createdAt"`
	UpdatedAt       string          `json:"updatedAt"`
	Attachments     []Attachment    `json:"attachments,omitempty"`
}

type RecordInput struct {
	Type       string          `json:"type"`
	OccurredAt string          `json:"occurredAt"`
	Title      string          `json:"title"`
	Payload    json.RawMessage `json:"payload"`
	Hospital   string          `json:"hospital"`
	Doctor     string          `json:"doctor"`
	NextDueAt  string          `json:"nextDueAt"`
	Source     string          `json:"source"`
}

type WeightRecord struct {
	ID              string  `json:"id"`
	PetID           string  `json:"petId"`
	MeasuredAt      string  `json:"measuredAt"`
	WeightKg        float64 `json:"weightKg"`
	Note            string  `json:"note,omitempty"`
	CreatedByType   string  `json:"createdByType"`
	CreatedByUserID string  `json:"createdByUserId,omitempty"`
	CreatedAt       string  `json:"createdAt"`
}

type WeightInput struct {
	MeasuredAt string  `json:"measuredAt"`
	WeightKg   float64 `json:"weightKg"`
	Note       string  `json:"note"`
}

// Actor identifies who performed a write: a logged-in user or a guest grant.
type Actor struct {
	Type    string
	UserID  string
	GrantID string
}

func UserActor(userID string) Actor { return Actor{Type: "user", UserID: userID} }

func GuestActor(grantID string) Actor { return Actor{Type: "guest", GrantID: grantID} }

type AdminDevice struct {
	ID         string `json:"id"`
	UserID     string `json:"userId"`
	Username   string `json:"username"`
	Name       string `json:"name"`
	LastSeenAt string `json:"lastSeenAt,omitempty"`
	CreatedAt  string `json:"createdAt"`
	RevokedAt  string `json:"revokedAt,omitempty"`
}

type InviteCode struct {
	ID        string `json:"id"`
	MaxUses   int    `json:"maxUses"`
	UsedCount int    `json:"usedCount"`
	ExpiresAt string `json:"expiresAt"`
	Status    string `json:"status"`
	CreatedAt string `json:"createdAt"`
}

type ReminderRule struct {
	ID             string `json:"id"`
	PetID          string `json:"petId"`
	Type           string `json:"type"`
	IntervalDays   int    `json:"intervalDays"`
	AnchorRecordID string `json:"anchorRecordId,omitempty"`
	NextDueAt      string `json:"nextDueAt,omitempty"`
	AdvanceOffsets []int  `json:"advanceOffsets"`
	Enabled        bool   `json:"enabled"`
}

type ReminderInstance struct {
	ID             string `json:"id"`
	RuleID         string `json:"ruleId"`
	PetID          string `json:"petId"`
	PetName        string `json:"petName,omitempty"`
	Type           string `json:"type"`
	OccurrenceKey  string `json:"occurrenceKey"`
	DueAt          string `json:"dueAt"`
	Status         string `json:"status"`
	AdvanceOffsets []int  `json:"advanceOffsets"`
	SnoozedUntil   string `json:"snoozedUntil,omitempty"`
	CompletedAt    string `json:"completedAt,omitempty"`
	RecordID       string `json:"recordId,omitempty"`
	Role           string `json:"role,omitempty"`
}

type Attachment struct {
	ID           string `json:"id"`
	PetID        string `json:"petId"`
	RecordID     string `json:"recordId,omitempty"`
	OriginalName string `json:"originalName,omitempty"`
	Mime         string `json:"mime"`
	Size         int64  `json:"size"`
	SHA256       string `json:"sha256"`
	CreatedAt    string `json:"createdAt"`
}
