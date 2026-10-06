package passwordreset

import "testing"

func TestGenerateCodeIsSixRandomDigits(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 200; i++ {
		c, err := generateCode()
		if err != nil {
			t.Fatal(err)
		}
		if !wellFormed(c) {
			t.Fatalf("%q is not 6 digits", c)
		}
		seen[c] = true
	}
	if len(seen) < 190 {
		t.Fatalf("only %d distinct codes out of 200 — not random", len(seen))
	}
}

func TestWellFormed(t *testing.T) {
	for _, c := range []string{"000000", "123456", "999999"} {
		if !wellFormed(c) {
			t.Errorf("%q should be well-formed", c)
		}
	}
	for _, c := range []string{"", "12345", "1234567", "12a456", " 12345", "１２３４５６"} {
		if wellFormed(c) {
			t.Errorf("%q should not be well-formed", c)
		}
	}
}

func TestHashIsBoundToKeyUserAndPurpose(t *testing.T) {
	key := deriveKey("", "jwt-secret")
	h := hashCode(key, 1, "reset", "123456")
	if h == "123456" || len(h) != 64 {
		t.Fatalf("hash looks wrong: %q", h)
	}
	if !codeMatches(key, 1, "reset", "123456", h) {
		t.Fatal("the right code must match")
	}
	for name, ok := range map[string]bool{
		"wrong code":    codeMatches(key, 1, "reset", "123457", h),
		"other user":    codeMatches(key, 2, "reset", "123456", h),
		"other purpose": codeMatches(key, 1, "change", "123456", h),
		"other key":     codeMatches(deriveKey("otp-secret", "jwt-secret"), 1, "reset", "123456", h),
		"garbage hash":  codeMatches(key, 1, "reset", "123456", "zz"),
	} {
		if ok {
			t.Errorf("%s must not match", name)
		}
	}
}

func TestDeriveKeyNeverUsesJWTSecretDirectly(t *testing.T) {
	if string(deriveKey("", "jwt-secret")) == "jwt-secret" {
		t.Fatal("the JWT secret must be domain-separated, not reused as is")
	}
	if string(deriveKey("otp", "jwt-secret")) != "otp" {
		t.Fatal("a configured OTP secret is used as is")
	}
}

func TestMaskPhone(t *testing.T) {
	if got := maskPhone("+77071234567"); got != "+7 ••• ••• 45 67" {
		t.Fatalf("got %q", got)
	}
}

func TestCheckPassword(t *testing.T) {
	if checkPassword("1234567") != ErrWeakPassword {
		t.Error("7 chars is too short")
	}
	if checkPassword("12345678") != nil {
		t.Error("8 chars is enough")
	}
	if checkPassword("пароль12") != nil { // 8 runes, 14 bytes
		t.Error("length counts characters, not bytes")
	}
	long := make([]byte, 73)
	for i := range long {
		long[i] = 'a'
	}
	if checkPassword(string(long)) != ErrPasswordTooLong {
		t.Error("over bcrypt's 72 bytes must be refused")
	}
}
