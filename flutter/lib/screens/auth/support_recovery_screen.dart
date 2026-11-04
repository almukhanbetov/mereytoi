import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/auth/password_reset_rules.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/providers.dart';
import '../../widgets/app_password_field.dart';
import 'backup_code_recovery_screen.dart';
import 'recovery_code_screen.dart';

/// «Не помню резервный код» — asks support for a temporary code. The answer
/// never says whether the account exists. Someone who already got a code goes
/// on to [TempCodeRecoveryScreen] from here; its result is handed back to
/// [BackupCodeRecoveryScreen] unchanged.
class SupportRecoveryRequestScreen extends ConsumerStatefulWidget {
  const SupportRecoveryRequestScreen({super.key, this.initialLogin = ''});

  final String initialLogin;

  @override
  ConsumerState<SupportRecoveryRequestScreen> createState() =>
      _SupportRecoveryRequestScreenState();
}

class _SupportRecoveryRequestScreenState
    extends ConsumerState<SupportRecoveryRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _loginController = TextEditingController(
    text: widget.initialLogin,
  );
  bool _busy = false;
  bool _sent = false;
  bool _sentByPhone = false;
  Object? _error;

  @override
  void dispose() {
    _loginController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final login = _loginController.text.trim();
      await ref.read(authServiceProvider).requestSupportRecovery(login: login);
      if (mounted) {
        setState(() {
          _sent = true;
          _sentByPhone = !login.contains('@');
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openTempCode() async {
    final done = await Navigator.of(context).push<BackupRecoveryDone>(
      MaterialPageRoute(
        builder: (_) =>
            TempCodeRecoveryScreen(initialLogin: _loginController.text.trim()),
      ),
    );
    if (!mounted || done == null) return;
    Navigator.of(context).pop(done);
  }

  String _errorText(AppLocale locale, Object error) {
    if (error is ApiException && error.statusCode == 429) {
      return t(
        locale,
        ru: 'Слишком много запросов. Попробуйте снова через 15 минут.',
        kz: 'Сұраулар тым көп. 15 минуттан кейін қайталап көріңіз.',
        en: 'Too many requests. Try again in 15 minutes.',
      );
    }
    return apiErrorMessage(locale, error);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            locale,
            ru: 'Запрос в поддержку',
            kz: 'Қолдау қызметіне сұрау',
            en: 'Request to support',
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
                    ru: 'Не помню резервный код',
                    kz: 'Резервтік код есімде жоқ',
                    en: 'I don\'t remember my backup code',
                  ),
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  t(
                    locale,
                    ru:
                        'Менеджер проверит, что аккаунт ваш, и передаст '
                        'временный код. Это происходит не сразу.',
                    kz:
                        'Менеджер аккаунттың сіздікі екенін тексеріп, уақытша '
                        'кодты береді. Бұл бірден болмайды.',
                    en:
                        'A manager will check that the account is yours and '
                        'give you a temporary code. This doesn\'t happen '
                        'right away.',
                  ),
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_sent) ...[
                  Text(
                    t(
                      locale,
                      ru: 'Если аккаунт найден, запрос будет передан в поддержку.',
                      kz: 'Аккаунт табылса, сұрау қолдау қызметіне жіберіледі.',
                      en: 'If the account is found, the request will be passed to support.',
                    ),
                    key: const ValueKey('support-request-sent'),
                    style: textTheme.titleMedium,
                  ),
                  // Shown for every phone, known or not, so it says nothing
                  // about this one. The backend never picks between accounts
                  // sharing a number.
                  if (_sentByPhone) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      t(
                        locale,
                        ru:
                            'Если телефон привязан к нескольким аккаунтам, '
                            'запрос не будет создан. В этом случае укажите email.',
                        kz:
                            'Телефон бірнеше аккаунтқа байланған болса, сұрау '
                            'жасалмайды. Бұл жағдайда email енгізіңіз.',
                        en:
                            'If this phone is linked to several accounts, no '
                            'request is created. In that case, enter your email.',
                      ),
                      key: const ValueKey('support-phone-hint'),
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    OutlinedButton(
                      key: const ValueKey('support-use-email'),
                      onPressed: () => setState(() {
                        _sent = false;
                        _loginController.clear();
                      }),
                      child: Text(
                        t(
                          locale,
                          ru: 'Указать email',
                          kz: 'Email енгізу',
                          en: 'Enter email',
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  TextFormField(
                    key: const ValueKey('support-login'),
                    controller: _loginController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.username],
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: t(
                        locale,
                        ru: 'Email или телефон',
                        kz: 'Email немесе телефон',
                        en: 'Email or phone',
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? t(
                            locale,
                            ru: 'Введите email или телефон',
                            kz: 'Email немесе телефонды енгізіңіз',
                            en: 'Enter your email or phone',
                          )
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _errorText(locale, _error!),
                      key: const ValueKey('support-error'),
                      style: TextStyle(
                        color: context.mereytoiColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    key: const ValueKey('support-submit'),
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
                              ru: 'Отправить запрос в поддержку',
                              kz: 'Қолдау қызметіне сұрау жіберу',
                              en: 'Send request to support',
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  key: const ValueKey('support-have-code'),
                  onPressed: _busy ? null : _openTempCode,
                  child: Text(
                    t(
                      locale,
                      ru: 'У меня есть временный код',
                      kz: 'Менде уақытша код бар',
                      en: 'I have a temporary code',
                    ),
                    textAlign: TextAlign.center,
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

/// «Временный код восстановления» — sets a new password with the code from
/// support. On success the new backup code is shown once, then the screen
/// pops with [BackupRecoveryDone], like [BackupCodeRecoveryScreen] does.
class TempCodeRecoveryScreen extends ConsumerStatefulWidget {
  const TempCodeRecoveryScreen({super.key, this.initialLogin = ''});

  final String initialLogin;

  @override
  ConsumerState<TempCodeRecoveryScreen> createState() =>
      _TempCodeRecoveryScreenState();
}

class _TempCodeRecoveryScreenState
    extends ConsumerState<TempCodeRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _loginController = TextEditingController(
    text: widget.initialLogin,
  );
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(authProvider.notifier)
          .recoverWithSupportCode(
            login: _loginController.text.trim(),
            tempCode: _codeController.text,
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
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        final message = t(
          locale,
          ru:
              'Код неверный или больше не действует. Проверьте данные или '
              'запросите новый код у менеджера.',
          kz:
              'Код қате немесе енді жарамсыз. Деректерді тексеріңіз немесе '
              'менеджерден жаңа код сұраңыз.',
          en:
              'The code is wrong or no longer valid. Check your details or '
              'ask a manager for a new code.',
        );
        if (_loginController.text.contains('@')) return message;
        final useEmail = t(
          locale,
          ru: 'Если телефон привязан к нескольким аккаунтам, укажите email.',
          kz: 'Телефон бірнеше аккаунтқа байланған болса, email енгізіңіз.',
          en: 'If this phone is linked to several accounts, enter your email.',
        );
        return '$message $useEmail';
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
    final textTheme = Theme.of(context).textTheme;
    String? required(String? v, String message) =>
        (v == null || v.trim().isEmpty) ? message : null;
    final showTooltip = t(
      locale,
      ru: 'Показать пароль',
      kz: 'Құпия сөзді көрсету',
      en: 'Show password',
    );
    final hideTooltip = t(
      locale,
      ru: 'Скрыть пароль',
      kz: 'Құпия сөзді жасыру',
      en: 'Hide password',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            locale,
            ru: 'Временный код',
            kz: 'Уақытша код',
            en: 'Temporary code',
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
                    ru: 'Временный код восстановления',
                    kz: 'Қалпына келтірудің уақытша коды',
                    en: 'Temporary recovery code',
                  ),
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  t(
                    locale,
                    ru:
                        'Введите код, который передал менеджер. Он действует '
                        '15 минут и только один раз.',
                    kz:
                        'Менеджер берген кодты енгізіңіз. Ол 15 минут және '
                        'бір рет қана жарамды.',
                    en:
                        'Enter the code a manager gave you. It works for '
                        '15 minutes and only once.',
                  ),
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const ValueKey('temp-login'),
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
                  key: const ValueKey('temp-code'),
                  controller: _codeController,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: t(
                      locale,
                      ru: 'Временный код',
                      kz: 'Уақытша код',
                      en: 'Temporary code',
                    ),
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                  ),
                  validator: (v) => required(
                    v,
                    t(
                      locale,
                      ru: 'Введите временный код',
                      kz: 'Уақытша кодты енгізіңіз',
                      en: 'Enter the temporary code',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppPasswordField(
                  key: const ValueKey('temp-new-password'),
                  controller: _passwordController,
                  labelText: t(
                    locale,
                    ru: 'Новый пароль',
                    kz: 'Жаңа құпиясөз',
                    en: 'New password',
                  ),
                  textInputAction: TextInputAction.next,
                  showTooltip: showTooltip,
                  hideTooltip: hideTooltip,
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
                  key: const ValueKey('temp-confirm-password'),
                  controller: _confirmController,
                  // Keeps «Сменить пароль» above the keyboard.
                  scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                  labelText: t(
                    locale,
                    ru: 'Повторите новый пароль',
                    kz: 'Жаңа құпиясөзді қайталаңыз',
                    en: 'Repeat new password',
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _busy ? null : _submit(),
                  showTooltip: showTooltip,
                  hideTooltip: hideTooltip,
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
                    key: const ValueKey('temp-error'),
                    style: TextStyle(
                      color: context.mereytoiColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  key: const ValueKey('temp-submit'),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
