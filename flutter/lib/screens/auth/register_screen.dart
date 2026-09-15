import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_password_field.dart';
import 'login_screen.dart';

/// POST /api/auth/register — {name, email, phone?, password}, exactly the
/// backend's `registerInput` (phone is optional there; min password length
/// 6 is enforced server-side, mirrored here only as a friendlier inline
/// validator so the request isn't sent just to bounce off a 400).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(authSubmitProvider.notifier)
        .register(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

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
        title: Text(t(locale, ru: 'Регистрация', kz: 'Тіркелу')),
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
                  t(locale, ru: 'Создать аккаунт', kz: 'Аккаунт жасау'),
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  t(
                    locale,
                    ru: 'Сохраняйте прогресс планирования тоя',
                    kz: 'Той жоспарлау барысын сақтаңыз',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: InputDecoration(
                    labelText: t(locale, ru: 'Имя', kz: 'Атыңыз'),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? t(locale, ru: 'Введите имя', kz: 'Атыңызды енгізіңіз')
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) {
                      return t(
                        locale,
                        ru: 'Введите email',
                        kz: 'Email енгізіңіз',
                      );
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return t(
                        locale,
                        ru: 'Введите корректный email',
                        kz: 'Email дұрыс емес',
                      );
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: InputDecoration(
                    labelText: t(
                      locale,
                      ru: 'Телефон (необязательно)',
                      kz: 'Телефон (міндетті емес)',
                    ),
                    hintText: '+7 700 000 00 00',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppPasswordField(
                  controller: _passwordController,
                  labelText: t(locale, ru: 'Пароль', kz: 'Құпия сөз'),
                  onFieldSubmitted: (_) => _submit(),
                  showTooltip: t(
                    locale,
                    ru: 'Показать пароль',
                    kz: 'Құпия сөзді көрсету',
                  ),
                  hideTooltip: t(
                    locale,
                    ru: 'Скрыть пароль',
                    kz: 'Құпия сөзді жасыру',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return t(
                        locale,
                        ru: 'Введите пароль',
                        kz: 'Құпия сөзді енгізіңіз',
                      );
                    }
                    if (v.length < 6) {
                      return t(
                        locale,
                        ru: 'Минимум 6 символов',
                        kz: 'Кемінде 6 таңба',
                      );
                    }
                    return null;
                  },
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
                      : Text(
                          t(locale, ru: 'Зарегистрироваться', kz: 'Тіркелу'),
                        ),
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: TextButton(
                    onPressed: submitting
                        ? null
                        : () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          ),
                    child: Text(
                      t(
                        locale,
                        ru: 'Уже есть аккаунт? Войти',
                        kz: 'Аккаунт бар ма? Кіру',
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
