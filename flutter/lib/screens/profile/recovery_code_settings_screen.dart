import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/providers.dart';
import '../../state/recovery_code_provider.dart';
import '../../widgets/app_password_field.dart';
import '../auth/recovery_code_screen.dart';

/// Профиль → Безопасность → Резервный код восстановления. Shows whether
/// the account has a backup code; creates one (accounts from before backup
/// codes have none) or replaces it — replacing asks for confirmation, since
/// the old code stops working at once. Both need the current password. An
/// existing code can never be viewed: only a new one is shown, once (on
/// [RecoveryCodeScreen]).
class RecoveryCodeSettingsScreen extends ConsumerStatefulWidget {
  const RecoveryCodeSettingsScreen({super.key});

  @override
  ConsumerState<RecoveryCodeSettingsScreen> createState() =>
      _RecoveryCodeSettingsScreenState();
}

class _RecoveryCodeSettingsScreenState
    extends ConsumerState<RecoveryCodeSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<bool> _confirmReplace(AppLocale locale) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          t(
            locale,
            ru: 'Заменить резервный код?',
            kz: 'Резервтік кодты ауыстыру керек пе?',
            en: 'Replace the backup code?',
          ),
        ),
        content: Text(
          t(
            locale,
            ru:
                'Текущий код сразу перестанет работать. Новый код будет '
                'показан один раз — сохраните его.',
            kz:
                'Ағымдағы код бірден жарамсыз болады. Жаңа код бір рет '
                'көрсетіледі — оны сақтаңыз.',
            en:
                'The current code will stop working at once. The new code '
                'is shown only once — save it.',
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('recovery-replace-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(locale, ru: 'Отмена', kz: 'Болдырмау', en: 'Cancel')),
          ),
          TextButton(
            key: const ValueKey('recovery-replace-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              t(locale, ru: 'Заменить', kz: 'Ауыстыру', en: 'Replace'),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _create({required bool replacing}) async {
    if (!_formKey.currentState!.validate()) return;
    final locale = ref.read(localeProvider);
    if (replacing && !await _confirmReplace(locale)) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await ref
          .read(authServiceProvider)
          .replaceRecoveryCode(currentPassword: _passwordController.text);
      _passwordController.clear();
      ref.read(authProvider.notifier).markRecoveryCodeCreated();
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => RecoveryCodeScreen(code: code),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorText(AppLocale locale, Object error) {
    if (error is ApiException) {
      if (error.statusCode == 429) {
        return t(
          locale,
          ru: 'Слишком много попыток. Попробуйте снова через 15 минут.',
          kz: 'Әрекеттер тым көп. 15 минуттан кейін қайталап көріңіз.',
          en: 'Too many attempts. Try again in 15 minutes.',
        );
      }
      if (error.debugMessage == 'wrong_current_password') {
        return t(
          locale,
          ru: 'Неверный текущий пароль',
          kz: 'Ағымдағы құпиясөз қате',
          en: 'Wrong current password',
        );
      }
    }
    return apiErrorMessage(locale, error);
  }

  Widget _status(BuildContext context, AppLocale locale, bool? hasCode) {
    final colors = context.mereytoiColors;
    final missing = hasCode == false;
    final (icon, color, text) = switch (hasCode) {
      false => (
        Icons.warning_amber_rounded,
        colors.goldPrimary,
        t(
          locale,
          ru:
              'Резервный код ещё не создан. Без него забытый пароль можно '
              'восстановить только через менеджера.',
          kz:
              'Резервтік код әлі жасалмаған. Онсыз ұмытылған құпиясөзді тек '
              'менеджер арқылы қалпына келтіруге болады.',
          en:
              'No backup code yet. Without one, a forgotten password can only '
              'be restored through a manager.',
        ),
      ),
      true => (
        Icons.verified_user_outlined,
        colors.success,
        t(
          locale,
          ru: 'Резервный код создан. Посмотреть его снова нельзя.',
          kz: 'Резервтік код жасалған. Оны қайта көру мүмкін емес.',
          en: 'A backup code exists. It can\'t be shown again.',
        ),
      ),
      null => (
        Icons.info_outline_rounded,
        colors.textSecondary,
        t(
          locale,
          ru: 'Новый код заменит прежний, если он был.',
          kz: 'Жаңа код бұрынғысын ауыстырады, егер ол болса.',
          en: 'A new code replaces the previous one, if any.',
        ),
      ),
    };
    return Container(
      key: ValueKey(
        missing ? 'recovery-status-missing' : 'recovery-status-$hasCode',
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final textTheme = Theme.of(context).textTheme;
    final status = ref.watch(recoveryCodeStatusProvider);
    final hasCode = status.valueOrNull;
    final replacing = hasCode != false;
    return Scaffold(
      appBar: AppBar(
        // Short: the full «Резервный код восстановления» didn't fit an app
        // bar on a 390dp phone (seen on device).
        title: Text(
          t(
            locale,
            ru: 'Резервный код',
            kz: 'Резервтік код',
            en: 'Backup code',
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
                    ru:
                        'С резервным кодом можно сменить забытый пароль без SMS '
                        'и WhatsApp. Код показывается только один раз, сразу '
                        'после создания, — сохраните его в надёжном месте.',
                    kz:
                        'Резервтік кодпен ұмытылған құпиясөзді SMS пен '
                        'WhatsApp-сыз өзгертуге болады. Код тек бір рет, '
                        'жасалғаннан кейін бірден көрсетіледі — оны сенімді '
                        'жерде сақтаңыз.',
                    en:
                        'A backup code lets you reset a forgotten password '
                        'without SMS or WhatsApp. It is shown only once, right '
                        'after it is created — keep it somewhere safe.',
                  ),
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                if (status.isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  _status(context, locale, hasCode),
                const SizedBox(height: AppSpacing.lg),
                AppPasswordField(
                  key: const ValueKey('recovery-settings-password'),
                  controller: _passwordController,
                  labelText: t(
                    locale,
                    ru: 'Текущий пароль',
                    kz: 'Ағымдағы құпиясөз',
                    en: 'Current password',
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) =>
                      _busy ? null : _create(replacing: replacing),
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
                          ru: 'Введите текущий пароль',
                          kz: 'Ағымдағы құпиясөзді енгізіңіз',
                          en: 'Enter your current password',
                        )
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _errorText(locale, _error!),
                    key: const ValueKey('recovery-settings-error'),
                    style: TextStyle(
                      color: context.mereytoiColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  key: const ValueKey('recovery-settings-create'),
                  onPressed: _busy || status.isLoading
                      ? null
                      : () => _create(replacing: replacing),
                  child: _busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: context.mereytoiColors.onGoldDisabled,
                          ),
                        )
                      : Text(
                          replacing
                              ? t(
                                  locale,
                                  ru: 'Заменить код',
                                  kz: 'Кодты ауыстыру',
                                  en: 'Replace the code',
                                )
                              : t(
                                  locale,
                                  ru: 'Создать резервный код',
                                  kz: 'Резервтік код жасау',
                                  en: 'Create a backup code',
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
