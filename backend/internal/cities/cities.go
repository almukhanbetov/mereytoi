// Package cities is the app's fixed directory of Kazakhstan cities — the
// source of GET /api/cities and of the `?city_id=` filter on
// GET /api/listings.
//
// Deliberately code, not a table: listings.city stays the free-text column
// it has always been (providers/restaurant admins type it by hand), so the
// prod data holds variants like "Алматы", "Алматы " (trailing space),
// "Almaty" and "Түркістан". Matching a city therefore goes through a
// closed list of known aliases per city after normalization — never exact
// string equality and never fuzzy matching. A blank city never matches any
// city. IDs are stable API contract (the mobile app persists them), so a
// city is only ever appended, never renumbered.
package cities

import "strings"

type City struct {
	ID     int    `json:"id"`
	NameRU string `json:"name_ru"`
	NameKZ string `json:"name_kz"`
	NameEN string `json:"name_en"`
}

type entry struct {
	City
	// aliases are extra spellings beyond the three names above (which are
	// always matched too): historical names, alternative transliterations,
	// mixed-alphabet variants seen in real data.
	aliases []string
}

// directory is in display order — All() returns it as is.
var directory = []entry{
	{City{1, "Алматы", "Алматы", "Almaty"}, []string{"Алма-Ата", "Alma-Ata", "Almaty city"}},
	{City{2, "Астана", "Астана", "Astana"}, []string{"Нур-Султан", "Нұр-Сұлтан", "Nur-Sultan", "Акмола", "Ақмола", "Akmola", "Целиноград"}},
	{City{3, "Шымкент", "Шымкент", "Shymkent"}, []string{"Чимкент", "Chimkent"}},
	{City{4, "Караганда", "Қарағанды", "Karaganda"}, []string{"Караганды", "Karagandy", "Qaragandy"}},
	{City{5, "Тараз", "Тараз", "Taraz"}, []string{"Джамбул", "Жамбыл", "Dzhambul", "Zhambyl"}},
	{City{6, "Актобе", "Ақтөбе", "Aktobe"}, []string{"Актюбинск", "Aqtobe", "Aktyubinsk"}},
	{City{7, "Павлодар", "Павлодар", "Pavlodar"}, nil},
	{City{8, "Усть-Каменогорск", "Өскемен", "Oskemen"}, []string{"Оскемен", "Ust-Kamenogorsk", "Öskemen"}},
	{City{9, "Семей", "Семей", "Semey"}, []string{"Семипалатинск", "Semei", "Semipalatinsk"}},
	{City{10, "Костанай", "Қостанай", "Kostanay"}, []string{"Кустанай", "Qostanay", "Kostanai", "Kustanay"}},
	{City{11, "Кызылорда", "Қызылорда", "Kyzylorda"}, []string{"Кзыл-Орда", "Qyzylorda"}},
	{City{12, "Атырау", "Атырау", "Atyrau"}, []string{"Гурьев", "Guryev"}},
	{City{13, "Актау", "Ақтау", "Aktau"}, []string{"Aqtau"}},
	{City{14, "Уральск", "Орал", "Oral"}, []string{"Uralsk"}},
	{City{15, "Туркестан", "Түркістан", "Turkistan"}, []string{"Туркістан", "Түркестан", "Turkestan"}},
	{City{16, "Петропавловск", "Петропавл", "Petropavl"}, []string{"Petropavlovsk"}},
	{City{17, "Талдыкорган", "Талдықорған", "Taldykorgan"}, []string{"Талдыкорған", "Taldyqorgan"}},
}

// aliasToID maps every normalized name/alias to its city's ID. Built once
// at init; a duplicate alias across two cities is a programming error and
// panics at startup (also covered by a test).
var aliasToID = func() map[string]int {
	m := map[string]int{}
	for _, e := range directory {
		names := append([]string{e.NameRU, e.NameKZ, e.NameEN}, e.aliases...)
		for _, n := range names {
			key := Normalize(n)
			if prev, ok := m[key]; ok && prev != e.ID {
				panic("cities: alias " + n + " belongs to two cities")
			}
			m[key] = e.ID
		}
	}
	return m
}()

// All returns every city in stable display order (a copy — callers can't
// mutate the directory).
func All() []City {
	out := make([]City, len(directory))
	for i, e := range directory {
		out[i] = e.City
	}
	return out
}

// ByID looks a city up by its stable ID.
func ByID(id int) (City, bool) {
	for _, e := range directory {
		if e.ID == id {
			return e.City, true
		}
	}
	return City{}, false
}

// Normalize is the one comparison form for city text: surrounding
// whitespace trimmed, Unicode-aware lowercase (Cyrillic and Kazakh letters
// included), hyphens treated as spaces and inner whitespace collapsed — so
// "Алматы ", "АЛМАТЫ" and "алматы" are equal, as are "Алма-Ата" and
// "алма ата".
func Normalize(s string) string {
	s = strings.ToLower(strings.ReplaceAll(s, "-", " "))
	return strings.Join(strings.Fields(s), " ")
}

// IDForText resolves free-text city input to a city ID; 0 when the text is
// blank or not a known name/alias.
func IDForText(cityText string) int {
	key := Normalize(cityText)
	if key == "" {
		return 0
	}
	return aliasToID[key]
}

// MatchesCity reports whether a stored free-text city belongs to cityID.
// Blank text never matches.
func MatchesCity(cityText string, cityID int) bool {
	id := IDForText(cityText)
	return id != 0 && id == cityID
}
