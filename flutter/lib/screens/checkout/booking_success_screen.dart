import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../domain/pdf/pdf_booking_lines.dart';
import '../../models/booking.dart';
import '../../services/pdf_service.dart';
import '../../state/booking_submit_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/providers.dart';
import '../../widgets/app_icon_badge.dart';
import '../auth/login_screen.dart';
import '../claim/claim_screen.dart';
import '../manager_chat/manager_chat_screen.dart';
import '../root_shell.dart';

const _pdfService = PdfService();

/// Shown right after a confirmed `POST /api/bookings` (never before —
/// `CheckoutScreen` only gets here via `ref.listen` on a genuine state
/// change to `AsyncData(non-null)`). Renders straight off the server's own
/// response (brief section 8 — "использовать ответ backend, не
/// пересчитывать"): booking number, total, item list, status, plus the
/// three requested CTAs and — additively, only when actually present —
/// the same onboarding block `BookingWorkspaceCTA.jsx` shows on web.
class BookingSuccessScreen extends ConsumerStatefulWidget {
  const BookingSuccessScreen({super.key, required this.result});

  final BookingCreateResult result;

  @override
  ConsumerState<BookingSuccessScreen> createState() =>
      _BookingSuccessScreenState();
}

enum _ResendState { idle, sending, done }

class _BookingSuccessScreenState extends ConsumerState<BookingSuccessScreen> {
  bool _pdfBusy = false;
  _ResendState _resendState = _ResendState.idle;

  Booking get _booking => widget.result.booking;
  BookingOnboarding? get _onboarding => widget.result.onboarding;

