package promotion

import (
	"fmt"
	"testing"
)

func ids(n int) []uint {
	out := make([]uint, n)
	for i := range out {
		out[i] = uint(i + 1)
	}
	return out
}

func render(items []Item) string {
	s := ""
	for i, it := range items {
		if i > 0 {
			s += " "
		}
		if it.Promoted {
			s += fmt.Sprintf("[%d]", it.ListingID)
		} else {
			s += fmt.Sprintf("%d", it.ListingID)
		}
	}
	return s
}

var defaultLayout = Layout{First: 2, Every: 6}

func TestMergeFirstAdIsSecondThenEverySix(t *testing.T) {
	// 20 regular results, ads 15, 3, 18 (all part of the result).
	got := render(Merge(ids(20), []uint{15, 3, 18}, defaultLayout))
	want := "1 [15] 2 4 5 6 7 8 [3] 9 10 11 12 13 14 [18] 16 17 19 20"
	if got != want {
		t.Fatalf("\n got %s\nwant %s", got, want)
	}
}

func TestMergeNoAdsKeepsRegularResult(t *testing.T) {
	if got := render(Merge(ids(5), nil, defaultLayout)); got != "1 2 3 4 5" {
		t.Fatal(got)
	}
	// An ad that is not part of this result (other city/category/search)
	// never appears.
	if got := render(Merge(ids(5), []uint{99}, defaultLayout)); got != "1 2 3 4 5" {
		t.Fatal(got)
	}
}

func TestMergeNeverLeavesGapsOrAdjacentAds(t *testing.T) {
	// Only 3 regular cards left after taking one ad: room for one slot.
	if got := render(Merge(ids(4), []uint{2, 3, 4}, defaultLayout)); got != "1 [2] 3 4" {
		t.Fatal(got)
	}
	// One result which is itself promoted: no regular card before slot 1,
	// so it stays a regular card instead of an ad on an empty page.
	if got := render(Merge(ids(1), []uint{1}, defaultLayout)); got != "1" {
		t.Fatal(got)
	}
	if got := render(Merge(nil, []uint{1}, defaultLayout)); got != "" {
		t.Fatal(got)
	}
	for n := 0; n < 40; n++ {
		for a := 0; a <= n; a++ {
			items := Merge(ids(n), ids(a), defaultLayout)
			if len(items) != n {
				t.Fatalf("n=%d a=%d: %d items, every listing must appear exactly once", n, a, len(items))
			}
			seen := map[uint]bool{}
			for i, it := range items {
				if seen[it.ListingID] {
					t.Fatalf("n=%d a=%d: %d twice", n, a, it.ListingID)
				}
				seen[it.ListingID] = true
				if it.Promoted && i > 0 && items[i-1].Promoted {
					t.Fatalf("n=%d a=%d: adjacent ads in %s", n, a, render(items))
				}
				if it.Promoted && i == 0 {
					t.Fatalf("n=%d a=%d: ad in position 1", n, a)
				}
			}
		}
	}
}

func TestMergeKeepsRegularOrder(t *testing.T) {
	organic := []uint{9, 4, 7, 1, 8, 2, 6, 3, 5}
	items := Merge(organic, []uint{7, 2}, defaultLayout)
	var regular []uint
	for _, it := range items {
		if !it.Promoted {
			regular = append(regular, it.ListingID)
		}
	}
	want := []uint{9, 4, 1, 8, 6, 3, 5} // 7 and 2 became ads, the rest kept their order
	if fmt.Sprint(regular) != fmt.Sprint(want) {
		t.Fatalf("regular order %v, want %v", regular, want)
	}
}

func TestMergeDuplicateAdsAreIgnored(t *testing.T) {
	if got := render(Merge(ids(10), []uint{5, 5, 5}, defaultLayout)); got != "1 [5] 2 3 4 6 7 8 9 10" {
		t.Fatal(got)
	}
}

