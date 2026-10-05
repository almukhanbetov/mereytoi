package media

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPosterURLFor(t *testing.T) {
	url, path, ok := PosterURLFor("/uploads/1788712840932742688.mp4", "uploads")
	if !ok || url != "/uploads/posters/1788712840932742688.jpg" || path != filepath.Join("uploads", "posters", "1788712840932742688.jpg") {
		t.Errorf("got %q, %q, %v", url, path, ok)
	}
	if url, _, ok := PosterURLFor("/uploads/Clip.MOV", "uploads"); !ok || url != "/uploads/posters/Clip.jpg" {
		t.Errorf("mov: got %q, %v", url, ok)
	}

	for _, bad := range []string{
		"",
		"https://cdn.example.com/uploads/1.mp4", // external
		"//evil.example/uploads/1.mp4",
		"uploads/1.mp4", // not the served prefix
		"/uploads/",
		"/uploads/../etc/passwd.mp4", // traversal
		"/uploads/..%2f1.mp4",
		"/uploads/a/1.mp4",   // subfolder
		`/uploads/a\1.mp4`,   // backslash
		"/uploads/.1.mp4",    // hidden
		"/uploads/1.mp4?x=1", // query
		"/uploads/1.mp4#t=5",
		"/uploads/1.jpg", // not a video
		"/uploads/1",
	} {
		if url, path, ok := PosterURLFor(bad, "uploads"); ok {
			t.Errorf("PosterURLFor(%q) = %q, %q; want ignored", bad, url, path)
		}
	}
}

func writePoster(t *testing.T, dir, name string, data []byte) {
	t.Helper()
	os.MkdirAll(filepath.Join(dir, PosterDirName), 0755)
	if err := os.WriteFile(filepath.Join(dir, PosterDirName, name), data, 0644); err != nil {
		t.Fatal(err)
	}
}

func TestVideosWithPosters(t *testing.T) {
	dir := t.TempDir()
	writePoster(t, dir, "1.jpg", fakeJPEG)
	writePoster(t, dir, "3.jpg", fakeJPEG)
	writePoster(t, dir, "empty.jpg", nil) // half-made: treated as missing
	os.MkdirAll(filepath.Join(dir, PosterDirName, "dir.jpg"), 0755)

	in := []string{
		"/uploads/1.mp4",                // poster exists
		"/uploads/2.mp4",                // no poster yet
		"/uploads/3.mp4",                // poster exists
		"https://youtu.be/x.mp4",        // external
		"/uploads/../posters/1.jpg.mp4", // malformed
		"/uploads/empty.mp4",
		"/uploads/dir.mp4",
		"/uploads/1.mp4", // repeated
	}
	want := []string{
		"/uploads/posters/1.jpg", "", "/uploads/posters/3.jpg", "", "", "", "", "/uploads/posters/1.jpg",
	}

	got := VideosWithPosters(in, dir)
	if len(got) != len(in) {
		t.Fatalf("len = %d, want %d", len(got), len(in))
	}
	for i, v := range got {
		if v.URL != in[i] {
			t.Errorf("[%d] url = %q, want %q (order/value must match video_urls)", i, v.URL, in[i])
		}
		poster := ""
		if v.PosterURL != nil {
			poster = *v.PosterURL
		}
		if poster != want[i] {
			t.Errorf("[%d] %s: poster_url = %q, want %q", i, in[i], poster, want[i])
		}
	}
}

func TestVideosWithPostersNeverNil(t *testing.T) {
	if v := VideosWithPosters(nil, t.TempDir()); v == nil || len(v) != 0 {
		t.Errorf("got %#v, want an empty non-nil slice", v)
	}
}

func TestVideosWithPostersDoesNotGenerate(t *testing.T) {
	dir := t.TempDir()
	VideosWithPosters([]string{"/uploads/1.mp4"}, dir)
	if _, err := os.Stat(filepath.Join(dir, PosterDirName)); !os.IsNotExist(err) {
		t.Errorf("a lookup must not create anything, stat err = %v", err)
	}
}
