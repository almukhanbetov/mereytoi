import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/auth/password_reset_rules.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/password_reset_provider.dart';
import '../../state/providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_password_field.dart';
import '../../widgets/otp_code_field.dart';

enum _Step { choose, current, sendCode, code, newPassword, success }

/// Profile → Security → Change password, for a signed-in (active) user:
///   A. with the current password — PUT /api/users/me/password
///      {current_password, new_password};
///   B. without it — a code to the account's own phone
///      (POST /api/users/me/password/code), then PUT with {code, new_password}.
///      Offered only while code delivery is available
///      (GET /api/auth/password/config) and the profile has a phone.
///
/// Either way the backend retires every older session and returns a fresh
/// token, which AuthNotifier.changePassword stores like a login's — the user
/// stays signed in. System Back walks back one step (B: password → code →
/// choice; A: form → choice); out only from the choice.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  _Step _step = _Step.choose;

  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _repeatController = TextEditingController();
  final _codeController = TextEditingController();

  bool _busy = false;
  bool _resending = false;
  bool _codeInvalid = false;
  String? _error;
  String? _currentError;
  String _phoneHint = '';

  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.removeListener(_rebuild);
    // Nothing secret outlives the screen.
    for (final c in [
      _currentController,
      _newController,
      _repeatController,
      _codeController,
    ]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  AppLocale get _locale => ref.read(localeProvider);

  /// The masked profile phone, if it's a number a code can go to (watched,
  /// so the screen follows the signed-in user).
  String? get _profilePhoneMasked {
    final auth = ref.watch(authProvider);
    if (auth is! AuthAuthenticated) return null;
    final normalized = normalizeKzPhone(auth.user.phone);
    return normalized == null ? null : maskKzPhone(normalized);
  }

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
    _currentError = null;
  });

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
        en: 'Too many attempts. Try again later.',
      ),
      PasswordResetFailure.weakPassword => t(
        locale,
        ru: 'Минимум 8 символов',
        kz: 'Кемінде 8 таңба',
        en: 'At least 8 characters',
      ),
      PasswordResetFailure.phoneMissing => t(
        locale,
        ru: 'Добавьте номер телефона в профиле.',
        kz: 'Профильге телефон нөмірін қосыңыз.',
        en: 'Add a phone number to your profile.',
      ),
      PasswordResetFailure.deliveryUnavailable => t(
        locale,
        ru: 'Отправка кода сейчас недоступна.',
        kz: 'Код жіберу қазір қолжетімсіз.',
        en: 'Sending a code is unavailable right now.',
      ),
      _ => apiErrorMessage(locale, error),
    };
  }

  // ---- Variant A ----

  Future<void> _submitWithCurrent() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _currentError = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (mounted) _go(_Step.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (passwordResetFailureOf(e) ==
            PasswordResetFailure.wrongCurrentPassword) {
          // The new password stays; only the current one was wrong.
          _currentError = t(
            _locale,
            ru: 'Неверный текущий пароль',
            kz: 'Ағымдағы құпиясөз қате',
            en: 'Current password is incorrect',
          );
        } else {
          _error = _failureText(e);
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Variant B ----

  Future<void> _sendCode({bool resend = false}) async {
    if (resend ? (_resending || _secondsLeft > 0) : _busy) return;
    setState(() {
      if (resend) {
        _resending = true;
      } else {
        _busy = true;
      }
      _error = null;
    });
    try {
      final result = await ref
          .read(authServiceProvider)
          .requestPasswordChangeCode(lang: _locale.name);
      if (!mounted) return;
      setState(() {
        _phoneHint = result.phoneHint;
        _codeInvalid = false;
        _codeController.clear();
        _step = _Step.code;
      });
      _startCountdown(result.resendAfter);
    } catch (e) {
      if (!mounted) return;
      if (resend) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_failureText(e))));
      } else {
        setState(() => _error = _failureText(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _resending = false;
        });
      }
    }
  }

  Future<void> _submitWithCode() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .changePassword(
            code: _codeController.text,
            newPassword: _newController.text,
          );
      if (!mounted) return;
      _timer?.cancel();
      _go(_Step.success);
    } catch (e) {
      if (!mounted) return;
      if (passwordResetFailureOf(e) == PasswordResetFailure.invalidCode) {
        setState(() {
          _step = _Step.code;
          _codeInvalid = true;
          _codeController.clear();
        });
      } else {
        setState(() => _error = _failureText(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    switch (_step) {
      case _Step.choose:
      case _Step.success:
        Navigator.of(context).pop();
      case _Step.current:
      case _Step.sendCode:
      case _Step.code:
        _timer?.cancel();
        _secondsLeft = 0;
        // Passwords typed for one variant don't carry over to the other.
        for (final c in [
          _currentController,
          _newController,
          _repeatController,
          _codeController,
        ]) {
          c.clear();
        }
        _go(_Step.choose);
      case _Step.newPassword:
        _go(_Step.code);
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
              ru: 'Изменить пароль',
              kz: 'Құпиясөзді өзгерту',
              en: 'Change password',
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
            child: switch (_step) {
              _Step.choose => _buildChoose(context, locale),
              _Step.current => _buildCurrent(context, locale),
              _Step.sendCode => _buildSendCode(context, locale),
              _Step.code => _buildCode(context, locale),
              _Step.newPassword => _buildNewPassword(context, locale),
              _Step.success => _buildSuccess(context, locale),
            },
          ),
        ),
      ),
    );
  }

  // ---- building blocks ----

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

  Widget _primary(
    BuildContext context, {
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    bool busy = false,
  }) {
    return ElevatedButton(
      key: key,
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: context.mereytoiColors.onGold,
              ),
            )
          : Text(label),
    );
  }

  ({String show, String hide}) _tooltips(AppLocale locale) => (
    show: t(
      locale,
      ru: 'Показать пароль',
      kz: 'Құпия сөзді көрсету',
      en: 'Show password',
    ),
    hide: t(
      locale,
      ru: 'Скрыть пароль',
      kz: 'Құпия сөзді жасыру',
      en: 'Hide password',
    ),
  );

  /// The "new password" + "repeat" pair, shared by A and B.
  List<Widget> _newPasswordFields(AppLocale locale, {VoidCallback? onDone}) {
    final tips = _tooltips(locale);
    return [
      AppPasswordField(
        key: const ValueKey('change-new-password'),
        controller: _newController,
        labelText: t(
          locale,
          ru: 'Новый пароль',
          kz: 'Жаңа құпиясөз',
          en: 'New password',
        ),
        textInputAction: TextInputAction.next,
        showTooltip: tips.show,
        hideTooltip: tips.hide,
        validator: (v) =>
            newPasswordProblem(v ?? '', v ?? '') == NewPasswordProblem.tooShort
            ? t(
                locale,
                ru: 'Минимум 8 символов',
                kz: 'Кемінде 8 таңба',
                en: 'At least 8 characters',
              )
            : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      AppPasswordField(
        key: const ValueKey('change-repeat-password'),
        controller: _repeatController,
        labelText: t(
          locale,
          ru: 'Повторите новый пароль',
          kz: 'Жаңа құпиясөзді қайталаңыз',
          en: 'Repeat new password',
        ),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => onDone?.call(),
        showTooltip: tips.show,
        hideTooltip: tips.hide,
        validator: (v) => (v ?? '') != _newController.text
            ? t(
                locale,
                ru: 'Пароли не совпадают',
                kz: 'Құпиясөздер сәйкес келмейді',
                en: 'Passwords don\'t match',
              )
            : null,
      ),
    ];
  }

  // ---- steps ----

  Widget _buildChoose(BuildContext context, AppLocale locale) {
    final colors = context.mereytoiColors;
    final available =
        ref.watch(passwordResetAvailableProvider).valueOrNull ?? false;
    final masked = _profilePhoneMasked;
    final bEnabled = available && masked != null;
    final bSubtitle = !available
        ? t(
            locale,
            ru: 'Вход по коду сейчас недоступен',
            kz: 'Код арқылы өзгерту қазір қолжетімсіз',
            en: 'Not available right now',
          )
        : masked == null
        ? t(
            locale,
            ru: 'Добавьте номер телефона в профиле',
            kz: 'Профильге телефон нөмірін қосыңыз',
            en: 'Add a phone number to your profile',
          )
        : t(
            locale,
            ru: 'Код в WhatsApp на $masked',
            kz: 'WhatsApp арқылы код: $masked',
            en: 'A code via WhatsApp to $masked',
          );

    Widget option({
      required Key key,
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback? onTap,
    }) {
      final enabled = onTap != null;
      return Opacity(
        opacity: enabled ? 1 : 0.5,
        child: AppCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: colors.goldPrimary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      key: const ValueKey('change-step-choose'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          t(
            locale,
            ru: 'Как вы хотите подтвердить?',
            kz: 'Қалай растайсыз?',
            en: 'How do you want to confirm?',
          ),
          null,
        ),
        const SizedBox(height: AppSpacing.md),
        option(
          key: const ValueKey('change-option-current'),
          icon: Icons.lock_outline_rounded,
          title: t(
            locale,
            ru: 'Я помню текущий пароль',
            kz: 'Ағымдағы құпиясөзді білемін',
            en: 'I know my current password',
          ),
          subtitle: t(
            locale,
            ru: 'Введите текущий и новый пароль',
            kz: 'Ағымдағы және жаңа құпиясөзді енгізіңіз',
            en: 'Enter your current and new password',
          ),
          onTap: () => _go(_Step.current),
        ),
        const SizedBox(height: AppSpacing.sm),
        option(
          key: const ValueKey('change-option-code'),
          icon: Icons.sms_outlined,
          title: t(
            locale,
            ru: 'Я не помню текущий пароль',
            kz: 'Ағымдағы құпиясөз есімде жоқ',
            en: 'I don\'t remember my current password',
          ),
          subtitle: bSubtitle,
          onTap: bEnabled ? () => _go(_Step.sendCode) : null,
        ),
      ],
    );
  }

  Widget _buildCurrent(BuildContext context, AppLocale locale) {
    final tips = _tooltips(locale);
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('change-step-current'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            t(
              locale,
              ru: 'Смена пароля',
              kz: 'Құпиясөзді ауыстыру',
              en: 'Change password',
            ),
            t(
              locale,
              ru: 'Новый пароль — минимум 8 символов.',
              kz: 'Жаңа құпиясөз — кемінде 8 таңба.',
              en: 'The new password needs at least 8 characters.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPasswordField(
            key: const ValueKey('change-current-password'),
            controller: _currentController,
            labelText: t(
              locale,
              ru: 'Текущий пароль',
              kz: 'Ағымдағы құпиясөз',
              en: 'Current password',
            ),
            textInputAction: TextInputAction.next,
            showTooltip: tips.show,
            hideTooltip: tips.hide,
            validator: (v) => (v ?? '').isEmpty
                ? t(
                    locale,
                    ru: 'Введите текущий пароль',
                    kz: 'Ағымдағы құпиясөзді енгізіңіз',
                    en: 'Enter your current password',
                  )
                : null,
          ),
          if (_currentError != null) _errorText(context, _currentError!),
          const SizedBox(height: AppSpacing.sm),
          ..._newPasswordFields(locale, onDone: _submitWithCurrent),
          if (_error != null) _errorText(context, _error!),
          const SizedBox(height: AppSpacing.lg),
          _primary(
            context,
            key: const ValueKey('change-submit-current'),
            busy: _busy,
            onPressed: _submitWithCurrent,
            label: t(
              locale,
              ru: 'Изменить пароль',
              kz: 'Құпиясөзді өзгерту',
              en: 'Change password',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendCode(BuildContext context, AppLocale locale) {
    final masked = _profilePhoneMasked;
    return Column(
      key: const ValueKey('change-step-send'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          t(
            locale,
            ru: 'Подтверждение по коду',
            kz: 'Код арқылы растау',
            en: 'Confirm with a code',
          ),
          t(
            locale,
            ru: 'Код будет отправлен на номер, указанный в вашем профиле.',
            kz: 'Код профиліңіздегі телефон нөміріне жіберіледі.',
            en: 'The code will be sent to the phone number in your profile.',
          ),
        ),
        if (masked != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            masked,
            key: const ValueKey('change-masked-phone'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: context.mereytoiColors.goldPrimary,
            ),
          ),
        ],
        if (_error != null) _errorText(context, _error!),
        const SizedBox(height: AppSpacing.lg),
        _primary(
          context,
          key: const ValueKey('change-send-code'),
          busy: _busy,
          onPressed: _sendCode,
          label: t(
            locale,
            ru: 'Отправить код',
            kz: 'Кодты жіберу',
            en: 'Send code',
          ),
        ),
      ],
    );
  }

  Widget _buildCode(BuildContext context, AppLocale locale) {
    final colors = context.mereytoiColors;
    final countdown =
        '${(_secondsLeft ~/ 60).toString().padLeft(2, '0')}:'
        '${(_secondsLeft % 60).toString().padLeft(2, '0')}';
    // The same mask as on the previous step (and in "forgot password");
    // the backend's own hint only if the profile phone can't be masked.
    final hint = _profilePhoneMasked ?? _phoneHint;
    return Column(
      key: const ValueKey('change-step-code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          t(locale, ru: 'Введите код', kz: 'Кодты енгізіңіз', en: 'Enter code'),
          null,
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            hint,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: colors.goldPrimary),
          ),
        ],
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
                  key: const ValueKey('change-countdown'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                )
              : TextButton(
                  key: const ValueKey('change-resend'),
                  onPressed: _resending ? null : () => _sendCode(resend: true),
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
        _primary(
          context,
          key: const ValueKey('change-code-continue'),
          onPressed: _codeController.text.length == 6
              ? () => _go(_Step.newPassword)
              : null,
          label: t(locale, ru: 'Далее', kz: 'Әрі қарай', en: 'Next'),
        ),
      ],
    );
  }

  Widget _buildNewPassword(BuildContext context, AppLocale locale) {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('change-step-new'),
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
          ..._newPasswordFields(locale, onDone: _submitWithCode),
          if (_error != null) _errorText(context, _error!),
          const SizedBox(height: AppSpacing.lg),
          _primary(
            context,
            key: const ValueKey('change-submit-code'),
            busy: _busy,
            onPressed: _submitWithCode,
            label: t(
              locale,
              ru: 'Изменить пароль',
              kz: 'Құпиясөзді өзгерту',
              en: 'Change password',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, AppLocale locale) {
    final colors = context.mereytoiColors;
    return Column(
      key: const ValueKey('change-step-success'),
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
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: const ValueKey('change-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t(locale, ru: 'Готово', kz: 'Дайын', en: 'Done')),
          ),
        ),
      ],
    );
  }
}