func TestMergeCustomLayout(t *testing.T) {
	if got := render(Merge(ids(6), []uint{6, 5}, Layout{First: 1, Every: 2})); got != "[6] 1 2 [5] 3 4" {
		t.Fatal(got)
	}
	if got := render(Merge(ids(3), []uint{1}, Layout{})); got != "1 2 3" {
		t.Fatalf("invalid layout must place nothing, got %s", got)
	}
}

func noTiebreak(id uint) uint64 { return uint64(id) }

func TestRotateAlternatesAdvertisers(t *testing.T) {
	// Advertiser 1 promotes three listings, advertiser 2 one, advertiser 3 one.
	got := Rotate([]Candidate{
		{ListingID: 10, AdvertiserID: 1, Impressions: 0},
		{ListingID: 11, AdvertiserID: 1, Impressions: 0},
		{ListingID: 12, AdvertiserID: 1, Impressions: 0},
		{ListingID: 20, AdvertiserID: 2, Impressions: 0},
		{ListingID: 30, AdvertiserID: 3, Impressions: 0},
	}, noTiebreak)
	if fmt.Sprint(got) != "[10 20 30 11 12]" {
		t.Fatalf("got %v: one advertiser must not take every slot", got)
	}
}

func TestRotateLeastShownFirst(t *testing.T) {
	got := Rotate([]Candidate{
		{ListingID: 10, AdvertiserID: 1, Impressions: 500},
		{ListingID: 20, AdvertiserID: 2, Impressions: 20},
		{ListingID: 30, AdvertiserID: 3, Impressions: 100},
	}, noTiebreak)
	if fmt.Sprint(got) != "[20 30 10]" {
		t.Fatalf("got %v", got)
	}
	// Inside one advertiser the least-shown listing goes first.
	got = Rotate([]Candidate{
		{ListingID: 10, AdvertiserID: 1, Impressions: 9},
		{ListingID: 11, AdvertiserID: 1, Impressions: 2},
	}, noTiebreak)
	if fmt.Sprint(got) != "[11 10]" {
		t.Fatalf("got %v", got)
	}
}

func TestRotateTiebreakSharesTopSlot(t *testing.T) {
	cands := []Candidate{{ListingID: 1, AdvertiserID: 1}, {ListingID: 2, AdvertiserID: 2}}
	first := map[uint]bool{}
	for seed := uint64(0); seed < 8; seed++ {
		s := seed
		got := Rotate(cands, func(id uint) uint64 { return (uint64(id) * 0x9E3779B97F4A7C15) ^ s*0xBF58476D1CE4E5B9 })
		first[got[0]] = true
	}
	if !first[1] || !first[2] {
		t.Fatalf("equally-shown advertisers should both get the first slot across seeds, got %v", first)
	}
}

func TestCursorRoundTripAndTamper(t *testing.T) {
	q := QueryKey("hosts", "1", "ерлан")
	raw := Cursor{Query: q, Ads: []uint{3, 1}, Offset: 20}.Sign("s3cret")
	c, err := ParseCursor(raw, "s3cret", q)
	if err != nil || c.Offset != 20 || fmt.Sprint(c.Ads) != "[3 1]" {
		t.Fatalf("round trip: %+v %v", c, err)
	}
	if _, err := ParseCursor(raw, "other", q); err != ErrBadCursor {
		t.Fatal("wrong secret must fail")
	}
	if _, err := ParseCursor(raw, "s3cret", QueryKey("venues", "1", "")); err != ErrBadCursor {
		t.Fatal("cursor of another query must fail")
	}
	forged := Cursor{Query: q, Ads: []uint{9}, Offset: 0}.Sign("guess")
	if _, err := ParseCursor(forged, "s3cret", q); err != ErrBadCursor {
		t.Fatal("forged cursor must fail")
	}
	if _, err := ParseCursor("garbage", "s3cret", q); err != ErrBadCursor {
		t.Fatal("garbage must fail")
	}
}
