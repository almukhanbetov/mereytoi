package passwordreset

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"math/big"
)

const codeDigits = 6

var codeSpace = big.NewInt(1_000_000) // 10^codeDigits

// generateCode returns a uniformly random 6-digit code from crypto/rand.
func generateCode() (string, error) {
	n, err := rand.Int(rand.Reader, codeSpace)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%0*d", codeDigits, n.Int64()), nil
}

// wellFormed reports whether s looks like a code at all (6 ASCII digits).
func wellFormed(s string) bool {
	if len(s) != codeDigits {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

// deriveKey picks the HMAC key codes are stored under: the dedicated
// secret if one is configured, otherwise a key derived from the JWT secret
// (domain-separated, so the JWT secret itself is never used directly).
func deriveKey(otpSecret, jwtSecret string) []byte {
	if otpSecret != "" {
		return []byte(otpSecret)
	}
	mac := hmac.New(sha256.New, []byte(jwtSecret))
	mac.Write([]byte("mereytoi/password-reset-code/v1"))
	return mac.Sum(nil)
}

// hashCode is what's stored instead of the code: an HMAC bound to the user
// and purpose, so a row can't be reused for another account or flow, and a
// leaked table can't be brute-forced (10^6 codes) without the key, which
// isn't in the database.
func hashCode(key []byte, userID uint, purpose, code string) string {
	mac := hmac.New(sha256.New, key)
	fmt.Fprintf(mac, "%d:%s:%s", userID, purpose, code)
	return hex.EncodeToString(mac.Sum(nil))
}

// codeMatches compares in constant time.
func codeMatches(key []byte, userID uint, purpose, code, storedHash string) bool {
	want, err := hex.DecodeString(storedHash)
	if err != nil {
		return false
	}
	got, _ := hex.DecodeString(hashCode(key, userID, purpose, code))
	return hmac.Equal(got, want)
}
