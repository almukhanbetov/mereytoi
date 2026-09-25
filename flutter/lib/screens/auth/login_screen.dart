import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_password_field.dart';
import '../../widgets/claim/claim_entry_sheet.dart';
import 'register_screen.dart';

/// POST /api/auth/login — one "identifier" field (email or phone, same as
/// the site's own login form) + password. Pushed on top of whatever screen
/// the guest was already on (see the account icon in HomeScreen); on
/// success this just pops back to it — no dedicated post-login route in
/// this stage, per the brief's own "не обязательно менять весь navigation".
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final identifier = _identifierController.text.trim();
    final isEmail = identifier.contains('@');
    ref
        .read(authSubmitProvider.notifier)
        .login(
          email: isEmail ? identifier : null,
          phone: isEmail ? null : identifier,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

    // Closes this screen the moment a session actually exists — whether
    // it came from *this* form or (in principle) from something else
    // updating authProvider while this screen happened to be open.
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next is AuthAuthenticated) Navigator.of(context).maybePop();
    });

    final submitState = ref.watch(authSubmitProvider);
    final submitting = submitState.isLoading;
    final submitError = submitState.maybeWhen(
      error: (e, _) => e,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(t(locale, ru: 'Вход', kz: 'Кіру', en: 'Sign in')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
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
                    ru: 'С возвращением',
                    kz: 'Қайта көргенімізге қуаныштымыз',
                    en: 'Welcome back',
                  ),
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  t(
                    locale,
                    ru: 'Войдите, чтобы продолжить планирование тоя',
                    kz: 'Тойды жоспарлауды жалғастыру үшін кіріңіз',
                    en: 'Sign in to continue planning your event',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _identifierController,
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
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? t(
                          locale,
                          ru: 'Введите email или телефон',
                          kz: 'Email немесе телефонды енгізіңіз',
                          en: 'Enter your email or phone',
                        )
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppPasswordField(
                  controller: _passwordController,
                  labelText: t(
                    locale,
                    ru: 'Пароль',
                    kz: 'Құпия сөз',
                    en: 'Password',
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
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
                  validator: (v) => (v == null || v.isEmpty)
                      ? t(
                          locale,
                          ru: 'Введите пароль',
                          kz: 'Құпия сөзді енгізіңіз',
                          en: 'Enter your password',
                        )
                      : null,
                ),
                if (submitError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    apiErrorMessage(locale, submitError),
                    style: TextStyle(
                      color: context.mereytoiColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: submitting ? null : _submit,
                  child: submitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: context.mereytoiColors.onGold,
                          ),
                        )
                      : Text(t(locale, ru: 'Войти', kz: 'Кіру', en: 'Sign in')),
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: TextButton(
                    onPressed: submitting
                        ? null
                        : () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                    child: Text(
                      t(
                        locale,
                        ru: 'Нет аккаунта? Зарегистрироваться',
                        kz: 'Аккаунт жоқ па? Тіркелу',
                        en: 'Don\'t have an account? Sign up',
                      ),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: submitting
                        ? null
                        : () => openClaimEntrySheet(context),
                    child: Text(
                      t(
                        locale,
                        ru: 'Есть ссылка-приглашение?',
                        kz: 'Шақыру сілтемесі бар ма?',
                        en: 'Have an invite link?',
                      ),
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
