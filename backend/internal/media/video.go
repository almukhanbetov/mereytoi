package media

import (
	"os"
	"path/filepath"
	"strings"
)

// uploadsURLPrefix is where the backend serves its uploads dir.
const uploadsURLPrefix = "/uploads/"

// Video is one entry of a listing's API "videos" field: the video URL as
// stored (identical to the matching video_urls entry) plus its poster's URL,
// or null while no poster file exists.
type Video struct {
	URL       string  `json:"url"`
	PosterURL *string `json:"poster_url"`
}

// PosterURLFor maps an uploaded video's URL to its poster's URL
// ("/uploads/123.mp4" → "/uploads/posters/123.jpg", see PosterPathFor) and
// the poster's path under uploadsDir. ok is false for anything that isn't a
// plain file directly in /uploads with a video extension — external URLs,
// subfolders, "..", hidden names, query strings — so a stored URL can never
// steer the lookup outside the posters folder.
func PosterURLFor(videoURL, uploadsDir string) (posterURL, posterPath string, ok bool) {
	name, found := strings.CutPrefix(videoURL, uploadsURLPrefix)
	if !found || name == "" || strings.ContainsAny(name, `/\?#`) ||
		strings.HasPrefix(name, ".") || !posterVideoExt[strings.ToLower(filepath.Ext(name))] {
		return "", "", false
	}
	poster := filepath.Base(PosterPathFor(name))
	return uploadsURLPrefix + PosterDirName + "/" + poster,
		filepath.Join(uploadsDir, PosterDirName, poster), true
}

// VideosWithPosters builds the "videos" field for videoURLs, in the same
// order, setting PosterURL only when a non-empty poster file is already on
// disk. It only looks — never generates — and checks each poster once per
// call even if a URL repeats. Never nil, so the field is always an array.
func VideosWithPosters(videoURLs []string, uploadsDir string) []Video {
	videos := make([]Video, 0, len(videoURLs))
	exists := map[string]bool{}
	for _, u := range videoURLs {
		v := Video{URL: u}
		if posterURL, posterPath, ok := PosterURLFor(u, uploadsDir); ok {
			has, seen := exists[posterPath]
			if !seen {
				info, err := os.Stat(posterPath)
				has = err == nil && info.Mode().IsRegular() && info.Size() > 0
				exists[posterPath] = has
			}
			if has {
				v.PosterURL = &posterURL
			}
		}
		videos = append(videos, v)
	}
	return videos
}
