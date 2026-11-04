package mail

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"net"
	"net/smtp"
	"strings"
	"time"
)

const (
	// implicitTLSPort — submission over TLS from the first byte (RFC 8314).
	implicitTLSPort = "465"
	dialTimeout     = 5 * time.Second
)

// sessionTimeout caps a whole SMTP session. net/smtp has no deadlines of its
// own, so without this a server that accepts and then stalls would keep the
// goroutine and the connection forever, long after Send gave up on them.
var sessionTimeout = 30 * time.Second

// SMTPSender is the production transport — plain standard SMTP, no
// provider-specific API/SDK. It also happens to be exactly what a local
// Mailpit/MailHog container speaks (see docker-compose.yml's `mailpit`
// service and MAIL_* in .env.example), so the same code path is used for
// both dev and production; only the env vars differ.
type SMTPSender struct {
	Host     string
	Port     string
	Username string
	Password string
	// UseTLS requires an encrypted connection (SMTP_USE_TLS): TLS from the
	// start on port 465, STARTTLS otherwise. Off, it stays plain, which is
	// what a local Mailpit speaks.
	UseTLS bool
	// FromAddr/FromName build the message's own From header — kept here
	// rather than only in Service, since the raw RFC 5322 message this
	// sender builds needs it too.
	FromAddr string
	FromName string
}

func (s *SMTPSender) Send(ctx context.Context, msg Message) error {
	done := make(chan error, 1)
	go func() { done <- s.sendSync(msg) }()

	// net/smtp has no context-aware API; this is the bounded timeout this
	// project relies on instead of a real queue (brief section 16 — see
	// the mail package doc comment on service.go's deliverTimeout for the
	// tradeoff this was chosen over).
	select {
	case err := <-done:
		return err
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (s *SMTPSender) sendSync(msg Message) error {
	addr := fmt.Sprintf("%s:%s", s.Host, s.Port)

	c, err := s.connect(addr)
	if err != nil {
		return err
	}
	defer c.Close()

	if s.Username != "" {
		if ok, _ := c.Extension("AUTH"); ok {
			auth := smtp.PlainAuth("", s.Username, s.Password, s.Host)
			if err := c.Auth(auth); err != nil {
				return fmt.Errorf("auth: %w", err)
			}
		}
	}

	if err := c.Mail(s.FromAddr); err != nil {
		return fmt.Errorf("mail from: %w", err)
	}
	if err := c.Rcpt(msg.To); err != nil {
		return fmt.Errorf("rcpt to: %w", err)
	}
	w, err := c.Data()
	if err != nil {
		return fmt.Errorf("data: %w", err)
	}
	if _, err := w.Write(buildRawMessage(msg, s.FromAddr, s.FromName)); err != nil {
		return fmt.Errorf("write body: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("close body: %w", err)
	}
	return c.Quit()
}

// connect opens the session, encrypted when UseTLS says so. A server that
// doesn't offer STARTTLS is refused rather than falling back to plain text:
// these messages can carry password reset codes, and anyone on the path can
// strip the offer.
func (s *SMTPSender) connect(addr string) (*smtp.Client, error) {
	tlsConfig := &tls.Config{ServerName: s.Host, MinVersion: tls.VersionTLS12}
	dialer := &net.Dialer{Timeout: dialTimeout}
	if s.UseTLS && s.Port == implicitTLSPort {
		conn, err := tls.DialWithDialer(dialer, "tcp", addr, tlsConfig)
		if err != nil {
			return nil, fmt.Errorf("tls dial %s: %w", addr, err)
		}
		_ = conn.SetDeadline(time.Now().Add(sessionTimeout))
		c, err := smtp.NewClient(conn, s.Host)
		if err != nil {
			conn.Close()
			return nil, fmt.Errorf("smtp session: %w", err)
		}
		return c, nil
	}
	conn, err := dialer.Dial("tcp", addr)
	if err != nil {
		return nil, fmt.Errorf("dial %s: %w", addr, err)
	}
	_ = conn.SetDeadline(time.Now().Add(sessionTimeout))
	c, err := smtp.NewClient(conn, s.Host)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("smtp session: %w", err)
	}
	if s.UseTLS {
		if ok, _ := c.Extension("STARTTLS"); !ok {
			c.Close()
			return nil, errors.New("starttls: not offered by the server")
		}
		if err := c.StartTLS(tlsConfig); err != nil {
			c.Close()
			return nil, fmt.Errorf("starttls: %w", err)
		}
	}
	return c, nil
}

// buildRawMessage assembles a minimal RFC 5322 multipart/alternative
// message (plain text + HTML parts) by hand — this project has no MIME
// library dependency yet and the message shape is simple enough not to
// need one. Headers are ASCII-safe; the Subject is the one header that can
// contain non-ASCII (Cyrillic RU/KZ copy), so it goes through RFC 2047
// Q-encoding.
func buildRawMessage(msg Message, fromAddr, fromName string) []byte {
	const boundary = "mereytoi-boundary-7f3a"

	var b strings.Builder
	fmt.Fprintf(&b, "From: %s <%s>\r\n", fromName, fromAddr)
	fmt.Fprintf(&b, "To: %s\r\n", msg.To)
	fmt.Fprintf(&b, "Subject: %s\r\n", qEncode(msg.Subject))
	if msg.ReplyTo != "" {
		fmt.Fprintf(&b, "Reply-To: %s\r\n", msg.ReplyTo)
	}
	b.WriteString("MIME-Version: 1.0\r\n")
	fmt.Fprintf(&b, "Content-Type: multipart/alternative; boundary=%q\r\n", boundary)
	b.WriteString("\r\n")

	fmt.Fprintf(&b, "--%s\r\n", boundary)
	b.WriteString("Content-Type: text/plain; charset=UTF-8\r\n\r\n")
	b.WriteString(msg.TextBody)
	b.WriteString("\r\n\r\n")

	fmt.Fprintf(&b, "--%s\r\n", boundary)
	b.WriteString("Content-Type: text/html; charset=UTF-8\r\n\r\n")
	b.WriteString(msg.HTMLBody)
	b.WriteString("\r\n\r\n")

	fmt.Fprintf(&b, "--%s--\r\n", boundary)
	return []byte(b.String())
}

// qEncode RFC-2047-encodes a header value that may contain non-ASCII text
// (every subject line here does — RU/KZ copy). Plain ASCII subjects (EN
// fallback) pass through byte-identical, just wrapped in the same encoding,
// which every mail client renders correctly either way.
func qEncode(s string) string {
	return "=?UTF-8?B?" + base64.StdEncoding.EncodeToString([]byte(s)) + "?="
}
