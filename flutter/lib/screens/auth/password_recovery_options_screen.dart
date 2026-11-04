import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../state/locale_provider.dart';
import '../../state/password_reset_provider.dart';
import 'backup_code_recovery_screen.dart';
import 'email_otp_recovery_screen.dart';
import 'support_recovery_screen.dart';

/// «Забыли пароль?» — the ways to recover. A code by email is offered only
/// when the backend can send one; what the chosen flow hands back is passed
/// on to the login screen unchanged.
class PasswordRecoveryOptionsScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryOptionsScreen({super.key, this.initialLogin = ''});

  final String initialLogin;

  @override
  ConsumerState<PasswordRecoveryOptionsScreen> createState() =>
      _PasswordRecoveryOptionsScreenState();
}

class _PasswordRecoveryOptionsScreenState
    extends ConsumerState<PasswordRecoveryOptionsScreen> {
  bool _opening = false;

  /// A second tap while a flow is opening or open doesn't stack another one.
  Future<void> _open(Widget screen) async {
    if (_opening) return;
    _opening = true;
    final outcome = await Navigator.of(
      context,
    ).push<BackupRecoveryOutcome>(MaterialPageRoute(builder: (_) => screen));
    _opening = false;
    if (outcome != null && mounted) {
      Navigator.of(context).pop(outcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialLogin = widget.initialLogin;
    final locale = ref.watch(localeProvider);
    final emailAvailable =
        ref.watch(emailOtpAvailableProvider).valueOrNull ?? false;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            locale,
            ru: 'Забыли пароль?',
            kz: 'Құпиясөзді ұмыттыңыз ба?',
            en: 'Forgot password?',
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(
                  locale,
                  ru: 'Как восстановить доступ?',
                  kz: 'Қолжетімділікті қалай қалпына келтіресіз?',
                  en: 'How do you want to recover access?',
                ),
                style: textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (emailAvailable) ...[
                ElevatedButton(
                  key: const ValueKey('forgot-email-code'),
                  onPressed: () => _open(
                    EmailOtpRecoveryScreen(
                      initialEmail: initialLogin.contains('@')
                          ? initialLogin
                          : '',
                    ),
                  ),
                  child: Text(
                    t(
                      locale,
                      ru: 'Получить код на email',
                      kz: 'Кодты email-ге алу',
                      en: 'Get a code by email',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              OutlinedButton(
                key: const ValueKey('forgot-have-code'),
                onPressed: () =>
                    _open(BackupCodeRecoveryScreen(initialLogin: initialLogin)),
                child: Text(
                  t(
                    locale,
                    ru: 'У меня есть резервный код',
                    kz: 'Менде резервтік код бар',
                    en: 'I have a backup code',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                key: const ValueKey('forgot-support'),
                onPressed: () => _open(
                  SupportRecoveryRequestScreen(initialLogin: initialLogin),
                ),
                child: Text(
                  emailAvailable
                      ? t(
                          locale,
                          ru: 'Нет доступа к email / не помню резервный код',
                          kz: 'Email-ге кіру мүмкіндігі жоқ / резервтік код есімде жоқ',
                          en: 'No access to email / forgot my backup code',
                        )
                      : t(
                          locale,
                          ru: 'Не помню резервный код',
                          kz: 'Резервтік код есімде жоқ',
                          en: 'I don\'t remember my backup code',
                        ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                t(
                  locale,
                  ru:
                      'Без email и резервного кода поможет менеджер: он проверит, '
                      'что аккаунт ваш, и передаст временный код.',
                  kz:
                      'Email мен резервтік код болмаса, менеджер көмектеседі: ол '
                      'аккаунттың сіздікі екенін тексеріп, уақытша кодты береді.',
                  en:
                      'Without email or a backup code, a manager can help: they '
                      'check that the account is yours and give you a temporary '
                      'code.',
                ),
                style: textTheme.bodySmall?.copyWith(
                  color: context.mereytoiColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
