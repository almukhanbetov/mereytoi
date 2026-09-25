import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../state/locale_provider.dart';
import '../state/theme_provider.dart';

/// Этап 10Б-А2 — shared by both entry points into "Оформление"
/// (`ProfileScreen`'s own row and `HomeScreen`'s app-bar icon, see
/// `_ThemeToggleButton` there): moved out of `profile_screen.dart`, which
/// only ever renders for an authenticated user, so a guest — who couldn't
/// reach this sheet at all before — now gets the exact same widget, reading
/// and writing the exact same [themeModeProvider]/[ThemeStorage], never a
/// second theme-picker implementation.

String themeModeLabel(AppLocale locale, ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => t(locale, ru: 'Системная', kz: 'Жүйелік', en: 'System'),
    ThemeMode.light => t(locale, ru: 'Светлая', kz: 'Ашық', en: 'Light'),
    ThemeMode.dark => t(locale, ru: 'Тёмная', kz: 'Қараңғы', en: 'Dark'),
  };
}

/// The sun/moon/auto glyph for a mode — used both inside the sheet's own
/// tiles and by `HomeScreen`'s compact trigger button, so the icon someone
/// taps always matches the icon they see inside the sheet that opens.
IconData themeModeIcon(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };
}

/// "Оформление" — Системная / Светлая / Тёмная. A plain bottom sheet of
/// radio-style tiles, the same mobile pattern the rest of this app already
/// uses for a single pick-one choice (see `category_picker_sheet.dart`)
/// rather than a segmented control, which reads more like a desktop/web
/// control at this width.
class ThemeModeSheet extends ConsumerWidget {
  const ThemeModeSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final current = ref.watch(themeModeProvider);
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
                t(locale, ru: 'Оформление', kz: 'Көрініс', en: 'Appearance'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final mode in ThemeMode.values)
                _ThemeModeTile(
                  mode: mode,
                  label: themeModeLabel(locale, mode),
                  icon: themeModeIcon(mode),
                  selected: current == mode,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).setMode(mode);
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

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final String label;
  final IconData icon;
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
              Icon(
                icon,
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
              if (selected)
                Icon(Icons.check_rounded, size: 20, color: colors.goldPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
