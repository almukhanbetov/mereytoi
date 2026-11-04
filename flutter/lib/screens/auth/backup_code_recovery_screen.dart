import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/auth/password_reset_rules.dart';
import '../../models/user.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/password_reset_provider.dart';
import '../../widgets/app_password_field.dart';
import 'recovery_code_screen.dart';
import 'support_recovery_screen.dart';

/// What [BackupCodeRecoveryScreen] hands back to the login screen.
sealed class BackupRecoveryOutcome {
  const BackupRecoveryOutcome();
}

/// Password recovered: the session is saved; the caller activates it.
class BackupRecoveryDone extends BackupRecoveryOutcome {
  const BackupRecoveryDone(this.user);
  final User user;
}

/// The person chose the WhatsApp code flow instead.
class BackupRecoveryUseWhatsApp extends BackupRecoveryOutcome {
  const BackupRecoveryUseWhatsApp();
}

/// Password set with a code from email: the person signs in themselves.
class EmailRecoveryDone extends BackupRecoveryOutcome {
  const EmailRecoveryDone(this.email);
  final String email;
}

/// Recovery with a backup code — two ways out, both on this screen. With a saved backup
/// code: email/phone, the code, a new password; nothing is delivered anywhere.
/// On success the new backup code (which replaced the used one) is shown once,
/// then the screen pops with [BackupRecoveryDone]. Without one: «Не помню
/// резервный код» goes on to the support flow.
class BackupCodeRecoveryScreen extends ConsumerStatefulWidget {
  const BackupCodeRecoveryScreen({super.key, this.initialLogin = ''});

  final String initialLogin;

  @override
  ConsumerState<BackupCodeRecoveryScreen> createState() =>
      _BackupCodeRecoveryScreenState();
}

