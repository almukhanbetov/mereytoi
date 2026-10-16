package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/almukhanbetov/mereytoi/backend/internal/cities"
)

// CityHandler serves the fixed city directory (see internal/cities) — no
// DB involved.
type CityHandler struct{}

func NewCityHandler() *CityHandler {
	return &CityHandler{}
}

// List returns every city in stable display order: GET /api/cities.
func (h *CityHandler) List(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"cities": cities.All()})
}
