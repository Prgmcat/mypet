package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"strconv"
	"strings"

	"golang.org/x/crypto/argon2"
)

const (
	argonTime    uint32 = 3
	argonMemory  uint32 = 64 * 1024
	argonThreads uint8  = 4
	argonKeyLen  uint32 = 32
	saltLen             = 16
)

func HashPassword(password string) (string, error) {
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key := argon2.IDKey([]byte(password), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	return fmt.Sprintf("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s",
		argonMemory, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	), nil
}

func VerifyPassword(encoded, password string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" || parts[2] != "v=19" {
		return false
	}
	var memory, timeCost uint32
	var threads uint8
	for _, kv := range strings.Split(parts[3], ",") {
		pair := strings.SplitN(kv, "=", 2)
		if len(pair) != 2 {
			return false
		}
		switch pair[0] {
		case "m":
			v, err := strconv.ParseUint(pair[1], 10, 32)
			if err != nil {
				return false
			}
			memory = uint32(v)
		case "t":
			v, err := strconv.ParseUint(pair[1], 10, 32)
			if err != nil {
				return false
			}
			timeCost = uint32(v)
		case "p":
			v, err := strconv.ParseUint(pair[1], 10, 8)
			if err != nil {
				return false
			}
			threads = uint8(v)
		}
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false
	}
	got := argon2.IDKey([]byte(password), salt, timeCost, memory, threads, uint32(len(want)))
	return subtle.ConstantTimeCompare(got, want) == 1
}
