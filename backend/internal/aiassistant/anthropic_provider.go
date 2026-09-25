package aiassistant

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"
)

// maxToolIterations bounds the agentic loop — the model asking for another
// search, reading its result, asking again, etc. Five rounds is generous
// for "find a venue matching these filters" and keeps a worst-case request
// from running away in latency/cost if the model gets stuck re-querying.
const maxToolIterations = 5

// AnthropicProvider is the real, working Provider implementation — Claude
// via the Messages API. Model is configurable (see config.AIAssistantModel)
// so an operator can move to a cheaper/newer model without a code change.
type AnthropicProvider struct {
	client anthropic.Client
	model  string
}

// NewAnthropicProvider builds a client bound to apiKey — never falls back
// to reading ANTHROPIC_API_KEY from the ambient environment itself, so
// "no key configured" is decided once, explicitly, by config.Load (see
// Service.Ask's own ErrNotConfigured check) rather than implicitly by the
// SDK.
func NewAnthropicProvider(apiKey, model string) *AnthropicProvider {
	return &AnthropicProvider{
		client: anthropic.NewClient(option.WithAPIKey(apiKey)),
		model:  model,
	}
}

func (p *AnthropicProvider) Chat(ctx context.Context, req ChatRequest) (string, error) {
	messages := make([]anthropic.MessageParam, 0, len(req.Messages))
	for _, m := range req.Messages {
		block := anthropic.NewTextBlock(m.Content)
		if m.Role == RoleAssistant {
			messages = append(messages, anthropic.NewAssistantMessage(block))
		} else {
			messages = append(messages, anthropic.NewUserMessage(block))
		}
	}

	tools := make([]anthropic.ToolUnionParam, 0, len(req.Tools))
	for _, t := range req.Tools {
		tools = append(tools, anthropic.ToolUnionParam{OfTool: &anthropic.ToolParam{
			Name:        t.Name,
			Description: anthropic.String(t.Description),
			InputSchema: schemaFromMap(t.InputSchema),
		}})
	}

	for i := 0; i < maxToolIterations; i++ {
		resp, err := p.client.Messages.New(ctx, anthropic.MessageNewParams{
			Model:     anthropic.Model(p.model),
			MaxTokens: 1024,
			System:    []anthropic.TextBlockParam{{Text: req.System}},
			Messages:  messages,
			Tools:     tools,
		})
		if err != nil {
			return "", fmt.Errorf("anthropic: %w", err)
		}

		messages = append(messages, resp.ToParam())

		if resp.StopReason != anthropic.StopReasonToolUse {
			return textFromBlocks(resp.Content), nil
		}

		toolResults := make([]anthropic.ContentBlockParamUnion, 0)
		for _, block := range resp.Content {
			toolUse, ok := block.AsAny().(anthropic.ToolUseBlock)
			if !ok {
				continue
			}
			result, isErr := req.Execute(ctx, ToolCall{
				Name:  toolUse.Name,
				Input: json.RawMessage(toolUse.JSON.Input.Raw()),
			})
			toolResults = append(toolResults, anthropic.NewToolResultBlock(toolUse.ID, result, isErr))
		}
		if len(toolResults) == 0 {
			// The model claimed tool_use but no block actually parsed as
			// one — nothing to feed back; stop rather than loop forever.
			return textFromBlocks(resp.Content), nil
		}
		messages = append(messages, anthropic.NewUserMessage(toolResults...))
	}

	return "", errors.New("anthropic: exceeded max tool iterations")
}

func textFromBlocks(blocks []anthropic.ContentBlockUnion) string {
	out := ""
	for _, block := range blocks {
		if text, ok := block.AsAny().(anthropic.TextBlock); ok {
			out += text.Text
		}
	}
	return out
}

// schemaFromMap adapts our vendor-neutral map[string]any JSON Schema into
// the SDK's typed ToolInputSchemaParam — Properties is the only piece every
// tool in this package actually uses (see search.go's tool definition).
func schemaFromMap(schema map[string]any) anthropic.ToolInputSchemaParam {
	props, _ := schema["properties"].(map[string]any)
	return anthropic.ToolInputSchemaParam{Properties: props}
}
