package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/almukhanbetov/mereytoi/backend/internal/models"
)

type EventTaskHandler struct {
	DB *gorm.DB
}

func NewEventTaskHandler(db *gorm.DB) *EventTaskHandler {
	return &EventTaskHandler{DB: db}
}

type taskInput struct {
	Title      string  `json:"title" binding:"required"`
	AssigneeID *uint   `json:"assignee_id"`
	DueDate    *string `json:"due_date"`
}

// Create — POST /api/events/:id/tasks (editor+).
func (h *EventTaskHandler) Create(c *gin.Context) {
	var in taskInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	eventID := currentEventID(c)
	task := models.EventTask{
		EventID:     eventID,
		Title:       in.Title,
		AssigneeID:  in.AssigneeID,
		DueDate:     parseEventDate(in.DueDate),
		Status:      models.TaskTodo,
		CreatedByID: currentUserID(c),
	}
	if err := h.DB.Create(&task).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create task"})
		return
	}

	logActivity(h.DB, eventID, currentUserID(c), "task.created", map[string]any{"title": task.Title})
	c.JSON(http.StatusCreated, gin.H{"task": task})
}

// List — GET /api/events/:id/tasks (any member).
func (h *EventTaskHandler) List(c *gin.Context) {
	var tasks []models.EventTask
	if err := h.DB.Preload("Assignee").Where("event_id = ?", currentEventID(c)).Order("created_at asc").Find(&tasks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch tasks"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"tasks": tasks})
}

type updateTaskInput struct {
	Title      *string `json:"title"`
	AssigneeID *uint   `json:"assignee_id"`
	DueDate    *string `json:"due_date"`
	Status     *string `json:"status" binding:"omitempty,oneof=todo doing done"`
}

// Update — PUT /api/events/:id/tasks/:taskId. Editing title/assignee/due
// date needs editor+; marking done/undone is allowed for any member
// (including viewers) — "другой участник отмечает task выполненным" from
// the brief — enforced here by only requiring editor+ when something other
// than Status is being changed.
func (h *EventTaskHandler) Update(c *gin.Context) {
	taskID, ok := atoiParam(c, "taskId")
	if !ok {
		return
	}

	var task models.EventTask
	if err := h.DB.Where("id = ? AND event_id = ?", taskID, currentEventID(c)).First(&task).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "task not found"})
		return
	}

	var in updateTaskInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	onlyStatusChange := in.Title == nil && in.AssigneeID == nil && in.DueDate == nil
	if !onlyStatusChange && models.RoleRank(currentEventRole(c)) < models.RoleRank(models.EventRoleEditor) {
		c.JSON(http.StatusForbidden, gin.H{"error": "insufficient role"})
		return
	}

	if in.Title != nil {
		task.Title = *in.Title
	}
	if in.AssigneeID != nil {
		task.AssigneeID = in.AssigneeID
	}
	if in.DueDate != nil {
		task.DueDate = parseEventDate(in.DueDate)
	}
	wasCompleted := task.Status == models.TaskDone
	if in.Status != nil {
		task.Status = *in.Status
	}

	if err := h.DB.Save(&task).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update task"})
		return
	}

	if !wasCompleted && task.Status == models.TaskDone {
		logActivity(h.DB, currentEventID(c), currentUserID(c), "task.completed", map[string]any{"title": task.Title})
	}

	c.JSON(http.StatusOK, gin.H{"task": task})
}

// Delete — DELETE /api/events/:id/tasks/:taskId (editor+).
func (h *EventTaskHandler) Delete(c *gin.Context) {
	taskID, ok := atoiParam(c, "taskId")
	if !ok {
		return
	}
	if err := h.DB.Where("id = ? AND event_id = ?", taskID, currentEventID(c)).Delete(&models.EventTask{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete task"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "task deleted"})
}
