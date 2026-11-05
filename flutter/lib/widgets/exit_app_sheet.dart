import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../state/locale_provider.dart';

/// Asks before closing the app. Closing only ends the Android activity: the
/// session and the saved token are left untouched for the next launch.
///
/// Does nothing unless [context]'s screen is on top, so a second tap or Back
/// can't stack another sheet over the first.
Future<void> showExitAppSheet(BuildContext context, AppLocale locale) async {
  if (!ModalRoute.isCurrentOf(context)!) return;
  final localizations = MaterialLocalizations.of(context);
  final exit = await Navigator.of(context).push(
    _ExitAppRoute(
      barrierLabel: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      builder: (_) => _ExitAppSheet(locale: locale),
    ),
  );
  if (exit == true) await SystemNavigator.pop();
}

/// A tap outside closes the sheet only once it has finished opening: the second
/// tap of a double tap on the Home button lands outside, and would close the
/// sheet before anyone saw it.
class _ExitAppRoute extends ModalBottomSheetRoute<bool> {
  _ExitAppRoute({required super.builder, required super.barrierLabel})
    : super(isScrollControlled: false, backgroundColor: Colors.transparent);

  bool _opened = false;

  @override
  bool get barrierDismissible => _opened;

  @override
  TickerFuture didPush() {
    final opening = super.didPush();
    opening.whenCompleteOrCancel(() {
      _opened = true;
      if (isActive) changedInternalState();
    });
    return opening;
  }
}

class _ExitAppSheet extends StatefulWidget {
  const _ExitAppSheet({required this.locale});

  final AppLocale locale;

  @override
  State<_ExitAppSheet> createState() => _ExitAppSheetState();
}

class _ExitAppSheetState extends State<_ExitAppSheet> {
  // A second tap would pop the shell underneath the closing sheet.
  bool _decided = false;

  void _close(bool exit) {
    if (_decided) return;
    _decided = true;
    Navigator.of(context).pop(exit);
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    t(
                      locale,
                      ru: 'Закрыть приложение?',
                      kz: 'Қолданбаны жабу керек пе?',
                      en: 'Close the app?',
                    ),
                    style: textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  t(
                    locale,
                    ru: 'Вы можете вернуться в любое время',
                    kz: 'Кез келген уақытта орала аласыз',
                    en: 'You can come back at any time',
                  ),
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  key: const ValueKey('exit-app-stay'),
                  autofocus: true,
                  onPressed: () => _close(false),
                  child: Text(
                    t(locale, ru: 'Остаться', kz: 'Қалу', en: 'Stay'),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton(
                  key: const ValueKey('exit-app-confirm'),
                  onPressed: () => _close(true),
                  child: Text(t(locale, ru: 'Выйти', kz: 'Шығу', en: 'Exit')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
