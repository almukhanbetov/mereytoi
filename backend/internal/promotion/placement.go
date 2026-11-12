// Package promotion holds the store-independent rules of paid promotion:
// where ads go in a catalog result, in which order advertisers rotate, the
// signed pagination cursor, and verification of store purchases.
package promotion

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"sort"
	"strings"
)

// Item is one position of a merged result.
type Item struct {
	ListingID uint
	Promoted  bool
}

// Layout says where ads go: the first at 1-based position First, then one
// after every Every regular cards.
type Layout struct {
	First int
	Every int
}

// Valid reports whether the layout can place anything.
func (l Layout) Valid() bool { return l.First >= 1 && l.Every >= 1 }

// slots is how many ads fit around n regular cards: an ad needs First-1
// regular cards before the first slot and Every more before each next one,
// so an ad never lands in an empty tail or next to another ad.
func (l Layout) slots(n int) int {
	if !l.Valid() || n < l.First-1 {
		return 0
	}
	return 1 + (n-(l.First-1))/l.Every
}

// Merge builds the full result. organic is the regular result in its own
// order; ads is the rotation order of promoted listings, every one of which
// must also match the query (callers take ads from the same result).
//
// A listing shown as an ad is removed from the regular part, so it appears
// once; promoted listings that don't get a slot stay where they were in the
// regular order. Regular cards keep their relative order. With no ads, or
// no room for one, the regular result comes back unchanged — no gaps.
func Merge(organic, ads []uint, layout Layout) []Item {
	inOrganic := make(map[uint]bool, len(organic))
	for _, id := range organic {
		inOrganic[id] = true
	}
	// Only ads that are part of this result, once each.
	seen := map[uint]bool{}
	var candidates []uint
	for _, id := range ads {
		if inOrganic[id] && !seen[id] {
			seen[id] = true
			candidates = append(candidates, id)
		}
	}

	// The most ads k such that the regular cards left after removing them
	// still have room for k slots.
	k := len(candidates)
	for k > 0 && layout.slots(len(organic)-k) < k {
		k--
	}
	placed := make(map[uint]bool, k)
	for _, id := range candidates[:k] {
		placed[id] = true
	}

	out := make([]Item, 0, len(organic))
	next := 0    // next ad to place
	regular := 0 // regular cards emitted so far
	emitDue := func() {
		for next < k && regular == layout.First-1+next*layout.Every {
			out = append(out, Item{ListingID: candidates[next], Promoted: true})
			next++
		}
	}
	emitDue()
	for _, id := range organic {
		if placed[id] {
			continue
		}
		out = append(out, Item{ListingID: id})
		regular++
		emitDue()
	}
	return out
}

// Candidate is a promoted listing eligible for this result.
type Candidate struct {
	ListingID    uint
	AdvertiserID uint // the owner; one advertiser may promote several listings
	Impressions  uint // counted so far for its running promotion
}

// Rotate orders candidates so advertisers take turns: round-robin across
// advertisers (the least-shown advertiser first), and inside one
// advertiser its least-shown listing first. tiebreak decides equal counts
// (a per-request seed, so equally-shown advertisers share the top slot).
func Rotate(cands []Candidate, tiebreak func(uint) uint64) []uint {
	byAdv := map[uint][]Candidate{}
	total := map[uint]uint{}
	for _, c := range cands {
		byAdv[c.AdvertiserID] = append(byAdv[c.AdvertiserID], c)
		total[c.AdvertiserID] += c.Impressions
	}
	advs := make([]uint, 0, len(byAdv))
	for a, list := range byAdv {
		sort.Slice(list, func(i, j int) bool {
			if list[i].Impressions != list[j].Impressions {
				return list[i].Impressions < list[j].Impressions
			}
			return tiebreak(list[i].ListingID) < tiebreak(list[j].ListingID)
		})
		advs = append(advs, a)
	}
	sort.Slice(advs, func(i, j int) bool {
		ai, aj := advs[i], advs[j]
		// Per listing, so an advertiser with many listings isn't punished
		// for their combined count against a single-listing advertiser.
		ri := float64(total[ai]) / float64(len(byAdv[ai]))
		rj := float64(total[aj]) / float64(len(byAdv[aj]))
		if ri != rj {
			return ri < rj
		}
		return tiebreak(ai+1<<32) < tiebreak(aj+1<<32)
	})
	var out []uint
	for round := 0; ; round++ {
		added := false
		for _, a := range advs {
			if round < len(byAdv[a]) {
				out = append(out, byAdv[a][round].ListingID)
				added = true
			}
		}
		if !added {
			return out
		}
	}
}

// Cursor carries what a next page needs to continue the same result: the
// ad order chosen for page one (so later pages can't repeat or reshuffle
// ads), the offset, and a fingerprint of the query it belongs to.
type Cursor struct {
	Query  string `json:"q"`
	Ads    []uint `json:"a"`
	Offset int    `json:"o"`
}

// ErrBadCursor means the cursor is malformed, forged or for another query.
var ErrBadCursor = errors.New("invalid cursor")

// MaxCursorAds bounds the ad list a cursor can carry.
const MaxCursorAds = 200

// Sign encodes the cursor with an HMAC so clients can't edit the ad order.
func (c Cursor) Sign(secret string) string {
	if len(c.Ads) > MaxCursorAds {
		c.Ads = c.Ads[:MaxCursorAds]
	}
	data, _ := json.Marshal(c)
	body := base64.RawURLEncoding.EncodeToString(data)
	return body + "." + mac(secret, body)
}

// ParseCursor checks the signature and that the cursor is for query.
func ParseCursor(raw, secret, query string) (Cursor, error) {
	body, sig, ok := strings.Cut(raw, ".")
	if !ok || !hmac.Equal([]byte(sig), []byte(mac(secret, body))) {
		return Cursor{}, ErrBadCursor
	}
	data, err := base64.RawURLEncoding.DecodeString(body)
	if err != nil {
		return Cursor{}, ErrBadCursor
	}
	var c Cursor
	if err := json.Unmarshal(data, &c); err != nil || c.Offset < 0 || c.Query != query || len(c.Ads) > MaxCursorAds {
		return Cursor{}, ErrBadCursor
	}
	return c, nil
}

func mac(secret, body string) string {
	m := hmac.New(sha256.New, []byte("promotion-cursor:"+secret))
	m.Write([]byte(body))
	return base64.RawURLEncoding.EncodeToString(m.Sum(nil))
}

// QueryKey fingerprints the filters of a catalog request.
func QueryKey(parts ...string) string {
	h := sha256.Sum256([]byte(strings.Join(parts, "\x00")))
	return base64.RawURLEncoding.EncodeToString(h[:12])
}
