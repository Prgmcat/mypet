package auth

import "testing"

func TestHashAndVerifyPassword(t *testing.T) {
	const password = "Passw0rd!"
	hash, err := HashPassword(password)
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if hash == password {
		t.Fatal("password must not be stored in plain text")
	}
	if !VerifyPassword(hash, password) {
		t.Fatal("correct password should verify")
	}
	if VerifyPassword(hash, "wrong-password") {
		t.Fatal("wrong password must not verify")
	}
	if VerifyPassword("not-a-phc-string", password) {
		t.Fatal("malformed hash must not verify")
	}
}

func TestHashUsesRandomSalt(t *testing.T) {
	a, err := HashPassword("Passw0rd!")
	if err != nil {
		t.Fatal(err)
	}
	b, err := HashPassword("Passw0rd!")
	if err != nil {
		t.Fatal(err)
	}
	if a == b {
		t.Fatal("two hashes of the same password must differ")
	}
}
