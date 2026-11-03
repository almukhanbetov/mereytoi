import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../state/locale_provider.dart';

/// Shows a freshly issued one-time backup code — after registration, after
/// recovering the password with the previous code, or after replacing it in
/// security settings. The code lives only in this widget: it is never
/// written to storage, and this screen is the only time it is shown. It
/// can't be left (system back included) until the person confirms they
/// saved it; then it pops with `true`.
class RecoveryCodeScreen extends ConsumerStatefulWidget {
  const RecoveryCodeScreen({super.key, required this.code});

  /// As the backend formats it: "ABCD-EFGH-…".
  final String code;

  @override
  ConsumerState<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends ConsumerState<RecoveryCodeScreen> {
  bool _saved = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: _saved,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(
                    locale,
                    ru: 'Ваш код для восстановления пароля',
                    kz: 'Құпиясөзді қалпына келтіруге арналған кодыңыз',
                    en: 'Your password recovery code',
                  ),
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  key: const ValueKey('recovery-code-value'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.lg,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceSoft,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: colors.goldPrimary),
                  ),
                  child: SelectableText(
                    widget.code,
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['RobotoMono', 'Courier'],
                      letterSpacing: 1.2,
                      height: 1.5,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey('recovery-code-copy'),
                  onPressed: _copy,
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _copied
                        ? t(
                            locale,
                            ru: 'Скопировано',
                            kz: 'Көшірілді',
                            en: 'Copied',
                          )
                        : t(
                            locale,
                            ru: 'Скопировать код',
                            kz: 'Кодты көшіру',
                            en: 'Copy code',
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.goldPrimary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 20,
                        color: colors.goldPrimary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          t(
                            locale,
                            ru:
                                'Сохраните код в надёжном месте. Он понадобится '
                                'для восстановления пароля. Код показывается '
                                'только сейчас — посмотреть его позже нельзя.',
                            kz:
                                'Кодты сенімді жерде сақтаңыз. Ол құпиясөзді '
                                'қалпына келтіру үшін қажет болады. Код тек қазір '
                                'көрсетіледі — кейін оны көру мүмкін емес.',
                            en:
                                'Keep this code somewhere safe. You will need it '
                                'to recover your password. It is shown only now '
                                '— you can\'t view it again later.',
                          ),
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                CheckboxListTile(
                  key: const ValueKey('recovery-code-saved'),
                  value: _saved,
                  onChanged: (v) => setState(() => _saved = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: colors.goldPrimary,
                  title: Text(
                    t(
                      locale,
                      ru: 'Я сохранил код',
                      kz: 'Мен кодты сақтадым',
                      en: 'I have saved the code',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ElevatedButton(
                  key: const ValueKey('recovery-code-done'),
                  onPressed: _saved
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: Text(t(locale, ru: 'Готово', kz: 'Дайын', en: 'Done')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