class _BackupCodeRecoveryScreenState
    extends ConsumerState<BackupCodeRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _loginController = TextEditingController(
    text: widget.initialLogin,
  );
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _fallbackKey = GlobalKey();
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _loginController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(authProvider.notifier)
          .recoverWithCode(
            login: _loginController.text.trim(),
            code: _codeController.text,
            newPassword: _passwordController.text,
          );
      _codeController.clear();
      _passwordController.clear();
      _confirmController.clear();
      if (!mounted) return;
      if (result.recoveryCode.isNotEmpty) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => RecoveryCodeScreen(code: result.recoveryCode),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(BackupRecoveryDone(result.user));
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
        _showFallback();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A refused code usually means there is no valid one: keeps the way out in
  /// view next to the error.
  void _showFallback() {
    // After the keyboard has gone, or the viewport still changes under this.
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      final target = _fallbackKey.currentContext;
      if (!mounted || target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 1,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  /// «Не помню резервный код» — the support flow finishes this screen too.
  Future<void> _openSupport() async {
    final done = await Navigator.of(context).push<BackupRecoveryDone>(
      MaterialPageRoute(
        builder: (_) => SupportRecoveryRequestScreen(
          initialLogin: _loginController.text.trim(),
        ),
      ),
    );
    if (!mounted || done == null) return;
    Navigator.of(context).pop(done);
  }

  String _errorText(AppLocale locale, Object error) {
    if (error is ApiException) {
      final reason = error.debugMessage;
      if (error.statusCode == 429 || reason == 'too_many_attempts') {
        return t(
          locale,
          ru: 'Слишком много попыток. Попробуйте снова через 15 минут.',
          kz: 'Әрекеттер тым көп. 15 минуттан кейін қайталап көріңіз.',
          en: 'Too many attempts. Try again in 15 minutes.',
        );
      }
      if (reason == 'invalid_recovery_code') {
        return t(
          locale,
          ru: 'Неверный резервный код или данные аккаунта',
          kz: 'Резервтік код немесе аккаунт деректері қате',
          en: 'Wrong backup code or account details',
        );
      }
      if (reason == 'weak_password') {
        return t(
          locale,
          ru: 'Пароль должен быть не короче $minNewPasswordLength символов',
          kz: 'Құпиясөз кемінде $minNewPasswordLength таңбадан тұруы керек',
          en: 'Password must be at least $minNewPasswordLength characters',
        );
      }
    }
    return apiErrorMessage(locale, error);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final whatsAppAvailable =
        ref.watch(passwordResetAvailableProvider).valueOrNull ?? false;
    final textTheme = Theme.of(context).textTheme;
    String? required(String? v, String message) =>
        (v == null || v.trim().isEmpty) ? message : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            locale,
            ru: 'Восстановление пароля',
            kz: 'Құпиясөзді қалпына келтіру',
            en: 'Password recovery',
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(
                    locale,
                    ru: 'Есть резервный код',
                    kz: 'Резервтік код бар',
                    en: 'I have a backup code',
                  ),
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  t(
                    locale,
                    ru:
                        'Код не приходит по SMS, WhatsApp или email: он есть, '
                        'только если вы сохранили его раньше.',
                    kz:
                        'Код SMS, WhatsApp немесе email арқылы келмейді: ол '
                        'тек бұрын сақтаған болсаңыз ғана бар.',
                    en:
                        'This code doesn\'t come by SMS, WhatsApp or email: you '
                        'only have one if you saved it earlier.',
                  ),
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const ValueKey('recovery-login'),
                  controller: _loginController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: InputDecoration(
                    labelText: t(
                      locale,
                      ru: 'Email или телефон',
                      kz: 'Email немесе телефон',
                      en: 'Email or phone',
                    ),
                  ),
                  validator: (v) => required(
                    v,
                    t(
                      locale,
                      ru: 'Введите email или телефон',
                      kz: 'Email немесе телефонды енгізіңіз',
                      en: 'Enter your email or phone',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const ValueKey('recovery-code-input'),
                  controller: _codeController,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  // Keeps the explanation below the field above the keyboard.
                  scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
                  decoration: InputDecoration(
                    helperText: t(
                      locale,
                      ru:
                          'Это код, который вы сохранили при регистрации или '
                          'создали в Профиль → Безопасность.',
                      kz:
                          'Бұл тіркелу кезінде сақтаған немесе Профиль → '
                          'Қауіпсіздік бөлімінде жасаған кодыңыз.',
                      en:
                          'The code you saved at sign-up or created in '
                          'Profile → Security.',
                    ),
                    helperMaxLines: 3,
                    labelText: t(
                      locale,
                      ru: 'Резервный код',
                      kz: 'Резервтік код',
                      en: 'Backup code',
                    ),
                    hintText: 'XXXX-XXXX-XXXX-…',
                  ),
                  validator: (v) => required(
                    v,
                    t(
                      locale,
                      ru: 'Введите резервный код',
                      kz: 'Резервтік кодты енгізіңіз',
                      en: 'Enter your backup code',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppPasswordField(
                  key: const ValueKey('recovery-new-password'),
                  controller: _passwordController,
                  labelText: t(
                    locale,
                    ru: 'Новый пароль',
                    kz: 'Жаңа құпиясөз',
                    en: 'New password',
                  ),
                  textInputAction: TextInputAction.next,
                  showTooltip: t(
                    locale,
                    ru: 'Показать пароль',
                    kz: 'Құпия сөзді көрсету',
                    en: 'Show password',
                  ),
                  hideTooltip: t(
                    locale,
                    ru: 'Скрыть пароль',
                    kz: 'Құпия сөзді жасыру',
                    en: 'Hide password',
                  ),
                  validator: (v) =>
                      (v == null || v.length < minNewPasswordLength)
                      ? t(
                          locale,
                          ru: 'Не короче $minNewPasswordLength символов',
                          kz: 'Кемінде $minNewPasswordLength таңба',
                          en: 'At least $minNewPasswordLength characters',
                        )
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppPasswordField(
                  key: const ValueKey('recovery-confirm-password'),
                  controller: _confirmController,
                  // Keeps «Сменить пароль» and «Не помню резервный код» above
                  // the keyboard.
                  scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 330),
                  labelText: t(
                    locale,
                    ru: 'Повторите пароль',
                    kz: 'Құпиясөзді қайталаңыз',
                    en: 'Repeat password',
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _busy ? null : _submit(),
                  showTooltip: t(
                    locale,
                    ru: 'Показать пароль',
                    kz: 'Құпия сөзді көрсету',
                    en: 'Show password',
                  ),
                  hideTooltip: t(
                    locale,
                    ru: 'Скрыть пароль',
                    kz: 'Құпия сөзді жасыру',
                    en: 'Hide password',
                  ),
                  validator: (v) => v != _passwordController.text
                      ? t(
                          locale,
                          ru: 'Пароли не совпадают',
                          kz: 'Құпиясөздер сәйкес емес',
                          en: 'Passwords don\'t match',
                        )
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _errorText(locale, _error!),
                    key: const ValueKey('recovery-error'),
                    style: TextStyle(
                      color: context.mereytoiColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  key: const ValueKey('recovery-submit'),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: context.mereytoiColors.onGold,
                          ),
                        )
                      : Text(
                          t(
                            locale,
                            ru: 'Сменить пароль',
                            kz: 'Құпиясөзді өзгерту',
                            en: 'Change password',
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                Text(
                  t(
                    locale,
                    ru: 'Нет резервного кода?',
                    kz: 'Резервтік код жоқ па?',
                    en: 'No backup code?',
                  ),
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  t(
                    locale,
                    ru:
                        'Менеджер проверит, что аккаунт ваш, и передаст '
                        'временный код. Если помните пароль, войдите и создайте '
                        'код в Профиль → Безопасность.',
                    kz:
                        'Менеджер аккаунттың сіздікі екенін тексеріп, уақытша '
                        'кодты береді. Құпиясөз есіңізде болса, кіріп, Профиль '
                        '→ Қауіпсіздік бөлімінде код жасаңыз.',
                    en:
                        'A manager will check that the account is yours and '
                        'give you a temporary code. If you remember your '
                        'password, sign in and create a code in Profile → '
                        'Security.',
                  ),
                  style: textTheme.bodySmall?.copyWith(
                    color: context.mereytoiColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                KeyedSubtree(
                  key: _fallbackKey,
                  child: OutlinedButton(
                    key: const ValueKey('recovery-no-code'),
                    onPressed: _busy ? null : _openSupport,
                    child: Text(
                      t(
                        locale,
                        ru: 'Не помню резервный код',
                        kz: 'Резервтік код есімде жоқ',
                        en: 'I don\'t remember my backup code',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                if (whatsAppAvailable) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('recovery-use-whatsapp'),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(const BackupRecoveryUseWhatsApp()),
                      child: Text(
                        t(
                          locale,
                          ru: 'Получить код в WhatsApp',
                          kz: 'Кодты WhatsApp арқылы алу',
                          en: 'Get a code via WhatsApp',
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
