package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"math/big"
	"strings"

	"github.com/google/uuid"
)

const inviteAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func NewID() string {
	id, err := uuid.NewV7()
	if err != nil {
		return uuid.NewString()
	}
	return id.String()
}

func NewToken() (plain, hash string, err error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", "", err
	}
	plain = base64.RawURLEncoding.EncodeToString(buf)
	return plain, HashToken(plain), nil
}

func HashToken(plain string) string {
	sum := sha256.Sum256([]byte(plain))
	return hex.EncodeToString(sum[:])
}

func NewInviteCode() (plain, hash string, err error) {
	var b strings.Builder
	for i := 0; i < 8; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(inviteAlphabet))))
		if err != nil {
			return "", "", err
		}
		b.WriteByte(inviteAlphabet[n.Int64()])
	}
	plain = b.String()
	return plain, HashToken(plain), nil
}

func NewResetCode() (plain, hash string, err error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", "", err
	}
	plain = fmt.Sprintf("%06d", n.Int64())
	return plain, HashToken(plain), nil
}
