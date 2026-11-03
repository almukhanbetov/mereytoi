// Package recoverycode implements password recovery with a one-time backup
// code: no SMS, WhatsApp or email involved. A code is issued at
// registration (and can be replaced from security settings); recovering
// the password with it atomically sets the new password, retires the code,
// stores a fresh one and revokes every existing session.
package recoverycode

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

// alphabet is Crockford's base32: no I, L, O or U, so a hand-copied code
// can't confuse 1/I/L or 0/O. 32 symbols = 5 bits each; 256 % 32 == 0, so
// mapping a random byte with `b % 32` is unbiased.
const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

// Length is the number of symbols in a code: 28 × 5 = 140 bits of entropy.
const Length = 28

// groupSize — a code is shown as 7 groups of 4 ("ABCD-EFGH-…").
const groupSize = 4

// hashPrefix tags the stored hash's scheme so it can change later.
const hashPrefix = "sha256:"

// Generate returns a fresh random code in canonical form (28 symbols, no
// separators). It uses crypto/rand and never falls back to anything weaker.
func Generate() (string, error) {
	buf := make([]byte, Length)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	out := make([]byte, Length)
	for i, b := range buf {
		out[i] = alphabet[int(b)%len(alphabet)]
	}
	return string(out), nil
}

// Format groups a canonical code for display: "ABCD-EFGH-JKMN-…".
func Format(code string) string {
	var b strings.Builder
	for i, r := range code {
		if i > 0 && i%groupSize == 0 {
			b.WriteByte('-')
		}
		b.WriteRune(r)
	}
	return b.String()
}

// Normalize turns what a person typed into canonical form: case-folded,
// separators and spaces dropped, and the look-alikes Crockford excludes
// mapped back (O→0, I/L→1). ok is false unless the result is exactly a
// well-formed code.
func Normalize(input string) (code string, ok bool) {
	var b strings.Builder
	for _, r := range strings.ToUpper(input) {
		switch {
		case r == '-' || r == ' ' || r == '\t' || r == '\n' || r == '\r':
			continue
		case r == 'O':
			r = '0'
		case r == 'I' || r == 'L':
			r = '1'
		}
		if !strings.ContainsRune(alphabet, r) {
			return "", false
		}
		b.WriteRune(r)
	}
	code = b.String()
	return code, len(code) == Length
}

// Hash is what the database stores: SHA-256 of the canonical code. A code
// carries 140 bits of entropy, so — like an API token — it can't be
// brute-forced from its hash and needs no salt or slow KDF; a fast hash also
// lets recovery find the account by indexed equality instead of comparing
// against every user.
func Hash(code string) string {
	sum := sha256.Sum256([]byte(code))
	return hashPrefix + hex.EncodeToString(sum[:])
}
