package mail

import (
	"context"
	"log"
	"strconv"
	"time"

	"github.com/almukhanbetov/mereytoi/backend/internal/config"
)

// deliverTimeout bounds how long a single send can add to the request that
// triggered it (brief section 16: "perform post-commit send with timeout
// and clear logging" — the option this stage picked over building a queue;
// see the stage report for the tradeoff). Mailpit/a real SMTP provider
// both complete in well under a second normally; this is a ceiling for the
// pathological case (DNS hang, firewall black-hole), not a normal-path
// budget.
const deliverTimeout = 8 * time.Second

// Service is the one thing handlers depend on — never Sender or SMTP
// details directly. Constructed once in routes.Register from config.Config
// and handed to the handlers that need it (EventMemberHandler,
// EventRequestHandler), the same way *gorm.DB already is.
type Service struct {
	sender      Sender
	enabled     bool
	fromAddr    string
	fromName    string
	frontendURL string
}

// NewService builds the real, config-driven Service — MAIL_DRIVER=log uses
// LogSender (brief section 3's no-container dev option), anything else
// (including the default, "smtp") uses SMTPSender pointed at
// MAIL_HOST/PORT, authenticating only if MAIL_USERNAME is set (so it works
// unauthenticated against a local Mailpit and authenticated against a real
// provider with the same code path).
func NewService(cfg config.Config) *Service {
	var sender Sender
	if cfg.MailDriver == "log" {
		sender = LogSender{}
	} else {
		sender = &SMTPSender{
			Host:     cfg.MailHost,
			Port:     cfg.MailPort,
			Username: cfg.MailUsername,
			Password: cfg.MailPassword,
			UseTLS:   cfg.MailUseTLS,
			FromAddr: cfg.MailFromAddress,
			FromName: cfg.MailFromName,
		}
	}
	return NewServiceWithSender(sender, cfg)
}

// NewServiceWithSender builds a Service around a caller-supplied Sender —
// production never uses this directly (NewService is what routes.Register
// calls); it exists so routes_test.go and mail_test.go can inject a mock
// Sender through the exact same routes.Register entrypoint production uses,
// instead of duplicating the route tree just to test email dispatch.
func NewServiceWithSender(sender Sender, cfg config.Config) *Service {
	return &Service{
		sender:      sender,
		enabled:     cfg.MailEnabled,
		fromAddr:    cfg.MailFromAddress,
		fromName:    cfg.MailFromName,
		frontendURL: cfg.FrontendURL,
	}
}

// deliver is the one place every Send* method below funnels through — it
// owns every cross-cutting rule from the brief: MAIL_ENABLED=false / no
// recipient skip cleanly (section 5, section 21), nothing here ever
// returns an error to the caller (section 14 — a handler cannot fail its
// business transaction over an email), and logging never includes the
// rendered body (section 26 — the invitation link/token lives in there).
func (s *Service) deliver(to, subject string, data contentData) {
	if !s.enabled {
		log.Printf("[mail] skipped (MAIL_ENABLED=false) to=%s subject=%q", to, subject)
		return
	}
	if to == "" {
		log.Printf("[mail] skipped (no recipient email) subject=%q", subject)
		return
	}

	html, err := renderHTML(subject, data)
	if err != nil {
		// A template bug, not a transport failure — still must not fail
		// the caller's business transaction.
		log.Printf("[mail] FAILED to render to=%s subject=%q err=%v", to, subject, err)
		return
	}
	text := renderText(data)

	ctx, cancel := context.WithTimeout(context.Background(), deliverTimeout)
	defer cancel()

	err = s.sender.Send(ctx, Message{
		To:       to,
		Subject:  subject,
		HTMLBody: html,
		TextBody: text,
	})
	if err != nil {
		log.Printf("[mail] FAILED to send to=%s subject=%q err=%v", to, subject, err)
		return
	}
	log.Printf("[mail] sent to=%s subject=%q", to, subject)
}

func (s *Service) link(path string) string {
	return s.frontendURL + path
}

// ---- Typed call sites — one per brief-section-6 email event. Each builds
// its own contentData (heading/paragraphs/facts/CTA, all already localized
// via copy.go's pick()) and hands it to deliver. Lang is accepted per call
// (see copy.go's pick doc comment on why every current call site passes
// "ru") rather than hard-coded, so this is a one-line change at the call
// site, not here, once a stored preference exists.

