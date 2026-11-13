package handlers

import "strings"

// normalizeContactPhone brings a provider's phone or WhatsApp number to the
// international format the apps link to (wa.me / tel:): "+7XXXXXXXXXX"
// for Kazakhstan, "+<country code><number>" otherwise. Spaces, dashes,
// dots and brackets are ignored; a local "8 7xx…", "7 7xx…" or a bare
// 10-digit "7xx…" number is taken as Kazakhstani.
//
// An empty value is allowed (ok, ""): app versions released before phone
// became required still send it empty, and their requests must keep
// working. Anything else that doesn't parse is rejected (ok false).
func normalizeContactPhone(raw string) (string, bool) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return "", true
	}
	plus := strings.HasPrefix(s, "+")
	var digits strings.Builder
	for i, r := range s {
		switch {
		case r >= '0' && r <= '9':
			digits.WriteRune(r)
		case r == '+' && i == 0:
		case r == ' ' || r == '-' || r == '(' || r == ')' || r == '.' || r == ' ':
		default:
			return "", false
		}
	}
	d := digits.String()
	if plus {
		if strings.HasPrefix(d, "7") {
			if len(d) != 11 {
				return "", false
			}
			return "+" + d, true
		}
		if len(d) < 8 || len(d) > 15 || d[0] == '0' {
			return "", false
		}
		return "+" + d, true
	}
	switch {
	case len(d) == 11 && (d[0] == '8' || d[0] == '7'):
		return "+7" + d[1:], true
	case len(d) == 10 && d[0] == '7':
		return "+7" + d, true
	}
	return "", false
}
