package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type SiteStatisticsHandler struct {
	DB *gorm.DB
}

func NewSiteStatisticsHandler(db *gorm.DB) *SiteStatisticsHandler {
	return &SiteStatisticsHandler{DB: db}
}

const maxStatValue = 100_000_000

// getOrSeed returns the single statistics row, creating it with the
// homepage's original hardcoded values the first time it's requested.
func (h *SiteStatisticsHandler) getOrSeed() (models.SiteStatistics, error) {
	var stats models.SiteStatistics
	err := h.DB.First(&stats).Error
	if err == gorm.ErrRecordNotFound {
		stats = models.SiteStatistics{
			EventsCount:      250,
			HappyGuestsCount: 15000,
			YearsExperience:  8,
			CitiesCount:      5,
		}
		err = h.DB.Create(&stats).Error
	}
	return stats, err
}

func statsJSON(s models.SiteStatistics) gin.H {
	return gin.H{
		"events_count":       s.EventsCount,
		"happy_guests_count": s.HappyGuestsCount,
		"years_experience":   s.YearsExperience,
		"cities_count":       s.CitiesCount,
	}
}

// Get returns the homepage statistics — GET /api/site-statistics (public).
func (h *SiteStatisticsHandler) Get(c *gin.Context) {
	stats, err := h.getOrSeed()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch statistics"})
		return
	}
	c.JSON(http.StatusOK, statsJSON(stats))
}

type siteStatisticsInput struct {
	EventsCount      *int `json:"events_count"`
	HappyGuestsCount *int `json:"happy_guests_count"`
	YearsExperience  *int `json:"years_experience"`
	CitiesCount      *int `json:"cities_count"`
}

func validStat(v *int) bool {
	return v == nil || (*v >= 0 && *v <= maxStatValue)
}

// Update edits one or more statistics fields — PUT /api/site-statistics
// (admin). Omitted fields are left unchanged.
func (h *SiteStatisticsHandler) Update(c *gin.Context) {
	var in siteStatisticsInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "values must be whole numbers"})
		return
	}

	if !validStat(in.EventsCount) || !validStat(in.HappyGuestsCount) || !validStat(in.YearsExperience) || !validStat(in.CitiesCount) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "values must be integers between 0 and 100000000"})
		return
	}

	stats, err := h.getOrSeed()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch statistics"})
		return
	}

	if in.EventsCount != nil {
		stats.EventsCount = *in.EventsCount
	}
	if in.HappyGuestsCount != nil {
		stats.HappyGuestsCount = *in.HappyGuestsCount
	}
	if in.YearsExperience != nil {
		stats.YearsExperience = *in.YearsExperience
	}
	if in.CitiesCount != nil {
		stats.CitiesCount = *in.CitiesCount
	}

	if err := h.DB.Save(&stats).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update statistics"})
		return
	}

	c.JSON(http.StatusOK, statsJSON(stats))
}
