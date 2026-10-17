package cities

import (
	"strings"
	"testing"
)

func TestAllHasSeventeenCitiesInStableOrder(t *testing.T) {
	all := All()
	if len(all) != 17 {
		t.Fatalf("want 17 cities, got %d", len(all))
	}
	for i, c := range all {
		if c.ID != i+1 {
			t.Fatalf("position %d: want id %d, got %d (%s)", i, i+1, c.ID, c.NameRU)
		}
		if c.NameRU == "" || c.NameKZ == "" || c.NameEN == "" {
			t.Fatalf("city %d has an empty name: %+v", c.ID, c)
		}
	}
	if all[0].NameRU != "Алматы" || all[1].NameRU != "Астана" || all[16].NameRU != "Талдыкорган" {
		t.Fatalf("unexpected order: %+v", all)
	}

	// All returns a copy — mutating it must not leak into the directory.
	all[0].NameRU = "mutated"
	if All()[0].NameRU != "Алматы" {
		t.Fatal("All() exposed the internal directory")
	}
}

func TestByID(t *testing.T) {
	if c, ok := ByID(15); !ok || c.NameKZ != "Түркістан" {
		t.Fatalf("ByID(15) = %+v, %v", c, ok)
	}
	for _, id := range []int{0, -1, 18, 999} {
		if _, ok := ByID(id); ok {
			t.Fatalf("ByID(%d) should not exist", id)
		}
	}
}

func TestMatchesCityRealProdVariants(t *testing.T) {
	cases := []struct {
		text string
		id   int
	}{
		// Values actually present in prod listings.city.
		{"Алматы", 1}, {"Алматы ", 1}, {"Almaty", 1},
		{"Астана", 2}, {"Шымкент", 3}, {"Түркістан", 15},
		// Case/whitespace/hyphen normalization.
		{"  алматы  ", 1}, {"АЛМАТЫ", 1}, {"almaty", 1}, {"Алма-Ата", 1}, {"алма ата", 1},
		// Turkistan in every expected spelling, incl. mixed-alphabet "Туркістан".
		{"Туркестан", 15}, {"Түркістан", 15}, {"Туркістан", 15}, {"Turkistan", 15}, {"Turkestan", 15},
		// Kazakh names with Kazakh-specific capitals lowercase correctly.
		{"ӨСКЕМЕН", 8}, {"Усть-Каменогорск", 8}, {"ҚАРАҒАНДЫ", 4}, {"Орал", 14}, {"Нұр-Сұлтан", 2},
	}
	for _, tc := range cases {
		if !MatchesCity(tc.text, tc.id) {
			t.Errorf("MatchesCity(%q, %d) = false, want true", tc.text, tc.id)
		}
	}
}

func TestMatchesCityRejects(t *testing.T) {
	cases := []struct {
		text string
		id   int
	}{
		{"", 1}, {"   ", 1}, // blank never belongs to a city
		{"Астана", 1}, // other city
		{"Алм", 1},    // no fuzzy/prefix matching
		{"Алматинская область", 1},
		{"Almaty", 0}, {"Almaty", 99}, // unknown id
	}
	for _, tc := range cases {
		if MatchesCity(tc.text, tc.id) {
			t.Errorf("MatchesCity(%q, %d) = true, want false", tc.text, tc.id)
		}
	}
}

func TestEveryNameResolvesToItsOwnCity(t *testing.T) {
	for _, e := range directory {
		names := append([]string{e.NameRU, e.NameKZ, e.NameEN}, e.aliases...)
		for _, n := range names {
			if got := IDForText(n); got != e.ID {
				t.Errorf("%q resolves to %d, want %d", n, got, e.ID)
			}
			if got := IDForText(" " + strings.ToUpper(n) + " "); got != e.ID {
				t.Errorf("upper-cased %q resolves to %d, want %d", n, got, e.ID)
			}
		}
	}
}
