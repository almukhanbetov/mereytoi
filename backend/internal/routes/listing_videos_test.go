package routes_test

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// GET /api/listings/:id (the one response web and Flutter render videos
// from) adds "videos": [{url, poster_url}] next to the untouched video_urls.
func TestListingDetailVideosWithPosters(t *testing.T) {
	t.Chdir(t.TempDir()) // the backend serves ./uploads
	os.MkdirAll(filepath.Join("uploads", "posters"), 0755)
	os.WriteFile(filepath.Join("uploads", "posters", "111.jpg"), []byte{0xFF, 0xD8, 0xFF, 0xD9}, 0644)

	srv, db := setupTestServer(t)
	listing := seedListing(t, db, "Video Posters Artist", 0)
	videoURLs := []string{
		"/uploads/111.mp4",              // poster on disk
		"/uploads/222.mp4",              // no poster yet
		"https://example.com/clip.mp4",  // external
		"/uploads/../../etc/passwd.mp4", // malformed
	}
	listing.VideoURLs = videoURLs
	if err := db.Save(&listing).Error; err != nil {
		t.Fatal(err)
	}

	res, err := http.Get(srv.URL + "/api/listings/" + itoa(int(listing.ID)))
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d", res.StatusCode)
	}
	var body struct {
		Listing struct {
			VideoURLs json.RawMessage `json:"video_urls"`
			Videos    []struct {
				URL       string  `json:"url"`
				PosterURL *string `json:"poster_url"`
			} `json:"videos"`
		} `json:"listing"`
	}
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}

	// video_urls: exactly what it always was.
	wantRaw, _ := json.Marshal(videoURLs)
	if string(body.Listing.VideoURLs) != string(wantRaw) {
		t.Errorf("video_urls = %s, want %s", body.Listing.VideoURLs, wantRaw)
	}

	var gotURLs, gotPosters []string
	for _, v := range body.Listing.Videos {
		gotURLs = append(gotURLs, v.URL)
		p := "<null>"
		if v.PosterURL != nil {
			p = *v.PosterURL
		}
		gotPosters = append(gotPosters, p)
	}
	if !reflect.DeepEqual(gotURLs, videoURLs) {
		t.Errorf("videos[].url = %v, want %v", gotURLs, videoURLs)
	}
	wantPosters := []string{"/uploads/posters/111.jpg", "<null>", "<null>", "<null>"}
	if !reflect.DeepEqual(gotPosters, wantPosters) {
		t.Errorf("videos[].poster_url = %v, want %v", gotPosters, wantPosters)
	}

}

// A listing without videos gets "videos": [] — and the list endpoint, which
// no client renders videos from, is left exactly as it was.
func TestListingVideosFieldScope(t *testing.T) {
	t.Chdir(t.TempDir())
	srv, db := setupTestServer(t)
	listing := seedListing(t, db, "No Video Venue", 0)

	_, detail := apiClient{t: t, base: srv.URL}.do("GET", "/api/listings/"+itoa(int(listing.ID)), nil)
	l, _ := detail["listing"].(map[string]any)
	if v, ok := l["videos"].([]any); !ok || len(v) != 0 {
		t.Errorf("detail videos = %#v, want []", l["videos"])
	}

	_, list := apiClient{t: t, base: srv.URL}.do("GET", "/api/listings", nil)
	items, _ := list["listings"].([]any)
	for _, it := range items {
		if _, has := it.(map[string]any)["videos"]; has {
			t.Errorf("list endpoint unexpectedly has videos: %v", it)
		}
	}
}
