package mail

import (
	"bufio"
	"context"
	"net"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// plainSMTPServer answers like a server without STARTTLS, and records whether
// a message body ever reached it.
func plainSMTPServer(t *testing.T) (host, port string, gotData *atomic.Bool) {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	gotData = &atomic.Bool{}
	go func() {
		for {
			conn, err := l.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				r := bufio.NewReader(conn)
				conn.Write([]byte("220 test ESMTP\r\n"))
				inBody := false
				for {
					line, err := r.ReadString('\n')
					if err != nil {
						return
					}
					if inBody {
						if strings.TrimSpace(line) == "." {
							inBody = false
							conn.Write([]byte("250 ok\r\n"))
						}
						continue
					}
					switch cmd := strings.ToUpper(strings.TrimSpace(line)); {
					case strings.HasPrefix(cmd, "EHLO"):
						conn.Write([]byte("250-test\r\n250 SIZE 1000\r\n"))
					case strings.HasPrefix(cmd, "DATA"):
						gotData.Store(true)
						inBody = true
						conn.Write([]byte("354 go\r\n"))
					case strings.HasPrefix(cmd, "QUIT"):
						conn.Write([]byte("221 bye\r\n"))
						return
					default:
						conn.Write([]byte("250 ok\r\n"))
					}
				}
			}()
		}
	}()
	host, port, _ = net.SplitHostPort(l.Addr().String())
	return host, port, gotData
}

func send(t *testing.T, s *SMTPSender) error {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return s.Send(ctx, Message{To: "a@test.local", Subject: "s", TextBody: "secret", HTMLBody: "secret"})
}

func TestTLSRequiredRefusesServerWithoutStartTLS(t *testing.T) {
	host, port, gotData := plainSMTPServer(t)
	err := send(t, &SMTPSender{Host: host, Port: port, UseTLS: true, FromAddr: "f@test.local", FromName: "F"})
	if err == nil || !strings.HasPrefix(err.Error(), "starttls") {
		t.Fatalf("err = %v", err)
	}
	if gotData.Load() {
		t.Fatal("the message went out unencrypted")
	}
}

// A server that accepts and then says nothing must not hold the session open.
func TestStalledServerDoesNotHoldTheSessionForever(t *testing.T) {
	old := sessionTimeout
	sessionTimeout = 100 * time.Millisecond
	defer func() { sessionTimeout = old }()

	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	go func() {
		conn, err := l.Accept()
		if err == nil {
			defer conn.Close()
			time.Sleep(5 * time.Second)
		}
	}()
	host, port, _ := net.SplitHostPort(l.Addr().String())
	s := &SMTPSender{Host: host, Port: port, FromAddr: "f@test.local", FromName: "F"}
	done := make(chan error, 1)
	go func() { done <- s.sendSync(Message{To: "a@test.local"}) }()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("a stalled server counted as delivered")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("the session is still stuck")
	}
}

func TestPlainDeliveryWhenTLSNotRequested(t *testing.T) {
	host, port, gotData := plainSMTPServer(t)
	if err := send(t, &SMTPSender{Host: host, Port: port, FromAddr: "f@test.local", FromName: "F"}); err != nil {
		t.Fatal(err)
	}
	if !gotData.Load() {
		t.Fatal("nothing delivered")
	}
}

func TestOTPEmailCarriesTheCodeInEveryLanguageAndNotInTheSubject(t *testing.T) {
	s := &Service{enabled: true, sender: LogSender{}}
	for _, lang := range []string{"ru", "kz", "en", ""} {
		subject := pick(lang, "Код восстановления пароля MEREYTOI", "MEREYTOI құпиясөзін қалпына келтіру коды", "Your MEREYTOI password recovery code")
		html, text, err := s.renderPasswordResetOTP(lang, subject, "042137")
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(html, "042137") || !strings.Contains(text, "042137") {
			t.Fatalf("%q: no code in the body", lang)
		}
		if strings.Contains(subject, "042137") {
			t.Fatalf("%q: code in the subject", lang)
		}
	}
}

type countingSender struct{ sent int }

func (c *countingSender) Send(context.Context, Message) error {
	c.sent++
	return nil
}

// MAIL_ENABLED governs notifications only; codes use the same sender either way.
func TestMailEnabledGovernsNotificationsNotOTP(t *testing.T) {
	for _, enabled := range []bool{false, true} {
		sender := &countingSender{}
		s := &Service{enabled: enabled, sender: sender}
		s.SendInvitation("ru", "a@test.local", "I", "E", "editor", "tok")
		wantNotifications := 0
		if enabled {
			wantNotifications = 1
		}
		if sender.sent != wantNotifications {
			t.Fatalf("enabled=%v: notifications sent %d", enabled, sender.sent)
		}
		if err := s.SendPasswordResetOTP(context.Background(), "ru", "a@test.local", "042137"); err != nil {
			t.Fatal(err)
		}
		if sender.sent != wantNotifications+1 {
			t.Fatalf("enabled=%v: code not sent", enabled)
		}
	}
}
