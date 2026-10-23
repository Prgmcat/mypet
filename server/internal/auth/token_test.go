package auth

import "testing"

func TestTokenHashIsStableAndNotPlain(t *testing.T) {
	plain, hash, err := NewToken()
	if err != nil {
		t.Fatal(err)
	}
	if plain == "" || hash == "" {
		t.Fatal("token and hash must not be empty")
	}
	if plain == hash {
		t.Fatal("hash must not equal plain token")
	}
	if HashToken(plain) != hash {
		t.Fatal("hash must be stable")
	}
}

func TestInviteAndResetCodes(t *testing.T) {
	code, hash, err := NewInviteCode()
	if err != nil {
		t.Fatal(err)
	}
	if len(code) != 8 || hash == code {
		t.Fatalf("unexpected invite code: %q", code)
	}
	reset, resetHash, err := NewResetCode()
	if err != nil {
		t.Fatal(err)
	}
	if len(reset) != 6 || resetHash == reset {
		t.Fatalf("unexpected reset code: %q", reset)
	}
}
