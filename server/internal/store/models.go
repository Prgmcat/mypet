package store

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
	ID                 string  `json:"id"`
	OwnerUserID        string  `json:"ownerUserId"`
	Name               string  `json:"name"`
	Species            string  `json:"species"`
	Breed              string  `json:"breed"`
	Sex                string  `json:"sex"`
	Birthday           string  `json:"birthday,omitempty"`
	BirthdayEstimated  bool    `json:"birthdayEstimated"`
	Neutered           string  `json:"neutered"`
	AvatarPath         string  `json:"avatarPath,omitempty"`
	CurrentWeightKg    float64 `json:"currentWeightKg,omitempty"`
	Allergies          string  `json:"allergies,omitempty"`
	ChronicConditions  string  `json:"chronicConditions,omitempty"`
	Medications        string  `json:"medications,omitempty"`
	IdentityNo         string  `json:"identityNo"`
	Status             string  `json:"status"`
	Version            int     `json:"version"`
	CreatedAt          string  `json:"createdAt"`
	UpdatedAt          string  `json:"updatedAt"`
	Role               string  `json:"role,omitempty"`
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