  Future<void> _withPdf(Future<void> Function(PdfBookingData) action) async {
    setState(() => _pdfBusy = true);
    try {
      await action(pdfDataFromBooking(_booking));
    } catch (_) {
      if (!mounted) return;
      final locale = ref.read(localeProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              locale,
              ru: 'Не удалось создать PDF',
              kz: 'PDF жасау сәтсіз аяқталды',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _resendClaim() async {
    if (_resendState != _ResendState.idle) return;
    setState(() => _resendState = _ResendState.sending);
    try {
      await ref.read(authServiceProvider).claimResend(_booking.phone);
    } catch (_) {
      // Neutral endpoint (brief section 12) — never surfaces a real error;
      // a network failure here just leaves the customer able to try again.
    } finally {
      if (mounted) setState(() => _resendState = _ResendState.done);
    }
  }

  void _openMyEvent() {
    ref.read(selectedTabProvider.notifier).state = 2;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootShell()),
      (r) => false,
    );
  }

  void _openManagerChat() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ManagerChatScreen()));
  }

  void _finish() {
    ref.read(bookingSubmitProvider.notifier).reset();
    ref.read(selectedTabProvider.notifier).state = 0;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootShell()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final booking = _booking;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            t(locale, ru: 'Заявка отправлена', kz: 'Өтінім жіберілді'),
          ),
        ),
        // Matches the same bottom-safe-area convention every other
        // scrolling-body screen with content near the edge already uses
        // (login/register/profile/claim) — without it, the final button
        // here sits flush against the home indicator / gesture area on a
        // real device instead of clearing it.
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: AppIconBadge(
                  icon: Icons.check_rounded,
                  background: context.mereytoiColors.surfaceSoft,
                  iconColor: context.mereytoiColors.goldPrimary,
                  iconSize: 32,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Text(
                  t(locale, ru: 'Спасибо!', kz: 'Рахмет!'),
                  style: Theme.of(context).textTheme.displayMedium,
                ),
              ),
              if (booking.publicRef.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Center(
                  child: Text(
                    '№ ${booking.publicRef}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Text(
                  t(
                    locale,
                    ru: 'Мы свяжемся с вами в ближайшее время.',
                    kz: 'Жақын арада сізбен байланысамыз.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final item in booking.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        formatPrice(item.totalPrice),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              Divider(
                color: context.mereytoiColors.divider,
                height: AppSpacing.lg,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t(locale, ru: 'Итого', kz: 'Барлығы'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    formatPrice(booking.total),
                    style: TextStyle(
                      color: context.mereytoiColors.goldSoft,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_onboarding != null) ...[
                _OnboardingBlock(
                  onboarding: _onboarding!,
                  locale: locale,
                  resendState: _resendState,
                  onResend: _resendClaim,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              OutlinedButton.icon(
                onPressed: _openMyEvent,
                icon: const Icon(Icons.celebration_outlined, size: 18),
                label: Text(t(locale, ru: 'Мой той', kz: 'Менің тойым')),
              ),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton.icon(
                onPressed: _openManagerChat,
                icon: const Icon(Icons.support_agent_rounded, size: 18),
                label: Text(
                  t(
                    locale,
                    ru: 'Связаться с менеджером',
                    kz: 'Менеджермен байланысу',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pdfBusy
                          ? null
                          : () => _withPdf(_pdfService.open),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text(t(locale, ru: 'Открыть PDF', kz: 'PDF ашу')),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pdfBusy
                          ? null
                          : () => _withPdf(_pdfService.share),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: Text(t(locale, ru: 'Поделиться', kz: 'Бөлісу')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _finish,
                  child: Text(t(locale, ru: 'Продолжить', kz: 'Жалғастыру')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mirrors `BookingWorkspaceCTA.jsx` exactly — additive, renders nothing
/// beyond what `onboarding.status`/`delivery_status` actually says, never
/// inventing a channel or cooldown the neutral resend endpoint doesn't
/// return (brief section 11's own constraint).
class _OnboardingBlock extends StatelessWidget {
  const _OnboardingBlock({
    required this.onboarding,
    required this.locale,
    required this.resendState,
    required this.onResend,
  });

  final BookingOnboarding onboarding;
  final AppLocale locale;
  final _ResendState resendState;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    if (onboarding.status == 'existing_account') {
      return AppCardLike(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t(
                locale,
                ru: 'Заявка добавлена в ваш кабинет MEREYTOI.',
                kz: 'Өтінім сіздің MEREYTOI кабинетіңізге қосылды.',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: Text(
                t(locale, ru: 'Открыть кабинет', kz: 'Кабинетті ашу'),
              ),
            ),
          ],
        ),
      );
    }

    if ((onboarding.status == 'created_pending' ||
            onboarding.status == 'pending_claim') &&
        onboarding.claimToken != null) {
      final intro = onboarding.status == 'created_pending'
          ? t(
              locale,
              ru: 'Для вас создано пространство «Мой той».',
              kz: '«Менің тойым» кеңістігі сіз үшін жасалды.',
            )
          : t(
              locale,
              ru: 'Для вас уже подготовлено пространство «Мой той».',
              kz: '«Менің тойым» кеңістігі сіз үшін дайын.',
            );

      return AppCardLike(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(intro, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              t(
                locale,
                ru: 'В нём можно вместе с близкими выбирать услуги, обсуждать варианты, сравнивать цены и контролировать бюджет.',
                kz: 'Онда жақындарыңызбен бірге қызметтерді таңдап, нұсқаларды талқылап, бағаларды салыстырып, бюджетті бақылай аласыз.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (onboarding.deliveryStatus == 'sent' &&
                onboarding.deliveryChannel == 'whatsapp') ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                t(
                  locale,
                  ru: 'Ссылка на «Мой той» отправлена в WhatsApp.',
                  kz: '«Менің тойым» сілтемесі WhatsApp-қа жіберілді.',
                ),
                style: TextStyle(
                  color: context.mereytoiColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (onboarding.deliveryStatus == 'sent' &&
                onboarding.deliveryChannel == 'telegram') ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                t(
                  locale,
                  ru: 'Ссылка на «Мой той» отправлена в Telegram.',
                  kz: '«Менің тойым» сілтемесі Telegram-ға жіберілді.',
                ),
                style: TextStyle(
                  color: context.mereytoiColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ClaimScreen(token: onboarding.claimToken!),
                ),
              ),
              child: Text(
                t(locale, ru: 'Открыть мой той', kz: 'Менің тойымды ашу'),
              ),
            ),
            if (onboarding.deliveryStatus == 'failed' ||
                onboarding.deliveryStatus == 'skipped') ...[
              const SizedBox(height: AppSpacing.xs),
              if (resendState == _ResendState.done)
                Text(
                  t(
                    locale,
                    ru: 'Если ссылка не пришла в течение пары минут, свяжитесь с нами.',
                    kz: 'Сілтеме бірнеше минут ішінде келмесе, бізбен байланысыңыз.',
                  ),
                  style: TextStyle(
                    color: context.mereytoiColors.textSecondary,
                    fontSize: 12,
                  ),
                )
              else
                TextButton(
                  onPressed: resendState == _ResendState.sending
                      ? null
                      : onResend,
                  child: Text(
                    t(
                      locale,
                      ru: 'Отправить ссылку ещё раз',
                      kz: 'Сілтемені қайта жіберу',
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// A minimal boxed container matching this screen's own card look, without
/// pulling in `AppCard`'s image-oriented layout assumptions.
class AppCardLike extends StatelessWidget {
  const AppCardLike({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.mereytoiColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.mereytoiColors.divider),
      ),
      child: child,
    );
  }
}