// SendInvitation — brief section 7. The most important email: a secure,
// already-existing invitation token turned into a clickable link, never a
// raw ID.
func (s *Service) SendInvitation(lang, to, inviterName, eventTitle, role, token string) {
	heading := pick(lang, "Приглашение в "+eventTitle, eventTitle+" — шақыру", "You're invited to "+eventTitle)
	intro := pick(lang,
		inviterName+" приглашает вас помочь спланировать «"+eventTitle+"» на MEREYTOI.",
		inviterName+" сізді MEREYTOI-де «"+eventTitle+"» тойын жоспарлауға көмектесуге шақырады.",
		inviterName+" invited you to help plan \""+eventTitle+"\" on MEREYTOI.")
	explain := pick(lang,
		"Перейдите по ссылке ниже, войдите или зарегистрируйтесь и присоединяйтесь к команде мероприятия.",
		"Төмендегі сілтеме арқылы кіріңіз немесе тіркеліңіз де, іс-шара тобына қосылыңыз.",
		"Open the link below, sign in or register, and join the event's team.")
	cta := pick(lang, "Присоединиться к мероприятию", "Іс-шараға қосылу", "Join event")

	data := contentData{
		Heading:    heading,
		Paragraphs: []string{intro, explain},
		FactRows: []FactRow{
			{Label: pick(lang, "Мероприятие", "Іс-шара", "Event"), Value: eventTitle},
			{Label: pick(lang, "Роль", "Рөл", "Role"), Value: roleLabel(lang, role)},
		},
		CTAText: cta,
		CTAURL:  s.link("/invite/" + token),
	}
	s.deliver(to, heading, data)
}

// SendInvitationAccepted — brief section 6B, explicitly optional; included
// here since it costs nothing extra once SendInvitation exists and the
// in-app equivalent (models.NotifInvitationAccepted) already fires from
// the same call site (event_member_handler.go's AcceptInvitation).
func (s *Service) SendInvitationAccepted(lang, to, memberName, eventTitle string, eventID uint) {
	heading := pick(lang, "Приглашение принято", "Шақыру қабылданды", "Invitation accepted")
	body := pick(lang,
		memberName+" присоединил(ась)ся к «"+eventTitle+"» и теперь может помогать с выбором.",
		memberName+" «"+eventTitle+"» тойына қосылды және енді таңдауға көмектесе алады.",
		memberName+" joined \""+eventTitle+"\" and can now help with planning.")
	cta := pick(lang, "Открыть мероприятие", "Іс-шараны ашу", "Open event")

	data := contentData{
		Heading:    heading,
		Paragraphs: []string{body},
		CTAText:    cta,
		CTAURL:     s.link("/profile/events/" + itoa(eventID)),
	}
	s.deliver(to, heading, data)
}

// SendRequestSubmittedAdmin — brief section 6C / 11. Fired once per
// admin recipient (event_request_handler.go's Submit already resolves
// "every admin" the same way for the in-app notification — see
// adminUserIDs in notification_helpers.go; this reuses that same
// resolution, not a second one).
func (s *Service) SendRequestSubmittedAdmin(lang, to, eventTitle string, requestID, revision uint, resubmitted bool) {
	heading := pick(lang, "Новая заявка", "Жаңа өтінім", "New request")
	if resubmitted {
		heading = pick(lang, "Заявка отправлена повторно", "Өтінім қайта жіберілді", "Request resubmitted")
	}
	body := pick(lang,
		"Организатор отправил заявку по мероприятию «"+eventTitle+"». Проверьте её в панели администратора.",
		"Ұйымдастырушы «"+eventTitle+"» тойы бойынша өтінім жіберді. Оны әкімшілік панелінде тексеріңіз.",
		"The organizer submitted a request for \""+eventTitle+"\". Review it in the admin panel.")
	cta := pick(lang, "Открыть заявку", "Өтінімді ашу", "Open request")

	data := contentData{
		Heading:    heading,
		Paragraphs: []string{body},
		FactRows: []FactRow{
			{Label: pick(lang, "Мероприятие", "Іс-шара", "Event"), Value: eventTitle},
			{Label: pick(lang, "Ревизия", "Түзету", "Revision"), Value: strconv.Itoa(int(revision))},
		},
		CTAText: cta,
		CTAURL:  s.link("/admin/event-requests/" + itoa(requestID)),
	}
	s.deliver(to, heading, data)
}

