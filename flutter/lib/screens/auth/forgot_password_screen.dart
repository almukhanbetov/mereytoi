import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/auth/password_reset_rules.dart';
import '../../state/locale_provider.dart';
import '../../state/providers.dart';
import '../../widgets/app_password_field.dart';
import '../../widgets/otp_code_field.dart';

enum _Step { phone, code, password, success }

/// "Forgot password?" — phone → one-time code (WhatsApp) → new password →
/// done, all on one screen; system Back walks back one step at a time.
///
/// Backend: POST /api/auth/password/forgot (the same neutral answer for any
/// number, so this always moves on to the code step and never says whether
/// an account exists), then POST /api/auth/password/reset with phone, code
/// and new password together — the code is checked there, so a wrong one
/// sends the user back to the code step with their new password kept.
///
/// Pops with the phone as typed once the password is changed, so Login can
/// pre-fill it; never signs in by itself.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialPhone = ''});

  final String initialPhone;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  _Step _step = _Step.phone;

  final _phoneFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  late final _phoneController = TextEditingController(
    text: widget.initialPhone,
  );
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatController = TextEditingController();

  /// The number codes go to, normalized like the backend does.
  String _phone = '';

  bool _requesting = false;
  bool _resending = false;
  bool _submitting = false;
  bool _codeInvalid = false;
  String? _phoneError;
  String? _passwordError;

  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    // "Next" enables as soon as all six digits are in.
    _codeController.addListener(_codeChanged);
  }

  void _codeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  AppLocale get _locale => ref.read(localeProvider);

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _secondsLeft = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  String _failureText(Object error) {
    final locale = _locale;
    return switch (passwordResetFailureOf(error)) {
      PasswordResetFailure.tooManyRequests => t(
        locale,
        ru: 'Слишком много попыток. Попробуйте позже.',
        kz: 'Әрекет тым көп. Кейінірек қайталап көріңіз.',
        en: 'Too many attempts. Please try again later.',
      ),
      PasswordResetFailure.weakPassword => t(
        locale,
        ru: 'Минимум 8 символов',
        kz: 'Кемінде 8 таңба',
        en: 'At least 8 characters',
      ),
      _ => apiErrorMessage(locale, error),
    };
  }

  Future<void> _requestCode() async {
    if (_requesting || !_phoneFormKey.currentState!.validate()) return;
    final phone = normalizeKzPhone(_phoneController.text)!;
    setState(() {
      _requesting = true;
      _phoneError = null;
    });
    try {
      final wait = await ref
          .read(authServiceProvider)
          .requestPasswordReset(phone: phone, lang: _locale.name);
      if (!mounted) return;
      setState(() {
        _phone = phone;
        _step = _Step.code;
        _codeInvalid = false;
        _codeController.clear();
      });
      _startCountdown(wait);
    } catch (e) {
      if (mounted) setState(() => _phoneError = _failureText(e));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _resend() async {
    if (_resending || _secondsLeft > 0) return;
    setState(() => _resending = true);
    try {
      final wait = await ref
          .read(authServiceProvider)
          .requestPasswordReset(phone: _phone, lang: _locale.name);
      if (!mounted) return;
      setState(() {
        _codeInvalid = false;
        _codeController.clear();
      });
      _startCountdown(wait);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_failureText(e))));
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _toPassword() {
    if (_codeController.text.length != 6) return;
    setState(() {
      _step = _Step.password;
      _codeInvalid = false;
      _passwordError = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting || !_passwordFormKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _passwordError = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .resetPassword(
            phone: _phone,
            code: _codeController.text,
            newPassword: _passwordController.text,
          );
      if (!mounted) return;
      _timer?.cancel();
      setState(() => _step = _Step.success);
    } catch (e) {
      if (!mounted) return;
      if (passwordResetFailureOf(e) == PasswordResetFailure.invalidCode) {
        // Back to the code; the new password stays filled in.
        setState(() {
          _step = _Step.code;
          _codeInvalid = true;
          _codeController.clear();
        });
      } else {
        setState(() => _passwordError = _failureText(e));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _finish() =>
      Navigator.of(context).pop<String>(_phoneController.text.trim());

  /// System/AppBar Back: one step back, and out only from the first step.
  void _back() {
    switch (_step) {
      case _Step.phone:
        Navigator.of(context).pop();
      case _Step.code:
        _timer?.cancel();
        setState(() {
          _step = _Step.phone;
          _secondsLeft = 0;
        });
      case _Step.password:
        setState(() => _step = _Step.code);
      case _Step.success:
        _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_step != _Step.success) ...[
                  _StepIndicator(current: _step.index, locale: locale),
                  const SizedBox(height: AppSpacing.xl),
                ],
                switch (_step) {
                  _Step.phone => _buildPhone(context, locale),
                  _Step.code => _buildCode(context, locale),
                  _Step.password => _buildPassword(context, locale),
                  _Step.success => _buildSuccess(context, locale),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String title, String? subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }

  Widget _errorText(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Text(
      text,
      style: TextStyle(color: context.mereytoiColors.error, fontSize: 13),
    ),
  );

  Widget _busyLabel(BuildContext context, bool busy, String label) => busy
      ? SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: context.mereytoiColors.onGold,
          ),
        )
      : Text(label);

  Widget _buildPhone(BuildContext context, AppLocale locale) {
    return Form(
      key: _phoneFormKey,
      child: Column(
        key: const ValueKey('step-phone'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            t(
              locale,
              ru: 'Введите номер телефона',
              kz: 'Телефон нөмірін енгізіңіз',
              en: 'Enter phone number',
            ),
            t(
              locale,
              ru: 'Номер, с которым вы зарегистрированы.',
              kz: 'Тіркелген нөміріңіз.',
              en: 'The number your account is registered with.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            key: const ValueKey('reset-phone'),
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            onFieldSubmitted: (_) => _requestCode(),
            decoration: InputDecoration(
              labelText: t(locale, ru: 'Телефон', kz: 'Телефон', en: 'Phone'),
              hintText: '+7 7XX XXX XX XX',
            ),
            validator: (v) => normalizeKzPhone(v ?? '') == null
                ? t(
                    locale,
                    ru: 'Введите номер в формате +7 7XX XXX XX XX',
                    kz: 'Нөмірді +7 7XX XXX XX XX форматында енгізіңіз',
                    en: 'Enter the number as +7 7XX XXX XX XX',
                  )
                : null,
          ),
          if (_phoneError != null) _errorText(context, _phoneError!),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            key: const ValueKey('reset-get-code'),
            onPressed: _requesting ? null : _requestCode,
            child: _busyLabel(
              context,
              _requesting,
              t(locale, ru: 'Получить код', kz: 'Код алу', en: 'Get code'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCode(BuildContext context, AppLocale locale) {
    final colors = context.mereytoiColors;
    final countdown =
        '${(_secondsLeft ~/ 60).toString().padLeft(2, '0')}:'
        '${(_secondsLeft % 60).toString().padLeft(2, '0')}';
    return Column(
      key: const ValueKey('step-code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          t(locale, ru: 'Введите код', kz: 'Кодты енгізіңіз', en: 'Enter code'),
          null,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          maskKzPhone(_phone),
          key: const ValueKey('reset-masked-phone'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colors.goldPrimary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          t(
            locale,
            ru: 'Если номер зарегистрирован, код придёт в WhatsApp.',
            kz: 'Егер нөмір тіркелген болса, код WhatsApp арқылы келеді.',
            en: 'If the number is registered, the code will arrive via WhatsApp.',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        OtpCodeField(
          controller: _codeController,
          hasError: _codeInvalid,
          semanticsLabel: t(
            locale,
            ru: 'Введите код',
            kz: 'Кодты енгізіңіз',
            en: 'Enter code',
          ),
          onCompleted: (_) => setState(() => _codeInvalid = false),
        ),
        if (_codeInvalid)
          _errorText(
            context,
            t(
              locale,
              ru: 'Неверный или истёкший код',
              kz: 'Код қате немесе мерзімі өтіп кеткен',
              en: 'Invalid or expired code',
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: _secondsLeft > 0
              ? Text(
                  t(
                    locale,
                    ru: 'Повторно отправить через $countdown',
                    kz: 'Қайта жіберу: $countdown',
                    en: 'Resend in $countdown',
                  ),
                  key: const ValueKey('reset-countdown'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                )
              : TextButton(
                  key: const ValueKey('reset-resend'),
                  onPressed: _resending ? null : _resend,
                  child: _resending
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.goldPrimary,
                          ),
                        )
                      : Text(
                          t(
                            locale,
                            ru: 'Отправить код снова',
                            kz: 'Кодты қайта жіберу',
                            en: 'Resend code',
                          ),
                        ),
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        ElevatedButton(
          key: const ValueKey('reset-code-continue'),
          onPressed: _codeController.text.length == 6 ? _toPassword : null,
          child: Text(t(locale, ru: 'Далее', kz: 'Әрі қарай', en: 'Next')),
        ),
      ],
    );
  }

  Widget _buildPassword(BuildContext context, AppLocale locale) {
    String? problemText(NewPasswordProblem? p) => switch (p) {
      NewPasswordProblem.tooShort => t(
        locale,
        ru: 'Минимум 8 символов',
        kz: 'Кемінде 8 таңба',
        en: 'At least 8 characters',
      ),
      NewPasswordProblem.mismatch => t(
        locale,
        ru: 'Пароли не совпадают',
        kz: 'Құпиясөздер сәйкес келмейді',
        en: 'Passwords don\'t match',
      ),
      null => null,
    };
    final show = t(
      locale,
      ru: 'Показать пароль',
      kz: 'Құпия сөзді көрсету',
      en: 'Show password',
    );
    final hide = t(
      locale,
      ru: 'Скрыть пароль',
      kz: 'Құпия сөзді жасыру',
      en: 'Hide password',
    );
    return Form(
      key: _passwordFormKey,
      child: Column(
        key: const ValueKey('step-password'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            t(
              locale,
              ru: 'Новый пароль',
              kz: 'Жаңа құпиясөз',
              en: 'New password',
            ),
            t(
              locale,
              ru: 'Минимум 8 символов',
              kz: 'Кемінде 8 таңба',
              en: 'At least 8 characters',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPasswordField(
            key: const ValueKey('reset-new-password'),
            controller: _passwordController,
            labelText: t(
              locale,
              ru: 'Новый пароль',
              kz: 'Жаңа құпиясөз',
              en: 'New password',
            ),
            textInputAction: TextInputAction.next,
            showTooltip: show,
            hideTooltip: hide,
            validator: (v) => (v ?? '').runes.length < minNewPasswordLength
                ? problemText(NewPasswordProblem.tooShort)
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppPasswordField(
            key: const ValueKey('reset-repeat-password'),
            controller: _repeatController,
            labelText: t(
              locale,
              ru: 'Повторите новый пароль',
              kz: 'Жаңа құпиясөзді қайталаңыз',
              en: 'Repeat new password',
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            showTooltip: show,
            hideTooltip: hide,
            validator: (v) =>
                newPasswordProblem(_passwordController.text, v ?? '') ==
                    NewPasswordProblem.mismatch
                ? problemText(NewPasswordProblem.mismatch)
                : null,
          ),
          if (_passwordError != null) _errorText(context, _passwordError!),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            key: const ValueKey('reset-submit'),
            onPressed: _submitting ? null : _submit,
            child: _busyLabel(
              context,
              _submitting,
              t(
                locale,
                ru: 'Изменить пароль',
                kz: 'Құпиясөзді өзгерту',
                en: 'Change password',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, AppLocale locale) {
    final colors = context.mereytoiColors;
    return Column(
      key: const ValueKey('step-success'),
      children: [
        const SizedBox(height: AppSpacing.xl),
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.goldPrimary.withValues(alpha: 0.14),
            border: Border.all(color: colors.goldPrimary, width: 1.5),
          ),
          child: Icon(Icons.check_rounded, size: 40, color: colors.goldPrimary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          t(
            locale,
            ru: 'Пароль успешно изменён',
            kz: 'Құпиясөз сәтті өзгертілді',
            en: 'Password changed successfully',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          t(
            locale,
            ru: 'Теперь войдите с новым паролем.',
            kz: 'Енді жаңа құпиясөзбен кіріңіз.',
            en: 'Now sign in with your new password.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: const ValueKey('reset-sign-in'),
            onPressed: _finish,
            child: Text(t(locale, ru: 'Войти', kz: 'Кіру', en: 'Sign in')),
          ),
        ),
      ],
    );
  }
}

/// "1 Телефон — 2 Код — 3 Пароль" as three thin bars with labels; the
/// current and finished steps in gold.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.locale});

  final int current;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final labels = [
      t(locale, ru: 'Телефон', kz: 'Телефон', en: 'Phone'),
      t(locale, ru: 'Код', kz: 'Код', en: 'Code'),
      t(locale, ru: 'Пароль', kz: 'Құпиясөз', en: 'Password'),
    ];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 3,
                  decoration: BoxDecoration(
                    color: i <= current ? colors.goldPrimary : colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${i + 1} ${labels[i]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: i == current ? colors.goldPrimary : colors.textMuted,
                    fontWeight: i == current ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
