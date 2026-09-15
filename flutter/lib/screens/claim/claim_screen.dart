import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/claim/claim_status.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/providers.dart';
import '../events/event_workspace_screen.dart';
import '../root_shell.dart';

/// The one bridge a brand-new "pending" account (created by the
/// booking→onboarding pipeline server-side) has into an actual session —
/// mirrors frontend/src/app/claim/[token]/page.js's own state machine
/// (loading → success/used/expired/invalid), reached either by pasting a
/// claim link/token (see `openClaimEntrySheet`) or a `mereytoi://claim/:token`
/// deep link. Single-use server-side — this screen never retries the same
/// token automatically.
class ClaimScreen extends ConsumerStatefulWidget {
  const ClaimScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends ConsumerState<ClaimScreen> {
  ClaimStatus _status = ClaimStatus.loading;
  int? _eventId;

  @override
  void initState() {
    super.initState();
    _claim();
  }

  Future<void> _claim() async {
    setState(() => _status = ClaimStatus.loading);
    try {
      // Never logs the token itself — only that a claim attempt happened.
      final eventId = await ref.read(authProvider.notifier).claim(widget.token);
      if (!mounted) return;
      setState(() {
        _status = ClaimStatus.success;
        _eventId = eventId;
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      if (_eventId != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EventWorkspaceScreen(eventId: _eventId!),
          ),
        );
      } else {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const RootShell()));
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _status = classifyClaimError(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: switch (_status) {
            ClaimStatus.loading => _StatusView(
              icon: null,
              title: null,
              text: t(
                locale,
                ru: 'Открываем ваше пространство…',
                kz: 'Кеңістігіңіз ашылуда…',
              ),
              showSpinner: true,
            ),
            ClaimStatus.success => _StatusView(
              icon: '✨',
              title: t(locale, ru: 'Готово!', kz: 'Дайын!'),
              text: t(
                locale,
                ru: 'Открываем «Мой той»…',
                kz: '«Менің тойым» ашылуда…',
              ),
            ),
            ClaimStatus.used => _StatusView(
              icon: '🔓',
              title: t(
                locale,
                ru: 'Ссылка уже использована',
                kz: 'Сілтеме бұрын қолданылған',
              ),
              text: t(
                locale,
                ru: 'Похоже, пространство уже открывали раньше. Войдите в свой аккаунт, чтобы продолжить.',
                kz: 'Бұл кеңістік бұрын ашылған сияқты. Жалғастыру үшін аккаунтыңызға кіріңіз.',
              ),
              loginCta: true,
            ),
            ClaimStatus.expired => _StatusView(
              icon: '⏳',
              title: t(
                locale,
                ru: 'Ссылка больше не активна',
                kz: 'Сілтеме енді белсенді емес',
              ),
              text: t(
                locale,
                ru: 'Срок действия ссылки истёк.',
                kz: 'Сілтеменің мерзімі аяқталды.',
              ),
              resendCta: true,
            ),
            ClaimStatus.invalid => _StatusView(
              icon: '🚫',
              title: t(
                locale,
                ru: 'Ссылка недействительна',
                kz: 'Сілтеме жарамсыз',
              ),
              text: t(
                locale,
                ru: 'Проверьте, что ссылка скопирована полностью.',
                kz: 'Сілтеменің толық көшірілгенін тексеріңіз.',
              ),
            ),
            ClaimStatus.networkError => _StatusView(
              icon: '📡',
              title: t(locale, ru: 'Нет соединения', kz: 'Байланыс жоқ'),
              text: t(
                locale,
                ru: 'Проверьте интернет-соединение и попробуйте ещё раз.',
                kz: 'Интернет байланысын тексеріп, қайта көріңіз.',
              ),
              retry: _claim,
            ),
          },
        ),
      ),
    );
  }
}

class _StatusView extends ConsumerWidget {
  const _StatusView({
    this.icon,
    this.title,
    required this.text,
    this.showSpinner = false,
    this.loginCta = false,
    this.resendCta = false,
    this.retry,
  });

  final String? icon;
  final String? title;
  final String text;
  final bool showSpinner;
  final bool loginCta;
  final bool resendCta;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSpinner)
          CircularProgressIndicator(color: context.mereytoiColors.goldPrimary),
        if (icon != null) Text(icon!, style: const TextStyle(fontSize: 40)),
        if (title != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            title!,
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (retry != null) ...[
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: retry,
            child: Text(t(locale, ru: 'Повторить', kz: 'Қайталау')),
          ),
        ],
        if (loginCta) ...[
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const RootShell()),
            ),
            child: Text(t(locale, ru: 'На главную', kz: 'Басты бетке')),
          ),
        ],
        if (resendCta) ...[
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const _ResendClaimSheet(),
            ),
            child: Text(
              t(
                locale,
                ru: 'Отправить ссылку заново',
                kz: 'Сілтемені қайта жіберу',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// `POST /api/auth/claim/resend` — always the same neutral response
/// regardless of outcome (brief: never reveal whether a phone has a
/// pending account), so this sheet's own success copy is deliberately
/// vague too, matching that same posture.
class _ResendClaimSheet extends ConsumerStatefulWidget {
  const _ResendClaimSheet();

  @override
  ConsumerState<_ResendClaimSheet> createState() => _ResendClaimSheetState();
}

class _ResendClaimSheetState extends ConsumerState<_ResendClaimSheet> {
  final _phoneController = TextEditingController();
  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).claimResend(phone);
      if (mounted) setState(() => _sent = true);
    } catch (err) {
      if (mounted) {
        setState(() => _error = apiErrorMessage(ref.read(localeProvider), err));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.mereytoiColors.surfaceElevated,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _sent
                  ? [
                      Text(
                        t(
                          locale,
                          ru: 'Если кабинет связан с этим номером, ссылка будет отправлена.',
                          kz: 'Егер кабинет осы нөмірмен байланысты болса, сілтеме жіберіледі.',
                        ),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(t(locale, ru: 'Понятно', kz: 'Түсінікті')),
                      ),
                    ]
                  : [
                      Text(
                        t(
                          locale,
                          ru: 'Отправить ссылку заново',
                          kz: 'Сілтемені қайта жіберу',
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: t(locale, ru: 'Телефон', kz: 'Телефон'),
                          hintText: '+7 700 000 00 00',
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: context.mereytoiColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: context.mereytoiColors.onGold,
                                  ),
                                )
                              : Text(t(locale, ru: 'Отправить', kz: 'Жіберу')),
                        ),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}
