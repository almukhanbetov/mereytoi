import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/auth/password_reset_rules.dart';
import '../../state/locale_provider.dart';
import '../../state/providers.dart';
import '../../widgets/app_password_field.dart';
import 'backup_code_recovery_screen.dart';

/// Password recovery with a code sent by email: the address first, then the
/// code and a new password on the same screen. The answer to a request never
/// says whether the account exists. On success the screen pops with
/// [EmailRecoveryDone]; signing in stays the person's own step.
class EmailOtpRecoveryScreen extends ConsumerStatefulWidget {
  const EmailOtpRecoveryScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  /// Matches the backend's cooldown between codes.
  static const resendSeconds = 60;

  @override
  ConsumerState<EmailOtpRecoveryScreen> createState() =>
      _EmailOtpRecoveryScreenState();
}

class _EmailOtpRecoveryScreenState
    extends ConsumerState<EmailOtpRecoveryScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  Timer? _timer;
  int _secondsLeft = 0;
  bool _sent = false;
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = EmailOtpRecoveryScreen.resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .requestEmailOtp(
            email: _emailController.text.trim(),
            lang: ref.read(localeProvider).name,
          );
      if (!mounted) return;
      _codeController.clear();
      setState(() => _sent = true);
      _startCountdown();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitEmail() async {
    if (_busy || !_emailFormKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _send();
  }

  Future<void> _submitReset() async {
    if (_busy || !_resetFormKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _emailController.text.trim();
      await ref
          .read(authServiceProvider)
          .resetWithEmailOtp(
            email: email,
            otp: _codeController.text.trim(),
            newPassword: _passwordController.text,
          );
      _codeController.clear();
      _passwordController.clear();
      _confirmController.clear();
      if (mounted) Navigator.of(context).pop(EmailRecoveryDone(email));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeEmail() {
    _timer?.cancel();
    _codeController.clear();
    _passwordController.clear();
    _confirmController.clear();
    setState(() {
      _sent = false;
      _secondsLeft = 0;
      _error = null;
    });
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
          ru: 'Код неверный или больше не действует. Запросите новый код.',
          kz: 'Код қате немесе енді жарамсыз. Жаңа код сұраңыз.',
          en: 'The code is wrong or no longer valid. Ask for a new one.',
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

  Widget _errorLine(AppLocale locale) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(
      _errorText(locale, _error!),
      key: const ValueKey('otp-error'),
      style: TextStyle(color: context.mereytoiColors.error, fontSize: 13),
    ),
  );

  Widget _progress() => SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(
      strokeWidth: 2.2,
      color: context.mereytoiColors.onGoldDisabled,
    ),
  );

  Widget _emailStep(AppLocale locale, TextTheme textTheme) => Form(
    key: _emailFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(
            locale,
            ru: 'Введите email аккаунта, и мы отправим на него код.',
            kz: 'Аккаунттың email-ін енгізіңіз, біз оған код жібереміз.',
            en: 'Enter your account email and we\'ll send a code to it.',
          ),
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          key: const ValueKey('otp-email'),
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          onFieldSubmitted: (_) => _busy ? null : _submitEmail(),
          decoration: const InputDecoration(labelText: 'Email'),
          validator: (v) => (v == null || !v.contains('@'))
              ? t(
                  locale,
                  ru: 'Введите email',
                  kz: 'Email енгізіңіз',
                  en: 'Enter your email',
                )
              : null,
        ),
        if (_error != null) _errorLine(locale),
        const SizedBox(height: AppSpacing.lg),
        ElevatedButton(
          key: const ValueKey('otp-send'),
          onPressed: _busy ? null : _submitEmail,
          child: _busy
              ? _progress()
              : Text(
                  t(
                    locale,
                    ru: 'Отправить код',
                    kz: 'Кодты жіберу',
                    en: 'Send code',
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _resetStep(AppLocale locale, TextTheme textTheme) {
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
    final canResend = !_busy && _secondsLeft <= 0;
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(
              locale,
              ru:
                  'Если аккаунт с таким email найден, мы отправили на него код. '
                  'Он действует 10 минут. Проверьте также папку «Спам».',
              kz:
                  'Мұндай email-мен аккаунт табылса, біз оған код жібердік. Ол '
                  '10 минут жарамды. «Спам» қалтасын да тексеріңіз.',
              en:
                  'If an account with this email exists, we\'ve sent a code to '
                  'it. It works for 10 minutes. Check your spam folder too.',
            ),
            key: const ValueKey('otp-sent'),
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: Text(
                  _emailController.text.trim(),
                  key: const ValueKey('otp-email-shown'),
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
              ),
              TextButton(
                key: const ValueKey('otp-change-email'),
                onPressed: _busy ? null : _changeEmail,
                child: Text(
                  t(locale, ru: 'Изменить', kz: 'Өзгерту', en: 'Change'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            key: const ValueKey('otp-code'),
            controller: _codeController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.oneTimeCode],
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              labelText: t(
                locale,
                ru: 'Код из письма',
                kz: 'Хаттағы код',
                en: 'Code from the email',
              ),
            ),
            validator: (v) => (v == null || v.trim().length != 6)
                ? t(
                    locale,
                    ru: 'Введите 6 цифр из письма',
                    kz: 'Хаттағы 6 цифрды енгізіңіз',
                    en: 'Enter the 6 digits from the email',
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppPasswordField(
            key: const ValueKey('otp-new-password'),
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
            validator: (v) => (v == null || v.length < minNewPasswordLength)
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
            key: const ValueKey('otp-confirm-password'),
            controller: _confirmController,
            // Keeps «Сменить пароль» and the resend button above the keyboard.
            scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 190),
            labelText: t(
              locale,
              ru: 'Повторите пароль',
              kz: 'Құпиясөзді қайталаңыз',
              en: 'Repeat password',
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _busy ? null : _submitReset(),
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
          if (_error != null) _errorLine(locale),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            key: const ValueKey('otp-submit'),
            onPressed: _busy ? null : _submitReset,
            child: _busy
                ? _progress()
                : Text(
                    t(
                      locale,
                      ru: 'Сменить пароль',
                      kz: 'Құпиясөзді өзгерту',
                      en: 'Change password',
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            key: const ValueKey('otp-resend'),
            onPressed: canResend ? _send : null,
            child: Text(
              _secondsLeft > 0
                  ? t(
                      locale,
                      ru: 'Отправить ещё раз через $_secondsLeft с',
                      kz: '$_secondsLeft с кейін қайта жіберу',
                      en: 'Send again in $_secondsLeft s',
                    )
                  : t(
                      locale,
                      ru: 'Отправить код ещё раз',
                      kz: 'Кодты қайта жіберу',
                      en: 'Send the code again',
                    ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
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
            ru: 'Код на email',
            kz: 'Email-ге код',
            en: 'Code by email',
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
          child: _sent
              ? _resetStep(locale, textTheme)
              : _emailStep(locale, textTheme),
        ),
      ),
    );
  }
}
