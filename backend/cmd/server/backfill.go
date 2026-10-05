package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
	"github.com/almukhanbetov/mereytoi/backend/internal/media"
	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

// runBackfillPosters is `server backfill-posters [--dry-run]`: makes the
// missing posters for every video already in listings.video_urls. Run by
// hand only (e.g. `docker compose exec backend ./server backfill-posters`),
// never on startup. It only reads the DB — its own plain connection, no
// AutoMigrate, no seed — and only writes poster files. Exit code 1 if any
// video failed.
func runBackfillPosters(args []string) int {
	fs := flag.NewFlagSet("backfill-posters", flag.ContinueOnError)
	dryRun := fs.Bool("dry-run", false, "only report what would be created; write nothing")
	uploadsDir := fs.String("uploads", "./uploads", "uploads directory the backend serves")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	out := log.New(os.Stdout, "", log.LstdFlags)
	database, err := gorm.Open(postgres.Open(config.Load().DSN()), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Warn),
	})
	if err != nil {
		out.Printf("[poster-backfill] cannot connect to the database: %v", err)
		return 1
	}
	videos, err := loadBackfillVideos(database)
	if err != nil {
		out.Printf("[poster-backfill] cannot read listings: %v", err)
		return 1
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	s := media.Backfill(ctx, videos, media.BackfillOptions{
		UploadsDir: *uploadsDir,
		DryRun:     *dryRun,
		Generate:   media.GeneratePoster,
		Log:        out,
	})
	if s.Failed > 0 {
		return 1
	}
	return 0
}

// loadBackfillVideos reads every listing's video_urls (active or not), in
// id order. Read-only.
func loadBackfillVideos(database *gorm.DB) ([]media.BackfillVideo, error) {
	var listings []models.Listing
	if err := database.Select("id", "video_urls").Order("id").Find(&listings).Error; err != nil {
		return nil, err
	}
	var videos []media.BackfillVideo
	for _, l := range listings {
		for _, u := range l.VideoURLs {
			videos = append(videos, media.BackfillVideo{ListingID: l.ID, URL: u})
		}
	}
	return videos, nil
}
