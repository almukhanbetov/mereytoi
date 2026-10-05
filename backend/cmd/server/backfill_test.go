package main

import (
	"testing"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/media"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

func TestLoadBackfillVideosReadsAllListings(t *testing.T) {
	database, err := gorm.Open(sqlite.Open("file::memory:"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := database.AutoMigrate(&models.Category{}, &models.Listing{}); err != nil {
		t.Fatal(err)
	}
	cat := models.Category{Slug: "c", NameRu: "c", NameKz: "c"}
	database.Create(&cat)
	listings := []models.Listing{
		{CategoryID: cat.ID, NameRu: "a", NameKz: "a", IsActive: true, VideoURLs: []string{"/uploads/1.mp4", "https://x/y.mp4"}},
		{CategoryID: cat.ID, NameRu: "b", NameKz: "b", IsActive: true},
		{CategoryID: cat.ID, NameRu: "c", NameKz: "c", IsActive: true, VideoURLs: []string{"/uploads/1.mp4"}},
	}
	for i := range listings {
		database.Create(&listings[i])
	}
	// Inactive listings are included too (they can be switched back on).
	database.Model(&listings[2]).Update("is_active", false)

	var before models.Listing
	database.First(&before, listings[0].ID)

	got, err := loadBackfillVideos(database)
	if err != nil {
		t.Fatal(err)
	}
	want := []media.BackfillVideo{
		{ListingID: listings[0].ID, URL: "/uploads/1.mp4"},
		{ListingID: listings[0].ID, URL: "https://x/y.mp4"},
		{ListingID: listings[2].ID, URL: "/uploads/1.mp4"},
	}
	if len(got) != len(want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("[%d] got %+v, want %+v", i, got[i], want[i])
		}
	}

	var after models.Listing
	database.First(&after, listings[0].ID)
	if !after.UpdatedAt.Equal(before.UpdatedAt) {
		t.Error("reading must not touch the listing")
	}
}
