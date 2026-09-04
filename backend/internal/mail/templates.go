package mail

import (
	"bytes"
	"embed"
	"fmt"
	"html/template"
	"strings"
)

//go:embed templates/*.tmpl
var templatesFS embed.FS

var htmlTmpl = template.Must(template.ParseFS(templatesFS, "templates/*.html.tmpl"))

// FactRow is one label/value line in an email's small "facts" table (event
// name, role, revision number, manager comment, total, booking ref — every
// email type below uses a different subset of these).
type FactRow struct {
	Label string
	Value string
}

// contentData is the one generic shape every transactional email in this
// stage renders through (templates/transactional.html.tmpl). The brief's
// suggested folder layout names five separate templates (invitation,
// request_changes, request_approved, request_rejected,
// request_submitted_admin) — here that split happens in Go instead, as five
// small build*Data functions in service.go, because the actual HTML/CSS
// structure (heading, paragraphs, an optional facts table, one CTA button)
// is identical across all five; five near-duplicate template files would
// just be the same markup copy-pasted five times with different filenames.
// What differs between them is the *copy and data*, which lives in copy.go
// and service.go instead — same separation-of-concerns goal, less
// duplication. Documented in the 11A stage report.
type contentData struct {
	Heading    string
	Paragraphs []string
	FactRows   []FactRow
	CTAText    string
	CTAURL     string
}

// renderHTML wraps contentData in the shared dark/gold layout used by every
// MEREYTOI transactional email.
func renderHTML(preheader string, data contentData) (string, error) {
	var contentBuf bytes.Buffer
	if err := htmlTmpl.ExecuteTemplate(&contentBuf, "transactional_content", data); err != nil {
		return "", fmt.Errorf("render content: %w", err)
	}

	layoutData := struct {
		Preheader string
		Content   template.HTML
	}{Preheader: preheader, Content: template.HTML(contentBuf.String())} // #nosec G203 -- contentBuf was itself produced by html/template, which already escaped every dynamic value; wrapping it lets the layout template embed already-safe markup instead of re-escaping it into text.

	var out bytes.Buffer
	if err := htmlTmpl.ExecuteTemplate(&out, "layout", layoutData); err != nil {
		return "", fmt.Errorf("render layout: %w", err)
	}
	return out.String(), nil
}

// renderText builds the plain-text fallback part of the email directly from
// the same contentData used for the HTML part — every mail client that
// prefers plain text (or has images/HTML disabled) still gets the full
// content, including the link, not just "please view in HTML."
func renderText(data contentData) string {
	var b strings.Builder
	b.WriteString(data.Heading)
	b.WriteString("\n\n")
	for _, p := range data.Paragraphs {
		b.WriteString(p)
		b.WriteString("\n\n")
	}
	for _, row := range data.FactRows {
		fmt.Fprintf(&b, "%s: %s\n", row.Label, row.Value)
	}
	if len(data.FactRows) > 0 {
		b.WriteString("\n")
	}
	if data.CTAURL != "" {
		fmt.Fprintf(&b, "%s: %s\n", data.CTAText, data.CTAURL)
	}
	b.WriteString("\nMEREYTOI · mereytoi.kz")
	return b.String()
}
