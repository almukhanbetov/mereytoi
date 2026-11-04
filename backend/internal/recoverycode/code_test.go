package recoverycode

import (
	"strings"
	"testing"
)

func TestGenerateIsLongRandomAndUnambiguous(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 2000; i++ {
		c, err := Generate()
		if err != nil {
			t.Fatal(err)
		}
		if len(c) != Length {
			t.Fatalf("length %d", len(c))
		}
		for _, r := range c {
			if !strings.ContainsRune(alphabet, r) {
				t.Fatalf("symbol %q outside the alphabet", r)
			}
		}
		if seen[c] {
			t.Fatal("duplicate code")
		}
		seen[c] = true
	}
	// 5 bits per symbol.
	if bits := Length * 5; bits < 128 {
		t.Fatalf("only %d bits of entropy", bits)
	}
}

func TestFormatAndNormalizeRoundTrip(t *testing.T) {
	c, _ := Generate()
	f := Format(c)
	if strings.Count(f, "-") != Length/groupSize-1 {
		t.Fatalf("groups: %s", f)
	}
	for _, typed := range []string{f, strings.ToLower(f), strings.ReplaceAll(f, "-", " "), " " + c + "\n"} {
		got, ok := Normalize(typed)
		if !ok || got != c {
			t.Fatalf("Normalize(%q) = %q, %v", typed, got, ok)
		}
	}
}

func TestNormalizeMapsLookAlikesAndRejectsJunk(t *testing.T) {
	base := strings.Repeat("A", Length-3)
	if got, ok := Normalize(base + "OIL"); !ok || got != base+"011" {
		t.Fatalf("look-alikes: %q %v", got, ok)
	}
	for _, bad := range []string{"", "short", strings.Repeat("A", Length+1), base + "U12", base + "!12"} {
		if _, ok := Normalize(bad); ok {
			t.Fatalf("accepted %q", bad)
		}
	}
}

func TestHashIsStableAndNotTheCode(t *testing.T) {
	c, _ := Generate()
	h := Hash(c)
	if h != Hash(c) || strings.Contains(h, c) || !strings.HasPrefix(h, hashPrefix) {
		t.Fatalf("hash %q", h)
	}
	d, _ := Generate()
	if Hash(d) == h {
		t.Fatal("different codes, same hash")
	}
}

func TestTemporaryCodeIsShorterAndNotABackupCode(t *testing.T) {
	c, err := generate(TempLength)
	if err != nil {
		t.Fatal(err)
	}
	if got, ok := normalize(strings.ToLower(Format(c)), TempLength); !ok || got != c {
		t.Fatalf("round trip: %q %v", got, ok)
	}
	if _, ok := Normalize(c); ok {
		t.Fatal("a temporary code passes as a backup code")
	}
	if bits := TempLength * 5; bits < 80 {
		t.Fatalf("only %d bits of entropy", bits)
	}
}
