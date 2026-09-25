import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../state/locale_provider.dart';

/// Each language's own name, in its own script — a picker lists options by
/// what they're called in themselves, not translated through whichever
/// language happens to be active right now (the site's own `<T>`-based
/// language menu, where one exists, follows the same convention).
String localeNativeName(AppLocale locale) {
  return switch (locale) {
    AppLocale.ru => 'Русский',
    AppLocale.kz => 'Қазақша',
    AppLocale.en => 'English',
  };
}

/// "Язык" — Русский / Қазақша / English. Same pick-one bottom-sheet
/// pattern as [ThemeModeSheet] (radio-style tiles, selected one checked),
/// deliberately the identical shape so a user who's already learned one
/// picker in this app recognizes the other instantly. `AppLocale.en` was
/// already a real third value in `locale_provider.dart` — every `t()` call
/// site without an explicit `en:` string already falls back to Russian, so
/// enabling it here doesn't require translating everything else first.
class LocaleSheet extends ConsumerWidget {
  const LocaleSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);
    final colors = context.mereytoiColors;

    return SafeArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(current, ru: 'Язык', kz: 'Тіл', en: 'Language'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final locale in AppLocale.values)
                _LocaleTile(
                  label: localeNativeName(locale),
                  selected: current == locale,
                  onTap: () {
                    ref.read(localeProvider.notifier).setLocale(locale);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocaleTile extends StatelessWidget {
  const _LocaleTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              // A plain radio indicator, not a per-language glyph: Material's
              // own `translate`/`translate_rounded` icon is literally drawn
              // as a stylized CJK character next to "A" — the real intended
              // design, not a font-fallback bug — which read as unrelated
              // hieroglyphs to a user picking between Russian/Kazakh/English.
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? colors.goldPrimary : colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: selected ? colors.textPrimary : colors.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
