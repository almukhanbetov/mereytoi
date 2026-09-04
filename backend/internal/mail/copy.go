package mail

// pick mirrors the frontend's <T ru kz en/> component (frontend/src/context/
// AppProviders.jsx) for the one place this backend renders user-facing
// copy: en falls back to ru when unauthored, anything other than "kz"/"en"
// falls back to ru. There is nowhere on the User model to read a stored
// language preference from (see the 11A stage report, section "language
// selection" — the frontend's RU/KZ/EN toggle is a client-side-only
// localStorage value, never sent to or stored by the backend), so every
// call site in service.go currently always passes lang="ru"; pick still
// takes a lang parameter (rather than being hard-coded to the ru branch)
// so language selection is a one-line change at the call site the day a
// stored preference exists, not a rewrite of every template.
func pick(lang, ru, kz, en string) string {
	switch lang {
	case "kz":
		return kz
	case "en":
		if en != "" {
			return en
		}
		return ru
	default:
		return ru
	}
}

func roleLabel(lang, role string) string {
	switch role {
	case "editor":
		return pick(lang, "участник", "қатысушы", "participant")
	case "viewer":
		return pick(lang, "наблюдатель", "бақылаушы", "viewer")
	default:
		return role
	}
}