// SendRequestChangesRequested — brief section 8. Also covers section 6G
// ("important manager comment if not already included in
// changes_requested") — the current API can only set ManagerComment
// together with this exact transition (AdminUpdateStatus requires
// `status`), so the comment is always already here; there is no separate
// "manager left a comment" moment to email about, mirroring why
// models.NotifManagerCommentAdded is likewise declared-but-never-fired.
func (s *Service) SendRequestChangesRequested(lang, to, eventTitle, managerComment string, eventID, revision uint) {
	heading := pick(lang, "Требуются изменения в заявке", "Өтінімге өзгеріс қажет", "Changes requested on your request")
	body := pick(lang,
		"Менеджер MEREYTOI рассмотрел заявку по «"+eventTitle+"» и просит внести изменения перед подтверждением.",
		"MEREYTOI менеджері «"+eventTitle+"» өтінімін қарап, растаудан бұрын өзгеріс енгізуді сұрайды.",
		"MEREYTOI's manager reviewed your request for \""+eventTitle+"\" and asked for changes before approving it.")
	cta := pick(lang, "Открыть заявку", "Өтінімді ашу", "Open request")

	rows := []FactRow{
		{Label: pick(lang, "Мероприятие", "Іс-шара", "Event"), Value: eventTitle},
		{Label: pick(lang, "Ревизия", "Түзету", "Revision"), Value: strconv.Itoa(int(revision))},
	}
	if managerComment != "" {
		rows = append(rows, FactRow{Label: pick(lang, "Комментарий менеджера", "Менеджер пікірі", "Manager's comment"), Value: managerComment})
	}

	data := contentData{
		Heading:    heading,
		Paragraphs: []string{body},
		FactRows:   rows,
		CTAText:    cta,
		CTAURL:     s.link("/profile/events/" + itoa(eventID) + "/request"),
	}
	s.deliver(to, heading, data)
}

// SendRequestApproved — brief section 9.
func (s *Service) SendRequestApproved(lang, to, eventTitle, managerComment string, eventID uint, total uint, bookingRef string) {
	heading := pick(lang, "Заявка подтверждена", "Өтінім расталды", "Request approved")
	body := pick(lang,
		"Отличные новости — ваша заявка по «"+eventTitle+"» подтверждена MEREYTOI.",
		"Жақсы жаңалық — «"+eventTitle+"» бойынша өтініміңіз MEREYTOI тарапынан расталды.",
		"Great news — your request for \""+eventTitle+"\" has been approved by MEREYTOI.")
	cta := pick(lang, "Открыть подтверждённую заявку", "Расталған өтінімді ашу", "Open confirmed request")

	rows := []FactRow{{Label: pick(lang, "Мероприятие", "Іс-шара", "Event"), Value: eventTitle}}
	if total > 0 {
		rows = append(rows, FactRow{Label: pick(lang, "Итоговая сумма", "Жалпы сома", "Total"), Value: formatTenge(total)})
	}
	if bookingRef != "" {
		rows = append(rows, FactRow{Label: pick(lang, "Номер брони", "Брондау нөмірі", "Booking reference"), Value: bookingRef})
	}
	if managerComment != "" {
		rows = append(rows, FactRow{Label: pick(lang, "Комментарий менеджера", "Менеджер пікірі", "Manager's comment"), Value: managerComment})
	}

	data := contentData{
		Heading:    heading,
		Paragraphs: []string{body},
		FactRows:   rows,
		CTAText:    cta,
		CTAURL:     s.link("/profile/events/" + itoa(eventID) + "/request"),
	}
	s.deliver(to, heading, data)
}

// SendRequestRejected — brief section 10.
func (s *Service) SendRequestRejected(lang, to, eventTitle, managerComment string, eventID uint) {
	heading := pick(lang, "Заявка отклонена", "Өтінім қабылданбады", "Request rejected")
	body := pick(lang,
		"К сожалению, заявка по «"+eventTitle+"» была отклонена MEREYTOI.",
		"Өкінішке орай, «"+eventTitle+"» бойынша өтінім MEREYTOI тарапынан қабылданбады.",
		"Unfortunately, your request for \""+eventTitle+"\" was rejected by MEREYTOI.")
	cta := pick(lang, "Открыть мероприятие", "Іс-шараны ашу", "Open event")

	rows := []FactRow{{Label: pick(lang, "Мероприятие", "Іс-шара", "Event"), Value: eventTitle}}
	if managerComment != "" {
		rows = append(rows, FactRow{Label: pick(lang, "Причина", "Себебі", "Reason"), Value: managerComment})
	}

	data := contentData{
		Heading:    heading,
		Paragraphs: []string{body},
		FactRows:   rows,
		CTAText:    cta,
		CTAURL:     s.link("/profile/events/" + itoa(eventID) + "/request"),
	}
	s.deliver(to, heading, data)
}

func itoa(id uint) string { return strconv.FormatUint(uint64(id), 10) }

// formatTenge mirrors frontend/src/lib/format.js's formatPrice — ru-RU
// thousands grouping (space separator) plus the ₸ symbol — so the number
// in an email reads identically to the number the same total is shown as
// everywhere else on the site.
func formatTenge(n uint) string {
	s := strconv.FormatUint(uint64(n), 10)
	var grouped []byte
	for i, c := range []byte(s) {
		if i > 0 && (len(s)-i)%3 == 0 {
			grouped = append(grouped, ' ')
		}
		grouped = append(grouped, c)
	}
	return string(grouped) + " ₸"
}
