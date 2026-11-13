package handlers

import "testing"

func TestNormalizeContactPhone(t *testing.T) {
	ok := map[string]string{
		"":                  "",
		"  ":                "",
		"+7 701 123 45 67":  "+77011234567",
		"8 (701) 123-45-67": "+77011234567",
		"87011234567":       "+77011234567",
		"77011234567":       "+77011234567",
		"7011234567":        "+77011234567",
		"+7-727-250-00-00":  "+77272500000",
		"+998 90 123 45 67": "+998901234567",
		"+90 532 123 45 67": "+905321234567",
		"+7 701 123 45 67":  "+77011234567",
	}
	for in, want := range ok {
		got, valid := normalizeContactPhone(in)
		if !valid || got != want {
			t.Errorf("%q → %q %v, want %q", in, got, valid, want)
		}
	}
	for _, bad := range []string{"abc", "+7 701 123", "+7701123456789", "12345", "8701123456", "+0123456789", "+7 701 123 45 67 ext 2", "@whatsapp", "+77011234567+"} {
		if got, valid := normalizeContactPhone(bad); valid {
			t.Errorf("%q accepted as %q", bad, got)
		}
	}
}
