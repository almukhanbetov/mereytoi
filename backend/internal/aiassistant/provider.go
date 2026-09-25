// Package aiassistant is the AI event-planning assistant's server side —
// "подобрать ресторан, зал и услуги для мероприятия" (stage 1 brief). It is
// a deliberately separate feature from Manager Chat (internal/models/
// manager_chat.go) and from the guest lead form (BookingHandler.Create):
// neither of those is touched by anything in this package, and this
// package touches nothing of theirs either.
package aiassistant

import (
	"context"
	"encoding/json"
)

// Role mirrors the two sides of a chat turn — same shape as
// ManagerMessage.SenderType's "user"/"manager" split, just named for a
// model conversation instead.
type Role string

const (
	RoleUser      Role = "user"
	RoleAssistant Role = "assistant"
)

// ChatMessage is one already-exchanged turn. Deliberately plain
// role+content text — tool_use/tool_result bookkeeping lives inside a
// Provider's own Chat loop and is never exposed to callers, so this type
// stays vendor-neutral (brief section 3: "интерфейс провайдера, чтобы
// модель можно было заменить позже").
type ChatMessage struct {
	Role    Role
	Content string
}

// ToolSpec is one function the model may call, described the same way
// every LLM function-calling API wants it (name + description + JSON
// Schema input) — this shape is the lowest common denominator across
// vendors, not Anthropic-specific.
type ToolSpec struct {
	Name        string
	Description string
	InputSchema map[string]any
}

// ToolCall is the model asking to invoke one ToolSpec.
type ToolCall struct {
	Name  string
	Input json.RawMessage
}

// ToolExecutor runs one ToolCall and returns the text to feed back to the
// model. isError marks a failed lookup (e.g. a DB error) as a tool error —
// the model still gets to see it and respond helpfully ("не удалось
// выполнить поиск, попробуйте позже") rather than the whole request
// aborting.
type ToolExecutor func(ctx context.Context, call ToolCall) (result string, isError bool)

// ChatRequest is one full turn: system prompt, conversation so far, the
// tools available, and the executor that actually runs them. Provider.Chat
// owns the entire tool-use loop internally (calling Execute as many times
// as the model asks, up to its own internal iteration cap) and returns only
// the model's final natural-language reply.
type ChatRequest struct {
	System   string
	Messages []ChatMessage
	Tools    []ToolSpec
	Execute  ToolExecutor
}

// Provider is the one seam a real LLM vendor's adapter implements — same
// pattern as this codebase's existing internal/whatsapp.Sender /
// internal/telegram.Sender interfaces: one small method, real
// implementations swapped in via config, nothing else in this package
// (or its caller) needs to know which vendor is behind it.
type Provider interface {
	Chat(ctx context.Context, req ChatRequest) (string, error)
}
